import SwiftUI

struct HistoryView: View {
    let tracks: [IdentificationResult]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Recent")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(tracks.count) track\(tracks.count == 1 ? "" : "s")")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 8)

            if tracks.isEmpty {
                HStack {
                    Spacer()
                    VStack(spacing: 4) {
                        Image(systemName: "music.note.list")
                            .font(.title3)
                            .foregroundStyle(.tertiary)
                        Text("No tracks identified yet")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 12)
                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(tracks) { track in
                            HistoryRow(track: track)
                        }
                    }
                }
            }
        }
    }
}

private struct HistoryRow: View {
    let track: IdentificationResult

    private var timeText: String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: track.timestamp, relativeTo: Date())
    }

    var body: some View {
        HStack(spacing: 8) {
            AlbumArtView(artworkURL: track.artworkURL, size: Constants.UserInterface.historyThumbnailSize)

            VStack(alignment: .leading, spacing: 1) {
                Text(track.trackTitle)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Text(track.artist)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            Text(timeText)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(Color.white.opacity(0.03))
        )
    }
}

#Preview {
    HistoryView(tracks: [
        IdentificationResult(
            trackTitle: "Bohemian Rhapsody",
            artist: "Queen",
            album: "A Night at the Opera",
            releaseYear: "1975",
            confidence: 0.95,
            fingerprint: "abc123",
            provider: "AcoustID"
        ),
        IdentificationResult(
            trackTitle: "Stairway to Heaven",
            artist: "Led Zeppelin",
            album: "Led Zeppelin IV",
            releaseYear: "1971",
            confidence: 0.88,
            fingerprint: "def456",
            provider: "AcoustID"
        ),
    ])
    .frame(width: 380, height: 200)
    .background(Color(hex: 0x1A1A2E))
}
