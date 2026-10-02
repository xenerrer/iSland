import Foundation

/// What the system says is playing, as reported by the media adapter: any app that registers with Now Playing
/// (Music, Spotify, a browser tab...).
public struct NowPlayingState: Equatable, Sendable {
    public var bundleID: String?
    /// For web apps and helpers, the app that owns them (e.g. the browser).
    public var parentBundleID: String?
    public var title = ""
    /// On YouTube this is the channel's name.
    public var artist = ""
    public var album = ""
    public var isPlaying = false
    public var duration: Double?
    public var elapsed: Double?
    public var rate: Double = 0
    /// When `elapsed` was measured.
    public var timestamp: Date?
    /// Base64 of the cover image; decoded by the view layer only when it changes.
    public var artworkBase64: String?

    public init() {}

    /// There is something worth showing: a title or an artist.
    public var hasTrack: Bool { !title.isEmpty || !artist.isEmpty }

    /// Playback position now, extrapolated from the last report while playing.
    public func elapsedNow(at now: Date = Date()) -> Double? {
        guard let elapsed else { return nil }
        var value = elapsed
        if isPlaying, let timestamp { value += now.timeIntervalSince(timestamp) * (rate > 0 ? rate : 1) }
        if let duration, duration > 0 { value = min(value, duration) }
        return max(0, value)
    }
}

/// Turns the adapter's output (one JSON object per line) into a `NowPlayingState`.
///
/// Lines look like `{"type":"data","diff":false,"payload":{...}}`. A full message replaces the state; a `diff`
/// message carries only the keys that changed (`null` clears one). An empty payload means nothing is playing.
public struct NowPlayingDecoder {
    public private(set) var state = NowPlayingState()
    public init() {}

    /// Feeds one line. Returns true when the state changed. Malformed lines are ignored.
    @discardableResult
    public mutating func ingest(line: Data) -> Bool {
        guard let message = try? JSONValue.parse(line), message["type"]?.stringValue == "data" else { return false }
        let before = state
        let isDiff = message["diff"]?.boolValue ?? false
        if !isDiff { state = NowPlayingState() }
        if case .object(let members)? = message["payload"] {
            for member in members { apply(member.key, member.value) }
        }
        return state != before
    }

    private mutating func apply(_ key: String, _ value: JSONValue) {
        let text = value.stringValue
        switch key {
        case "title": state.title = text ?? ""
        case "artist": state.artist = text ?? ""
        case "album": state.album = text ?? ""
        case "bundleIdentifier": state.bundleID = text
        case "parentApplicationBundleIdentifier": state.parentBundleID = text
        case "playing": state.isPlaying = value.boolValue ?? false
        case "duration": state.duration = value.doubleValue
        case "elapsedTime": state.elapsed = value.doubleValue
        case "playbackRate": state.rate = value.doubleValue ?? 0
        case "timestamp": state.timestamp = text.flatMap { Self.parseDate($0) }
        case "artworkData": state.artworkBase64 = (text?.isEmpty == false) ? text : nil
        default: break
        }
    }

    private static func parseDate(_ text: String) -> Date? {
        let plain = ISO8601DateFormatter()
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return plain.date(from: text) ?? fractional.date(from: text)
    }
}
