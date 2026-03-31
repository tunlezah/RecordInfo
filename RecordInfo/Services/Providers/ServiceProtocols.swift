import Foundation

// MARK: - Service Protocols

@MainActor
protocol AudioServiceProtocol: AnyObject, Sendable {
    func start() async throws
    func stop()
    func getBufferData() -> Data
    var currentLevel: Float { get }
    var bufferFillPercentage: Double { get }
    var isRunning: Bool { get }
}

@MainActor
protocol FingerprintServiceProtocol: Sendable {
    func generateFingerprint(from audioData: Data, sampleRate: Int, duration: Double) async throws -> String
    func hashFingerprint(_ fingerprint: String) -> String
}

@MainActor
protocol RecognitionServiceProtocol: Sendable {
    func identifyCurrentAudio() async throws -> IdentificationResult?
}

@MainActor
protocol CooldownManagerProtocol: Sendable {
    func shouldSkip(fingerprintHash: String, trackKey: String) -> Bool
    func registerDetection(fingerprintHash: String, trackKey: String)
    func isInGlobalCooldown() -> Bool
    func remainingCooldown() -> TimeInterval
}
