public indirect enum StateValue: Codable, Sendable, Equatable {
    case integer(String)
    case boolean(Bool)
    case bitvector(width: Int, bits: String)
    case string(String)
    case sequence([StateValue])
    case record([String: StateValue])
    case set([StateValue])
    case opaque(String)

    private struct WireKey: CodingKey {
        let stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }
    private enum Key: String, CodingKey { case type, value, width }
    public init(from decoder: any Decoder) throws {
        guard decoder.codingPath.count <= 256 else { throw FormalEvidenceError.limit("State value nesting") }
        let container = try decoder.container(keyedBy: Key.self)
        let type = try container.decode(String.self,forKey: .type)
        switch type {
        case "integer":
            let value = try container.decode(String.self,forKey: .value)
            guard Self.validInteger(value) else { throw FormalEvidenceError.invalid("Noncanonical state integer") }; self = .integer(value)
        case "boolean": self = .boolean(try container.decode(Bool.self,forKey: .value))
        case "bitvector":
            let width = try container.decode(Int.self,forKey: .width)
            let bits = try container.decode(String.self,forKey: .value)
            guard width > 0, bits.utf8.count == width, bits.utf8.allSatisfy({ $0 == 48 || $0 == 49 }) else { throw FormalEvidenceError.invalid("State bitvector width/value") }
            self = .bitvector(width: width,bits: bits)
        case "string": self = .string(try container.decode(String.self,forKey: .value))
        case "sequence": self = .sequence(try container.decode([StateValue].self,forKey: .value))
        case "record": self = .record(try container.decode([String:StateValue].self,forKey: .value))
        case "set": self = .set(try container.decode([StateValue].self,forKey: .value))
        case "opaque": self = .opaque(try container.decode(String.self,forKey: .value))
        default: throw FormalEvidenceError.unsupported("State value tag")
        }
        let wire = try decoder.container(keyedBy: WireKey.self)
        guard Set(wire.allKeys.map(\.stringValue)) == (type == "bitvector" ? ["type","value","width"] : ["type","value"]) else { throw FormalEvidenceError.invalid("Unexpected state value field") }
    }
    public func encode(to encoder: any Encoder) throws {
        guard encoder.codingPath.count <= 256 else { throw FormalEvidenceError.limit("State value nesting") }
        var container = encoder.container(keyedBy: Key.self)
        switch self {
        case .integer(let value):
            guard Self.validInteger(value) else { throw FormalEvidenceError.invalid("Noncanonical state integer") }
            try container.encode("integer",forKey: .type); try container.encode(value,forKey: .value)
        case .boolean(let value): try container.encode("boolean",forKey: .type); try container.encode(value,forKey: .value)
        case .bitvector(let width,let bits):
            guard width > 0, bits.utf8.count == width, bits.utf8.allSatisfy({ $0 == 48 || $0 == 49 }) else { throw FormalEvidenceError.invalid("State bitvector width/value") }
            try container.encode("bitvector",forKey: .type); try container.encode(width,forKey: .width); try container.encode(bits,forKey: .value)
        case .string(let value): try container.encode("string",forKey: .type); try container.encode(value,forKey: .value)
        case .sequence(let value): try container.encode("sequence",forKey: .type); try container.encode(value,forKey: .value)
        case .record(let value): try container.encode("record",forKey: .type); try container.encode(value,forKey: .value)
        case .set(let value): try container.encode("set",forKey: .type); try container.encode(value,forKey: .value)
        case .opaque(let value): try container.encode("opaque",forKey: .type); try container.encode(value,forKey: .value)
        }
    }
    private static func validInteger(_ value: String) -> Bool {
        var bytes = value.utf8[...]
        if bytes.first == 45 { bytes = bytes.dropFirst(); if bytes.first == 48 { return false } }
        guard let first = bytes.first, (48...57).contains(first), bytes.count == 1 || first != 48 else { return false }
        return bytes.allSatisfy { (48...57).contains($0) }
    }
}
