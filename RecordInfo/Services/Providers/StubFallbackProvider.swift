import Foundation

struct StubFallbackProvider: MusicRecognitionProvider {
    let name = "Stub Fallback"

    func identify(audioData: Data, duration: Double, sampleRate: Int) async throws -> IdentificationResult? {
        return nil
    }
}
