@preconcurrency import AVFoundation
import AudioToolbox
import CoreAudio
import Foundation

/// Thread-safe live input level, written from the audio tap thread and read
/// by the recording panel for its waveform visualization.
final class AudioLevelMeter: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Float = 0

    func update(_ newValue: Float) {
        lock.lock()
        // Fast attack, slower release: peaks land instantly so speech reads
        // as movement, while the falloff keeps the waveform from flickering.
        value = newValue > value ? newValue : value * 0.72 + newValue * 0.28
        lock.unlock()
    }

    var level: Float {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func reset() {
        lock.lock()
        value = 0
        lock.unlock()
    }
}

@MainActor
final class SystemAudioRecorder: AudioRecording {
    let levelMeter = AudioLevelMeter()
    private let engine = AVAudioEngine()
    private let storage = SampleStorage()
    private let preferences: MicrophonePreferences?
    private var tapInstalled = false
    private var isCapturing = false
    private var activeCaptureDeviceID: AudioDeviceID?
    private var configurationChangeObserver: NSObjectProtocol?

    init(preferences: MicrophonePreferences? = nil) {
        self.preferences = preferences
        // Fires when the pinned device vanishes mid-recording (mic unplugged):
        // re-resolve — which lands on the backup mic — and keep capturing.
        configurationChangeObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { @Sendable [weak self] _ in
            Task { @MainActor in self?.handleConfigurationChange() }
        }
    }

    deinit {
        if let configurationChangeObserver {
            NotificationCenter.default.removeObserver(configurationChangeObserver)
        }
    }

    func start() throws {
        cancel()
        storage.reset()
        levelMeter.reset()
        try configureAndStartEngine()
        isCapturing = true
    }

    private func configureAndStartEngine() throws {
        let input = engine.inputNode
        pinCaptureDevice(on: input)
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
        // The tap block runs on AVFoundation's realtime messenger thread.
        // It must be @Sendable with Sendable-only captures: a plain closure
        // formed in this @MainActor method is inferred MainActor-isolated and
        // the Swift 6 runtime traps (EXC_BREAKPOINT) on the audio thread.
        let pipeline = TapConversionPipeline(
            converter: converter,
            targetFormat: targetFormat,
            sourceSampleRate: sourceFormat.sampleRate,
            storage: storage,
            levelMeter: levelMeter,
            gain: preferences?.boost.gain ?? 1
        )
        input.installTap(onBus: 0, bufferSize: 2_048, format: sourceFormat) { @Sendable buffer, _ in
            pipeline.process(buffer)
        }
        tapInstalled = true
        engine.prepare()
        do { try engine.start() } catch {
            // Tear down without touching storage: on a mid-recording restart
            // the samples captured before the disconnect must survive.
            tearDown()
            throw DictationFailure(message: "Could not start the microphone.", recovery: error.localizedDescription)
        }
    }

    /// Points the input AUHAL at the resolved capture device (preferred mic,
    /// else backup, else system default). Without preferences, or if the HAL
    /// refuses, the engine keeps following the system default input.
    private func pinCaptureDevice(on input: AVAudioInputNode) {
        guard let preferences,
              let device = preferences.resolveCaptureDevice(),
              let unit = input.audioUnit else {
            activeCaptureDeviceID = nil
            return
        }
        var deviceID = device.id
        let status = AudioUnitSetProperty(
            unit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &deviceID,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
        activeCaptureDeviceID = status == noErr ? device.id : nil
    }

    private func handleConfigurationChange() {
        guard isCapturing else { return }
        // Our own device pinning also raises this notification — ignore it
        // when the engine is still running on the device we just resolved.
        if engine.isRunning,
           let activeCaptureDeviceID,
           preferences?.resolveCaptureDevice()?.id == activeCaptureDeviceID {
            return
        }
        tearDown()
        // Captured samples stay in storage; if the backup mic also fails the
        // user still gets everything recorded up to the disconnect.
        try? configureAndStartEngine()
    }

    func stop() throws -> RecordedAudio {
        isCapturing = false
        tearDown()
        let samples = storage.snapshot()
        guard !samples.isEmpty else {
            throw DictationFailure(message: "No audio was captured.", recovery: "Hold the configured push-to-talk key and speak before releasing it.")
        }
        return RecordedAudio(samples: samples, sampleRate: 16_000)
    }

    func cancel() {
        isCapturing = false
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
    private let gain: Float

    init(
        converter: AVAudioConverter,
        targetFormat: AVAudioFormat,
        sourceSampleRate: Double,
        storage: SampleStorage,
        levelMeter: AudioLevelMeter,
        gain: Float
    ) {
        self.converter = converter
        self.targetFormat = targetFormat
        self.sourceSampleRate = sourceSampleRate
        self.storage = storage
        self.levelMeter = levelMeter
        self.gain = gain
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
        if gain != 1 {
            // Mic boost: clamp so an 8× hot signal clips instead of wrapping.
            for index in 0..<count {
                channel[index] = max(-1, min(1, channel[index] * gain))
            }
        }
        storage.append(channel, count: count)
        guard count > 0 else { return }
        var sum: Float = 0
        for index in 0..<count { sum += channel[index] * channel[index] }
        // Perceptual mapping: linear RMS leaves normal speech (~0.01–0.1)
        // near the floor, so the bars barely move. -50…-8 dBFS onto 0…1
        // makes quiet speech visible and loud speech peg the bars.
        let rms = (sum / Float(count)).squareRoot()
        let decibels = 20 * log10(max(rms, .leastNormalMagnitude))
        levelMeter.update(min(1, max(0, (decibels + 50) / 42)))
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
