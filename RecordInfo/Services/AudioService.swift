import AVFoundation
import Foundation

// Thread-safe audio buffer and metrics, used from audio tap callback
final class AudioBufferStorage: @unchecked Sendable {
    private let lock = NSLock()
    private var circularBuffer: [Float] = []
    private var writeIndex: Int = 0
    private var filled: Bool = false
    private let capacity: Int

    let noiseGateThreshold: Float
    let normalizationTarget: Float
    let gapAmplitudeThreshold: Float
    let gapSilenceThreshold: Double

    // Metrics updated from audio thread, read from main thread
    private var _currentLevel: Float = 0.0
    private var _gapDetected: Bool = false
    private var _gapSilenceDuration: Double = 0.0

    init(
        capacity: Int,
        noiseGateThreshold: Float,
        normalizationTarget: Float,
        gapAmplitudeThreshold: Float = 0.02,
        gapSilenceThreshold: Double = 2.0
    ) {
        self.capacity = capacity
        self.noiseGateThreshold = noiseGateThreshold
        self.normalizationTarget = normalizationTarget
        self.gapAmplitudeThreshold = gapAmplitudeThreshold
        self.gapSilenceThreshold = gapSilenceThreshold
        self.circularBuffer = [Float](repeating: 0, count: capacity)
    }

    var currentLevel: Float {
        lock.lock()
        defer { lock.unlock() }
        return _currentLevel
    }

    var gapDetected: Bool {
        lock.lock()
        defer { lock.unlock() }
        return _gapDetected
    }

    func write(_ samples: [Float]) {
        lock.lock()
        defer { lock.unlock() }
        for sample in samples {
            circularBuffer[writeIndex] = sample
            writeIndex += 1
            if writeIndex >= capacity {
                writeIndex = 0
                filled = true
            }
        }
    }

    func readAll() -> [Float] {
        lock.lock()
        defer { lock.unlock() }
        if filled {
            let part1 = Array(circularBuffer[writeIndex...])
            let part2 = Array(circularBuffer[..<writeIndex])
            return part1 + part2
        } else {
            return Array(circularBuffer[..<writeIndex])
        }
    }

    var fillPercentage: Double {
        lock.lock()
        defer { lock.unlock() }
        guard capacity > 0 else { return 0 }
        if filled { return 1.0 }
        return Double(writeIndex) / Double(capacity)
    }

    func updateMetrics(rms: Float, frameDuration: Double) {
        lock.lock()
        defer { lock.unlock() }
        _currentLevel = rms
        let isQuiet = rms < gapAmplitudeThreshold
        if isQuiet {
            _gapSilenceDuration += frameDuration
            if _gapSilenceDuration >= gapSilenceThreshold {
                _gapDetected = true
            }
        } else {
            if _gapDetected { _gapDetected = false }
            _gapSilenceDuration = 0.0
        }
    }

    func applyNoiseGate(_ samples: [Float]) -> [Float] {
        let threshold = noiseGateThreshold
        return samples.map { abs($0) < threshold ? 0 : $0 }
    }

    func normalizeSamples(_ samples: [Float]) -> [Float] {
        guard !samples.isEmpty else { return [] }
        let peak = samples.map { abs($0) }.max() ?? 0
        guard peak > 0 else { return samples }
        let scale = normalizationTarget / peak
        return samples.map { $0 * scale }
    }
}

@Observable
@MainActor
final class AudioService: AudioServiceProtocol {

    // MARK: - Published State

    private(set) var currentLevel: Float = 0.0
    private(set) var isListening: Bool = false
    private(set) var gapDetected: Bool = false

    var isRunning: Bool { isListening }

    var bufferFillPercentage: Double {
        bufferStorage?.fillPercentage ?? 0
    }

    // MARK: - Configuration

    var bufferLengthSeconds: Double = 20.0
    var sampleRate: Double = 11025.0
    var noiseGateThreshold: Float = 0.01
    var normalizationTarget: Float = 0.9

    // MARK: - Private State

    private var audioEngine: AVAudioEngine?
    private var bufferStorage: AudioBufferStorage?
    private var levelPollingTask: Task<Void, Never>?

    private var maxBufferSamples: Int {
        Int(bufferLengthSeconds * sampleRate)
    }

    // MARK: - Public Methods

