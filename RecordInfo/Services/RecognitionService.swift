import Foundation

@Observable
@MainActor
final class RecognitionService: RecognitionServiceProtocol {

    // MARK: - Dependencies

    private let audioService: AudioService
    private let fingerprintService: FingerprintService
    private let cooldownManager: CooldownManager
    private let primaryProvider: any MusicRecognitionProvider
    private let fallbackProvider: (any MusicRecognitionProvider)?
    private let settings: AppSettings

    // MARK: - State

    private(set) var isProcessing: Bool = false
    private(set) var lastError: String?

    // MARK: - Init

    init(
        audioService: AudioService,
        fingerprintService: FingerprintService,
        cooldownManager: CooldownManager,
        primaryProvider: any MusicRecognitionProvider,
        fallbackProvider: (any MusicRecognitionProvider)? = nil,
        settings: AppSettings
    ) {
        self.audioService = audioService
        self.fingerprintService = fingerprintService
        self.cooldownManager = cooldownManager
        self.primaryProvider = primaryProvider
        self.fallbackProvider = fallbackProvider
        self.settings = settings
    }

    // MARK: - Errors

    enum RecognitionError: LocalizedError {
        case notListening
        case emptyBuffer
        case inCooldown(TimeInterval)
        case duplicateDetection

        var errorDescription: String? {
            switch self {
            case .notListening:
                return "Audio service is not currently listening."
            case .emptyBuffer:
                return "Audio buffer is empty."
            case .inCooldown(let remaining):
                return "In cooldown for \(Int(remaining)) more seconds."
            case .duplicateDetection:
                return "This track was recently detected. Skipping."
            }
        }
    }

    // MARK: - Public API

    /// Runs the full recognition pipeline: capture -> fingerprint -> cooldown check -> identify.
    func identifyCurrentAudio() async throws -> IdentificationResult? {
        guard audioService.isListening else {
            throw RecognitionError.notListening
        }

        isProcessing = true
        lastError = nil
        defer { isProcessing = false }

        // 1. Get audio buffer data
        let bufferData = audioService.getBufferData()
        guard !bufferData.isEmpty else {
            throw RecognitionError.emptyBuffer
        }

        let sampleRate = Int(settings.sampleRate)
        let duration = settings.audioBufferLength

        // 2. Generate fingerprint
        let fingerprint = try await fingerprintService.generateFingerprint(
            from: bufferData,
            sampleRate: sampleRate,
            duration: duration
        )

        let fingerprintHash = fingerprintService.hashFingerprint(fingerprint)

        // 3. Try primary provider
        var result: IdentificationResult?
        do {
            result = try await primaryProvider.identify(
                audioData: bufferData,
                duration: duration,
                sampleRate: sampleRate
            )
        } catch {
            lastError = "[\(primaryProvider.name)] \(error.localizedDescription)"
        }

        // 4. Check confidence and try fallback if needed
        if let r = result, r.confidence < settings.confidenceThreshold {
            // Low confidence - try fallback if available
            result = nil
        }

        if result == nil, let fallback = fallbackProvider, settings.fallbackProviderEnabled {
            do {
                result = try await fallback.identify(
                    audioData: bufferData,
                    duration: duration,
                    sampleRate: sampleRate
                )
            } catch {
                lastError = "[\(fallback.name)] \(error.localizedDescription)"
            }
        }

        // 5. If we have a result, check cooldown and register
        if let result {
            let trackKey = CooldownManager.trackKey(artist: result.artist, title: result.trackTitle)

            if cooldownManager.shouldSkip(fingerprintHash: fingerprintHash, trackKey: trackKey) {
                throw RecognitionError.duplicateDetection
            }

            cooldownManager.registerDetection(fingerprintHash: fingerprintHash, trackKey: trackKey)
            return result
        }

        return nil
    }
}
