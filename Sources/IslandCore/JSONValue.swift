import Foundation

/// Order-preserving JSON tree.
///
/// Exists so we can edit a user's settings.json without reordering or rewriting anything we did not touch:
/// object members keep their order, and numbers keep their original text through a parse/serialize round trip.
public enum JSONValue: Equatable, Sendable {
    case null
    case bool(Bool)
    case number(String)
    case string(String)
    case array([JSONValue])
    case object([JSONMember])
}

public struct JSONMember: Equatable, Sendable {
    public var key: String
    public var value: JSONValue

    public init(_ key: String, _ value: JSONValue) {
        self.key = key
        self.value = value
    }
}

public struct JSONError: Error, CustomStringConvertible, Equatable {
    public let message: String
    public let offset: Int
    public var description: String { "\(message) (byte \(offset))" }
}

public extension JSONValue {
    /// Strict enough for real settings files; numbers are validated but kept verbatim.
    static func parse(_ data: Data) throws -> JSONValue {
        var parser = JSONParser(bytes: [UInt8](data))
        parser.skipBOM()
        let value = try parser.parseValue(depth: 0)
        parser.skipWhitespace()
        guard parser.index == parser.bytes.count else { throw parser.fail("unexpected trailing content") }
        return value
    }

    /// Object member lookup. With duplicate keys the last one wins, like JSON.parse.
    /// Setting `nil` removes the member; setting a new key appends it; setting an existing key keeps its position.
    subscript(_ key: String) -> JSONValue? {
        get {
            guard case .object(let members) = self else { return nil }
            return members.last(where: { $0.key == key })?.value
        }
        set {
            guard case .object(var members) = self else { return }
            if let index = members.lastIndex(where: { $0.key == key }) {
                if let newValue { members[index].value = newValue } else { members.remove(at: index) }
            } else if let newValue {
                members.append(JSONMember(key, newValue))
            }
            self = .object(members)
        }
    }

    /// Pretty-prints like `JSON.stringify(value, null, 2)`: 2-space indent, one array element per line, `"key": value`.
    func serialized() -> String {
        var out = ""
        write(to: &out, level: 0)
        return out
    }

    var stringValue: String? {
        if case .string(let text) = self { return text }
        return nil
    }

    var arrayValue: [JSONValue]? {
        if case .array(let items) = self { return items }
        return nil
    }

    var boolValue: Bool? {
        if case .bool(let value) = self { return value }
        return nil
    }

    var doubleValue: Double? {
        if case .number(let text) = self { return Double(text) }
        return nil
    }

    /// Single-line JSON, for wire output and display.
    func compact() -> String {
        switch self {
        case .null: return "null"
        case .bool(let value): return value ? "true" : "false"
        case .number(let text): return text
        case .string(let text): return Self.quote(text)
        case .array(let items): return "[" + items.map { $0.compact() }.joined(separator: ",") + "]"
        case .object(let members):
            return "{" + members.map { Self.quote($0.key) + ":" + $0.value.compact() }.joined(separator: ",") + "}"
        }
    }
}

private extension JSONValue {
    func write(to out: inout String, level: Int) {
        switch self {
        case .null: out += "null"
        case .bool(let value): out += value ? "true" : "false"
        case .number(let text): out += text
        case .string(let text): out += Self.quote(text)
        case .array(let items):
            if items.isEmpty { out += "[]"; return }
            out += "[\n"
            for (i, item) in items.enumerated() {
                out += Self.indent(level + 1)
                item.write(to: &out, level: level + 1)
                out += i < items.count - 1 ? ",\n" : "\n"
            }
            out += Self.indent(level) + "]"
        case .object(let members):
            if members.isEmpty { out += "{}"; return }
            out += "{\n"
            for (i, member) in members.enumerated() {
                out += Self.indent(level + 1) + Self.quote(member.key) + ": "
                member.value.write(to: &out, level: level + 1)
                out += i < members.count - 1 ? ",\n" : "\n"
            }
            out += Self.indent(level) + "}"
        }
    }

    static func indent(_ level: Int) -> String { String(repeating: "  ", count: level) }

    static func quote(_ text: String) -> String {
        var result = "\""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"": result += "\\\""
            case "\\": result += "\\\\"
            case "\n": result += "\\n"
            case "\r": result += "\\r"
            case "\t": result += "\\t"
            case "\u{08}": result += "\\b"
            case "\u{0C}": result += "\\f"
            default:
                if scalar.value < 0x20 {
                    result += String(format: "\\u%04x", scalar.value)
                } else {
                    result.unicodeScalars.append(scalar)
                }
            }
        }
        return result + "\""
    }
}

struct JSONParser {
    let bytes: [UInt8]
    var index = 0
    private let maxDepth = 256

    init(bytes: [UInt8]) { self.bytes = bytes }

    func fail(_ message: String) -> JSONError { JSONError(message: message, offset: index) }

    mutating func skipBOM() {
        if bytes.count >= 3, bytes[0] == 0xEF, bytes[1] == 0xBB, bytes[2] == 0xBF { index = 3 }
    }

    mutating func skipWhitespace() {
        while index < bytes.count {
            switch bytes[index] {
            case 0x20, 0x09, 0x0A, 0x0D: index += 1
            default: return
            }
        }
    }

    mutating func parseValue(depth: Int) throws -> JSONValue {
        guard depth < maxDepth else { throw fail("nesting too deep") }
        skipWhitespace()
        guard index < bytes.count else { throw fail("unexpected end of input") }
        switch bytes[index] {
        case UInt8(ascii: "{"): return try parseObject(depth: depth)
        case UInt8(ascii: "["): return try parseArray(depth: depth)
        case UInt8(ascii: "\""): return .string(try parseString())
        case UInt8(ascii: "t"): try expect("true"); return .bool(true)
        case UInt8(ascii: "f"): try expect("false"); return .bool(false)
        case UInt8(ascii: "n"): try expect("null"); return .null
        default: return try parseNumber()
        }
    }

