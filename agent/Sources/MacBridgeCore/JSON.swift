import Foundation

public enum JSON: Codable, Sendable, Equatable {
    case object([String: JSON]), array([JSON]), string(String), number(Double), bool(Bool), null
    public init(from decoder: any Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let b = try? c.decode(Bool.self) { self = .bool(b) }
        else if let s = try? c.decode(String.self) { self = .string(s) }
        else if let n = try? c.decode(Double.self) { self = .number(n) }
        else if let a = try? c.decode([JSON].self) { self = .array(a) }
        else { self = .object(try c.decode([String: JSON].self)) }
    }
    public func encode(to encoder: any Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .object(let x): try c.encode(x)
        case .array(let x): try c.encode(x)
        case .string(let x): try c.encode(x)
        case .number(let x): try c.encode(x)
        case .bool(let x): try c.encode(x)
        case .null: try c.encodeNil()
        }
    }
    public subscript(_ key: String) -> JSON? { if case .object(let x) = self { x[key] } else { nil } }
    public var string: String? { if case .string(let x) = self { x } else { nil } }
    public var object: [String: JSON]? { if case .object(let x) = self { x } else { nil } }
    public var array: [JSON]? { if case .array(let x) = self { x } else { nil } }
    public var number: Double? { if case .number(let x) = self { x } else { nil } }
    public static func parse(_ data: Data) throws -> JSON { try JSONDecoder().decode(JSON.self, from: data) }
    public func data() throws -> Data { try JSONEncoder().encode(self) }
}

public enum WireTime {
    public static func parse(_ text: String) -> Date? {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let d = f.date(from: text) { return d }
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: text)
    }
    public static func text(_ date: Date = Date()) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: date)
    }
}

public struct ContractError: Error, Sendable {
    public let code: String
    public init(code: String) { self.code = code }
}

/// Evaluates the deliberately small JSON Schema vocabulary in contracts/v1.schema.json.
/// This is not a general purpose JSON Schema implementation. Unknown keywords fail closed.
public struct ContractValidator: Sendable {
    private let root: JSON
    public init(schema: Data) throws {
        root = try JSON.parse(schema)
        try Self.checkVocabulary(root)
    }
    private static func checkVocabulary(_ schema: JSON) throws {
        guard let object = schema.object else { throw ContractError(code: "invalid_schema") }
        let known: Set<String> = ["$schema", "$id", "$defs", "$ref", "type", "properties", "required", "additionalProperties", "oneOf", "anyOf", "enum", "const", "items", "minItems", "maxItems", "uniqueItems", "minLength", "maxLength", "minimum", "maximum", "pattern", "format", "default", "description"]
        guard Set(object.keys).isSubset(of: known) else { throw ContractError(code: "unsupported_schema_keyword") }
        for key in ["$defs", "properties"] {
            for child in schema[key]?.object?.values ?? Dictionary<String, JSON>().values { try checkVocabulary(child) }
        }
        for key in ["oneOf", "anyOf"] { for child in schema[key]?.array ?? [] { try checkVocabulary(child) } }
        if let items = schema["items"] { try checkVocabulary(items) }
        if let format = schema["format"]?.string, !["uuid", "date-time", "uri"].contains(format) { throw ContractError(code: "unsupported_schema_format") }
    }
    public func validate(_ model: String, _ value: JSON) throws {
        guard let schema = root["$defs"]?[model] else { throw ContractError(code: "unknown_model") }
        guard matches(schema, value) else { throw ContractError(code: "invalid_message") }
    }
    private func matches(_ schema: JSON, _ value: JSON) -> Bool {
        if let path = schema["$ref"]?.string {
            guard path.hasPrefix("#/$defs/"), let target = root["$defs"]?[String(path.dropFirst(8))] else { return false }
            if !matches(target, value) { return false }
        }
        if let options = schema["oneOf"]?.array, options.filter({ matches($0, value) }).count != 1 { return false }
        if let options = schema["anyOf"]?.array, !options.contains(where: { matches($0, value) }) { return false }
        if let constant = schema["const"], constant != value { return false }
        if let values = schema["enum"]?.array, !values.contains(value) { return false }
        if let type = schema["type"]?.string {
            switch (type, value) {
            case ("object", .object), ("array", .array), ("string", .string), ("boolean", .bool), ("null", .null), ("number", .number): break
            case ("integer", .number(let n)) where n.isFinite && n.rounded() == n: break
            default: return false
            }
        }
        if let props = value.object {
            let declared = schema["properties"]?.object ?? [:]
            if schema["additionalProperties"] == .bool(false), !Set(props.keys).isSubset(of: Set(declared.keys)) { return false }
            for key in schema["required"]?.array ?? [] { guard let key = key.string, props[key] != nil else { return false } }
            for (key, subschema) in declared { if let child = props[key], !matches(subschema, child) { return false } }
        }
        if let array = value.array {
            if let min = schema["minItems"]?.number, Double(array.count) < min { return false }
            if let max = schema["maxItems"]?.number, Double(array.count) > max { return false }
            if let items = schema["items"], !array.allSatisfy({ matches(items, $0) }) { return false }
            if schema["uniqueItems"] == .bool(true) {
                for i in array.indices where array[..<i].contains(array[i]) { return false }
            }
        }
        if let n = value.number {
            if let min = schema["minimum"]?.number, n < min { return false }
            if let max = schema["maximum"]?.number, n > max { return false }
        }
        if let s = value.string {
            // JSON Schema length counts Unicode code points, not Swift grapheme clusters.
            if let min = schema["minLength"]?.number, Double(s.unicodeScalars.count) < min { return false }
            if let max = schema["maxLength"]?.number, Double(s.unicodeScalars.count) > max { return false }
            if let pattern = schema["pattern"]?.string, s.range(of: pattern, options: .regularExpression) == nil { return false }
            if let format = schema["format"]?.string {
                switch format {
                case "uuid": if UUID(uuidString: s) == nil { return false }
                case "date-time": if WireTime.parse(s) == nil { return false }
                case "uri":
                    guard !s.unicodeScalars.contains(where: { CharacterSet.whitespacesAndNewlines.contains($0) }),
                          let url = URLComponents(string: s), url.scheme != nil else { return false }
                    if ["http", "https"].contains(url.scheme), url.host?.isEmpty != false { return false }
                default: return false
                }
            }
        }
        return true
    }
}

public func envelope(_ type: String, _ fields: [String: JSON] = [:]) -> JSON {
    var data = fields
    data["v"] = .number(1); data["type"] = .string(type)
    data["id"] = .string(UUID().uuidString.lowercased()); data["ts"] = .string(WireTime.text())
    return .object(data)
}
