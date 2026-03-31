import SwiftUI

struct DebugView: View {
    @Environment(UIStateManager.self) private var stateManager

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Image(systemName: "ladybug.fill")
                    .foregroundStyle(Color(hex: 0xFF6B35))
                Text("DEBUG")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(Color(hex: 0xFF6B35))
                    .tracking(1.2)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 8) {
                // Audio Levels
                debugSection("Audio Level") {
                    HStack(spacing: 4) {
                        GeometryReader { geometry in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 2)
                                    .fill(Color.white.opacity(0.1))

                                RoundedRectangle(cornerRadius: 2)
                                    .fill(audioLevelColor)
                                    .frame(width: geometry.size.width * CGFloat(stateManager.audioLevel))
                            }
                        }
                        .frame(height: 8)

                        Text(String(format: "%.4f", stateManager.audioLevel))
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .frame(width: 55, alignment: .trailing)
                    }
                }

                // Buffer State
                debugSection("Buffer Fill") {
                    HStack(spacing: 4) {
                        ProgressView(value: stateManager.bufferFillPercentage)
                            .tint(Color(hex: 0x9B30FF))

                        Text("\(Int(stateManager.bufferFillPercentage * 100))%")
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .frame(width: 35, alignment: .trailing)
                    }
                }

                // Fingerprint Log
                debugSection("Last Fingerprint") {
                    let fingerprint = stateManager.currentResult?.fingerprint ?? "None"
                    let truncated = fingerprint.count > 60
                        ? String(fingerprint.prefix(60)) + "..."
                        : fingerprint
                    Text(truncated)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .textSelection(.enabled)
                }

                // API Response
                debugSection("Last API Response") {
                    ScrollView {
                        Text(stateManager.lastAPIResponse)
                            .font(.caption2.monospaced())
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    .frame(maxHeight: 60)
                }

                // Timestamps
                debugSection("Timing") {
                    VStack(alignment: .leading, spacing: 2) {
                        timestampRow(
                            "Last Detection",
                            value: stateManager.lastDetectionTime.map { formatTime($0) } ?? "Never"
                        )
                        timestampRow(
                            "Next Scheduled",
                            value: stateManager.secondsUntilNextDetection > 0
                                ? "\(Int(stateManager.secondsUntilNextDetection))s"
                                : "N/A"
                        )
                    }
                }
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.black.opacity(0.3))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Color(hex: 0xFF6B35).opacity(0.3), lineWidth: 1)
                )
        )
    }

    private var audioLevelColor: Color {
        let level = stateManager.audioLevel
        if level < 0.3 { return .green }
        if level < 0.7 { return .yellow }
        return .red
    }

    private func debugSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.caption2.weight(.medium))
                .foregroundStyle(Color(hex: 0xFF6B35).opacity(0.7))
            content()
        }
    }

    private func timestampRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption2.monospaced())
                .foregroundStyle(.tertiary)
            Spacer()
            Text(value)
                .font(.caption2.monospaced())
                .foregroundStyle(.secondary)
        }
    }

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: date)
    }
}

#Preview {
    DebugView()
        .environment(makePreviewStateManagerDebug())
        .frame(width: 380)
        .padding()
        .background(Color(hex: 0x1A1A2E))
}

@MainActor private func makePreviewStateManagerDebug() -> UIStateManager {
    UIStateManager(
        audioService: PreviewAudioServiceDbg(),
        fingerprintService: PreviewFingerprintServiceDbg(),
        recognitionService: PreviewRecognitionServiceDbg(),
        cooldownManager: PreviewCooldownManagerDbg()
    )
}

@MainActor
private final class PreviewAudioServiceDbg: AudioServiceProtocol {
    func start() async throws {}
    func stop() {}
    func getBufferData() -> Data { Data() }
    var currentLevel: Float { 0.3 }
    var bufferFillPercentage: Double { 0.65 }
    var isRunning: Bool { false }
}
@MainActor
private final class PreviewFingerprintServiceDbg: FingerprintServiceProtocol {
    func generateFingerprint(from audioData: Data, sampleRate: Int, duration: Double) async throws -> String { "" }
    func hashFingerprint(_ fingerprint: String) -> String { "" }
}
@MainActor
private final class PreviewRecognitionServiceDbg: RecognitionServiceProtocol {
    func identifyCurrentAudio() async throws -> IdentificationResult? { nil }
}
@MainActor
private final class PreviewCooldownManagerDbg: CooldownManagerProtocol {
    func shouldSkip(fingerprintHash: String, trackKey: String) -> Bool { false }
    func registerDetection(fingerprintHash: String, trackKey: String) {}
    func isInGlobalCooldown() -> Bool { false }
    func remainingCooldown() -> TimeInterval { 0 }
}
