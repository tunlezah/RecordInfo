import AVFoundation
import Foundation

@Observable
@MainActor
final class AudioService: AudioServiceProtocol {

    // MARK: - Published State

    private(set) var currentLevel: Float = 0.0
    private(set) var isListening: Bool = false
    private(set) var gapDetected: Bool = false

    var isRunning: Bool { isListening }

    var bufferFillPercentage: Double {
        bufferLock.lock()
        defer { bufferLock.unlock() }
        guard maxBufferSamples > 0 else { return 0 }
        if bufferFilled { return 1.0 }
        return Double(bufferWriteIndex) / Double(maxBufferSamples)
    }

    // MARK: - Configuration

    var bufferLengthSeconds: Double = 20.0
    var sampleRate: Double = 11025.0
    var noiseGateThreshold: Float = 0.01
    var normalizationTarget: Float = 0.9

    // MARK: - Private State

    private var audioEngine: AVAudioEngine?
    private let bufferLock = NSLock()
    private var circularBuffer: [Float] = []
    private var bufferWriteIndex: Int = 0
    private var bufferFilled: Bool = false

    private var gapSilenceDuration: Double = 0.0
    private let gapSilenceThreshold: Double = 2.0 // seconds of silence to detect gap
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

        resetBuffer()

        inputNode.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) {
            [weak self] buffer, _ in
            guard let self else { return }
            self.processInputBuffer(buffer, converter: converter, outputFormat: outputFormat)
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
        isListening = false
        currentLevel = 0.0
    }

    func getBufferData() -> Data {
        bufferLock.lock()
        defer { bufferLock.unlock() }

        let samples: [Float]
        if bufferFilled {
            // Read from writeIndex to end, then from 0 to writeIndex
            let part1 = Array(circularBuffer[bufferWriteIndex...])
            let part2 = Array(circularBuffer[..<bufferWriteIndex])
            samples = part1 + part2
        } else {
            samples = Array(circularBuffer[..<bufferWriteIndex])
        }

        let normalized = normalizeSamples(samples)
        return convertToPCM16Data(normalized)
    }

    func getCurrentLevel() -> Float {
        return currentLevel
    }

    // MARK: - Private Methods

    private func resetBuffer() {
        bufferLock.lock()
        defer { bufferLock.unlock() }

        circularBuffer = [Float](repeating: 0, count: maxBufferSamples)
        bufferWriteIndex = 0
        bufferFilled = false
    }

    private nonisolated func processInputBuffer(
        _ buffer: AVAudioPCMBuffer,
        converter: AVAudioConverter,
        outputFormat: AVAudioFormat
    ) {
        let frameCount = AVAudioFrameCount(
            Double(buffer.frameLength) * outputFormat.sampleRate / buffer.format.sampleRate
        )
        guard frameCount > 0 else { return }

        guard let convertedBuffer = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: frameCount) else {
            return
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

        if error != nil { return }

        guard let channelData = convertedBuffer.floatChannelData?[0] else { return }
        let count = Int(convertedBuffer.frameLength)

        var samples = [Float](repeating: 0, count: count)
        for i in 0..<count {
            samples[i] = channelData[i]
        }

        // Calculate RMS level
        let rms = calculateRMS(samples)

        // Noise gate
        let gated = applyNoiseGate(samples)

        // Write to circular buffer
        writeToBuffer(gated)

        // Detect gaps
        let isQuiet = rms < gapAmplitudeThreshold
        let frameDuration = Double(count) / outputFormat.sampleRate

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
                    // Silence ended after a detected gap - potential track transition
                    self.gapDetected = false
                }
                self.gapSilenceDuration = 0.0
            }
        }
    }

    private nonisolated func calculateRMS(_ samples: [Float]) -> Float {
        guard !samples.isEmpty else { return 0 }
        let sumOfSquares = samples.reduce(Float(0)) { $0 + $1 * $1 }
        return sqrt(sumOfSquares / Float(samples.count))
    }

    private nonisolated func applyNoiseGate(_ samples: [Float]) -> [Float] {
        return samples.map { abs($0) < noiseGateThreshold ? 0 : $0 }
    }

    private nonisolated func normalizeSamples(_ samples: [Float]) -> [Float] {
        guard !samples.isEmpty else { return [] }
        let peak = samples.map { abs($0) }.max() ?? 0
        guard peak > 0 else { return samples }
        let scale = normalizationTarget / peak
        return samples.map { $0 * scale }
    }

    private nonisolated func writeToBuffer(_ samples: [Float]) {
        bufferLock.lock()
        defer { bufferLock.unlock() }

        let max = circularBuffer.count
        for sample in samples {
            circularBuffer[bufferWriteIndex] = sample
            bufferWriteIndex += 1
            if bufferWriteIndex >= max {
                bufferWriteIndex = 0
                bufferFilled = true
            }
        }
    }

    private nonisolated func convertToPCM16Data(_ samples: [Float]) -> Data {
        var data = Data(capacity: samples.count * 2)
        for sample in samples {
            let clamped = max(-1.0, min(1.0, sample))
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
