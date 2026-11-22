import Foundation

/// JSON value that keeps object key order and number spelling, so a settings file
/// can be read, changed in one place and written back without disturbing anything else.
/// `formatted()` writes the same text as JavaScript's `JSON.stringify(value, null, 2)`,
/// which is how Claude Code writes `~/.claude/settings.json`.
public indirect enum JSONValue: Equatable, Sendable {
    case object([Member])
    case array([JSONValue])
    case string(String)
    /// The number exactly as spelled in the source.
    case number(String)
    case bool(Bool)
    case null

    public struct Member: Equatable, Sendable {
        public var name: String
        public var value: JSONValue
        public init(_ name: String, _ value: JSONValue) {
            self.name = name
            self.value = value
        }
    }

    public struct ParseError: Error, Equatable, CustomStringConvertible {
        public var message: String
        public var offset: Int
        public var description: String { "\(message) at byte \(offset)" }
    }

    // MARK: Access

    public var objectKeys: [String] {
        if case .object(let members) = self { return members.map(\.name) }
        return []
    }

    public var arrayValue: [JSONValue]? {
        if case .array(let items) = self { return items }
        return nil
    }

    public var stringValue: String? {
        if case .string(let s) = self { return s }
        return nil
    }

    public var isObject: Bool {
        if case .object = self { return true }
        return false
    }

    /// First member with this name, for objects.
    public subscript(name: String) -> JSONValue? {
        if case .object(let members) = self { return members.first { $0.name == name }?.value }
        return nil
    }

    // MARK: Parse

    public static func parse(_ text: String) throws -> JSONValue {
        var parser = Parser(bytes: Array(text.utf8))
        parser.skipWhitespace()
        let value = try parser.value(depth: 0)
        parser.skipWhitespace()
        guard parser.index == parser.bytes.count else { throw parser.error("Unexpected text after JSON") }
        return value
    }

    private struct Parser {
        let bytes: [UInt8]
        var index = 0

        func error(_ message: String) -> ParseError { ParseError(message: message, offset: index) }

        mutating func skipWhitespace() {
            while index < bytes.count, [0x20, 0x0A, 0x0D, 0x09].contains(bytes[index]) { index += 1 }
        }

        mutating func expect(_ literal: String) throws {
            let lit = Array(literal.utf8)
            guard index + lit.count <= bytes.count, Array(bytes[index ..< index + lit.count]) == lit else {
                throw error("Expected \(literal)")
            }
            index += lit.count
        }

        mutating func value(depth: Int) throws -> JSONValue {
            guard depth < 512 else { throw error("Nesting too deep") }
            guard index < bytes.count else { throw error("Unexpected end of input") }
            switch bytes[index] {
            case UInt8(ascii: "{"): return try object(depth: depth)
            case UInt8(ascii: "["): return try array(depth: depth)
            case UInt8(ascii: "\""): return .string(try string())
            case UInt8(ascii: "t"): try expect("true"); return .bool(true)
            case UInt8(ascii: "f"): try expect("false"); return .bool(false)
            case UInt8(ascii: "n"): try expect("null"); return .null
            case UInt8(ascii: "-"), UInt8(ascii: "0") ... UInt8(ascii: "9"): return .number(try number())
            default: throw error("Unexpected character")
            }
        }

        mutating func object(depth: Int) throws -> JSONValue {
            index += 1
            var members: [Member] = []
            skipWhitespace()
            if index < bytes.count, bytes[index] == UInt8(ascii: "}") {
                index += 1
                return .object(members)
            }
            while true {
                skipWhitespace()
                guard index < bytes.count, bytes[index] == UInt8(ascii: "\"") else { throw error("Expected key") }
                let name = try string()
                skipWhitespace()
                try expect(":")
                skipWhitespace()
                members.append(Member(name, try value(depth: depth + 1)))
                skipWhitespace()
                guard index < bytes.count else { throw error("Unterminated object") }
                if bytes[index] == UInt8(ascii: ",") { index += 1; continue }
                if bytes[index] == UInt8(ascii: "}") { index += 1; return .object(members) }
                throw error("Expected , or }")
            }
        }

        mutating func array(depth: Int) throws -> JSONValue {
            index += 1
            var items: [JSONValue] = []
            skipWhitespace()
            if index < bytes.count, bytes[index] == UInt8(ascii: "]") {
                index += 1
                return .array(items)
            }
            while true {
                skipWhitespace()
                items.append(try value(depth: depth + 1))
                skipWhitespace()
                guard index < bytes.count else { throw error("Unterminated array") }
                if bytes[index] == UInt8(ascii: ",") { index += 1; continue }
                if bytes[index] == UInt8(ascii: "]") { index += 1; return .array(items) }
                throw error("Expected , or ]")
            }
        }

        mutating func number() throws -> String {
            let start = index
            func digits() -> Int {
                let s = index
                while index < bytes.count, (UInt8(ascii: "0") ... UInt8(ascii: "9")).contains(bytes[index]) { index += 1 }
                return index - s
            }
            if bytes[index] == UInt8(ascii: "-") { index += 1 }
            guard index < bytes.count else { throw error("Bad number") }
            if bytes[index] == UInt8(ascii: "0") {
                index += 1
                if index < bytes.count, (UInt8(ascii: "0") ... UInt8(ascii: "9")).contains(bytes[index]) {
                    throw error("Leading zero")
                }
            } else if digits() == 0 {
                throw error("Bad number")
            }
            if index < bytes.count, bytes[index] == UInt8(ascii: ".") {
                index += 1
                guard digits() > 0 else { throw error("Bad fraction") }
            }
            if index < bytes.count, bytes[index] == UInt8(ascii: "e") || bytes[index] == UInt8(ascii: "E") {
                index += 1
                if index < bytes.count, bytes[index] == UInt8(ascii: "+") || bytes[index] == UInt8(ascii: "-") { index += 1 }
                guard digits() > 0 else { throw error("Bad exponent") }
            }
            return String(decoding: bytes[start ..< index], as: UTF8.self)
        }

        mutating func hex4() throws -> UInt32 {
            guard index + 4 <= bytes.count else { throw error("Bad \\u escape") }
            var v: UInt32 = 0
            for _ in 0 ..< 4 {
                let c = bytes[index]
                let d: UInt32
                switch c {
                case UInt8(ascii: "0") ... UInt8(ascii: "9"): d = UInt32(c - UInt8(ascii: "0"))
                case UInt8(ascii: "a") ... UInt8(ascii: "f"): d = UInt32(c - UInt8(ascii: "a") + 10)
                case UInt8(ascii: "A") ... UInt8(ascii: "F"): d = UInt32(c - UInt8(ascii: "A") + 10)
                default: throw error("Bad \\u escape")
                }
                v = v * 16 + d
                index += 1
            }
            return v
        }

        mutating func string() throws -> String {
            index += 1  // opening quote
            var out: [UInt8] = []
            while true {
                guard index < bytes.count else { throw error("Unterminated string") }
                let c = bytes[index]
                if c == UInt8(ascii: "\"") {
                    index += 1
                    return String(decoding: out, as: UTF8.self)
                }
                if c < 0x20 { throw error("Control character in string") }
                if c != UInt8(ascii: "\\") {
                    out.append(c)
                    index += 1
                    continue
                }
                index += 1
                guard index < bytes.count else { throw error("Bad escape") }
                let e = bytes[index]
                index += 1
                switch e {
                case UInt8(ascii: "\""): out.append(UInt8(ascii: "\""))
                case UInt8(ascii: "\\"): out.append(UInt8(ascii: "\\"))
                case UInt8(ascii: "/"): out.append(UInt8(ascii: "/"))
                case UInt8(ascii: "b"): out.append(0x08)
                case UInt8(ascii: "f"): out.append(0x0C)
                case UInt8(ascii: "n"): out.append(0x0A)
                case UInt8(ascii: "r"): out.append(0x0D)
                case UInt8(ascii: "t"): out.append(0x09)
                case UInt8(ascii: "u"):
                    var scalar = try hex4()
                    if (0xD800 ... 0xDBFF).contains(scalar), index + 1 < bytes.count,
                       bytes[index] == UInt8(ascii: "\\"), bytes[index + 1] == UInt8(ascii: "u")
                    {
                        let save = index
                        index += 2
                        let low = try hex4()
                        if (0xDC00 ... 0xDFFF).contains(low) {
                            scalar = 0x10000 + ((scalar - 0xD800) << 10) + (low - 0xDC00)
                        } else {
                            index = save
                        }
                    }
                    let s = Unicode.Scalar(scalar) ?? "\u{FFFD}"
                    out.append(contentsOf: Array(String(Character(s)).utf8))
                default: throw error("Bad escape")
                }
            }
        }
    }

    // MARK: Format

    /// Same text as `JSON.stringify(value, null, 2)` (no trailing newline).
    public func formatted() -> String {
        var out = ""
        write(to: &out, indent: 0)
        return out
    }

    private func write(to out: inout String, indent: Int) {
        switch self {
        case .null: out += "null"
        case .bool(let b): out += b ? "true" : "false"
        case .number(let n): out += n
        case .string(let s): Self.writeString(s, to: &out)
        case .array(let items):
            guard !items.isEmpty else { out += "[]"; return }
            let pad = String(repeating: "  ", count: indent + 1)
            out += "[\n"
            for (i, item) in items.enumerated() {
                out += pad
                item.write(to: &out, indent: indent + 1)
                out += i == items.count - 1 ? "\n" : ",\n"
            }
            out += String(repeating: "  ", count: indent) + "]"
        case .object(let members):
            guard !members.isEmpty else { out += "{}"; return }
            let pad = String(repeating: "  ", count: indent + 1)
            out += "{\n"
            for (i, member) in members.enumerated() {
                out += pad
                Self.writeString(member.name, to: &out)
                out += ": "
                member.value.write(to: &out, indent: indent + 1)
                out += i == members.count - 1 ? "\n" : ",\n"
            }
            out += String(repeating: "  ", count: indent) + "}"
        }
    }

    private static func writeString(_ s: String, to out: inout String) {
        out += "\""
        for scalar in s.unicodeScalars {
            switch scalar {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if scalar.value < 0x20 {
                    out += String(format: "\\u%04x", scalar.value)
                } else {
                    out.unicodeScalars.append(scalar)
                }
            }
        }
        out += "\""
    }
}
