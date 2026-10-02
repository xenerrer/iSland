import Foundation

/// Which displays carry an island. The default follows the main display (the one System Settings > Displays marks with the
/// menu bar), so plugging in a monitor changes nothing; the user can ask for every display, or one in particular.
public enum DisplayChoice: Equatable, Sendable {
    case main
    case all
    case specific(UInt32)

    public init(raw: String?) {
        switch raw {
        case "all": self = .all
        case let r? where r.hasPrefix("id:"):
            if let id = UInt32(r.dropFirst(3)) { self = .specific(id) } else { self = .main }
        default: self = .main
        }
    }

    public var raw: String {
        switch self {
        case .main: return "main"
        case .all: return "all"
        case .specific(let id): return "id:\(id)"
        }
    }

    /// The displays to put an island on, out of `available` (main display first, as `NSScreen.screens` lists them).
    /// A display that was chosen but is unplugged falls back to the main one: the island never vanishes altogether.
    public func targets(available: [UInt32]) -> [UInt32] {
        guard let main = available.first else { return [] }
        switch self {
        case .main: return [main]
        case .all: return available
        case .specific(let id): return available.contains(id) ? [id] : [main]
        }
    }
}
