import AppKit
import IslandCore

enum MediaCommand: Int {
    case togglePlayPause = 2
    case next = 4
    case previous = 5
}

/// Where the media adapter lives: inside the app bundle, or in the repository's ThirdParty folder when developing.
struct AdapterLocation {
    let script: String
    let framework: String

    static func find() -> AdapterLocation? {
        var pairs: [(script: URL, framework: URL)] = []
        if let resources = Bundle.main.resourceURL, let frameworks = Bundle.main.privateFrameworksURL {
            pairs.append((resources.appendingPathComponent("mediaremote-adapter.pl"),
                          frameworks.appendingPathComponent("MediaRemoteAdapter.framework")))
        }
        var folders: [URL] = []
        #if DEBUG
        // Only in a development build: a released app must never load an adapter from wherever an environment variable says.
        if let override = ProcessInfo.processInfo.environment["ISLAND_ADAPTER_DIR"] { folders.append(URL(fileURLWithPath: override)) }
        #endif
        var walk = Bundle.main.executableURL?.deletingLastPathComponent()
        for _ in 0..<8 {
            guard let current = walk else { break }
            folders.append(current.appendingPathComponent("ThirdParty/mediaremote-adapter"))
            walk = current.deletingLastPathComponent()
        }
        for folder in folders {
            pairs.append((folder.appendingPathComponent("mediaremote-adapter.pl"),
                          folder.appendingPathComponent("MediaRemoteAdapter.framework")))
        }
        let fm = FileManager.default
        guard let found = pairs.first(where: { fm.fileExists(atPath: $0.script.path) && fm.fileExists(atPath: $0.framework.path) })
        else { return nil }
        return AdapterLocation(script: found.script.path, framework: found.framework.path)
    }
}

/// What is playing, from any app that registers with the system's Now Playing.
///
/// macOS 15.4 closed the MediaRemote framework to ordinary apps, but not to Apple's own `/usr/bin/perl`, so a Perl
/// script loads the adapter framework and prints one JSON line per change. This class runs it as a child process.
@MainActor
final class NowPlayingManager: ObservableObject {
    @Published private(set) var state = NowPlayingState()
    @Published private(set) var artwork: NSImage?
    /// "Spotify", "Music", "Google Chrome"...
    @Published private(set) var appName: String?

    private var decoder = NowPlayingDecoder()
    private var buffer = Data()
    private var process: Process?
    private var stopped = true
    private var shownArtwork: String?
    private var restartDelay = 3.0
    private var startedAt: Date?
    private let location = AdapterLocation.find()

    var isAvailable: Bool { location != nil }

    func start() {
        stopped = false
        if location == nil { NSLog("iSland: media adapter not found; the music card stays off") }
        restartDelay = 3
        Task.detached(priority: .utility) { Self.reapOrphans() } // a `ps` scan: not on the main thread
        launch()
    }

    func stop() {
        stopped = true
        process?.terminate()
        process = nil
        publish(NowPlayingState())
    }

    func send(_ command: MediaCommand) {
        guard let location else { return }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        task.arguments = [location.script, location.framework, "send", String(command.rawValue)]
        task.environment = Self.cleanEnvironment
        task.standardOutput = FileHandle.nullDevice
        task.standardError = FileHandle.nullDevice
        try? task.run()
    }

    /// For demos and snapshots: show a made-up track.
    func preview(_ preview: NowPlayingState, appName: String?) {
        self.appName = appName
        artwork = nil
        state = preview
    }

    // MARK: Process

    /// A previous run that was killed outright (SIGKILL, a crash) leaves its adapter behind, reading nothing, until the
    /// next track change makes it write to a closed pipe. Those have been adopted by launchd (parent pid 1); stop them.
    nonisolated static func reapOrphans() {
        let list = Process()
        list.executableURL = URL(fileURLWithPath: "/bin/ps")
        list.arguments = ["-axo", "pid=,ppid=,command="]
        let pipe = Pipe()
        list.standardOutput = pipe
        list.standardError = FileHandle.nullDevice
        guard (try? list.run()) != nil else { return }
        let output = pipe.fileHandleForReading.readDataToEndOfFile()
        list.waitUntilExit()
        for pid in orphanedAdapterPIDs(inProcessList: String(decoding: output, as: UTF8.self)) { kill(pid, SIGTERM) }
    }

    /// Adapter `stream` processes whose parent is launchd, from `ps -axo pid=,ppid=,command=` output.
    nonisolated static func orphanedAdapterPIDs(inProcessList text: String) -> [Int32] {
        text.split(separator: "\n").compactMap { line in
            let fields = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: true)
            guard fields.count == 3, fields[1] == "1",
                  fields[2].contains("mediaremote-adapter.pl"), fields[2].contains(" stream")
            else { return nil }
            return Int32(fields[0])
        }
    }

    private func launch() {
        guard !stopped, process == nil, let location else { return }
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/bin/perl")
        task.arguments = [location.script, location.framework, "stream", "--debounce=120"]
        task.environment = Self.cleanEnvironment
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = FileHandle.nullDevice
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { handle.readabilityHandler = nil; return }
            Task { @MainActor in self?.receive(data) }
        }
        task.terminationHandler = { [weak self] finished in
            Task { @MainActor in self?.ended(finished) }
        }
        do {
            try task.run()
            process = task
            startedAt = Date()
            buffer.removeAll()
            decoder = NowPlayingDecoder()
        } catch {
            NSLog("iSland: could not start the media adapter: \(error)")
            scheduleRestart()
        }
    }

    private func ended(_ finished: Process) {
        guard process === finished else { return }
        process = nil
        // A helper that dies at once (a macOS update broke the framework) is retried with growing pauses, not every 3 s forever.
        if let startedAt, Date().timeIntervalSince(startedAt) > 30 { restartDelay = 3 } else { restartDelay = min(300, restartDelay * 2) }
        publish(NowPlayingState())
        scheduleRestart()
    }

    private func scheduleRestart() {
        guard !stopped else { return }
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(restartDelay))
            launch()
        }
    }

    private func receive(_ data: Data) {
        buffer.append(data)
        while let newline = buffer.firstIndex(of: 0x0A) {
            let line = Data(buffer[buffer.startIndex..<newline])
            buffer.removeSubrange(buffer.startIndex...newline)
            if decoder.ingest(line: line) { publish(decoder.state) }
        }
    }

    private func publish(_ new: NowPlayingState) {
        if new.artworkBase64 != shownArtwork {
            shownArtwork = new.artworkBase64
            artwork = new.artworkBase64.flatMap { Data(base64Encoded: $0) }.flatMap { NSImage(data: $0) }
        }
        let owner = new.parentBundleID ?? new.bundleID
        if owner != state.parentBundleID ?? state.bundleID || appName == nil { appName = Self.displayName(forBundleID: owner) }
        state = new
    }

    /// perl reads variables such as PERL5OPT and PERL5LIB that run code of their choosing; the adapter gets none of ours.
    nonisolated static let cleanEnvironment = ["PATH": "/usr/bin:/bin"]

    static func displayName(forBundleID id: String?) -> String? {
        guard let id else { return nil }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) else { return id }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }
}
