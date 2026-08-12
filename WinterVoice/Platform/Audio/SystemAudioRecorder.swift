@preconcurrency import AVFoundation
import Foundation

@MainActor
final class SystemAudioRecorder: AudioRecording {
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
        input.installTap(onBus: 0, bufferSize: 2_048, format: sourceFormat) { [storage] buffer, _ in
            let capacity = AVAudioFrameCount(Double(buffer.frameLength) * 16_000 / sourceFormat.sampleRate) + 1
            guard let converted = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }
            let supplier = AudioBufferSupplier(buffer: buffer)
            var conversionError: NSError?
            converter.convert(to: converted, error: &conversionError) { _, status in
                supplier.take(status: status)
            }
            guard conversionError == nil, let channel = converted.floatChannelData?[0] else { return }
            storage.append(channel, count: Int(converted.frameLength))
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
            throw DictationFailure(message: "No audio was captured.", recovery: "Hold Right Option and speak before releasing it.")
        }
        return RecordedAudio(samples: samples, sampleRate: 16_000)
    }

    func cancel() {
        tearDown()
        storage.reset()
    }

    private func tearDown() {
        if engine.isRunning { engine.stop() }
        if tapInstalled {
            engine.inputNode.removeTap(onBus: 0)
            tapInstalled = false
        }
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