    private mutating func expect(_ word: String) throws {
        let expected = Array(word.utf8)
        guard index + expected.count <= bytes.count, Array(bytes[index..<index + expected.count]) == expected else {
            throw fail("invalid literal")
        }
        index += expected.count
    }

    private mutating func parseNumber() throws -> JSONValue {
        let start = index
        while index < bytes.count {
            let c = bytes[index]
            let isNumberChar = (c >= 0x30 && c <= 0x39) || c == UInt8(ascii: "-") || c == UInt8(ascii: "+")
                || c == UInt8(ascii: ".") || c == UInt8(ascii: "e") || c == UInt8(ascii: "E")
            if isNumberChar { index += 1 } else { break }
        }
        guard index > start, let text = String(bytes: bytes[start..<index], encoding: .utf8), Double(text) != nil else {
            index = start
            throw fail("invalid value")
        }
        return .number(text)
    }

    private mutating func parseString() throws -> String {
        index += 1 // opening quote
        var out: [UInt8] = []
        while true {
            guard index < bytes.count else { throw fail("unterminated string") }
            let c = bytes[index]
            switch c {
            case UInt8(ascii: "\""):
                index += 1
                guard let text = String(bytes: out, encoding: .utf8) else { throw fail("invalid UTF-8 in string") }
                return text
            case UInt8(ascii: "\\"):
                index += 1
                guard index < bytes.count else { throw fail("unterminated escape") }
                let escape = bytes[index]
                index += 1
                switch escape {
                case UInt8(ascii: "\""): out.append(0x22)
                case UInt8(ascii: "\\"): out.append(0x5C)
                case UInt8(ascii: "/"): out.append(0x2F)
                case UInt8(ascii: "b"): out.append(0x08)
                case UInt8(ascii: "f"): out.append(0x0C)
                case UInt8(ascii: "n"): out.append(0x0A)
                case UInt8(ascii: "r"): out.append(0x0D)
                case UInt8(ascii: "t"): out.append(0x09)
                case UInt8(ascii: "u"): out.append(contentsOf: try parseUnicodeEscape())
                default: throw fail("invalid escape")
                }
            case 0..<0x20:
                throw fail("control character in string")
            default:
                out.append(c)
                index += 1
            }
        }
    }

    /// Called right after `\u`. Combines surrogate pairs.
    private mutating func parseUnicodeEscape() throws -> [UInt8] {
        var value = try parseHex4()
        if (0xD800...0xDBFF).contains(value) {
            guard index + 1 < bytes.count, bytes[index] == UInt8(ascii: "\\"), bytes[index + 1] == UInt8(ascii: "u") else {
                throw fail("unpaired surrogate")
            }
            index += 2
            let low = try parseHex4()
            guard (0xDC00...0xDFFF).contains(low) else { throw fail("invalid surrogate pair") }
            value = 0x10000 + ((value - 0xD800) << 10) + (low - 0xDC00)
        } else if (0xDC00...0xDFFF).contains(value) {
            throw fail("unpaired surrogate")
        }
        guard let scalar = Unicode.Scalar(value) else { throw fail("invalid unicode escape") }
        return Array(String(Character(scalar)).utf8)
    }

    private mutating func parseHex4() throws -> UInt32 {
        guard index + 4 <= bytes.count else { throw fail("truncated unicode escape") }
        var value: UInt32 = 0
        for _ in 0..<4 {
            let c = bytes[index]
            index += 1
            switch c {
            case 0x30...0x39: value = value * 16 + UInt32(c - 0x30)
            case 0x41...0x46: value = value * 16 + UInt32(c - 0x41 + 10)
            case 0x61...0x66: value = value * 16 + UInt32(c - 0x61 + 10)
            default: throw fail("invalid hex digit")
            }
        }
        return value
    }

    private mutating func parseArray(depth: Int) throws -> JSONValue {
        index += 1
        var items: [JSONValue] = []
        skipWhitespace()
        if index < bytes.count, bytes[index] == UInt8(ascii: "]") { index += 1; return .array(items) }
        while true {
            items.append(try parseValue(depth: depth + 1))
            skipWhitespace()
            guard index < bytes.count else { throw fail("unterminated array") }
            if bytes[index] == UInt8(ascii: ",") { index += 1; continue }
            if bytes[index] == UInt8(ascii: "]") { index += 1; return .array(items) }
            throw fail("expected , or ]")
        }
    }

    private mutating func parseObject(depth: Int) throws -> JSONValue {
        index += 1
        var members: [JSONMember] = []
        skipWhitespace()
        if index < bytes.count, bytes[index] == UInt8(ascii: "}") { index += 1; return .object(members) }
        while true {
            skipWhitespace()
            guard index < bytes.count, bytes[index] == UInt8(ascii: "\"") else { throw fail("expected string key") }
            let key = try parseString()
            skipWhitespace()
            guard index < bytes.count, bytes[index] == UInt8(ascii: ":") else { throw fail("expected :") }
            index += 1
            members.append(JSONMember(key, try parseValue(depth: depth + 1)))
            skipWhitespace()
            guard index < bytes.count else { throw fail("unterminated object") }
            if bytes[index] == UInt8(ascii: ",") { index += 1; continue }
            if bytes[index] == UInt8(ascii: "}") { index += 1; return .object(members) }
            throw fail("expected , or }")
        }
    }
}