    func start() async throws {
        guard !isListening else { return }

        // Request microphone permission before accessing audio hardware
        let granted = await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .audio) { allowed in
                continuation.resume(returning: allowed)
            }
        }
        guard granted else {
            throw AudioServiceError.microphonePermissionDenied
        }

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        let targetSampleRate = sampleRate

        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw AudioServiceError.formatCreationFailed
        }

        guard let converter = AVAudioConverter(
            from: inputFormat, to: outputFormat
        ) else {
            throw AudioServiceError.converterCreationFailed
        }

        let storage = AudioBufferStorage(
            capacity: maxBufferSamples,
            noiseGateThreshold: noiseGateThreshold,
            normalizationTarget: normalizationTarget
        )
        bufferStorage = storage

        // Tap closure captures ONLY Sendable values — no self
        inputNode.installTap(
            onBus: 0,
            bufferSize: 4096,
            format: inputFormat
        ) { buffer, _ in
            AudioService.processBuffer(
                buffer,
                converter: converter,
                outputFormat: outputFormat,
                storage: storage
            )
        }

        engine.prepare()
        try engine.start()

        audioEngine = engine
        isListening = true
        startLevelPolling(from: storage)
    }

    func stop() {
        levelPollingTask?.cancel()
        levelPollingTask = nil
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        bufferStorage = nil
        isListening = false
        currentLevel = 0.0
        gapDetected = false
    }

    func getBufferData() -> Data {
        guard let storage = bufferStorage else { return Data() }
        let samples = storage.readAll()
        let normalized = storage.normalizeSamples(samples)
        return AudioService.convertToPCM16Data(normalized)
    }

    // MARK: - Level Polling (reads from thread-safe storage)

    private func startLevelPolling(from storage: AudioBufferStorage) {
        levelPollingTask?.cancel()
        levelPollingTask = Task { [weak self] in
            while !Task.isCancelled {
                do { try await Task.sleep(for: .milliseconds(50)) } catch { return }
                guard let self, !Task.isCancelled else { return }
                self.currentLevel = storage.currentLevel
                self.gapDetected = storage.gapDetected
            }
        }
    }

    // MARK: - Static Audio Processing (no actor isolation)

    private static func processBuffer(
        _ buffer: AVAudioPCMBuffer,
        converter: AVAudioConverter,
        outputFormat: AVAudioFormat,
        storage: AudioBufferStorage
    ) {
        let frameCount = AVAudioFrameCount(
            Double(buffer.frameLength) * outputFormat.sampleRate
            / buffer.format.sampleRate
        )
        guard frameCount > 0 else { return }

        guard let converted = AVAudioPCMBuffer(
            pcmFormat: outputFormat, frameCapacity: frameCount
        ) else { return }

        var error: NSError?
        var consumed = false
        converter.convert(to: converted, error: &error) { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return buffer
        }
        if error != nil { return }

        guard let channelData = converted.floatChannelData?[0] else { return }
        let count = Int(converted.frameLength)

        var samples = [Float](repeating: 0, count: count)
        for idx in 0..<count { samples[idx] = channelData[idx] }

        let rms = calculateRMS(samples)
        let gated = storage.applyNoiseGate(samples)
        storage.write(gated)

        let frameDuration = Double(count) / outputFormat.sampleRate
        storage.updateMetrics(rms: rms, frameDuration: frameDuration)
    }

    private static func calculateRMS(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        let sum = samples.reduce(Float(0)) { $0 + $1 * $1 }
        return sqrt(sum / Float(samples.count))
    }

    private static func convertToPCM16Data(_ samples: [Float]) -> Data {
        var data = Data(capacity: samples.count * 2)
        for sample in samples {
            let clamped = Swift.max(-1.0, Swift.min(1.0, sample))
            var int16 = Int16(clamped * Float(Int16.max))
            withUnsafeBytes(of: &int16) { data.append(contentsOf: $0) }
        }
        return data
    }

    // MARK: - Errors

    enum AudioServiceError: LocalizedError {
        case microphonePermissionDenied
        case formatCreationFailed
        case converterCreationFailed

        var errorDescription: String? {
            switch self {
            case .microphonePermissionDenied:
                return "Microphone access denied. Grant permission in System Settings > Privacy & Security > Microphone."
            case .formatCreationFailed:
                return "Failed to create the target audio format."
            case .converterCreationFailed:
                return "Failed to create the audio format converter."
            }
        }
    }
}
