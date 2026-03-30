import SwiftUI

struct MainView: View {
    @Environment(UIStateManager.self) private var stateManager
    @Environment(AppSettings.self) private var settings
    @Environment(TrackHistory.self) private var history

    @State private var showSettings = false

    private var currentResult: IdentificationResult? {
        stateManager.currentResult
    }

    private var isIdentifiedState: Bool {
        if case .identified = stateManager.appState { return true }
        return false
    }

    var body: some View {
        ZStack {
            // Background gradient
            LinearGradient(
                colors: [Color(hex: 0x1A1A2E), Color(hex: 0x16213E)],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Status bar
                statusBar
                    .padding(.top, 8)
                    .padding(.horizontal, 16)

                Spacer().frame(height: 16)

                // Album art
                AlbumArtView(artworkURL: currentResult?.artworkURL)
                    .animation(.easeInOut(duration: 0.5), value: currentResult?.id)

                Spacer().frame(height: 16)

                // Track info
                trackInfo
                    .padding(.horizontal, 20)

                Spacer().frame(height: 12)

                // Confidence
                if let result = currentResult {
                    ConfidenceIndicator(confidence: result.confidence)
                        .padding(.horizontal, 30)
                        .transition(.opacity)
                }

                Spacer().frame(height: 16)

                // Controls
                controlsRow
                    .padding(.horizontal, 20)

                // Next scan countdown
                if settings.autoDetectionEnabled && stateManager.isListening {
                    nextScanCountdown
                        .padding(.top, 8)
                }

                Spacer().frame(height: 12)

                // Debug panel
                if settings.debugModeEnabled {
                    DebugView()
                        .padding(.horizontal, 12)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                Divider()
                    .overlay(Color.white.opacity(0.1))
                    .padding(.vertical, 6)

                // History
                HistoryView(tracks: history.tracks)
                    .padding(.horizontal, 12)
                    .frame(maxHeight: 140)

                Spacer().frame(height: 8)
            }
        }
        .frame(
            width: Constants.UI.mainWindowWidth,
            height: Constants.UI.mainWindowHeight
        )
        .animation(.easeInOut(duration: 0.3), value: settings.debugModeEnabled)
        .sheet(isPresented: $showSettings) {
            SettingsView(settings: settings)
        }
    }

    // MARK: - Status Bar

    private var statusBar: some View {
        HStack {
            StatusIndicator(state: stateManager.appState)
            Spacer()
            if case .coolingDown(let remaining) = stateManager.appState {
                Text("\(Int(remaining))s")
                    .font(.caption.monospaced())
                    .foregroundStyle(.yellow)
            }
        }
    }

    // MARK: - Track Info

    private var trackInfo: some View {
        VStack(spacing: 4) {
            if let result = currentResult {
                Text(result.trackTitle)
                    .font(.title2.weight(.bold))
                    .foregroundStyle(.white)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)

                Text(result.artist)
                    .font(.body.weight(.medium))
                    .foregroundStyle(Color(hex: 0x9B30FF))
                    .lineLimit(1)

                HStack(spacing: 4) {
                    Text(result.album)
                    if let year = result.releaseYear {
                        Text("\u{2022}")
                        Text(year)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            } else {
                Text("No Track Identified")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(.white.opacity(0.4))

                Text("Start listening to identify music")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
    }

    // MARK: - Controls Row

    private var controlsRow: some View {
        HStack(spacing: 12) {
            // Start/Stop toggle
            Button {
                if stateManager.isListening {
                    stateManager.stopListening()
                } else {
                    stateManager.startListening()
                }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: stateManager.isListening ? "stop.circle.fill" : "mic.circle.fill")
                        .font(.title3)
                    Text(stateManager.isListening ? "Stop" : "Start")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(stateManager.isListening ? .red : Color(hex: 0x6B2FA0))
            .controlSize(.large)

            // Manual Identify
            Button {
                stateManager.manualIdentify()
            } label: {
                Image(systemName: "waveform.badge.magnifyingglass")
                    .font(.title3)
                    .frame(width: 44, height: 36)
            }
            .buttonStyle(.bordered)
            .tint(Color(hex: 0xFF6B35))
            .disabled(!stateManager.isListening)

            // Now Playing
            Button {
                stateManager.openNowPlayingWindow()
            } label: {
                Image(systemName: "tv")
                    .font(.title3)
                    .frame(width: 44, height: 36)
            }
            .buttonStyle(.bordered)
            .tint(Color(hex: 0x9B30FF))

            // Settings
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape.fill")
                    .font(.title3)
                    .frame(width: 44, height: 36)
            }
            .buttonStyle(.bordered)
            .tint(.gray)
        }
    }

    // MARK: - Next Scan Countdown

    private var nextScanCountdown: some View {
        HStack(spacing: 4) {
            Image(systemName: "timer")
                .font(.caption2)
            Text("Next scan in \(Int(stateManager.secondsUntilNextDetection))s")
                .font(.caption2)
        }
        .foregroundStyle(.secondary)
    }
}

#Preview {
    MainView()
        .environment(UIStateManager(
            audioService: PreviewAudioService(),
            fingerprintService: PreviewFingerprintService(),
            recognitionService: PreviewRecognitionService(),
            cooldownManager: PreviewCooldownManager()
        ))
        .environment(AppSettings())
        .environment(TrackHistory())
}

// MARK: - Preview Helpers

private final class PreviewAudioService: AudioServiceProtocol, @unchecked Sendable {
    func start() async throws {}
    func stop() {}
    func getBufferData() -> Data { Data() }
    var currentLevel: Float { 0.3 }
    var bufferFillPercentage: Double { 0.65 }
    var isRunning: Bool { false }
}

private struct PreviewFingerprintService: FingerprintServiceProtocol {
    func generateFingerprint(from audioData: Data, sampleRate: Int, duration: Double) async throws -> String { "" }
    func hashFingerprint(_ fingerprint: String) -> String { "" }
}

private struct PreviewRecognitionService: RecognitionServiceProtocol {
    func identifyCurrentAudio() async throws -> IdentificationResult? { nil }
}

private struct PreviewCooldownManager: CooldownManagerProtocol {
    func shouldSkip(fingerprintHash: String, trackKey: String) -> Bool { false }
    func registerDetection(fingerprintHash: String, trackKey: String) {}
    func isInGlobalCooldown() -> Bool { false }
    func remainingCooldown() -> TimeInterval { 0 }
}
