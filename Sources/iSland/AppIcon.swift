import AppKit
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// The app icon, drawn in code so the whole project builds from source with no binary assets.
/// `iSland --icon out.png` writes a 1024 px master; scripts/make-icon.sh turns it into AppIcon.icns.
struct AppIconArt: View {
    private let orange = Color(red: 0.95, green: 0.54, blue: 0.38)

    var body: some View {
        ZStack(alignment: .top) {
            LinearGradient(colors: [Color(red: 0.08, green: 0.08, blue: 0.13), Color(red: 0.33, green: 0.17, blue: 0.42)],
                           startPoint: .topLeading, endPoint: .bottomTrailing)
            Circle().fill(orange.opacity(0.55)).frame(width: 520).blur(radius: 110).offset(y: 430)

            // A menu bar, and under it the glass card that opens from the notch: reads as "Mac", not as "save".
            Rectangle().fill(Color.white.opacity(0.10)).frame(height: 74)
            RoundedRectangle(cornerRadius: 84, style: .continuous)
                .fill(Color.white.opacity(0.11))
                .overlay(RoundedRectangle(cornerRadius: 84, style: .continuous).strokeBorder(Color.white.opacity(0.22), lineWidth: 3))
                .frame(width: 660, height: 330)
                .offset(y: 190)

            // The notch itself, with the Claude spinner glyph blooming inside it.
            NotchShape(topRadius: 46, bottomRadius: 110)
                .fill(Color.black)
                .frame(width: 470, height: 270)
                .overlay {
                    Text("✻")
                        .font(.system(size: 200, weight: .bold))
                        .foregroundStyle(orange)
                        .offset(y: -4)
                }
                .shadow(color: orange.opacity(0.35), radius: 40, y: 10)
        }
        .frame(width: 824, height: 824)
        .clipShape(RoundedRectangle(cornerRadius: 185, style: .continuous))
        .shadow(color: Color.black.opacity(0.4), radius: 26, y: 16)
        .frame(width: 1024, height: 1024)
    }

    @MainActor
    static func write(to path: String) -> Bool {
        let renderer = ImageRenderer(content: AppIconArt())
        renderer.scale = 1
        guard let image = renderer.cgImage,
              let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL,
                                                                UTType.png.identifier as CFString, 1, nil)
        else { return false }
        CGImageDestinationAddImage(destination, image, nil)
        return CGImageDestinationFinalize(destination)
    }
}
