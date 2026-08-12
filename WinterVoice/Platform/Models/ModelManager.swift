import Combine
import CryptoKit
import Foundation

struct ModelDescriptor: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let displayName: String
    let family: String
    let runtime: String
    let variant: String
    let quantization: String?
    let downloadURL: URL
    let fileName: String
    let fileSize: Int64
    let sha256: String?

    func validateForDownload() throws {
        guard downloadURL.scheme?.lowercased() == "https", downloadURL.host != nil else {
            throw DictationFailure(message: "Model download URL is not secure.", recovery: "Published model downloads must use HTTPS.")
        }
        guard Self.isSafePathComponent(id), Self.isSafePathComponent(fileName) else {
            throw DictationFailure(message: "Model descriptor path is invalid.", recovery: "Use safe model and file identifiers without path separators.")
        }
        guard let sha256, sha256.range(of: "^[0-9a-fA-F]{64}$", options: .regularExpression) != nil else {
            throw DictationFailure(message: "Model checksum is missing or invalid.", recovery: "Published models require a 64-character SHA-256 checksum.")
        }
    }

    static func isSafePathComponent(_ value: String) -> Bool {
        !value.isEmpty && value != "." && value != ".."
            && !value.contains("/") && !value.contains("\\")
            && (value as NSString).lastPathComponent == value
    }
}

struct InstalledModel: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let displayName: String
    let runtime: String
    let fileName: String
    let installedAt: Date
}

struct ModelRegistry: Codable, Equatable, Sendable {
    var installed: [InstalledModel]
    var activeModelID: String?

    static let empty = ModelRegistry(installed: [], activeModelID: nil)
}

enum ModelDownloadEvent: Sendable {
    case progress(received: Int64, expected: Int64)
    case downloaded(URL)
}

protocol ModelDownloading: AnyObject {
    func events(for descriptor: ModelDescriptor) -> AsyncThrowingStream<ModelDownloadEvent, Error>
}

final class URLSessionModelDownloader: NSObject, ModelDownloading, URLSessionDownloadDelegate, @unchecked Sendable {
    private struct Context {
        let continuation: AsyncThrowingStream<ModelDownloadEvent, Error>.Continuation
    }
    private let lock = NSLock()
    private var contexts: [Int: Context] = [:]
    private lazy var session = URLSession(configuration: .default, delegate: self, delegateQueue: nil)

    func events(for descriptor: ModelDescriptor) -> AsyncThrowingStream<ModelDownloadEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = session.downloadTask(with: descriptor.downloadURL)
            lock.withLock { contexts[task.taskIdentifier] = Context(continuation: continuation) }
            continuation.onTermination = { [weak task] _ in task?.cancel() }
            task.resume()
        }
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        lock.withLock { contexts[downloadTask.taskIdentifier] }?.continuation
            .yield(.progress(received: totalBytesWritten, expected: totalBytesExpectedToWrite))
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        guard let context = lock.withLock({ contexts[downloadTask.taskIdentifier] }) else { return }
        do {
            guard let response = downloadTask.response as? HTTPURLResponse, 200..<300 ~= response.statusCode else {
                throw DictationFailure(message: "Model download failed.", recovery: "The catalog host did not return the model file.")
            }
            let retained = FileManager.default.temporaryDirectory
                .appendingPathComponent("WinterVoiceModel.\(UUID().uuidString)")
            try FileManager.default.moveItem(at: location, to: retained)
            context.continuation.yield(.downloaded(retained))
        } catch {
            context.continuation.finish(throwing: error)
            lock.withLock { contexts[downloadTask.taskIdentifier] = nil }
        }
    }

    func urlSession(_ session: URLSession, task: URLSessionTask, didCompleteWithError error: Error?) {
        guard let context = lock.withLock({ contexts.removeValue(forKey: task.taskIdentifier) }) else { return }
        if let error, Self.isCancellation(error) { context.continuation.finish(throwing: CancellationError()) }
        else if let error { context.continuation.finish(throwing: error) }
        else { context.continuation.finish() }
    }

    private static func isCancellation(_ error: Error) -> Bool {
        let value = error as NSError
        return error is CancellationError || (value.domain == NSURLErrorDomain && value.code == NSURLErrorCancelled)
    }
}

protocol ModelStoring: Sendable {
    func loadRegistry() async -> ModelRegistry
    func install(source: URL, descriptor: ModelDescriptor, registry: ModelRegistry) async throws -> ModelRegistry
    func persist(_ registry: ModelRegistry) async throws
    func delete(_ model: InstalledModel, registry: ModelRegistry) async throws
    func removeTemporary(_ url: URL) async
}

protocol ModelRegistryWriting: Sendable {
    func write(_ registry: ModelRegistry, to url: URL) throws
}

struct AtomicModelRegistryWriter: ModelRegistryWriting {
    func write(_ registry: ModelRegistry, to url: URL) throws {
        try JSONEncoder().encode(registry).write(to: url, options: .atomic)
    }
}

