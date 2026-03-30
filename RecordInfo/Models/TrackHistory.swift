import Foundation
import SwiftUI

@Observable
final class TrackHistory {
    private(set) var tracks: [IdentificationResult] = []
    private let maxTracks = 10

    func add(_ result: IdentificationResult) {
        tracks.insert(result, at: 0)
        if tracks.count > maxTracks {
            tracks.removeLast()
        }
    }

    var lastThree: [IdentificationResult] {
        Array(tracks.prefix(3))
    }

    func clear() {
        tracks.removeAll()
    }
}
