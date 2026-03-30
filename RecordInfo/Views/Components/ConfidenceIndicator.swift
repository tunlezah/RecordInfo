import SwiftUI

struct ConfidenceIndicator: View {
    let confidence: Double

    @State private var animatedWidth: Double = 0

    private var confidenceColor: Color {
        if confidence < 0.4 {
            return .red
        } else if confidence < 0.7 {
            return .yellow
        } else {
            return .green
        }
    }

    private var gradientColors: [Color] {
        if confidence < 0.4 {
            return [.red, .orange]
        } else if confidence < 0.7 {
            return [.orange, .yellow]
        } else {
            return [.green, Color(hex: 0x00CC66)]
        }
    }

    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text("Confidence")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Spacer()
                Text("\(Int(confidence * 100))%")
                    .font(.caption.bold())
                    .foregroundStyle(confidenceColor)
            }

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.white.opacity(0.1))
                        .frame(height: 6)

                    RoundedRectangle(cornerRadius: 4)
                        .fill(
                            LinearGradient(
                                colors: gradientColors,
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                        .frame(width: geometry.size.width * animatedWidth, height: 6)
                }
            }
            .frame(height: 6)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 0.8)) {
                animatedWidth = confidence
            }
        }
        .onChange(of: confidence) { _, newValue in
            withAnimation(.easeOut(duration: 0.5)) {
                animatedWidth = newValue
            }
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        ConfidenceIndicator(confidence: 0.92)
        ConfidenceIndicator(confidence: 0.55)
        ConfidenceIndicator(confidence: 0.25)
    }
    .padding()
    .frame(width: 300)
    .background(Color(hex: 0x1A1A2E))
}
