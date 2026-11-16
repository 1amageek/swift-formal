import FormalCore
import FormalIR
import FormalSIL
import Foundation

struct ScalarDecoder {
    let path: String

    func function(_ function: SILModuleSyntax.Function, moduleID: String) throws -> (IRFunction, [ScalarLoweringResult.RuleApplication]) {
        let header = function.header.map(\.text)
        guard let colon = header.firstIndex(of: ":") else { throw bad("Missing function type") }
        let modifiers = header[1..<max(1, colon - 1)]
        guard modifiers.isEmpty else { throw FormalDiagnostic(.unsupportedAttribute, "Unsupported function attributes at SIL line \(function.line)", path: path) }
        var signature = ScalarTokens(Array(header.dropFirst(colon + 1)), path: path)
        try signature.expect("$@convention")
        try signature.expect("(")
        try signature.expect("thin")
        try signature.expect(")")
        try signature.expect("(")
        var parameterTypes: [IRType] = []
        if !signature.consume(")") {
            repeat {
                let type = try signature.type()
                parameterTypes.append(type)
            } while signature.consume(",")
            try signature.expect(")")
        }
        try signature.expect("->")
        let result = try signature.type()
        try signature.end()
        guard let first = function.blocks.first else { throw bad("Missing entry block") }
        var types: [String: IRType] = [:]
        var parameters: [String: [IRParameter]] = [:]
        for block in function.blocks {
            var arguments = ScalarTokens(block.arguments.map(\.text), path: path)
            var values: [IRParameter] = []
            if arguments.consume("(") {
                if !arguments.consume(")") {
                    repeat {
                        let id = try arguments.value()
                        try arguments.expect(":")
                        let type = try arguments.type()
                        guard types[id] == nil else { throw bad("Duplicate block argument") }
                        types[id] = type
                        values.append(.init(id: id, type: type))
                    } while arguments.consume(",")
                    try arguments.expect(")")
                }
            }
            try arguments.end()
            parameters[block.id] = values
        }
        guard parameters[first.id]?.map(\.type) == parameterTypes else { throw bad("Entry parameters differ from function signature") }
        var blocks: [IRBlock] = []
        var evidence: [ScalarLoweringResult.RuleApplication] = []
        for block in function.blocks {
            var instructions: [IRInstruction] = []
            for original in block.instructions {
                do {
                    let instruction = try decode(original, types: &types)
                    evidence.append(.init(symbol: function.symbol, block: block.id, silLine: original.line,
                        opcode: original.opcode, ruleID: "swift641.scalar.\(original.opcode).v0",
                        irInstructionIndex: instruction == nil ? nil : instructions.count))
                    if let instruction { instructions.append(instruction) }
                } catch let diagnostic as FormalDiagnostic {
                    throw FormalDiagnostic(diagnostic.code, "\(diagnostic.message) at SIL line \(original.line)", path: path)
                }
            }
            blocks.append(.init(id: block.id, parameters: parameters[block.id] ?? [], instructions: instructions))
        }
        return (IRFunction(moduleID: moduleID, symbol: function.symbol, result: result, blocks: blocks), evidence)
    }

