import Foundation

protocol MusicRecognitionProvider: Sendable {
    var name: String { get }
    func identify(audioData: Data, duration: Double, sampleRate: Int) async throws -> IdentificationResult?
}
