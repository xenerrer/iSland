@preconcurrency import AVFoundation
import AppKit
import IslandCore

/// The camera behind the mirror: on only while the mirror shows, so the camera light is on exactly then.
/// Every opening builds a fresh capture session and every closing throws it away, so the second time behaves exactly
/// like the first.
@MainActor
final class MirrorManager: ObservableObject {
    enum State: Equatable { case off, starting, running, denied, unavailable }

    @Published private(set) var state: State = .off
    @Published private(set) var session: AVCaptureSession?
    /// The photo just taken, for a few seconds: the card says where it went.
    @Published private(set) var lastPhoto: URL?
    /// True for an instant when the shutter fires.
    @Published private(set) var flash = false
    private var photoOutput: AVCapturePhotoOutput?
    private var pending: PhotoDelegate?
    /// The first photo asks, inside the mirror, whether iSland may save into Pictures. (Not a system alert: an app with no
    /// active window cannot count on clicks reaching one.)
    @Published private(set) var askingToSave = false
    private static let allowedKey = "mayWritePhotosToPictures"
    private let queue = DispatchQueue(label: "iSland.mirror")
    /// Bumped on every open and close, so a slow start that finishes after the mirror was closed is ignored.
    private var generation = 0
    private var errorObserver: NSObjectProtocol?

    /// Like the calendar, only a real .app may ask: a plain binary would be asking on behalf of Terminal or Claude.
    static var canAsk: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    func start() {
        generation += 1
        guard Self.canAsk else { state = .unavailable; return }
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            run(generation)
        case .notDetermined:
            state = .starting
            let wanted = generation
            AVCaptureDevice.requestAccess(for: .video) { granted in
                Task { @MainActor in
                    guard self.generation == wanted else { return } // closed while the question was up
                    if granted { self.run(wanted) } else { self.state = .denied }
                }
            }
        default:
            state = .denied
        }
    }

    func stop() {
        generation += 1
        state = .off
        let old = session
        session = nil
        photoOutput = nil
        lastPhoto = nil
        askingToSave = false
        if let errorObserver { NotificationCenter.default.removeObserver(errorObserver) }
        errorObserver = nil
        queue.async { old?.stopRunning() }
    }

    /// Takes a photo and saves it in Pictures/iSland. The first time, it asks whether iSland may save there. The picture is
    /// the way others see you (not mirrored like the preview).
    func takePhoto() {
        guard state == .running, let output = photoOutput else { return }
        guard UserDefaults.standard.bool(forKey: Self.allowedKey) else { askingToSave = true; return }
        flash = true
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(180))
            flash = false
        }
        let settings = output.availablePhotoCodecTypes.contains(.jpeg)
            ? AVCapturePhotoSettings(format: [AVVideoCodecKey: AVVideoCodecType.jpeg]) : AVCapturePhotoSettings()
        let delegate = PhotoDelegate { [weak self] data in
            Task { @MainActor in self?.save(data) }
        }
        pending = delegate
        output.capturePhoto(with: settings, delegate: delegate)
    }

    /// "Allow" on the question: remembers it and takes the photo that was waiting.
    func allowSaving() {
        UserDefaults.standard.set(true, forKey: Self.allowedKey)
        askingToSave = false
        takePhoto()
    }

    func declineSaving() { askingToSave = false }

    func revealLastPhoto() {
        if let lastPhoto { NSWorkspace.shared.activateFileViewerSelecting([lastPhoto]) }
    }

    private func save(_ data: Data?) {
        pending = nil
        guard let data else { NSLog("iSland: the camera gave no picture"); return }
        let folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Pictures/iSland", isDirectory: true)
        do {
            // Your face is nobody else's business: the folder and the files are readable by you alone.
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            let url = PhotoFiles.uniqueURL(in: folder, for: Date())
            try data.write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            lastPhoto = url
            Task { @MainActor in
                try? await Task.sleep(for: .seconds(6))
                if lastPhoto == url { lastPhoto = nil }
            }
        } catch {
            NSLog("iSland: could not save the photo: %@", String(describing: error))
        }
    }

    func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Camera") { NSWorkspace.shared.open(url) }
    }

    private func run(_ wanted: Int) {
        state = .starting
        let fresh = AVCaptureSession()
        fresh.sessionPreset = fresh.canSetSessionPreset(.photo) ? .photo : .high
        guard let device = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: device),
              fresh.canAddInput(input) else {
            NSLog("iSland: no camera found for the mirror")
            state = .unavailable
            return
        }
        fresh.addInput(input)
        let output = AVCapturePhotoOutput()
        if fresh.canAddOutput(output) {
            fresh.addOutput(output)
            photoOutput = output
        }
        errorObserver = NotificationCenter.default.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: fresh, queue: .main) { note in
            NSLog("iSland: camera error: %@", String(describing: note.userInfo?[AVCaptureSessionErrorKey]))
        }
        session = fresh
        queue.async { [weak self] in
            fresh.startRunning()
            let running = fresh.isRunning
            Task { @MainActor in
                guard let self, self.generation == wanted else { return }
                if !running { NSLog("iSland: the camera session did not start") }
                self.state = running ? .running : .unavailable
            }
        }
    }
}

/// Receives the finished photo from the camera.
final class PhotoDelegate: NSObject, AVCapturePhotoCaptureDelegate {
    private let done: (Data?) -> Void

    init(done: @escaping (Data?) -> Void) { self.done = done }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        if let error { NSLog("iSland: photo failed: %@", String(describing: error)) }
        done(error == nil ? photo.fileDataRepresentation() : nil)
    }
}
