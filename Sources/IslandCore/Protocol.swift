import Foundation

/// A yes/no question an agent is waiting on. The hook builds it from the agent's own payload,
/// so the app never needs to know any agent's schema.
public struct PermissionPrompt: Codable, Equatable, Sendable {
    public var tool: String
    /// Short verb phrase: "Run command", "Edit file"...
    public var title: String
    /// What exactly will happen: the command, the path, the URL. May be multi-line.
    public var detail: String
    /// Label of the persistent "always allow" rule the agent offered; nil when it offered none.
    public var alwaysLabel: String?
    /// How long the hook keeps waiting before it hands the question back to the agent's own terminal.
    public var waitSeconds: Int
    /// The command is so big (past `maxDetailCharacters`) that the island had to cut it off: there is part nobody can read
    /// here, so it offers no one-click yes and the answer belongs in the agent's own terminal. Anything shorter is allowed:
    /// the card scrolls, so all of it can be read.
    public var needsReview: Bool

    public init(tool: String, title: String, detail: String, alwaysLabel: String? = nil, waitSeconds: Int, needsReview: Bool = false) {
        self.tool = tool
        self.title = title
        self.detail = detail
        self.alwaysLabel = alwaysLabel
        self.waitSeconds = waitSeconds
        self.needsReview = needsReview
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        tool = try c.decode(String.self, forKey: .tool)
        title = try c.decode(String.self, forKey: .title)
        detail = try c.decode(String.self, forKey: .detail)
        alwaysLabel = try c.decodeIfPresent(String.self, forKey: .alwaysLabel)
        waitSeconds = try c.decode(Int.self, forKey: .waitSeconds)
        needsReview = try c.decodeIfPresent(Bool.self, forKey: .needsReview) ?? false
    }

    /// How many lines of the card the detail can take, and how much fits on one (a conservative estimate: monospaced text).
    public static let visibleLines = 6
    public static let charactersPerLine = 46
    /// The most text the card keeps (it scrolls inside its box); more than this is cut and cannot be approved from here.
    public static let maxDetailCharacters = 8000

    /// More than fits in the box: it scrolls.
    public var isLong: Bool { Self.estimatedLines(of: detail) > Self.visibleLines }
    /// Invisible or direction-changing characters were replaced by a visible mark (⍰) in the text.
    public var hasHiddenCharacters: Bool { detail.unicodeScalars.contains("\u{2370}") }

    public static func estimatedLines(of text: String) -> Int {
        max(1, text.split(separator: "\n", omittingEmptySubsequences: false)
            .reduce(0) { $0 + max(1, ($1.count + charactersPerLine - 1) / charactersPerLine) })
    }
}

/// Text from an agent, made safe to show in front of someone deciding on it.
public enum DisplayText {
    /// Control characters, invisible characters and the ones that flip the direction of text can make a command look like
    /// something it is not. They are replaced with a visible mark, and the caller is told that it happened.
    public static func sanitized(_ text: String) -> (text: String, changed: Bool) {
        var changed = false
        var result = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            let kind = scalar.properties.generalCategory
            if scalar == "\n" || scalar == "\t" || (kind != .control && kind != .format && kind != .lineSeparator && kind != .paragraphSeparator) {
                result.append(scalar)
            } else {
                result.append("\u{2370}") // ⍰
                changed = true
            }
        }
        return (String(result), changed)
    }
}

public enum Decision: String, Codable, Sendable {
    case allow
    /// Allow, and apply the persistent rule the agent suggested.
    case allowAlways
    case deny
    /// Decide nothing: the agent asks in its own terminal, exactly as if iSland were not running.
    case terminal
}

public struct DecisionReply: Codable, Equatable, Sendable {
    public var decision: Decision
    public init(_ decision: Decision) { self.decision = decision }
}
