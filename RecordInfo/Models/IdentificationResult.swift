import Foundation

struct IdentificationResult: Identifiable, Codable, Equatable {
    let id: UUID
    let trackTitle: String
    let artist: String
    let album: String
    let releaseYear: String?
    let artworkURL: URL?
    let confidence: Double  // 0.0 to 1.0
    let fingerprint: String
    let timestamp: Date
    let provider: String

    init(id: UUID = UUID(), trackTitle: String, artist: String, album: String, releaseYear: String? = nil, artworkURL: URL? = nil, confidence: Double, fingerprint: String, timestamp: Date = Date(), provider: String) {
        self.id = id
        self.trackTitle = trackTitle
        self.artist = artist
        self.album = album
        self.releaseYear = releaseYear
        self.artworkURL = artworkURL
        self.confidence = confidence
        self.fingerprint = fingerprint
        self.timestamp = timestamp
        self.provider = provider
    }
}
