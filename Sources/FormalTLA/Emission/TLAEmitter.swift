import FormalCore
import FormalIR
import Foundation

public struct TLAEmitter: TLAEmitting {
    public init() {}

    public func emit(_ program: IRProgram) throws -> [GeneratedFile] {
        try program.validate()
        guard let url = Bundle.module.url(forResource: "SwiftFormalRuntime", withExtension: "tla") else {
            throw FormalDiagnostic(.ioFailure, "Missing TLA runtime resource.")
        }
        let runtime = try String(contentsOf: url, encoding: .utf8)
        let functions = try program.functions.map(function).joined(separator: ",\n  ")
        let source = """
        ------------------------------ MODULE Program ------------------------------
        EXTENDS SwiftFormalRuntime
        CONSTANTS EntrySymbol, EntryArguments
        VARIABLE state
        ProgramData == <<
          \(functions)
        >>
        Init == /\\ InputTypesMatch(ProgramData, EntrySymbol, EntryArguments)
                /\\ state = Initial(ProgramData, EntrySymbol, EntryArguments)
        ActualStep == Step(ProgramData, state, state')
        Next == ActualStep \\/ (Terminal(state) /\\ UNCHANGED state)
        Spec == Init /\\ [][Next]_state
        NoTrap == state.status # "trapped"
        NoDeadlock == Terminal(state) \\/ ENABLED ActualStep
        ============================================================================

        """
        let properties = """
        ---------------------------- MODULE Properties -----------------------------
        EXTENDS Program
        Safety == NoTrap /\\ NoDeadlock
        ============================================================================

        """
        return [.init(path: "tla/Program.tla", contents: source),
                .init(path: "tla/SwiftFormalRuntime.tla", contents: runtime),
                .init(path: "tla/Properties.tla", contents: properties)]
    }

    private func function(_ value: IRFunction) throws -> String {
        let blocks = try value.blocks.map(block).joined(separator: ",\n    ")
        let rendered0 = try quote(value.moduleID)
        let rendered1 = try quote(value.symbol)
        let rendered2 = try type(value.result)
        return "[moduleID |-> \(rendered0), symbol |-> \(rendered1), resultType |-> \(rendered2), blocks |-> <<\n    \(blocks)\n  >>]"
    }

    private func block(_ value: IRBlock) throws -> String {
        let parameters = try value.parameters.map { parameter in
            let rendered0 = try quote(parameter.id)
            let rendered1 = try type(parameter.type)
            return "[id |-> \(rendered0), type |-> \(rendered1)]"
        }.joined(separator: ", ")
        let instructions = try value.instructions.map(instruction).joined(separator: ",\n      ")
        let rendered0 = try quote(value.id)
        return "[id |-> \(rendered0), parameters |-> <<\(parameters)>>, instructions |-> <<\n      \(instructions)\n    >>]"
    }

    private func type(_ value: IRType) throws -> String {
        switch value {
        case .bits(let width):
            return "[kind |-> \"bits\", width |-> \(width)]"
        case .aggregate(let elements):
            let rendered0 = try elements.map(type).joined(separator: ", ")
            return "[kind |-> \"aggregate\", elements |-> <<\(rendered0)>>]"
        case .function(let parameters, let result):
            let rendered0 = try parameters.map(type).joined(separator: ", ")
            let rendered1 = try type(result)
            return "[kind |-> \"function\", parameters |-> <<\(rendered0)>>, result |-> \(rendered1)]"
        }
    }

    private func instruction(_ value: IRInstruction) throws -> String {
        let fields: [String]
        switch value {
        case .literal(let destination, let value):
            let rendered0 = try quote(destination)
            fields = ["op |-> \"literal\"", "destination |-> \(rendered0)", "width |-> \(value.width)", "value |-> \(bitSequence(value))"]
        case .aggregate(let destination, let elements):
            let rendered0 = try quote(destination)
            let rendered1 = try list(elements)
            fields = ["op |-> \"aggregate\"", "destination |-> \(rendered0)", "elements |-> \(rendered1)"]
        case .extract(let destination, let source, let index):
            let rendered0 = try quote(destination)
            let rendered1 = try quote(source)
            fields = ["op |-> \"extract\"", "destination |-> \(rendered0)", "source |-> \(rendered1)", "index |-> \(index)"]
        case .binary(let destination, let operation, let left, let right):
            let rendered0 = try quote(destination)
            let rendered1 = try quote(operation.rawValue)
            let rendered2 = try quote(left)
            let rendered3 = try quote(right)
            fields = ["op |-> \"binary\"", "destination |-> \(rendered0)", "operation |-> \(rendered1)", "left |-> \(rendered2)", "right |-> \(rendered3)"]
        case .functionRef(let destination, let symbol):
            let rendered0 = try quote(destination)
            let rendered1 = try quote(symbol)
            fields = ["op |-> \"functionRef\"", "destination |-> \(rendered0)", "symbol |-> \(rendered1)"]
        case .call(let destination, let callee, let arguments):
            let rendered0 = try quote(destination)
            let rendered1 = try quote(callee)
            let rendered2 = try list(arguments)
            fields = ["op |-> \"call\"", "destination |-> \(rendered0)", "callee |-> \(rendered1)", "arguments |-> \(rendered2)"]
        case .jump(let block, let arguments):
            let rendered0 = try quote(block)
            let rendered1 = try list(arguments)
            fields = ["op |-> \"jump\"", "block |-> \(rendered0)", "arguments |-> \(rendered1)"]
        case .branch(let condition, let thenBlock, let thenArguments, let elseBlock, let elseArguments):
            let rendered0 = try quote(condition)
            let rendered1 = try quote(thenBlock)
            let rendered2 = try list(thenArguments)
            let rendered3 = try quote(elseBlock)
            let rendered4 = try list(elseArguments)
            fields = ["op |-> \"branch\"", "condition |-> \(rendered0)", "thenBlock |-> \(rendered1)", "thenArguments |-> \(rendered2)", "elseBlock |-> \(rendered3)", "elseArguments |-> \(rendered4)"]
        case .trapIf(let condition, let message):
            let rendered0 = try quote(condition)
            let rendered1 = try quote(message)
            fields = ["op |-> \"trapIf\"", "condition |-> \(rendered0)", "message |-> \(rendered1)"]
        case .returnValue(let source):
            let rendered0 = try quote(source)
            fields = ["op |-> \"returnValue\"", "source |-> \(rendered0)"]
        }
        return "[\(fields.joined(separator: ", "))]"
    }

    private func bitSequence(_ value: BitPattern) -> String {
        let bits = (0..<value.width).map { String((value.bits >> $0) & 1) }.joined(separator: ", ")
        return "<<\(bits)>>"
    }

    private func list(_ values: [String]) throws -> String {
        let quoted = try values.map(quote)
        return "<<\(quoted.joined(separator: ", "))>>"
    }

    private func quote(_ text: String) throws -> String {
        var result = "\""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"": result += "\\\""
            case "\\": result += "\\\\"
            case "\n": result += "\\n"
            case "\r": result += "\\r"
            case "\t": result += "\\t"
            default:
                guard scalar.value >= 32, scalar.value < 127 else {
                    throw FormalDiagnostic(.unsupportedType, "The initial TLA scalar slice requires ASCII string data.")
                }
                result.unicodeScalars.append(scalar)
            }
        }
        return result + "\""
    }
}