actor DiskModelStorage: ModelStoring {
    private let fileManager: FileManager
    private let root: URL
    private let registryWriter: any ModelRegistryWriting
    private var registryURL: URL { root.appendingPathComponent("registry.json") }

    init(root: URL, registryWriter: any ModelRegistryWriting = AtomicModelRegistryWriter()) {
        self.root = root
        self.registryWriter = registryWriter
        fileManager = FileManager()
    }

    func loadRegistry() -> ModelRegistry {
        guard let data = try? Data(contentsOf: registryURL),
              let decoded = try? JSONDecoder().decode(ModelRegistry.self, from: data) else { return .empty }
        let installed = decoded.installed.filter {
            ModelDescriptor.isSafePathComponent($0.id) && ModelDescriptor.isSafePathComponent($0.fileName)
        }
        return ModelRegistry(
            installed: installed,
            activeModelID: installed.contains(where: { $0.id == decoded.activeModelID }) ? decoded.activeModelID : nil
        )
    }

    func install(source: URL, descriptor: ModelDescriptor, registry: ModelRegistry) throws -> ModelRegistry {
        try descriptor.validateForDownload()
        try Task.checkCancellation()
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        let finalDirectory = root.appendingPathComponent(descriptor.id, isDirectory: true)
        let staging = root.appendingPathComponent(".\(descriptor.id).\(UUID().uuidString)", isDirectory: true)
        let backup = root.appendingPathComponent(".\(descriptor.id).backup.\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: staging, withIntermediateDirectories: false)
        var promoted = false
        var backedUp = false
        do {
            let stagedModel = staging.appendingPathComponent(descriptor.fileName)
            let actual = try copyAndHash(source: source, destination: stagedModel)
            guard actual == descriptor.sha256?.lowercased() else {
                throw DictationFailure(message: "Model verification failed.", recovery: "The downloaded file did not match its published SHA-256 checksum.")
            }
            try Task.checkCancellation()
            try JSONEncoder().encode(descriptor).write(to: staging.appendingPathComponent("metadata.json"), options: .atomic)
            if fileManager.fileExists(atPath: finalDirectory.path) {
                try fileManager.moveItem(at: finalDirectory, to: backup)
                backedUp = true
            }
            try fileManager.moveItem(at: staging, to: finalDirectory)
            promoted = true
            let model = InstalledModel(
                id: descriptor.id,
                displayName: descriptor.displayName,
                runtime: descriptor.runtime,
                fileName: descriptor.fileName,
                installedAt: Date()
            )
            var nextInstalled = registry.installed.filter { $0.id != model.id }
            nextInstalled.append(model)
            let next = ModelRegistry(installed: nextInstalled, activeModelID: registry.activeModelID)
            try persist(next)
            if backedUp { try? fileManager.removeItem(at: backup) }
            return next
        } catch {
            try? fileManager.removeItem(at: staging)
            if promoted { try? fileManager.removeItem(at: finalDirectory) }
            if backedUp { try? fileManager.moveItem(at: backup, to: finalDirectory) }
            throw error
        }
    }

    func persist(_ registry: ModelRegistry) throws {
        try Task.checkCancellation()
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        try registryWriter.write(registry, to: registryURL)
    }

    func delete(_ model: InstalledModel, registry: ModelRegistry) throws {
        guard ModelDescriptor.isSafePathComponent(model.id), ModelDescriptor.isSafePathComponent(model.fileName) else {
            throw DictationFailure(message: "Model path is invalid.", recovery: "The model registry entry cannot be deleted safely.")
        }
        try Task.checkCancellation()
        let directory = root.appendingPathComponent(model.id, isDirectory: true)
        let backup = root.appendingPathComponent(".\(model.id).delete.\(UUID().uuidString)", isDirectory: true)
        let exists = fileManager.fileExists(atPath: directory.path)
        if exists { try fileManager.moveItem(at: directory, to: backup) }
        do {
            try persist(registry)
            if exists { try? fileManager.removeItem(at: backup) }
        } catch {
            if exists {
                try? fileManager.removeItem(at: directory)
                try? fileManager.moveItem(at: backup, to: directory)
            }
            throw error
        }
    }

    func removeTemporary(_ url: URL) {
        try? fileManager.removeItem(at: url)
    }

    private func copyAndHash(source: URL, destination: URL) throws -> String {
        guard fileManager.createFile(atPath: destination.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        let input = try FileHandle(forReadingFrom: source)
        let output = try FileHandle(forWritingTo: destination)
        defer { try? input.close(); try? output.close() }
        var hasher = SHA256()
        while let chunk = try input.read(upToCount: 1_048_576), !chunk.isEmpty {
            try Task.checkCancellation()
            try output.write(contentsOf: chunk)
            hasher.update(data: chunk)
        }
        try output.synchronize()
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

@MainActor
final class ModelManager: ObservableObject {
    @Published private(set) var catalog: [ModelDescriptor] = []
    @Published private(set) var installed: [InstalledModel] = []
    @Published private(set) var activeModelID: String?
    @Published private(set) var downloadProgress: [String: Double] = [:]
    @Published private(set) var downloadingModelIDs: Set<String> = []
    @Published private(set) var installingModelIDs: Set<String> = []
    @Published private(set) var lastError: String?

    var activeModel: InstalledModel? { installed.first { $0.id == activeModelID } }
    var catalogMessage: String { "No supported downloadable model is published yet." }

    private let downloader: ModelDownloading
    private let storage: any ModelStoring
    private let initialRegistryTask: Task<ModelRegistry, Never>
    private var registryLoaded = false
    private var downloadTasks: [String: Task<Void, Never>] = [:]

    init(
        root: URL? = nil,
        downloader: ModelDownloading = URLSessionModelDownloader(),
        storage: (any ModelStoring)? = nil
    ) {
        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let resolvedRoot = root ?? applicationSupport.appendingPathComponent("WinterVoice/Models", isDirectory: true)
        self.downloader = downloader
        let resolvedStorage = storage ?? DiskModelStorage(root: resolvedRoot)
        self.storage = resolvedStorage
        initialRegistryTask = Task { await resolvedStorage.loadRegistry() }
        Task { [weak self] in
            await self?.ensureRegistryLoaded()
        }
    }

    func install(_ descriptor: ModelDescriptor) {
        guard downloadTasks[descriptor.id] == nil else { return }
        do { try descriptor.validateForDownload() } catch {
            lastError = (error as? DictationFailure)?.message ?? "Model descriptor is invalid."
            return
        }
        lastError = nil
        downloadingModelIDs.insert(descriptor.id)
        downloadTasks[descriptor.id] = Task { [weak self] in
            guard let self else { return }
            await ensureRegistryLoaded()
            do {
                for try await event in downloader.events(for: descriptor) {
                    try Task.checkCancellation()
                    switch event {
                    case .progress(let received, let expected):
                        guard expected > 0 else { downloadProgress[descriptor.id] = nil; continue }
                        downloadProgress[descriptor.id] = min(1, max(0, Double(received) / Double(expected)))
                    case .downloaded(let source):
                        downloadingModelIDs.remove(descriptor.id)
                        downloadProgress[descriptor.id] = nil
                        installingModelIDs.insert(descriptor.id)
                        defer { Task { await storage.removeTemporary(source) } }
                        let next = try await storage.install(
                            source: source,
                            descriptor: descriptor,
                            registry: ModelRegistry(installed: installed, activeModelID: activeModelID)
                        )
                        installed = next.installed
                        activeModelID = next.activeModelID
                    }
                }
            } catch {
                if !Self.isCancellation(error) {
                    lastError = (error as? DictationFailure)?.message ?? "Model installation failed."
                }
            }
            downloadProgress[descriptor.id] = nil
            downloadingModelIDs.remove(descriptor.id)
            installingModelIDs.remove(descriptor.id)
            downloadTasks[descriptor.id] = nil
        }
    }

    func cancelInstall(_ id: String) { downloadTasks[id]?.cancel() }

    func select(_ id: String) async throws {
        await ensureRegistryLoaded()
        guard ModelDescriptor.isSafePathComponent(id), installed.contains(where: { $0.id == id }) else {
            throw DictationFailure(message: "That model is not installed.", recovery: "Install it before selecting it.")
        }
        let registry = ModelRegistry(installed: installed, activeModelID: id)
        try await storage.persist(registry)
        activeModelID = id
    }

    func delete(_ model: InstalledModel) async throws {
        await ensureRegistryLoaded()
        let nextInstalled = installed.filter { $0.id != model.id }
        let nextActive = activeModelID == model.id ? nil : activeModelID
        try await storage.delete(model, registry: ModelRegistry(installed: nextInstalled, activeModelID: nextActive))
        installed = nextInstalled
        activeModelID = nextActive
    }

    func installDownloadedFile(_ source: URL, descriptor: ModelDescriptor) async throws {
        await ensureRegistryLoaded()
        let next = try await storage.install(
            source: source,
            descriptor: descriptor,
            registry: ModelRegistry(installed: installed, activeModelID: activeModelID)
        )
        installed = next.installed
        activeModelID = next.activeModelID
        lastError = nil
    }

    private func ensureRegistryLoaded() async {
        guard !registryLoaded else { return }
        let registry = await initialRegistryTask.value
        guard !registryLoaded else { return }
        installed = registry.installed
        activeModelID = registry.activeModelID
        registryLoaded = true
    }

    private static func isCancellation(_ error: Error) -> Bool {
        let value = error as NSError
        return error is CancellationError || (value.domain == NSURLErrorDomain && value.code == NSURLErrorCancelled)
    }
}

private extension NSLock {
    func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock()
        defer { unlock() }
        return try body()
    }
}
