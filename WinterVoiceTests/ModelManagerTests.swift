import CryptoKit
import Foundation
import XCTest
@testable import WinterVoice

@MainActor
final class ModelManagerTests: XCTestCase {
    func testPublishedCatalogIncludesVietnameseCapableAndEnglishModelsWithChecksums() throws {
        let catalog = PublishedModelCatalog.models

        XCTAssertEqual(catalog.count, 6)
        XCTAssertEqual(catalog.filter { !$0.isEnglishOnly }.map(\.variant), ["tiny", "base", "small"])
        XCTAssertEqual(catalog.filter(\.isEnglishOnly).map(\.variant), ["tiny.en", "base.en", "small.en"])
        XCTAssertTrue(catalog.filter { !$0.isEnglishOnly }.allSatisfy { $0.languageLabel.contains("Vietnamese") })
        for descriptor in catalog {
            try descriptor.validateForDownload()
            XCTAssertEqual(descriptor.downloadURL.host, "huggingface.co")
        }
    }

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
        let downloader = ManualModelDownloader()
        let subject = ModelManager(root: root.appendingPathComponent("store"), downloader: downloader)

        subject.install(descriptor(sha256: sha256Hex(bytes)))
        await waitUntil { downloader.requestCount == 1 }
        XCTAssertEqual(downloader.requestCount, 1)
        downloader.send(.progress(received: 4, expected: 16))
        await waitUntil { subject.downloadProgress["approved-model"] == 0.25 }
        XCTAssertEqual(subject.downloadProgress["approved-model"], 0.25)
        downloader.send(.progress(received: 16, expected: 16))
        downloader.send(.downloaded(source))
        downloader.finish()
        await waitUntil { !subject.installed.isEmpty && !subject.downloadingModelIDs.contains("approved-model") }

