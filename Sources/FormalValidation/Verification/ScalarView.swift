import FormalIR

public enum ScalarView: String, Codable, Sendable {
    case integer, signed, unsigned, boolean, number
    func accepts(_ type: IRType) -> Bool {
        switch (self, type) {
        case (.integer, .integer), (.boolean, .bits(width: 1)), (.number, .bits(width: 64)): true
        case (.signed, .bits), (.unsigned, .bits): true
        default: false
        }
    }
}
