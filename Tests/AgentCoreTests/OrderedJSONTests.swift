import Foundation
import Testing
@testable import AgentCore

@Suite("Ordered JSON")
struct OrderedJSONTests {
    /// Written the way `JSON.stringify(value, null, 2) + "\n"` writes it, as Claude Code does.
    static let sample = #"""
    {
      "zeta": 1,
      "alpha": [
        "a\"b\\c\n\t/",
        "ünïcødé ✓ 🚀",
        -1.5e+21,
        0.25,
        true,
        false,
        null,
        {},
        []
      ],
      "nested": {
        "b": {
          "c": [
            {
              "d": "\u0001"
            }
          ]
        },
        "a": "x"
      }
    }

    """#

    @Test func roundTripIsByteIdentical() throws {
        let value = try JSONValue.parse(Self.sample)
        #expect(value.formatted() + "\n" == Self.sample)
    }

    @Test func keyOrderIsPreserved() throws {
        let value = try JSONValue.parse(#"{"b":1,"a":2,"c":3}"#)
        #expect(value.objectKeys == ["b", "a", "c"])
    }

    @Test func compactInputIsPrettyPrinted() throws {
        let value = try JSONValue.parse(#"{"a":[1,{"b":"é"}]}"#)
        #expect(value.formatted() == "{\n  \"a\": [\n    1,\n    {\n      \"b\": \"é\"\n    }\n  ]\n}")
    }

    @Test func invalidJSONIsRejected() {
        for bad in ["", "{", #"{"a":}"#, #"{"a":1,}"#, "[1 2]", #"{"a":1} x"#, "nul", #""\x""#, "01"] {
            #expect(throws: JSONValue.ParseError.self, "\(bad)") { try JSONValue.parse(bad) }
        }
    }

    @Test func surrogatePairsDecode() throws {
        let value = try JSONValue.parse(#""🚀""#)
        #expect(value == .string("🚀"))
    }

    /// Opt-in check against a real file without writing to it:
    /// `PERCH_ROUNDTRIP_FILE=~/.claude/settings.json swift test --filter roundTripOfARealFile`
    @Test func roundTripOfARealFile() throws {
        guard let path = ProcessInfo.processInfo.environment["PERCH_ROUNDTRIP_FILE"] else { return }
        let text = try String(contentsOfFile: path, encoding: .utf8)
        let value = try JSONValue.parse(text)
        #expect(value.formatted() + "\n" == text)
    }
}
