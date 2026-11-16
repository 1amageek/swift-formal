public typealias PropertyView = ScalarView

extension ScalarView {
    var expressionType: PropertyExpression.Kind {
        switch self {
        case .boolean: .boolean
        case .number: .number
        default: .integer
        }
    }
}
