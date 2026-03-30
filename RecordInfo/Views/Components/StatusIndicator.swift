import SwiftUI

struct StatusIndicator: View {
    let state: AppState

    @State private var isPulsing = false

    private var statusColor: Color {
        switch state {
        case .idle:
            return .gray
        case .listening:
            return .blue
        case .processing:
            return .orange
        case .identified:
            return .green
        case .coolingDown:
            return .yellow
        case .error:
            return .red
        }
    }

    private var isListening: Bool {
        if case .listening = state { return true }
        return false
    }

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)
                .shadow(color: statusColor.opacity(0.6), radius: isPulsing ? 6 : 2)
                .scaleEffect(isPulsing ? 1.3 : 1.0)

            Text(state.displayText)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(statusColor.opacity(0.2))
                .overlay(
                    Capsule()
                        .strokeBorder(statusColor.opacity(0.4), lineWidth: 1)
                )
        )
        .onChange(of: isListening, initial: true) { _, listening in
            if listening {
                withAnimation(
                    .easeInOut(duration: 0.8)
                    .repeatForever(autoreverses: true)
                ) {
                    isPulsing = true
                }
            } else {
                withAnimation(.easeOut(duration: 0.3)) {
                    isPulsing = false
                }
            }
        }
    }
}

#Preview {
    VStack(spacing: 12) {
        StatusIndicator(state: .idle)
        StatusIndicator(state: .listening)
        StatusIndicator(state: .processing)
        StatusIndicator(state: .identified(IdentificationResult(
            trackTitle: "Test", artist: "Test", album: "Test",
            confidence: 0.9, fingerprint: "", provider: "test"
        )))
        StatusIndicator(state: .coolingDown(15))
        StatusIndicator(state: .error("Microphone unavailable"))
    }
    .padding()
    .background(Color(hex: 0x1A1A2E))
}
