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

    var isEnglishOnly: Bool { variant.hasSuffix(".en") }
    var languageLabel: String {
        isEnglishOnly ? "English only" : "Multilingual · Vietnamese supported"
    }
    var formattedFileSize: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }

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

enum PublishedModelCatalog {
    static let models: [ModelDescriptor] = [
        model(
            id: "whisper-tiny", name: "Whisper Tiny", variant: "tiny",
            bytes: 77_691_713, sha256: "be07e048e1e599ad46341c8d2a135645097a538221678b7acdd1b1919c6e1b21"
        ),
        model(
            id: "whisper-base", name: "Whisper Base", variant: "base",
            bytes: 147_951_465, sha256: "60ed5bc3dd14eea856493d334349b405782ddcaf0028d4b5df4088345fba2efe"
        ),
        model(
            id: "whisper-small", name: "Whisper Small", variant: "small",
            bytes: 487_601_967, sha256: "1be3a9b2063867b937e64e2ec7483364a79917e157fa98c5d94b5c1fffea987b"
        ),
        model(
            id: "whisper-tiny-en", name: "Whisper Tiny English", variant: "tiny.en",
            bytes: 77_704_715, sha256: "921e4cf8686fdd993dcd081a5da5b6c365bfde1162e72b08d75ac75289920b1f"
        ),
        model(
            id: "whisper-base-en", name: "Whisper Base English", variant: "base.en",
            bytes: 147_964_211, sha256: "a03779c86df3323075f5e796cb2ce5029f00ec8869eee3fdfb897afe36c6d002"
        ),
        model(
            id: "whisper-small-en", name: "Whisper Small English", variant: "small.en",
            bytes: 487_614_201, sha256: "c6138d6d58ecc8322097e0f987c32f1be8bb0a18532a3f88f734d1bbf9c41e5d"
        )
    ]

    private static func model(
        id: String, name: String, variant: String, bytes: Int64, sha256: String
    ) -> ModelDescriptor {
        ModelDescriptor(
            id: id,
            displayName: name,
            family: "whisper",
            runtime: "whisper.cpp",
            variant: variant,
            quantization: nil,
            downloadURL: URL(
                string: "https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-\(variant).bin"
            )!,
            fileName: "ggml-\(variant).bin",
            fileSize: bytes,
            sha256: sha256
        )
    }
}

struct InstalledModel: Identifiable, Codable, Equatable, Sendable {
    let id: String
    let displayName: String
    let runtime: String
    let fileName: String
    let installedAt: Date
    let isEnglishOnly: Bool

    init(
        id: String,
        displayName: String,
        runtime: String,
        fileName: String,
        installedAt: Date,
        isEnglishOnly: Bool
    ) {
        self.id = id
        self.displayName = displayName
        self.runtime = runtime
        self.fileName = fileName
        self.installedAt = installedAt
        self.isEnglishOnly = isEnglishOnly
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        displayName = try container.decode(String.self, forKey: .displayName)
        runtime = try container.decode(String.self, forKey: .runtime)
        fileName = try container.decode(String.self, forKey: .fileName)
        installedAt = try container.decode(Date.self, forKey: .installedAt)
        // Registries written before this field existed derive it from the
        // catalog file-naming convention they were installed under.
        isEnglishOnly = try container.decodeIfPresent(Bool.self, forKey: .isEnglishOnly)
            ?? fileName.contains(".en.")
    }
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

/// A registry paired with a monotonically increasing storage version.
/// Mutations resolve against the storage actor's own registry (never a
/// caller-supplied snapshot), and consumers apply results only when the
/// version is not older than what they already show — so two concurrent
/// installs can no longer clobber each other's entries.
struct RegistrySnapshot: Sendable, Equatable {
    let registry: ModelRegistry
    let version: UInt64
}

protocol ModelStoring: Sendable {
    func loadRegistry() async -> RegistrySnapshot
    func install(source: URL, descriptor: ModelDescriptor) async throws -> RegistrySnapshot
    func selectActive(_ id: String?) async throws -> RegistrySnapshot
    func delete(_ model: InstalledModel) async throws -> RegistrySnapshot
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
    private var cachedRegistry: ModelRegistry?
    private var registryVersion: UInt64 = 0
    private var registryURL: URL { root.appendingPathComponent("registry.json") }

