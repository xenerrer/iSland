import Foundation
import Testing
@testable import IslandCore

@Suite("JSONValue") struct JSONValueTests {
    @Test func roundTripKeepsOrderNumbersAndStyle() throws {
        let text = """
        {
          "z": 1,
          "a": [
            1.50,
            2e3,
            true,
            null,
            "x\\ny"
          ],
          "m": {}
        }
        """
        let value = try JSONValue.parse(Data(text.utf8))
        #expect(value.serialized() == text)
    }

    @Test func decodesUnicodeEscapesAndSurrogatePairs() throws {
        let value = try JSONValue.parse(Data(#"{"e":"caf\u00e9 \ud83d\ude00"}"#.utf8))
        #expect(value["e"] == .string("café 😀"))
    }

    @Test func rejectsMalformedInput() {
        for bad in ["", "{", "{\"a\":}", "[1,]", "{\"a\":1} x", "\"\\ud800\"", "{\"a\" 1}"] {
            #expect(throws: JSONError.self) { try JSONValue.parse(Data(bad.utf8)) }
        }
    }

    @Test func subscriptKeepsPositionAndAppendsNewKeys() throws {
        var value = try JSONValue.parse(Data(#"{"a":1,"b":2}"#.utf8))
        value["a"] = .number("9")
        value["c"] = .bool(true)
        value["b"] = nil
        #expect(value == .object([JSONMember("a", .number("9")), JSONMember("c", .bool(true))]))
    }
}
