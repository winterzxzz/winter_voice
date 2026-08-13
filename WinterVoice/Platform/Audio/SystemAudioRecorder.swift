@preconcurrency import AVFoundation
import Foundation

/// Thread-safe live input level, written from the audio tap thread and read
/// by the recording panel for its waveform visualization.
final class AudioLevelMeter: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Float = 0

    func update(_ newValue: Float) {
        lock.lock()
        value = newValue
        lock.unlock()
    }

    var level: Float {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func reset() { update(0) }
}

@MainActor
final class SystemAudioRecorder: AudioRecording {
    let levelMeter = AudioLevelMeter()
    private let engine = AVAudioEngine()
    private let storage = SampleStorage()
    private var tapInstalled = false

    func start() throws {
        cancel()
        let input = engine.inputNode
        let sourceFormat = input.outputFormat(forBus: 0)
        guard sourceFormat.sampleRate > 0, sourceFormat.channelCount > 0,
              let targetFormat = AVAudioFormat(
                commonFormat: .pcmFormatFloat32,
                sampleRate: 16_000,
                channels: 1,
                interleaved: false
              ),
              let converter = AVAudioConverter(from: sourceFormat, to: targetFormat) else {
            throw DictationFailure(message: "No microphone input is available.", recovery: "Connect or select a microphone and try again.")
        }
        storage.reset()
        levelMeter.reset()
        // The tap block runs on AVFoundation's realtime messenger thread.
        // It must be @Sendable with Sendable-only captures: a plain closure
        // formed in this @MainActor method is inferred MainActor-isolated and
        // the Swift 6 runtime traps (EXC_BREAKPOINT) on the audio thread.
        let pipeline = TapConversionPipeline(
            converter: converter,
            targetFormat: targetFormat,
            sourceSampleRate: sourceFormat.sampleRate,
            storage: storage,
            levelMeter: levelMeter
        )
        input.installTap(onBus: 0, bufferSize: 2_048, format: sourceFormat) { @Sendable buffer, _ in
            pipeline.process(buffer)
        }
        tapInstalled = true
        engine.prepare()
        do { try engine.start() } catch {
            cancel()
            throw DictationFailure(message: "Could not start the microphone.", recovery: error.localizedDescription)
        }
    }

    func stop() throws -> RecordedAudio {
        tearDown()
        let samples = storage.snapshot()
        guard !samples.isEmpty else {
            throw DictationFailure(message: "No audio was captured.", recovery: "Hold the configured push-to-talk key and speak before releasing it.")
        }
        return RecordedAudio(samples: samples, sampleRate: 16_000)
    }

    func cancel() {
        tearDown()
        storage.reset()
        levelMeter.reset()
    }

    private func tearDown() {
        if engine.isRunning { engine.stop() }
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
    }
}

private final class TapConversionPipeline: @unchecked Sendable {
    private let converter: AVAudioConverter
    private let targetFormat: AVAudioFormat
    private let sourceSampleRate: Double
    private let storage: SampleStorage
    private let levelMeter: AudioLevelMeter

    init(
        converter: AVAudioConverter,
        targetFormat: AVAudioFormat,
        sourceSampleRate: Double,
        storage: SampleStorage,
        levelMeter: AudioLevelMeter
    ) {
        self.converter = converter
        self.targetFormat = targetFormat
        self.sourceSampleRate = sourceSampleRate
        self.storage = storage
        self.levelMeter = levelMeter
    }

    func process(_ buffer: AVAudioPCMBuffer) {
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * 16_000 / sourceSampleRate) + 1
        guard let converted = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }
        let supplier = AudioBufferSupplier(buffer: buffer)
        var conversionError: NSError?
        converter.convert(to: converted, error: &conversionError) { _, status in
            supplier.take(status: status)
        }
        guard conversionError == nil, let channel = converted.floatChannelData?[0] else { return }
        let count = Int(converted.frameLength)
        storage.append(channel, count: count)
        guard count > 0 else { return }
        var sum: Float = 0
        for index in 0..<count { sum += channel[index] * channel[index] }
        levelMeter.update(min(1, (sum / Float(count)).squareRoot() * 6))
    }
}

private final class AudioBufferSupplier: @unchecked Sendable {
    private let lock = NSLock()
    private var buffer: AVAudioPCMBuffer?

    init(buffer: AVAudioPCMBuffer) { self.buffer = buffer }

    func take(status: UnsafeMutablePointer<AVAudioConverterInputStatus>) -> AVAudioBuffer? {
        lock.lock()
        defer { lock.unlock() }
        guard let buffer else {
            status.pointee = .noDataNow
            return nil
        }
        self.buffer = nil
        status.pointee = .haveData
        return buffer
    }
}

private final class SampleStorage: @unchecked Sendable {
    private let lock = NSLock()
    private var samples: [Float] = []

    func append(_ pointer: UnsafePointer<Float>, count: Int) {
        lock.lock()
        samples.append(contentsOf: UnsafeBufferPointer(start: pointer, count: count))
        lock.unlock()
    }

    func snapshot() -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        return samples
    }

    func reset() {
        lock.lock()
        samples.removeAll(keepingCapacity: true)
        lock.unlock()
    }
}