    init(root: URL, registryWriter: any ModelRegistryWriting = AtomicModelRegistryWriter()) {
        self.root = root
        self.registryWriter = registryWriter
        fileManager = FileManager()
    }

    func loadRegistry() -> RegistrySnapshot {
        RegistrySnapshot(registry: currentRegistry(), version: registryVersion)
    }

    private func currentRegistry() -> ModelRegistry {
        if let cachedRegistry { return cachedRegistry }
        let loaded = readRegistryFromDisk()
        cachedRegistry = loaded
        return loaded
    }

    private func readRegistryFromDisk() -> ModelRegistry {
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

    func selectActive(_ id: String?) throws -> RegistrySnapshot {
        let registry = currentRegistry()
        if let id {
            guard registry.installed.contains(where: { $0.id == id }) else {
                throw DictationFailure(message: "That model is not installed.", recovery: "Install it before selecting it.")
            }
        }
        try persist(ModelRegistry(installed: registry.installed, activeModelID: id))
        return loadRegistry()
    }

    func install(source: URL, descriptor: ModelDescriptor) throws -> RegistrySnapshot {
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
                installedAt: Date(),
                isEnglishOnly: descriptor.isEnglishOnly
            )
            let registry = currentRegistry()
            var nextInstalled = registry.installed.filter { $0.id != model.id }
            nextInstalled.append(model)
            try persist(ModelRegistry(installed: nextInstalled, activeModelID: registry.activeModelID))
            if backedUp { try? fileManager.removeItem(at: backup) }
            return loadRegistry()
        } catch {
            try? fileManager.removeItem(at: staging)
            if promoted { try? fileManager.removeItem(at: finalDirectory) }
            if backedUp { try? fileManager.moveItem(at: backup, to: finalDirectory) }
            throw error
        }
    }

    private func persist(_ registry: ModelRegistry) throws {
        try Task.checkCancellation()
        try fileManager.createDirectory(at: root, withIntermediateDirectories: true)
        try registryWriter.write(registry, to: registryURL)
        cachedRegistry = registry
        registryVersion += 1
    }

