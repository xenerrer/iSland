import Foundation

/// A small diagnostic log in `~/.island/island.log` (readable only by you): what the island did and anything that looked
/// wrong, so a visual glitch can be traced afterwards. It records events and sizes, never what was said in a chat: no
/// prompts, titles, commands or paths. It stops growing at 512 KB (the old half is dropped).
enum IslandLog {
    private static let queue = DispatchQueue(label: "island.log", qos: .utility)
    private static let limit = 512 * 1024
    private static let stamp: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        return f
    }()

    static var url: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".island/island.log")
    }

    /// `category` is a short tag: "island", "layout", "display", "anomaly"...
    static func write(_ category: String, _ message: String) {
        let line = "\(stamp.string(from: Date())) [\(category)] \(message)\n"
        queue.async {
            let fm = FileManager.default
            try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true,
                                    attributes: [.posixPermissions: 0o700])
            if !fm.fileExists(atPath: url.path) { fm.createFile(atPath: url.path, contents: nil, attributes: [.posixPermissions: 0o600]) }
            if let size = (try? fm.attributesOfItem(atPath: url.path))?[.size] as? Int, size > limit,
               let data = try? Data(contentsOf: url) {
                let tail = data.suffix(limit / 2)
                try? tail.write(to: url, options: .atomic)
                try? fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
            }
            guard let handle = try? FileHandle(forWritingTo: url) else { return }
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: Data(line.utf8))
        }
    }
}
