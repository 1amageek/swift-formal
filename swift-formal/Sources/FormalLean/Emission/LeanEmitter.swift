import FormalCore
import FormalIR
import Foundation

public struct LeanEmitter: LeanEmitting {
    public init() {}

    public func emit(_ program: IRProgram) throws -> [GeneratedFile] {
        try program.validate()
        guard let runtimeURL = Bundle.module.url(forResource: "Runtime", withExtension: "lean") else {
            throw FormalDiagnostic(.ioFailure, "Missing Lean runtime resource.")
        }
        let runtime = try String(contentsOf: runtimeURL, encoding: .utf8)
        let functions = try program.functions.map(function).joined(separator: ",\n  ")
        let source = "import SwiftFormal.Runtime\n\nopen SwiftFormal\n\nnamespace Generated\n\ndef program : Program := [\n  \(functions)\n]\n\nend Generated\n"
        let properties = """
        import Generated.Program

        namespace Generated

        def NoTrap (start : SwiftFormal.State) : Prop :=
          ∀ state, SwiftFormal.Reachable program start state →
            ∀ message, state.status ≠ SwiftFormal.Status.trapped message

        def Terminates (start : SwiftFormal.State) : Prop :=
          ∃ state value, SwiftFormal.Reachable program start state ∧
            state.status = SwiftFormal.Status.returned value

        end Generated

        """
        return [
            .init(path: "lean/lean-toolchain", contents: "leanprover/lean4:v4.35.0\n"),
            .init(path: "lean/lakefile.toml", contents: "name = \"swift-formal-generated\"\nversion = \"0.1.0\"\ndefaultTargets = [\"Generated\"]\n\n[[lean_lib]]\nname = \"SwiftFormal\"\n\n[[lean_lib]]\nname = \"Generated\"\n"),
            .init(path: "lean/SwiftFormal/Runtime.lean", contents: runtime),
            .init(path: "lean/Generated/Program.lean", contents: source),
            .init(path: "lean/Generated/Properties.lean", contents: properties),
            .init(path: "lean/Generated.lean", contents: "import Generated.Program\nimport Generated.Properties\n"),
        ]
    }

    private func function(_ value: IRFunction) throws -> String {
        let symbol = try quote(value.symbol)
        let result = try type(value.result)
        let blocks = try value.blocks.map(block).joined(separator: ",\n    ")
        let rendered0 = try quote(value.moduleID)
        return "{ moduleID := \(rendered0), symbol := \(symbol), result := \(result), blocks := [\n    \(blocks)\n  ] }"
    }

    private func block(_ value: IRBlock) throws -> String {
        let id = try quote(value.id)
        let parameters = try value.parameters.map { parameter in
            let id = try quote(parameter.id)
            let type = try type(parameter.type)
            return "{ id := \(id), type := \(type) }"
        }.joined(separator: ", ")
        let instructions = try value.instructions.map(instruction).joined(separator: ",\n      ")
        return "{ id := \(id), parameters := [\(parameters)], instructions := [\n      \(instructions)\n    ] }"
    }

    private func type(_ value: IRType) throws -> String {
        switch value {
        case .bits(let width):
            return "(.bits \(width))"
        case .aggregate(let elements):
            let rendered0 = try elements.map(type).joined(separator: ", ")
            return "(.aggregate [\(rendered0)])"
        case .function(let parameters, let result):
            let rendered0 = try parameters.map(type).joined(separator: ", ")
            let rendered1 = try type(result)
            return "(.function [\(rendered0)] \(rendered1))"
        }
    }

    private func instruction(_ value: IRInstruction) throws -> String {
        switch value {
        case .literal(let destination, let value):
            let rendered0 = try quote(destination)
            return "(.literal \(rendered0) \(value.width) \(value.bits))"
        case .aggregate(let destination, let elements):
            let rendered0 = try quote(destination)
            let rendered1 = try list(elements)
            return "(.aggregate \(rendered0) \(rendered1))"
        case .extract(let destination, let source, let index):
            let rendered0 = try quote(destination)
            let rendered1 = try quote(source)
            return "(.extract \(rendered0) \(rendered1) \(index))"
        case .binary(let destination, let operation, let left, let right):
            let rendered0 = try quote(destination)
            let rendered1 = try quote(left)
            let rendered2 = try quote(right)
            return "(.binary \(rendered0) .\(operation.rawValue) \(rendered1) \(rendered2))"
        case .functionRef(let destination, let symbol):
            let rendered0 = try quote(destination)
            let rendered1 = try quote(symbol)
            return "(.functionRef \(rendered0) \(rendered1))"
        case .call(let destination, let callee, let arguments):
            let rendered0 = try quote(destination)
            let rendered1 = try quote(callee)
            let rendered2 = try list(arguments)
            return "(.call \(rendered0) \(rendered1) \(rendered2))"
        case .jump(let block, let arguments):
            let rendered0 = try quote(block)
            let rendered1 = try list(arguments)
            return "(.jump \(rendered0) \(rendered1))"
        case .branch(let condition, let thenBlock, let thenArguments, let elseBlock, let elseArguments):
            let rendered0 = try quote(condition)
            let rendered1 = try quote(thenBlock)
            let rendered2 = try list(thenArguments)
            let rendered3 = try quote(elseBlock)
            let rendered4 = try list(elseArguments)
            return "(.branch \(rendered0) \(rendered1) \(rendered2) \(rendered3) \(rendered4))"
        case .trapIf(let condition, let message):
            let rendered0 = try quote(condition)
            let rendered1 = try quote(message)
            return "(.trapIf \(rendered0) \(rendered1))"
        case .returnValue(let source):
            let rendered0 = try quote(source)
            return "(.returnValue \(rendered0))"
        }
    }

    private func list(_ values: [String]) throws -> String {
        let quoted = try values.map(quote)
        return "[\(quoted.joined(separator: ", "))]"
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
                guard scalar.value >= 32 else { throw FormalDiagnostic(.unsupportedType, "Unsupported control character in Lean string.") }
                result.unicodeScalars.append(scalar)
            }
        }
        return result + "\""
    }
}
