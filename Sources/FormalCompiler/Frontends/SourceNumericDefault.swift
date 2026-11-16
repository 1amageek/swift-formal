/// The domain for JS-family scalar types left unconstrained by the source.
public enum SourceNumericDefault: String, Codable, Sendable {
    case number, bigint
    var scalarType: ScalarType { self == .number ? .number : .integer }
}