    func delete(_ model: InstalledModel) throws -> RegistrySnapshot {
        guard ModelDescriptor.isSafePathComponent(model.id), ModelDescriptor.isSafePathComponent(model.fileName) else {
            throw DictationFailure(message: "Model path is invalid.", recovery: "The model registry entry cannot be deleted safely.")
        }
        try Task.checkCancellation()
        let registry = currentRegistry()
        let next = ModelRegistry(
            installed: registry.installed.filter { $0.id != model.id },
            activeModelID: registry.activeModelID == model.id ? nil : registry.activeModelID
        )
        let directory = root.appendingPathComponent(model.id, isDirectory: true)
        let backup = root.appendingPathComponent(".\(model.id).delete.\(UUID().uuidString)", isDirectory: true)
        let exists = fileManager.fileExists(atPath: directory.path)
        if exists { try fileManager.moveItem(at: directory, to: backup) }
        do {
            try persist(next)
            if exists { try? fileManager.removeItem(at: backup) }
        } catch {
            if exists {
                try? fileManager.removeItem(at: directory)
                try? fileManager.moveItem(at: backup, to: directory)
            }
            throw error
        }
        return loadRegistry()
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
    @Published private(set) var catalog: [ModelDescriptor]
    @Published private(set) var installed: [InstalledModel] = []
    @Published private(set) var activeModelID: String?
    @Published private(set) var downloadProgress: [String: Double] = [:]
    @Published private(set) var downloadingModelIDs: Set<String> = []
    @Published private(set) var installingModelIDs: Set<String> = []
    @Published private(set) var lastError: String?

    var activeModel: InstalledModel? { installed.first { $0.id == activeModelID } }
    var activeModelURL: URL? {
        guard let activeModel else { return nil }
        return root
            .appendingPathComponent(activeModel.id, isDirectory: true)
            .appendingPathComponent(activeModel.fileName)
    }
    var catalogMessage: String { "Official whisper.cpp model artifacts from Hugging Face." }

    var localRuntimeUnloader: (() -> Void)?

    private let root: URL
    private let downloader: ModelDownloading
    private let storage: any ModelStoring
    private let initialRegistryTask: Task<RegistrySnapshot, Never>
    private var registryLoaded = false
    private var appliedRegistryVersion: UInt64 = 0
    private var downloadTasks: [String: Task<Void, Never>] = [:]

    init(
        root: URL? = nil,
        downloader: ModelDownloading = URLSessionModelDownloader(),
        storage: (any ModelStoring)? = nil
    ) {
        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let resolvedRoot = root ?? applicationSupport.appendingPathComponent("WinterVoice/Models", isDirectory: true)
        self.root = resolvedRoot
        self.downloader = downloader
        catalog = PublishedModelCatalog.models
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
                        let fraction = min(1, max(0, Double(received) / Double(expected)))
                        // Publish at ~1% granularity: every raw URLSession tick
                        // would re-render each view observing AppShellPresenter.
                        let previous = downloadProgress[descriptor.id] ?? 0
                        if downloadProgress[descriptor.id] == nil || fraction >= 1 || fraction - previous >= 0.01 {
                            downloadProgress[descriptor.id] = fraction
                        }
                    case .downloaded(let source):
                        downloadingModelIDs.remove(descriptor.id)
                        downloadProgress[descriptor.id] = nil
                        installingModelIDs.insert(descriptor.id)
                        defer { Task { await storage.removeTemporary(source) } }
                        apply(try await storage.install(source: source, descriptor: descriptor))
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

    func select(_ id: String) async {
        await ensureRegistryLoaded()
        guard ModelDescriptor.isSafePathComponent(id), installed.contains(where: { $0.id == id }) else {
            lastError = "That model is not installed."
            return
        }
        let previousActive = activeModelID
        do {
            apply(try await storage.selectActive(id))
            lastError = nil
            // The runtime may hold the previously selected model in memory;
            // re-selecting the same model must not drop a hot context.
            if previousActive != id { localRuntimeUnloader?() }
        } catch {
            lastError = (error as? DictationFailure)?.message ?? "Could not select the model."
        }
    }

    func delete(_ model: InstalledModel) async {
        await ensureRegistryLoaded()
        let wasActive = activeModelID == model.id
        do {
            apply(try await storage.delete(model))
            lastError = nil
            if wasActive { localRuntimeUnloader?() }
        } catch {
            lastError = (error as? DictationFailure)?.message ?? "Could not delete the model."
        }
    }

    func installDownloadedFile(_ source: URL, descriptor: ModelDescriptor) async throws {
        await ensureRegistryLoaded()
        apply(try await storage.install(source: source, descriptor: descriptor))
        lastError = nil
    }

    private func ensureRegistryLoaded() async {
        guard !registryLoaded else { return }
        let snapshot = await initialRegistryTask.value
        guard !registryLoaded else { return }
        apply(snapshot)
    }

    private func apply(_ snapshot: RegistrySnapshot) {
        // Ignore results that raced behind a newer mutation.
        guard !registryLoaded || snapshot.version >= appliedRegistryVersion else { return }
        installed = snapshot.registry.installed
        activeModelID = snapshot.registry.activeModelID
        appliedRegistryVersion = snapshot.version
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