    private func decode(_ instruction: SILModuleSyntax.Instruction, types: inout [String: IRType]) throws -> IRInstruction? {
        var tokens = ScalarTokens(instruction.operands.map(\.text), path: path)
        func destination() throws -> String {
            guard instruction.results.count == 1, let result = instruction.results.first, types[result] == nil else { throw bad("Expected one fresh SSA result") }
            return result
        }
        func typedValue(_ id: String) throws -> IRType {
            guard let type = types[id] else { throw bad("Unknown operand type: \(id)") }
            return type
        }
        let output: IRInstruction
        if ["br", "cond_br", "return"].contains(instruction.opcode), !instruction.results.isEmpty {
            throw bad("Terminator cannot define an SSA result")
        }
        switch instruction.opcode {
        case "debug_value":
            guard instruction.results.isEmpty else { throw bad("Debug metadata cannot define results") }
            // Debug metadata is not part of the selected execution observations.
            return nil
        case "integer_literal":
            let result = try destination()
            let type = try tokens.type()
            guard case .bits(let width) = type else { throw bad("Literal requires Builtin integer type") }
            try tokens.expect(",")
            let text = try tokens.next()
            let bits: UInt64
            if text.hasPrefix("-"), let signed = Int64(text) {
                if width < 64, signed < -(Int64(1) << (width - 1)) { throw bad("Integer literal is outside its declared width") }
                bits = UInt64(bitPattern: signed)
            }
            else if let unsigned = UInt64(text) {
                if width < 64, unsigned >= UInt64(1) << width { throw bad("Integer literal is outside its declared width") }
                bits = unsigned
            }
            else { throw bad("Invalid integer literal") }
            let mask = width == 64 ? UInt64.max : (UInt64(1) << width) - 1
            let value = try BitPattern(width: width, bits: bits & mask)
            types[result] = type
            output = .literal(destination: result, value: value)
        case "struct":
            let result = try destination()
            let type = try tokens.type()
            guard case .aggregate(let fields) = type else { throw bad("Unsupported nominal struct") }
            let arguments = try tokens.values()
            var actual: [IRType] = []
            for argument in arguments {
                let type = try typedValue(argument)
                actual.append(type)
            }
            guard actual == fields else { throw bad("Struct field type mismatch") }
            types[result] = type
            output = .aggregate(destination: result, elements: arguments)
        case "tuple":
            let result = try destination()
            let values = try tokens.values()
            var fields: [IRType] = []
            for value in values {
                let type = try typedValue(value)
                fields.append(type)
            }
            types[result] = .aggregate(fields)
            output = .aggregate(destination: result, elements: values)
        case "struct_extract", "tuple_extract":
            let result = try destination()
            let source = try tokens.value()
            try tokens.expect(",")
            let field = try tokens.next()
            let sourceType = try typedValue(source)
            guard case .aggregate(let fields) = sourceType else { throw bad("Projection requires aggregate") }
            let index: Int
            if instruction.opcode == "tuple_extract", let number = Int(field) { index = number }
            else if instruction.opcode == "struct_extract", field.hasPrefix("#"), field.hasSuffix("._value"), fields.count == 1 {
                let nominal = String(field.dropFirst().dropLast("._value".count))
                var expected = ScalarTokens([nominal], path: path)
                let expectedType = try expected.type()
                guard expectedType == sourceType else { throw bad("Nominal field type mismatch") }
                index = 0
            } else { throw bad("Unknown field projection") }
            guard fields.indices.contains(index) else { throw bad("Projection out of bounds") }
            types[result] = fields[index]
            output = .extract(destination: result, source: source, index: index)
        case "builtin":
            let result = try destination()
            let quoted = try tokens.next()
            let name = try quotedText(quoted)
            let arguments = try tokens.values()
            try tokens.expect(":")
            let declared = try tokens.type()
            let parts = name.split(separator: "_").map(String.init)
            guard let last = parts.last, last.hasPrefix("Int"), let width = Int(last.dropFirst(3)), (1...64).contains(width) else {
                throw FormalDiagnostic(.unsupportedOpcode, "Unsupported builtin: \(name)", path: path)
            }
            let stem = parts.dropLast().joined(separator: "_")
            let operations: [String: IROperation] = [
                "sadd_with_overflow": .signedAddOverflow, "ssub_with_overflow": .signedSubtractOverflow,
                "smul_with_overflow": .signedMultiplyOverflow, "uadd_with_overflow": .unsignedAddOverflow,
                "usub_with_overflow": .unsignedSubtractOverflow, "umul_with_overflow": .unsignedMultiplyOverflow,
                "cmp_slt": .signedLessThan, "cmp_ult": .unsignedLessThan, "cmp_eq": .equal,
                "and": .and, "or": .or, "xor": .xor,
            ]
            guard let operation = operations[stem], arguments.count == (operation.returnsOverflow ? 3 : 2) else {
                throw FormalDiagnostic(.unsupportedOpcode, "Unsupported builtin or arity: \(name)", path: path)
            }
            let leftType = try typedValue(arguments[0])
            let rightType = try typedValue(arguments[1])
            guard leftType == .bits(width: width), rightType == leftType else { throw bad("Builtin width mismatch") }
            let expected: IRType
            if operation.returnsOverflow {
                let hint = try typedValue(arguments[2])
                guard hint == .bits(width: 1) else { throw bad("Overflow reporting hint must be one bit") }
                // Swift 6.4.1 IRGen/GenBuiltin.cpp discards the third reporting-hint argument;
                // the LLVM intrinsic always produces the wrapped result and overflow flag.
                expected = .aggregate([leftType, .bits(width: 1)])
            } else if [.signedLessThan, .unsignedLessThan, .equal].contains(operation) { expected = .bits(width: 1) }
            else { expected = leftType }
            guard declared == expected else { throw bad("Builtin result type mismatch") }
            types[result] = expected
            output = .binary(destination: result, operation: operation, left: arguments[0], right: arguments[1])
        case "function_ref":
            let result = try destination()
            let symbol = try tokens.next()
            guard symbol.hasPrefix("@") else { throw bad("Invalid function symbol") }
            try tokens.expect(":")
            let type = try tokens.functionType()
            types[result] = type
            output = .functionRef(destination: result, symbol: String(symbol.dropFirst()))
        case "apply":
            let result = try destination()
            let callee = try tokens.value()
            let arguments = try tokens.values()
            try tokens.expect(":")
            let declared = try tokens.functionType()
            let actual = try typedValue(callee)
            guard actual == declared, case .function(let parameters, let resultType) = actual,
                  arguments.count == parameters.count else { throw bad("Call signature mismatch") }
            for (argument, parameter) in zip(arguments, parameters) {
                let type = try typedValue(argument)
                guard type == parameter else { throw bad("Call argument type mismatch") }
            }
            types[result] = resultType
            output = .call(destination: result, callee: callee, arguments: arguments)
        case "cond_fail":
            guard instruction.results.isEmpty else { throw bad("Trap cannot define a result") }
            let condition = try tokens.value()
            let type = try typedValue(condition)
            guard type == .bits(width: 1) else { throw bad("Trap condition must be one bit") }
            try tokens.expect(",")
            let message = try tokens.next()
            let decoded = try quotedText(message)
            output = .trapIf(condition: condition, message: decoded)
        case "br":
            let target = try tokens.next()
            let arguments = tokens.peek == "(" ? try tokens.values() : []
            output = .jump(block: target, arguments: arguments)
        case "cond_br":
            let condition = try tokens.value()
            try tokens.expect(",")
            let thenBlock = try tokens.next()
            let thenArguments = tokens.peek == "(" ? try tokens.values() : []
            try tokens.expect(",")
            let elseBlock = try tokens.next()
            let elseArguments = tokens.peek == "(" ? try tokens.values() : []
            output = .branch(condition: condition, thenBlock: thenBlock, thenArguments: thenArguments,
                             elseBlock: elseBlock, elseArguments: elseArguments)
        case "return":
            let source = try tokens.value()
            output = .returnValue(source)
        default: throw FormalDiagnostic(.unsupportedOpcode, "Unsupported opcode: \(instruction.opcode)", path: path)
        }
        try tokens.end()
        return output
    }

    private func bad(_ message: String) -> FormalDiagnostic { FormalDiagnostic(.silParseFailed, message, path: path) }

    private func quotedText(_ text: String) throws -> String {
        let data = Data(text.utf8)
        do { return try JSONDecoder().decode(String.self, from: data) }
        catch { throw FormalDiagnostic(.unsupportedType, "Unsupported SIL string escape", path: path) }
    }
}
