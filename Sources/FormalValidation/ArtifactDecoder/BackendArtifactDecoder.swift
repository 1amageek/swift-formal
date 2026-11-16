import FormalCore
import FormalIR

public struct BackendArtifactDecoder: Sendable {
    public init() {}

    public func decodeLeanProgram(_ source: String) throws -> IRProgram {
        let tokens = try RestrictedLexer.tokenize(source)
        let prefix = try RestrictedLexer.tokenize("import SwiftFormal.Runtime open SwiftFormal namespace Generated def program : Program :=")
        guard Array(tokens.prefix(prefix.count)) == prefix else { throw bad("Unexpected Lean program wrapper") }
        var parser = RestrictedDataParser(tokens: tokens, lean: true, cursor: prefix.count)
        let data = try parser.value()
        guard Array(tokens.dropFirst(parser.cursor)) == ["end", "Generated"] else { throw bad("Unexpected code after Lean program") }
        return try program(data, lean: true)
    }

    public func decodeTLAProgram(_ source: String) throws -> IRProgram {
        let tokens = try RestrictedLexer.tokenize(source)
        let prefix = try RestrictedLexer.tokenize("------------------------------ MODULE Program ------------------------------ EXTENDS SwiftFormalRuntime CONSTANTS EntrySymbol, EntryArguments VARIABLE state ProgramData ==")
        guard Array(tokens.prefix(prefix.count)) == prefix else { throw bad("Unexpected TLA program wrapper") }
        var parser = RestrictedDataParser(tokens: tokens, lean: false, cursor: prefix.count)
        let data = try parser.value()
        let suffix = try RestrictedLexer.tokenize("""
        Init == /\\ InputTypesMatch(ProgramData, EntrySymbol, EntryArguments)
                /\\ state = Initial(ProgramData, EntrySymbol, EntryArguments)
        ActualStep == Step(ProgramData, state, state')
        Next == ActualStep \\/ (Terminal(state) /\\ UNCHANGED state)
        Spec == Init /\\ [][Next]_state
        NoTrap == state.status # "trapped"
        NoDeadlock == Terminal(state) \\/ ENABLED ActualStep
        ============================================================================
        """)
        guard Array(tokens.dropFirst(parser.cursor)) == suffix else { throw bad("TLA transition, condition, frame, or property wrapper changed") }
        return try program(data, lean: false)
    }

    private func program(_ data: ArtifactData, lean: Bool) throws -> IRProgram {
        let functions = try list(data).map { data -> IRFunction in
            let fields = try record(data, keys: lean ? ["moduleID", "symbol", "result", "blocks"] : ["moduleID", "symbol", "resultType", "blocks"])
            let symbol = try text(fields["symbol"])
            let result = try type(fields[lean ? "result" : "resultType"], lean: lean)
            let blocks = try list(fields["blocks"]).map { data -> IRBlock in
                let fields = try record(data, keys: ["id", "parameters", "instructions"])
                let id = try text(fields["id"])
                let parameters = try list(fields["parameters"]).map { data -> IRParameter in
                    let fields = try record(data, keys: ["id", "type"])
                    let id = try text(fields["id"])
                    let type = try type(fields["type"], lean: lean)
                    return IRParameter(id: id, type: type)
                }
                let instructions = try list(fields["instructions"]).map { try instruction($0, lean: lean) }
                return IRBlock(id: id, parameters: parameters, instructions: instructions)
            }
            let moduleID = try text(fields["moduleID"])
            return IRFunction(moduleID: moduleID, symbol: symbol, result: result, blocks: blocks)
        }
        let program = IRProgram(functions: functions)
        try program.validate()
        return program
    }

    private func type(_ data: ArtifactData?, lean: Bool) throws -> IRType {
        if lean {
            guard case .constructor(let name, let args) = data else { throw bad("Invalid Lean type") }
            switch (name, args.count) {
            case ("bits", 1):
                let decoded0 = try integer(args[0])
                return .bits(width: decoded0)
            case ("aggregate", 1):
                let elements = try list(args[0])
                let types = try elements.map { try type($0, lean: true) }
                return .aggregate(types)
            case ("function", 2):
                let parameters = try list(args[0]).map { try type($0, lean: true) }
                let result = try type(args[1], lean: true)
                return .function(parameters: parameters, result: result)
            default: throw bad("Unknown Lean type constructor")
            }
        }
        guard case .record(let fields) = data else { throw bad("Invalid TLA type") }
        let kind = try text(fields["kind"])
        switch kind {
        case "bits":
            _ = try record(data, keys: ["kind", "width"])
            let decoded0 = try integer(fields["width"])
            return .bits(width: decoded0)
        case "aggregate":
            _ = try record(data, keys: ["kind", "elements"])
            let elements = try list(fields["elements"])
            let types = try elements.map { try type($0, lean: false) }
            return .aggregate(types)
        case "function":
            _ = try record(data, keys: ["kind", "parameters", "result"])
            let parameters = try list(fields["parameters"]).map { try type($0, lean: false) }
            let result = try type(fields["result"], lean: false)
            return .function(parameters: parameters, result: result)
        default: throw bad("Unknown TLA type")
        }
    }

