import FormalCore
import FormalIR
import FormalEvidence
import Foundation

public struct TLAEmitter: TLAEmitting {
    public init() {}

    public func emit(_ program: IRProgram) throws -> [GeneratedDocument] {
        try program.validate()
        guard let url = Bundle.module.url(forResource: "SwiftFormalRuntime", withExtension: "tla") else {
            throw FormalDiagnostic(.ioFailure, "Missing TLA runtime resource.")
        }
        let runtime = try String(contentsOf: url, encoding: .utf8)
        var source = TrackedEmission()
        source.append("""
        ------------------------------ MODULE Program ------------------------------
        EXTENDS SwiftFormalRuntime
        CONSTANTS EntrySymbol, EntryArguments
        VARIABLE state
        ProgramData == <<

        """)
        for (index, value) in program.functions.enumerated() {
            if index > 0 { source.append(",\n  ") }
            source.append(try function(value))
        }
        source.append("""

        >>
        Init == /\\ InputTypesMatch(ProgramData, EntrySymbol, EntryArguments)
                /\\ state = Initial(ProgramData, EntrySymbol, EntryArguments)
        ActualStep == Step(ProgramData, state, state')
        Next == ActualStep \\/ (Terminal(state) /\\ UNCHANGED state)
        Spec == Init /\\ [][Next]_state
        NoTrap == state.status # "trapped"
        NoFailure == state.status \\notin {"trapped", "panic", "undefinedBehavior"}
        NoDeadlock == Terminal(state) \\/ ENABLED ActualStep
        ============================================================================

        """)
        let programDigest = EvidenceIdentity.digest(try ArtifactJSON.encode(program))
        let properties = """
        ---------------------------- MODULE Properties -----------------------------
        EXTENDS Program
        Safety == NoFailure /\\ NoDeadlock
        ============================================================================

        """
        return [source.document(path: "tla/Program.tla",programDigest: programDigest),
                .init(path: "tla/SwiftFormalRuntime.tla", contents: runtime, origins: []),
                .init(path: "tla/Properties.tla", contents: properties, origins: [])]
    }

    private func function(_ value: IRFunction) throws -> TrackedEmission {
        let module = try quote(value.moduleID), symbol = try quote(value.symbol), result = try type(value.result)
        var text = TrackedEmission()
        text.append("[moduleID |-> \(module), symbol |-> \(symbol), resultType |-> \(result), blocks |-> <<\n    ")
        for (index, valueBlock) in value.blocks.enumerated() {
            if index > 0 { text.append(",\n    ") }
            text.append(try block(valueBlock,function: value.symbol))
        }
        text.append("\n  >>]"); text.mark(function: value.symbol,start: 0)
        return text
    }
    private func block(_ value: IRBlock, function: String) throws -> TrackedEmission {
        let parameters = try value.parameters.map { parameter in
            let id = try quote(parameter.id), kind = try type(parameter.type)
            return "[id |-> \(id), type |-> \(kind)]"
        }.joined(separator: ", ")
        let id = try quote(value.id)
        var text = TrackedEmission()
        text.append("[id |-> \(id), parameters |-> <<\(parameters)>>, instructions |-> <<\n      ")
        for (index, valueInstruction) in value.instructions.enumerated() {
            if index > 0 { text.append(",\n      ") }
            let start = text.byteCount
            text.append(try instruction(valueInstruction))
            text.mark(function: function,block: value.id,instruction: index,start: start)
        }
        text.append("\n    >>]"); text.mark(function: function,block: value.id,start: 0)
        return text
    }

    private func type(_ value: IRType) throws -> String {
        switch value {
        case .integer: return "[kind |-> \"integer\"]"
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
        case .integerLiteral(let destination, let value):
            let d = try quote(destination)
            let v = try quote(value.description)
            fields = ["op |-> \"integerLiteral\"", "destination |-> \(d)", "decimal |-> \(v)"]
        case .integerBinary(let destination, let operation, let left, let right):
            let d = try quote(destination)
            let o = try quote(operation.rawValue)
            let a = try quote(left)
            let b = try quote(right)
            fields = ["op |-> \"integerBinary\"", "destination |-> \(d)", "operation |-> \(o)", "left |-> \(a)", "right |-> \(b)"]
        case .failIf(let condition, let kind, let message):
            let c = try quote(condition)
            let k = try quote(kind.rawValue)
            let m = try quote(message)
            fields = ["op |-> \"failIf\"", "condition |-> \(c)", "kind |-> \(k)", "message |-> \(m)"]
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
