import CryptoKit
import Foundation
import XCTest
@testable import WinterVoice

@MainActor
final class ModelManagerTests: XCTestCase {
    func testDescriptorRejectsInsecureMissingChecksumAndEscapingPaths() {
        XCTAssertThrowsError(try descriptor(sha256: nil, url: "https://models.example/model.bin").validateForDownload())
        XCTAssertThrowsError(try descriptor(sha256: validHash, url: "http://models.example/model.bin").validateForDownload())
        XCTAssertThrowsError(try descriptor(sha256: validHash, id: "../escape").validateForDownload())
        XCTAssertThrowsError(try descriptor(sha256: validHash, fileName: "../model.bin").validateForDownload())
    }

    func testDownloaderProgressAndInstallHandoffUseMeasuredBytes() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ModelDownloaderTests.\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("source.bin")
        let bytes = Data("downloaded model".utf8)
        try bytes.write(to: source)
        let hash = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        let downloader = ManualModelDownloader()
        let subject = ModelManager(root: root.appendingPathComponent("store"), downloader: downloader)

        subject.install(descriptor(sha256: hash))
        for _ in 0..<200 where downloader.requestCount == 0 { await Task.yield() }
        XCTAssertEqual(downloader.requestCount, 1)
        downloader.send(.progress(received: 4, expected: 16))
        for _ in 0..<200 where subject.downloadProgress["approved-model"] != 0.25 { await Task.yield() }
        XCTAssertEqual(subject.downloadProgress["approved-model"], 0.25)
        downloader.send(.progress(received: 16, expected: 16))
        downloader.send(.downloaded(source))
        downloader.finish()
        for _ in 0..<200 where subject.installed.isEmpty || subject.downloadingModelIDs.contains("approved-model") { await Task.yield() }

        XCTAssertEqual(downloader.requestCount, 1)
        XCTAssertEqual(subject.installed.first?.id, "approved-model")
        XCTAssertNil(subject.downloadProgress["approved-model"])
    }

    func testCancellationTerminatesDownloaderWithoutInstall() async {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ModelCancelTests.\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let downloader = SuspendedModelDownloader()
        let subject = ModelManager(root: root, downloader: downloader)
        subject.install(descriptor(sha256: validHash))
        await Task.yield()
        subject.cancelInstall("approved-model")
        for _ in 0..<20 where !downloader.wasCancelled { await Task.yield() }
        XCTAssertTrue(downloader.wasCancelled)
        XCTAssertTrue(subject.installed.isEmpty)
    }

    func testVerifiedAtomicInstallPersistsSelectionAndDeletion() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ModelManagerTests.\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("source.bin")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let bytes = Data("approved model".utf8)
        try bytes.write(to: source)
        let hash = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        let descriptor = descriptor(sha256: hash)
        let subject = ModelManager(root: root.appendingPathComponent("store"))

        try await subject.installDownloadedFile(source, descriptor: descriptor)
        try await subject.select(descriptor.id)
        let restored = ModelManager(root: root.appendingPathComponent("store"))
        for _ in 0..<20 where restored.activeModel == nil { await Task.yield() }

        XCTAssertEqual(restored.activeModel?.id, descriptor.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("store/\(descriptor.id)/model.bin").path))
        try await restored.delete(try XCTUnwrap(restored.activeModel))
        XCTAssertNil(restored.activeModel)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("store/\(descriptor.id)").path))
    }

    func testChecksumMismatchInstallsNothing() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ModelManagerTests.\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("source.bin")
        try Data("wrong".utf8).write(to: source)
        let subject = ModelManager(root: root.appendingPathComponent("store"))

        do {
            try await subject.installDownloadedFile(source, descriptor: descriptor(sha256: String(repeating: "0", count: 64)))
            XCTFail("Expected checksum mismatch")
        } catch {}
        XCTAssertTrue(subject.installed.isEmpty)
    }

    func testDiskStorageDeleteRollsBackDirectoryAndRegistryWhenPersistenceFails() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ModelDeleteRollbackTests.\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let model = installedModel()
        let original = ModelRegistry(installed: [model], activeModelID: model.id)
        try createStoredModel(model, root: root, registry: original)
        let storage = DiskModelStorage(root: root, registryWriter: FailingRegistryWriter())

        do {
            try await storage.delete(model, registry: .empty)
            XCTFail("Expected registry persistence failure")
        } catch {}

        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("\(model.id)/\(model.fileName)").path))
        XCTAssertEqual(try decodeRegistry(root), original)
    }

    func testDiskStorageDeletePersistsRegistryThenRemovesBackup() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ModelDeleteSuccessTests.\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let model = installedModel()
        let original = ModelRegistry(installed: [model], activeModelID: model.id)
        try createStoredModel(model, root: root, registry: original)
        let storage = DiskModelStorage(root: root)

        try await storage.delete(model, registry: .empty)

        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent(model.id).path))
        XCTAssertEqual(try decodeRegistry(root), .empty)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.path).allSatisfy { !$0.contains(".delete.") })
    }

    func testSlowStorageDoesNotMonopolizeMainActorAndPublishesInstallingState() async throws {
        let storage = SuspendedModelStorage()
        let downloader = ManualModelDownloader()
        let subject = ModelManager(downloader: downloader, storage: storage)
        let source = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try Data("model".utf8).write(to: source)
        defer { try? FileManager.default.removeItem(at: source) }

        subject.install(descriptor(sha256: validHash))
        for _ in 0..<200 where downloader.requestCount == 0 { await Task.yield() }
        XCTAssertEqual(downloader.requestCount, 1)
        downloader.send(.downloaded(source))
        for _ in 0..<200 where !subject.installingModelIDs.contains("approved-model") { await Task.yield() }
        XCTAssertTrue(subject.installingModelIDs.contains("approved-model"))

        var mainActorRan = false
        await MainActor.run { mainActorRan = true }
        XCTAssertTrue(mainActorRan)
        let installStarted = await storage.installStarted
        XCTAssertTrue(installStarted)
        subject.cancelInstall("approved-model")
        await storage.cancelSuspension()
        for _ in 0..<200 where !subject.installingModelIDs.isEmpty { await Task.yield() }
        XCTAssertTrue(subject.installingModelIDs.isEmpty)
        XCTAssertTrue(subject.installed.isEmpty)
        XCTAssertNil(subject.lastError)
    }

    func testURLSessionCancellationErrorClearsLifecycleWithoutErrorOrInstall() async {
        let downloader = FailingModelDownloader(error: URLError(.cancelled))
        let subject = ModelManager(downloader: downloader)
        subject.install(descriptor(sha256: validHash))
        for _ in 0..<20 where !subject.downloadingModelIDs.isEmpty { await Task.yield() }
        XCTAssertTrue(subject.downloadingModelIDs.isEmpty)
        XCTAssertTrue(subject.installingModelIDs.isEmpty)
        XCTAssertTrue(subject.downloadProgress.isEmpty)
        XCTAssertTrue(subject.installed.isEmpty)
        XCTAssertNil(subject.lastError)
    }

    private var validHash: String { String(repeating: "a", count: 64) }

    private func installedModel() -> InstalledModel {
        InstalledModel(id: "approved-model", displayName: "Approved Model", runtime: "whisper.cpp", fileName: "model.bin", installedAt: Date(timeIntervalSince1970: 1))
    }

    private func createStoredModel(_ model: InstalledModel, root: URL, registry: ModelRegistry) throws {
        let directory = root.appendingPathComponent(model.id, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("model".utf8).write(to: directory.appendingPathComponent(model.fileName))
        try JSONEncoder().encode(registry).write(to: root.appendingPathComponent("registry.json"), options: .atomic)
    }

    private func decodeRegistry(_ root: URL) throws -> ModelRegistry {
        try JSONDecoder().decode(ModelRegistry.self, from: Data(contentsOf: root.appendingPathComponent("registry.json")))
    }

    private func descriptor(
        sha256: String?,
        url: String = "https://models.example/model.bin",
        id: String = "approved-model",
        fileName: String = "model.bin"
    ) -> ModelDescriptor {
        .init(
            id: id, displayName: "Approved Model", family: "whisper", runtime: "whisper.cpp",
            variant: "test", quantization: nil, downloadURL: URL(string: url)!,
            fileName: fileName, fileSize: 14, sha256: sha256
        )
    }
}