    private func instruction(_ data: ArtifactData, lean: Bool) throws -> IRInstruction {
        let name: String
        let args: [ArtifactData]
        if lean {
            guard case .constructor(let constructor, let arguments) = data else { throw bad("Invalid Lean instruction") }
            name = constructor
            args = arguments
        } else {
            guard case .record(let fields) = data else { throw bad("Invalid TLA instruction") }
            name = try text(fields["op"])
            let keys: [String]
            switch name {
            case "literal": keys = ["destination", "width", "value"]
            case "aggregate": keys = ["destination", "elements"]
            case "extract": keys = ["destination", "source", "index"]
            case "binary": keys = ["destination", "operation", "left", "right"]
            case "functionRef": keys = ["destination", "symbol"]
            case "call": keys = ["destination", "callee", "arguments"]
            case "jump": keys = ["block", "arguments"]
            case "branch": keys = ["condition", "thenBlock", "thenArguments", "elseBlock", "elseArguments"]
            case "trapIf": keys = ["condition", "message"]
            case "returnValue": keys = ["source"]
            default: throw bad("Unknown TLA opcode")
            }
            _ = try record(data, keys: Set(keys + ["op"]))
            args = try keys.map { key in
                guard let value = fields[key] else { throw bad("Missing opcode field") }
                return value
            }
        }
        switch (name, args.count) {
        case ("literal", 3):
            let width = try integer(args[1])
            let raw: UInt64
            if lean { raw = try number(args[2]) }
            else {
                let digits = try list(args[2])
                guard digits.count == width, (1...64).contains(width) else { throw bad("TLA literal width mismatch") }
                var value: UInt64 = 0
                for (index, digit) in digits.enumerated() {
                    let bit = try number(digit)
                    guard bit <= 1 else { throw bad("TLA literal is not a bit vector") }
                    value |= bit << index
                }
                raw = value
            }
            let value = try BitPattern(width: width, bits: raw)
            let decoded0 = try text(args[0])
            return .literal(destination: decoded0, value: value)
        case ("aggregate", 2):
            let decoded0 = try text(args[0])
            let decoded1 = try strings(args[1])
            return .aggregate(destination: decoded0, elements: decoded1)
        case ("extract", 3):
            let decoded0 = try text(args[0])
            let decoded1 = try text(args[1])
            let decoded2 = try integer(args[2])
            return .extract(destination: decoded0, source: decoded1, index: decoded2)
        case ("binary", 4):
            let operationName: String
            if lean {
                guard case .constructor(let operation, let arguments) = args[1], arguments.isEmpty else { throw bad("Invalid operation constructor") }
                operationName = operation
            } else { operationName = try text(args[1]) }
            guard let operation = IROperation(rawValue: operationName) else { throw bad("Unknown binary operation") }
            let decoded0 = try text(args[0])
            let decoded1 = try text(args[2])
            let decoded2 = try text(args[3])
            return .binary(destination: decoded0, operation: operation, left: decoded1, right: decoded2)
        case ("functionRef", 2):
            let decoded0 = try text(args[0])
            let decoded1 = try text(args[1])
            return .functionRef(destination: decoded0, symbol: decoded1)
        case ("call", 3):
            let decoded0 = try text(args[0])
            let decoded1 = try text(args[1])
            let decoded2 = try strings(args[2])
            return .call(destination: decoded0, callee: decoded1, arguments: decoded2)
        case ("jump", 2):
            let decoded0 = try text(args[0])
            let decoded1 = try strings(args[1])
            return .jump(block: decoded0, arguments: decoded1)
        case ("branch", 5):
            let decoded0 = try text(args[0])
            let decoded1 = try text(args[1])
            let decoded2 = try strings(args[2])
            let decoded3 = try text(args[3])
            let decoded4 = try strings(args[4])
            return .branch(condition: decoded0, thenBlock: decoded1, thenArguments: decoded2, elseBlock: decoded3, elseArguments: decoded4)
        case ("trapIf", 2):
            let decoded0 = try text(args[0])
            let decoded1 = try text(args[1])
            return .trapIf(condition: decoded0, message: decoded1)
        case ("returnValue", 1):
            let decoded0 = try text(args[0])
            return .returnValue(decoded0)
        default: throw bad("Unknown instruction or arity")
        }
    }

    private func text(_ data: ArtifactData?) throws -> String {
        guard case .text(let value) = data else { throw bad("Expected string") }
        return value
    }
    private func number(_ data: ArtifactData?) throws -> UInt64 {
        guard case .number(let value) = data else { throw bad("Expected unsigned number") }
        return value
    }
    private func integer(_ data: ArtifactData?) throws -> Int {
        let value = try number(data)
        guard let integer = Int(exactly: value) else { throw bad("Integer conversion overflow") }
        return integer
    }
    private func list(_ data: ArtifactData?) throws -> [ArtifactData] {
        guard case .list(let values) = data else { throw bad("Expected list") }
        return values
    }
    private func strings(_ data: ArtifactData?) throws -> [String] {
        let elements = try list(data)
        return try elements.map { try text($0) }
    }
    private func record(_ data: ArtifactData?, keys: Set<String>) throws -> [String: ArtifactData] {
        guard case .record(let fields) = data, Set(fields.keys) == keys else { throw bad("Record fields differ from the restricted schema") }
        return fields
    }
    private func bad(_ message: String) -> FormalDiagnostic { FormalDiagnostic(.integrityMismatch, message) }
}
