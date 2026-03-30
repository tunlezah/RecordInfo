import SwiftUI

struct NowPlayingView: View {
    @Environment(UIStateManager.self) private var stateManager
    @Environment(TrackHistory.self) private var history

    @State private var gradientPhase: Double = 0

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Animated gradient background
                animatedBackground

                VStack(spacing: 0) {
                    Spacer()

                    // Large album art
                    let artSize = min(geometry.size.width, geometry.size.height) * 0.55
                    AlbumArtView(
                        artworkURL: stateManager.currentResult?.artworkURL,
                        size: artSize
                    )
                    .shadow(color: Color(hex: 0x6B2FA0).opacity(0.6), radius: 30, x: 0, y: 10)

                    Spacer()
                        .frame(height: 40)

                    // Track info
                    VStack(spacing: 8) {
                        if let result = stateManager.currentResult {
                            Text(result.trackTitle)
                                .font(.system(size: 36, weight: .bold))
                                .foregroundStyle(.white)
                                .lineLimit(2)
                                .multilineTextAlignment(.center)

                            Text(result.artist)
                                .font(.system(size: 22, weight: .medium))
                                .foregroundStyle(.white.opacity(0.7))
                                .lineLimit(1)

                            if let year = result.releaseYear {
                                Text("\(result.album) \u{2022} \(year)")
                                    .font(.system(size: 16))
                                    .foregroundStyle(.white.opacity(0.4))
                                    .lineLimit(1)
                            }
                        } else {
                            Text("Waiting for Music...")
                                .font(.system(size: 28, weight: .medium))
                                .foregroundStyle(.white.opacity(0.4))
                        }
                    }
                    .padding(.horizontal, 40)

                    Spacer()

                    // Bottom strip: last 3 tracks
                    if !history.lastThree.isEmpty {
                        recentTracksStrip
                            .padding(.bottom, 30)
                    }
                }
                .padding()
            }
        }
        .ignoresSafeArea()
        .onAppear {
            withAnimation(
                .linear(duration: 8)
                .repeatForever(autoreverses: true)
            ) {
                gradientPhase = 1
            }
        }
    }

    private var animatedBackground: some View {
        LinearGradient(
            colors: [
                Color(hex: 0x1A1A2E),
                Color(hex: 0x6B2FA0).opacity(gradientPhase * 0.3 + 0.1),
                Color(hex: 0x16213E),
                Color(hex: 0x9B30FF).opacity((1 - gradientPhase) * 0.2 + 0.05),
                Color(hex: 0x1A1A2E),
            ],
            startPoint: UnitPoint(
                x: gradientPhase * 0.3,
                y: 0
            ),
            endPoint: UnitPoint(
                x: 1 - gradientPhase * 0.3,
                y: 1
            )
        )
        .ignoresSafeArea()
    }

    private var recentTracksStrip: some View {
        HStack(spacing: 16) {
            ForEach(history.lastThree) { track in
                HStack(spacing: 8) {
                    AlbumArtView(artworkURL: track.artworkURL, size: 36)

                    VStack(alignment: .leading, spacing: 1) {
                        Text(track.trackTitle)
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.white.opacity(0.7))
                            .lineLimit(1)

                        Text(track.artist)
                            .font(.caption2)
                            .foregroundStyle(.white.opacity(0.4))
                            .lineLimit(1)
                    }
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(.ultraThinMaterial)
                .opacity(0.3)
        )
    }
}

#Preview {
    NowPlayingView()
        .environment(makePreviewStateManager())
        .environment(TrackHistory())
        .frame(width: 800, height: 600)
}

private func makePreviewStateManager() -> UIStateManager {
    UIStateManager(
        audioService: PreviewAudioServiceNP(),
        fingerprintService: PreviewFingerprintServiceNP(),
        recognitionService: PreviewRecognitionServiceNP(),
        cooldownManager: PreviewCooldownManagerNP()
    )
}

private final class PreviewAudioServiceNP: AudioServiceProtocol, @unchecked Sendable {
    func start() async throws {}
    func stop() {}
    func getBufferData() -> Data { Data() }
    var currentLevel: Float { 0.0 }
    var bufferFillPercentage: Double { 0.0 }
    var isRunning: Bool { false }
}
private struct PreviewFingerprintServiceNP: FingerprintServiceProtocol {
    func generateFingerprint(from audioData: Data, sampleRate: Int, duration: Double) async throws -> String { "" }
    func hashFingerprint(_ fingerprint: String) -> String { "" }
}
private struct PreviewRecognitionServiceNP: RecognitionServiceProtocol {
    func identifyCurrentAudio() async throws -> IdentificationResult? { nil }
}
private struct PreviewCooldownManagerNP: CooldownManagerProtocol {
    func shouldSkip(fingerprintHash: String, trackKey: String) -> Bool { false }
    func registerDetection(fingerprintHash: String, trackKey: String) {}
    func isInGlobalCooldown() -> Bool { false }
    func remainingCooldown() -> TimeInterval { 0 }
}