private final class ManualModelDownloader: ModelDownloading, @unchecked Sendable {
    private let lock = NSLock()
    private(set) var requestCount = 0
    private var continuation: AsyncThrowingStream<ModelDownloadEvent, Error>.Continuation?
    func events(for descriptor: ModelDescriptor) -> AsyncThrowingStream<ModelDownloadEvent, Error> {
        requestCount += 1
        return AsyncThrowingStream { continuation in
            lock.withLock { self.continuation = continuation }
        }
    }
    func send(_ event: ModelDownloadEvent) { _ = lock.withLock { continuation?.yield(event) } }
    func finish() { lock.withLock { continuation?.finish() } }
}

private final class SuspendedModelDownloader: ModelDownloading, @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    var wasCancelled: Bool { lock.withLock { cancelled } }
    func events(for descriptor: ModelDescriptor) -> AsyncThrowingStream<ModelDownloadEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.onTermination = { [weak self] _ in self?.lock.withLock { self?.cancelled = true } }
        }
    }
}

private final class FailingModelDownloader: ModelDownloading, @unchecked Sendable {
    let error: Error
    init(error: Error) { self.error = error }
    func events(for descriptor: ModelDescriptor) -> AsyncThrowingStream<ModelDownloadEvent, Error> {
        AsyncThrowingStream { $0.finish(throwing: error) }
    }
}

private struct FailingRegistryWriter: ModelRegistryWriting {
    func write(_ registry: ModelRegistry, to url: URL) throws { throw TestStorageFailure.expected }
}

private enum TestStorageFailure: Error { case expected }

private actor SuspendedModelStorage: ModelStoring {
    private var continuation: CheckedContinuation<Void, Never>?
    private(set) var installStarted = false

    func loadRegistry() -> ModelRegistry { .empty }
    func install(source: URL, descriptor: ModelDescriptor, registry: ModelRegistry) async throws -> ModelRegistry {
        installStarted = true
        await withCheckedContinuation { continuation = $0 }
        try Task.checkCancellation()
        let model = InstalledModel(
            id: descriptor.id,
            displayName: descriptor.displayName,
            runtime: descriptor.runtime,
            fileName: descriptor.fileName,
            installedAt: Date()
        )
        return ModelRegistry(installed: [model], activeModelID: registry.activeModelID)
    }
    func persist(_ registry: ModelRegistry) async throws {}
    func delete(_ model: InstalledModel, registry: ModelRegistry) async throws {}
    func removeTemporary(_ url: URL) async {}
    func cancelSuspension() { continuation?.resume(); continuation = nil }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
