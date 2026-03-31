import SwiftUI

struct AlbumArtView: View {
    let artworkURL: URL?
    var size: CGFloat = Constants.UserInterface.albumArtSize

    var body: some View {
        Group {
            if let url = artworkURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fill)
                    case .failure:
                        placeholderView
                    case .empty:
                        ZStack {
                            placeholderView
                            ProgressView()
                                .controlSize(.large)
                                .tint(.white)
                        }
                    @unknown default:
                        placeholderView
                    }
                }
            } else {
                placeholderView
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: Color(hex: 0x6B2FA0).opacity(0.5), radius: 12, x: 0, y: 6)
    }

    private var placeholderView: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(hex: 0x6B2FA0),
                    Color(hex: 0x9B30FF)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )

            Image(systemName: "opticaldisc")
                .font(.system(size: size * 0.35))
                .foregroundStyle(.white.opacity(0.7))
                .symbolEffect(.pulse, options: .repeating)
        }
    }
}

extension Color {
    init(hex: UInt, opacity: Double = 1.0) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: opacity
        )
    }
}

#Preview {
    AlbumArtView(artworkURL: nil)
        .padding()
        .background(Color(hex: 0x1A1A2E))
}
