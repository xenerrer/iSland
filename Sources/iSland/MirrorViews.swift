@preconcurrency import AVFoundation
import AppKit
import SwiftUI

/// The live camera, mirrored like a bathroom mirror. A layer-hosting view: the preview layer is the view's own layer.
struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        layer.setAffineTransform(CGAffineTransform(scaleX: -1, y: 1))
        view.layer = layer
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {}
}

/// "Me, in a circle": the camera inside a ring hanging from the notch, and the way back to the usual island.
struct MirrorCard: View {
    @ObservedObject var mirror: MirrorManager
    /// Set when the mirror was opened from a meeting: joining is one click away.
    var joinURL: URL?
    let onBack: () -> Void

    var body: some View {
        VStack(spacing: IslandLayout.mirrorSpacing) {
            ZStack {
                Color.white.opacity(0.08)
                if mirror.state == .running, let session = mirror.session {
                    CameraPreview(session: session)
                } else {
                    placeholder
                }
                if mirror.askingToSave { consent }
            }
            .frame(width: IslandLayout.mirrorDiameter, height: IslandLayout.mirrorDiameter)
            .overlay(Circle().fill(Color.white).opacity(mirror.flash ? 0.85 : 0).animation(.easeOut(duration: 0.22), value: mirror.flash))
            .clipShape(Circle())
            .overlay(Circle().stroke(Color.white.opacity(0.25), lineWidth: 1.5))
            .overlay(alignment: .bottom) {
                if mirror.lastPhoto != nil {
                    Button(action: mirror.revealLastPhoto) {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark").font(.system(size: 9, weight: .bold))
                            Text(L10n.t("Photo saved") + " · " + L10n.t("Show"))
                        }
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(Color.white)
                        .padding(.horizontal, 9).padding(.vertical, 4)
                        .background(Capsule().fill(Color.black.opacity(0.65)))
                    }
                    .buttonStyle(.plain)
                    .padding(.bottom, 14)
                    .transition(.opacity)
                }
            }
            HStack(spacing: 14) {
                if mirror.state == .denied {
                    IslandButton(title: L10n.t("Open Settings"), kind: .neutral) { mirror.openPrivacySettings() }
                }
                Button(action: onBack) {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left").font(.system(size: 9, weight: .semibold))
                        Text(L10n.t("Back"))
                    }
                }
                .buttonStyle(SubtleButtonStyle())
                Button(action: mirror.takePhoto) {
                    ZStack {
                        Circle().stroke(Color.white.opacity(0.9), lineWidth: 2).frame(width: 28, height: 28)
                        Circle().fill(Color.white.opacity(0.9)).frame(width: 20, height: 20)
                    }
                }
                .buttonStyle(.plain)
                .disabled(mirror.state != .running)
                .opacity(mirror.state == .running ? 1 : 0.3)
                .help(L10n.t("Take photo"))
                .accessibilityLabel(L10n.t("Take photo"))
                if let joinURL {
                    IslandButton(title: L10n.t("Join"), kind: .allow) {
                        NSWorkspace.shared.open(joinURL)
                        onBack()
                    }
                }
            }
            .frame(height: IslandLayout.mirrorButtonHeight)
        }
    }

    /// The one question before the first photo, asked here so its buttons are the island's own.
    private var consent: some View {
        VStack(spacing: 8) {
            Text(L10n.t("Save photos in Pictures?")).font(.system(size: 12.5, weight: .semibold)).multilineTextAlignment(.center)
            Text(L10n.t("They stay in Pictures/iSland and never leave your Mac.")).font(.system(size: 10.5))
                .foregroundStyle(Color.white.opacity(0.7)).multilineTextAlignment(.center)
            HStack(spacing: 8) {
                Button(L10n.t("Not now")) { mirror.declineSaving() }.buttonStyle(CapsuleButtonStyle(fill: Color.white.opacity(0.18), foreground: Color.white))
                Button(L10n.t("Allow")) { mirror.allowSaving() }
                    .buttonStyle(CapsuleButtonStyle(fill: Color(red: 0.3, green: 0.85, blue: 0.45), foreground: Color.black.opacity(0.85)))
            }
        }
        .foregroundStyle(Color.white)
        .padding(.horizontal, 22)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.black.opacity(0.82))
    }

    private var placeholder: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.crop.circle").font(.system(size: 44, weight: .light))
            Text(message).font(.system(size: 11.5)).multilineTextAlignment(.center)
        }
        .foregroundStyle(Color.white.opacity(0.6))
        .padding(24)
    }

    private var message: String {
        switch mirror.state {
        case .starting: L10n.t("Turning the camera on…")
        case .denied: L10n.t("Camera access is off")
        case .unavailable: L10n.t("No camera available")
        case .off, .running: ""
        }
    }
}

/// A quiet way back: small, translucent, no color.
struct SubtleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(Color.white.opacity(configuration.isPressed ? 0.95 : 0.6))
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Capsule().fill(Color.white.opacity(0.09)))
            .contentShape(Capsule())
    }
}

/// A mirror, drawn: an upright oval with two strokes of reflection. (SF Symbols has nothing that reads as a mirror.)
struct MirrorGlyph: View {
    var size: CGFloat = 14

    var body: some View {
        ZStack {
            Ellipse().stroke(lineWidth: size * 0.1).frame(width: size * 0.72, height: size)
            Path { path in
                path.move(to: CGPoint(x: size * 0.30, y: size * 0.40))
                path.addLine(to: CGPoint(x: size * 0.46, y: size * 0.24))
                path.move(to: CGPoint(x: size * 0.30, y: size * 0.57))
                path.addLine(to: CGPoint(x: size * 0.57, y: size * 0.30))
            }
            .stroke(style: StrokeStyle(lineWidth: size * 0.09, lineCap: .round))
        }
        .frame(width: size, height: size)
    }
}