        XCTAssertEqual(downloader.requestCount, 1)
        XCTAssertEqual(subject.installed.first?.id, "approved-model")
        XCTAssertFalse(subject.downloadingModelIDs.contains("approved-model"))
        XCTAssertNil(subject.downloadProgress["approved-model"])
    }

    func testConcurrentInstallsMergeBothModelsIntoPersistedRegistry() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ModelConcurrentInstallTests.\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let bytesA = Data("first concurrent model".utf8)
        let bytesB = Data("second concurrent model".utf8)
        let sourceA = root.appendingPathComponent("a-source.bin")
        let sourceB = root.appendingPathComponent("b-source.bin")
        try bytesA.write(to: sourceA)
        try bytesB.write(to: sourceB)
        let store = root.appendingPathComponent("store")
        let downloader = ManualModelDownloader()
        let subject = ModelManager(root: store, downloader: downloader)

        subject.install(descriptor(sha256: sha256Hex(bytesA), id: "model-a", fileName: "a.bin"))
        subject.install(descriptor(sha256: sha256Hex(bytesB), id: "model-b", fileName: "b.bin"))
        await waitUntil { downloader.requestCount == 2 }
        XCTAssertEqual(downloader.requestCount, 2)
        downloader.send(.downloaded(sourceA), to: "model-a")
        downloader.finish("model-a")
        await waitUntil { subject.installed.contains { $0.id == "model-a" } }
        XCTAssertTrue(subject.installed.contains { $0.id == "model-a" })
        downloader.send(.downloaded(sourceB), to: "model-b")
        downloader.finish("model-b")
        await waitUntil { subject.installed.contains { $0.id == "model-b" } }

        XCTAssertEqual(Set(subject.installed.map(\.id)), ["model-a", "model-b"])
        XCTAssertEqual(Set(try decodeRegistry(store).installed.map(\.id)), ["model-a", "model-b"])
        XCTAssertNil(subject.lastError)
    }

    func testCancellationTerminatesDownloaderWithoutInstall() async {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ModelCancelTests.\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let downloader = SuspendedModelDownloader()
        let subject = ModelManager(root: root, downloader: downloader)
        subject.install(descriptor(sha256: validHash))
        await Task.yield()
        subject.cancelInstall("approved-model")
        await waitUntil { downloader.wasCancelled }
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
        let descriptor = descriptor(sha256: sha256Hex(bytes))
        let subject = ModelManager(root: root.appendingPathComponent("store"))

        try await subject.installDownloadedFile(source, descriptor: descriptor)
        await subject.select(descriptor.id)
        XCTAssertNil(subject.lastError)
        let restored = ModelManager(root: root.appendingPathComponent("store"))
        await waitUntil { restored.activeModel != nil }

        XCTAssertEqual(restored.activeModel?.id, descriptor.id)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("store/\(descriptor.id)/model.bin").path))
        await restored.delete(try XCTUnwrap(restored.activeModel))
        XCTAssertNil(restored.lastError)
        XCTAssertNil(restored.activeModel)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("store/\(descriptor.id)").path))
    }

    func testSelectingUninstalledModelSurfacesErrorWithoutThrowing() async {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ModelSelectErrorTests.\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let subject = ModelManager(root: root)

        await subject.select("not-installed")

        XCTAssertEqual(subject.lastError, "That model is not installed.")
        XCTAssertNil(subject.activeModelID)
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
            _ = try await storage.delete(model)
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

        _ = try await storage.delete(model)

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
        await waitUntil { downloader.requestCount == 1 }
        XCTAssertEqual(downloader.requestCount, 1)
        downloader.send(.downloaded(source))
        await waitUntil { subject.installingModelIDs.contains("approved-model") }
        XCTAssertTrue(subject.installingModelIDs.contains("approved-model"))

        var mainActorRan = false
        await MainActor.run { mainActorRan = true }
        XCTAssertTrue(mainActorRan)
        let installStarted = await storage.installStarted
        XCTAssertTrue(installStarted)
        subject.cancelInstall("approved-model")
        await storage.cancelSuspension()
        await waitUntil { subject.installingModelIDs.isEmpty }
        XCTAssertTrue(subject.installingModelIDs.isEmpty)
        XCTAssertTrue(subject.installed.isEmpty)
        XCTAssertNil(subject.lastError)
    }

    func testURLSessionCancellationErrorClearsLifecycleWithoutErrorOrInstall() async {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ModelURLSessionCancelTests.\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let downloader = FailingModelDownloader(error: URLError(.cancelled))
        let subject = ModelManager(root: root, downloader: downloader)
        subject.install(descriptor(sha256: validHash))
        await waitUntil { subject.downloadingModelIDs.isEmpty }
        XCTAssertTrue(subject.downloadingModelIDs.isEmpty)
        XCTAssertTrue(subject.installingModelIDs.isEmpty)
        XCTAssertTrue(subject.downloadProgress.isEmpty)
        XCTAssertTrue(subject.installed.isEmpty)
        XCTAssertNil(subject.lastError)
    }

    func testDownloadFailureSurfacesErrorAndClearsLifecycle() async {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("ModelDownloadFailureTests.\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let downloader = FailingModelDownloader(error: URLError(.timedOut))
        let subject = ModelManager(root: root, downloader: downloader)

        subject.install(descriptor(sha256: validHash))
        await waitUntil { subject.downloadingModelIDs.isEmpty }

        XCTAssertTrue(subject.downloadingModelIDs.isEmpty)
        XCTAssertNotNil(subject.lastError)
        XCTAssertTrue(subject.installingModelIDs.isEmpty)
        XCTAssertTrue(subject.downloadProgress.isEmpty)
        XCTAssertTrue(subject.installed.isEmpty)
    }

    private var validHash: String { String(repeating: "a", count: 64) }

    private func sha256Hex(_ bytes: Data) -> String {
        SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }

    private func installedModel() -> InstalledModel {
        InstalledModel(
            id: "approved-model",
            displayName: "Approved Model",
            runtime: "whisper.cpp",
            fileName: "model.bin",
            installedAt: Date(timeIntervalSince1970: 1),
            isEnglishOnly: false
        )
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
    private var requests = 0
    private var continuations: [String: AsyncThrowingStream<ModelDownloadEvent, Error>.Continuation] = [:]
    var requestCount: Int { lock.withLock { requests } }
    func events(for descriptor: ModelDescriptor) -> AsyncThrowingStream<ModelDownloadEvent, Error> {
        lock.withLock { requests += 1 }
        return AsyncThrowingStream { continuation in
            lock.withLock { self.continuations[descriptor.id] = continuation }
        }
    }
    func send(_ event: ModelDownloadEvent, to id: String = "approved-model") {
        _ = lock.withLock { continuations[id]?.yield(event) }
    }
    func finish(_ id: String = "approved-model") {
        lock.withLock { continuations[id]?.finish() }
    }
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
    private var registry: ModelRegistry = .empty
    private var version: UInt64 = 0
    private(set) var installStarted = false

    func loadRegistry() -> RegistrySnapshot {
        RegistrySnapshot(registry: registry, version: version)
    }

    func install(source: URL, descriptor: ModelDescriptor) async throws -> RegistrySnapshot {
        installStarted = true
        await withCheckedContinuation { continuation = $0 }
        try Task.checkCancellation()
        let model = InstalledModel(
            id: descriptor.id,
            displayName: descriptor.displayName,
            runtime: descriptor.runtime,
            fileName: descriptor.fileName,
            installedAt: Date(),
            isEnglishOnly: false
        )
        registry = ModelRegistry(
            installed: registry.installed.filter { $0.id != model.id } + [model],
            activeModelID: registry.activeModelID
        )
        version += 1
        return loadRegistry()
    }

    func selectActive(_ id: String?) throws -> RegistrySnapshot {
        registry = ModelRegistry(installed: registry.installed, activeModelID: id)
        version += 1
        return loadRegistry()
    }

    func delete(_ model: InstalledModel) throws -> RegistrySnapshot {
        registry = ModelRegistry(
            installed: registry.installed.filter { $0.id != model.id },
            activeModelID: registry.activeModelID == model.id ? nil : registry.activeModelID
        )
        version += 1
        return loadRegistry()
    }

    func removeTemporary(_ url: URL) {}
    func cancelSuspension() { continuation?.resume(); continuation = nil }
}

@MainActor
private func waitUntil(
    timeout: TimeInterval = 2,
    condition: @escaping @MainActor () -> Bool
) async {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition() && Date() < deadline {
        try? await Task.sleep(nanoseconds: 1_000_000)
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
