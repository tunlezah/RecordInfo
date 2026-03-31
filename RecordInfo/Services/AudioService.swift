import AVFoundation
import Foundation

// Thread-safe audio buffer storage, used from the audio tap callback thread
final class AudioBufferStorage: @unchecked Sendable {
    private let lock = NSLock()
    private var circularBuffer: [Float] = []
    private var writeIndex: Int = 0
    private var filled: Bool = false
    private let capacity: Int

    let noiseGateThreshold: Float
    let normalizationTarget: Float

    init(capacity: Int, noiseGateThreshold: Float, normalizationTarget: Float) {
        self.capacity = capacity
        self.noiseGateThreshold = noiseGateThreshold
        self.normalizationTarget = normalizationTarget
        self.circularBuffer = [Float](repeating: 0, count: capacity)
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

    private var gapSilenceDuration: Double = 0.0
    private let gapSilenceThreshold: Double = 2.0
    private let gapAmplitudeThreshold: Float = 0.02

    private var maxBufferSamples: Int {
        Int(bufferLengthSeconds * sampleRate)
    }

    // MARK: - Public Methods

    func start() async throws {
        guard !isListening else { return }

        let engine = AVAudioEngine()
        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        let targetSampleRate = sampleRate
        let targetChannels: AVAudioChannelCount = 1

        guard let outputFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: targetSampleRate,
            channels: targetChannels,
            interleaved: false
        ) else {
            throw AudioServiceError.formatCreationFailed
        }

        guard let converter = AVAudioConverter(from: inputFormat, to: outputFormat) else {
            throw AudioServiceError.converterCreationFailed
        }

        let storage = AudioBufferStorage(
            capacity: maxBufferSamples,
            noiseGateThreshold: noiseGateThreshold,
            normalizationTarget: normalizationTarget
        )
        bufferStorage = storage
        let gapThreshold = gapAmplitudeThreshold

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) {
            [weak self] buffer, _ in
            let (rms, isQuiet, frameDuration) = AudioService.processBuffer(
                buffer, converter: converter, outputFormat: outputFormat,
                storage: storage, gapThreshold: gapThreshold
            )

            Task { @MainActor [weak self] in
                guard let self else { return }
                self.currentLevel = rms

                if isQuiet {
                    self.gapSilenceDuration += frameDuration
                    if self.gapSilenceDuration >= self.gapSilenceThreshold {
                        self.gapDetected = true
                    }
                } else {
                    if self.gapDetected {
                        self.gapDetected = false
                    }
                    self.gapSilenceDuration = 0.0
                }
            }
        }

        engine.prepare()
        try engine.start()

        audioEngine = engine
        isListening = true
        gapDetected = false
        gapSilenceDuration = 0.0
    }

    func stop() {
        audioEngine?.inputNode.removeTap(onBus: 0)
        audioEngine?.stop()
        audioEngine = nil
        bufferStorage = nil
        isListening = false
        currentLevel = 0.0
    }

    func getBufferData() -> Data {
        guard let storage = bufferStorage else { return Data() }
        let samples = storage.readAll()
        let normalized = storage.normalizeSamples(samples)
        return AudioService.convertToPCM16Data(normalized)
    }

    func getCurrentLevel() -> Float {
        return currentLevel
    }

    // MARK: - Static Helpers (nonisolated, no actor state)

    private static func processBuffer(
        _ buffer: AVAudioPCMBuffer,
        converter: AVAudioConverter,
        outputFormat: AVAudioFormat,
        storage: AudioBufferStorage,
        gapThreshold: Float
    ) -> (rms: Float, isQuiet: Bool, frameDuration: Double) {
        let frameCount = AVAudioFrameCount(
            Double(buffer.frameLength) * outputFormat.sampleRate / buffer.format.sampleRate
        )
        guard frameCount > 0 else { return (0, true, 0) }

        guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: frameCount) else {
            return (0, true, 0)
        }

        var error: NSError?
        var consumed = false
        converter.convert(to: convertedBuffer, error: &error) { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return buffer
        }

        if error != nil { return (0, true, 0) }

        guard let channelData = convertedBuffer.floatChannelData?[0] else {
            return (0, true, 0)
        }
        let count = Int(convertedBuffer.frameLength)

        var samples = [Float](repeating: 0, count: count)
        for idx in 0..<count {
            samples[idx] = channelData[idx]
        }

        let rms = calculateRMS(samples)
        let gated = storage.applyNoiseGate(samples)
        storage.write(gated)

        let isQuiet = rms < gapThreshold
        let frameDuration = Double(count) / outputFormat.sampleRate

        return (rms, isQuiet, frameDuration)
    }

    private static func calculateRMS(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        let sumOfSquares = samples.reduce(Float(0)) { $0 + $1 * $1 }
        return sqrt(sumOfSquares / Float(samples.count))
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
        case formatCreationFailed
        case converterCreationFailed

        var errorDescription: String? {
            switch self {
            case .formatCreationFailed:
                return "Failed to create the target audio format."
            case .converterCreationFailed:
                return "Failed to create the audio format converter."
            }
        }
    }
}
