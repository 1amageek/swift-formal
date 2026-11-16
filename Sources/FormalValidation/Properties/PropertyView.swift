import FormalIR

public enum PropertyView: String, Codable, Sendable {
    case integer, signed, unsigned, boolean

    func accepts(_ type: IRType) -> Bool {
        switch (self, type) {
        case (.integer, .integer), (.boolean, .bits(width: 1)): true
        case (.signed, .bits), (.unsigned, .bits): true
        default: false
        }
    }
    var expressionType: PropertyExpression.Kind { self == .boolean ? .boolean : .integer }
}
