import FormalCore
import FormalIR

struct BoundProperty {
    let specification: PropertySpecification.Property
    let function: IRFunction
    let precondition: PropertyExpression
    let postcondition: PropertyExpression
    let inputTypes: [IRType]

    init(_ specification: PropertySpecification.Property, program: IRProgram) throws {
        guard let function = program.functions.first(where: { $0.symbol == specification.entry }), let first = function.blocks.first,
              first.parameters.count == specification.inputViews.count,
              specification.resultView.accepts(function.result) else { throw PropertySpecification.invalid("Entry signature or resultView mismatch") }
        for (view, parameter) in zip(specification.inputViews, first.parameters) {
            guard view.accepts(parameter.type) else { throw PropertySpecification.invalid("inputViews do not match the entry signature") }
        }
        self.specification = specification
        self.function = function
        self.inputTypes = first.parameters.map(\.type)
        self.precondition = try PropertyExpressionParser.parse(specification.requires, inputs: specification.inputViews, result: nil, numberLiterals: specification.resultView == .number)
        self.postcondition = try PropertyExpressionParser.parse(specification.ensures, inputs: specification.inputViews, result: specification.resultView)
    }
    var binders: String {
        zip(specification.inputViews.indices, specification.inputViews).map { index, view in
            "(a\(index) : \(view == .integer ? "Int" : view == .boolean ? "Bool" : "Nat"))"
        }.joined(separator: " ")
    }
    var names: [String] { specification.inputViews.indices.map { "a\($0)" } }
    var domains: [String] {
        inputTypes.enumerated().compactMap { index, type in
            if case .bits(let width) = type, specification.inputViews[index] != .boolean { return "a\(index) < \(Self.powerOfTwo(width))" }
            return nil
        }
    }
    var domainBinders: String { domains.enumerated().map { "(domain\($0.offset) : \($0.element))" }.joined(separator: " ") }
    var leanInputs: [String] {
        zip(specification.inputViews.indices, specification.inputViews).map { index, view in
            Self.leanView(view, type: inputTypes[index], name: "a\(index)")
        }
    }
    var leanArguments: [String] {
        inputTypes.enumerated().map { index, type in
            switch type {
            case .integer: "(.integer a\(index))"
            case .bits(let width): "(.bits \(width) \(specification.inputViews[index] == .boolean ? "(if a\(index) then 1 else 0)" : "a\(index)"))"
            default: preconditionFailure("Bound property contains a nonscalar input")
            }
        }
    }
    var leanPrecondition: String { precondition.lean(inputs: leanInputs, result: "False") }
    var leanPostcondition: String {
        let result = Self.leanView(specification.resultView, type: function.result, name: "r")
        let condition = postcondition.lean(inputs: leanInputs, result: result)
        if case .bits(let width) = function.result { return "r < 2 ^ \(width) ∧ \(condition)" }
        return condition
    }
    var resultPattern: String {
        switch function.result {
        case .integer: "(.integer r)"
        case .bits(let width): "(.bits \(width) r)"
        default: preconditionFailure("Bound property contains a nonscalar result")
        }
    }
    static func powerOfTwo(_ width: Int) -> String { width == 64 ? "18446744073709551616" : String(UInt64(1) << width) }
    private static func leanView(_ view: PropertyView, type: IRType, name: String) -> String {
        switch view {
        case .integer, .number: return name
        case .boolean: return name == "r" ? "(r = 1)" : "(\(name) = true)"
        case .unsigned: return "(Int.ofNat \(name))"
        case .signed:
            guard case .bits(let width) = type else { preconditionFailure("Signed view requires bits") }
            return "(SwiftFormal.signed \(width) \(name))"
        }
    }
}
