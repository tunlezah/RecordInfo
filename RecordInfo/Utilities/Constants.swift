import Foundation

enum Constants {
    enum Audio {
        static let defaultBufferLength: Double = 20.0  // seconds
        static let minBufferLength: Double = 10.0
        static let maxBufferLength: Double = 30.0
        static let defaultSampleRate: Double = 11025.0
        static let highSampleRate: Double = 44100.0
        static let bitsPerSample: Int = 16
        static let channels: Int = 1  // mono
    }

    enum Detection {
        static let defaultInterval: Double = 120.0  // seconds
        static let minInterval: Double = 30.0
        static let maxInterval: Double = 300.0
        static let defaultConfidenceThreshold: Double = 0.6
        static let defaultCooldown: Double = 30.0
        static let defaultPerTrackCooldown: Double = 300.0
        static let defaultSimilarityThreshold: Double = 0.8
    }

    enum API {
        static let acoustIDBaseURL = "https://api.acoustid.org/v2/lookup"
        static let musicBrainzBaseURL = "https://musicbrainz.org/ws/2"
        static let coverArtBaseURL = "https://coverartarchive.org"
        static let userAgent = "RecordInfo/1.0 (https://github.com/tunlezah/recordinfo)"
    }

    enum UI {
        static let mainWindowWidth: CGFloat = 420
        static let mainWindowHeight: CGFloat = 680
        static let albumArtSize: CGFloat = 280
        static let historyThumbnailSize: CGFloat = 40
        static let maxHistoryItems = 10
    }
}
