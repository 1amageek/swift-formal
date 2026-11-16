import FormalCore

public struct IRInterpreter: IRExecuting {
    public let maximumIntegerDigits: Int
    public let fuel: Int
    public let maximumStackDepth: Int
    public let maximumValueNodes: Int

    public init(fuel: Int = 100_000, maximumStackDepth: Int = 1_024, maximumValueNodes: Int = 1_000_000, maximumIntegerDigits: Int = 4096) {
        self.maximumIntegerDigits = maximumIntegerDigits
        self.fuel = fuel
        self.maximumStackDepth = maximumStackDepth
        self.maximumValueNodes = maximumValueNodes
    }

    public func run(_ program: IRProgram, entry: String, arguments: [IRValue]) throws -> IRExecutionResult {
        try program.validate()
        guard fuel > 0, maximumIntegerDigits > 0, maximumStackDepth > 0, maximumValueNodes > 0, maximumValueNodes < Int.max else { throw invalid("Execution limits must be positive and value capacity below Int.max") }
        guard let function = program.functions.first(where: { $0.symbol == entry }),
              let first = function.blocks.first, first.parameters.count == arguments.count else { throw invalid("Invalid entry point or argument count") }
        for (argument, parameter) in zip(arguments, first.parameters) {
            guard argument.type(in: program) == parameter.type else { throw invalid("Entry argument type mismatch") }
        }
        let functions = Dictionary(uniqueKeysWithValues: program.functions.map { ($0.symbol, $0) })
        var frame = ExecutionFrame(function: function.symbol, block: first.id, instruction: 0,
            values: Dictionary(uniqueKeysWithValues: zip(first.parameters.map(\.id), arguments)), returnDestination: nil)
        var callers: [ExecutionFrame] = []
        if exceedsValueBudget(frame, callers: callers) { return .init(outcome: .boundExceeded("values"), steps: 0) }
        for step in 0..<fuel {
            guard let currentFunction = functions[frame.function],
                  let block = currentFunction.blocks.first(where: { $0.id == frame.block }),
                  block.instructions.indices.contains(frame.instruction) else { throw invalid("Invalid program counter") }
            let instruction = block.instructions[frame.instruction]
            func value(_ id: String) throws -> IRValue {
                guard let value = frame.values[id] else { throw invalid("Unbound SSA value") }
                return value
            }
            switch instruction {
            case .integerLiteral(let destination, let literal):
                frame.values[destination] = .integer(literal); frame.instruction += 1
            case .integerBinary(let destination, let operation, let left, let right):
                let leftValue = try value(left)
                let rightValue = try value(right)
                guard case .integer(let a) = leftValue, case .integer(let b) = rightValue else { throw invalid("Invalid integer operands") }
                // Bound the prospective allocation before arbitrary precision arithmetic.
                if !operation.isComparison && (a.digitCount > min(maximumIntegerDigits, maximumValueNodes) / 2 || b.digitCount > min(maximumIntegerDigits, maximumValueNodes) / 2) {
                    return .init(outcome: .boundExceeded("integer digits"), steps: step)
                }
                let result: IRValue
                switch operation {
                case .add: result = .integer(a.adding(b))
                case .subtract: result = .integer(a.adding(b.negated()))
                case .multiply: result = .integer(a.multiplied(by: b))
                case .lessThan: result = .bits(try BitPattern(width: 1, bits: a < b ? 1 : 0))
                case .equal: result = .bits(try BitPattern(width: 1, bits: a == b ? 1 : 0))
                }
                frame.values[destination] = result; frame.instruction += 1
            case .failIf(let condition, let kind, let message):
                let conditionValue = try value(condition)
                guard case .bits(let bit) = conditionValue, bit.width == 1 else { throw invalid("Invalid failure condition") }
                if bit.bits == 1 { return .init(outcome: .failed(kind, message), steps: step + 1) }
                frame.instruction += 1
            case .literal(let destination, let literal): frame.values[destination] = .bits(literal); frame.instruction += 1
            case .aggregate(let destination, let elements):
                var values: [IRValue] = []
                for element in elements {
                    let elementValue = try value(element)
                    values.append(elementValue)
                }
                frame.values[destination] = .aggregate(values)
                frame.instruction += 1
            case .extract(let destination, let source, let index):
                let aggregate = try value(source)
                guard case .aggregate(let values) = aggregate, values.indices.contains(index) else { throw invalid("Invalid projection") }
                frame.values[destination] = values[index]
                frame.instruction += 1
            case .binary(let destination, let operation, let left, let right):
                let a = try value(left)
                let b = try value(right)
                guard case .bits(let leftBits) = a, case .bits(let rightBits) = b else { throw invalid("Invalid binary values") }
                frame.values[destination] = try BitArithmetic.evaluate(operation, leftBits, rightBits)
                frame.instruction += 1
            case .functionRef(let destination, let symbol): frame.values[destination] = .function(symbol); frame.instruction += 1
            case .call(let destination, let callee, let argumentIDs):
                let reference = try value(callee)
                guard case .function(let symbol) = reference, let target = functions[symbol], let initial = target.blocks.first else { throw invalid("Unresolved call") }
                if callers.count + 1 >= maximumStackDepth { return .init(outcome: .boundExceeded("stack"), steps: step) }
                var actual: [IRValue] = []
                for argument in argumentIDs {
                    let argumentValue = try value(argument)
                    actual.append(argumentValue)
                }
                frame.instruction += 1
                callers.append(frame)
                frame = ExecutionFrame(function: symbol, block: initial.id, instruction: 0,
                    values: Dictionary(uniqueKeysWithValues: zip(initial.parameters.map(\.id), actual)), returnDestination: destination)
            case .jump(let target, let arguments): try bind(target, arguments: arguments, frame: &frame, function: currentFunction)
            case .branch(let condition, let thenBlock, let thenArguments, let elseBlock, let elseArguments):
                let conditionValue = try value(condition)
                guard case .bits(let bit) = conditionValue, bit.width == 1 else { throw invalid("Invalid branch condition") }
                try bind(bit.bits == 1 ? thenBlock : elseBlock, arguments: bit.bits == 1 ? thenArguments : elseArguments,
                         frame: &frame, function: currentFunction)
            case .trapIf(let condition, let message):
                let conditionValue = try value(condition)
                guard case .bits(let bit) = conditionValue, bit.width == 1 else { throw invalid("Invalid trap condition") }
                if bit.bits == 1 { return .init(outcome: .trapped(message), steps: step + 1) }
                frame.instruction += 1
            case .returnValue(let source):
                let returned = try value(source)
                guard var caller = callers.popLast() else { return .init(outcome: .returned(returned), steps: step + 1) }
                guard let destination = frame.returnDestination else { throw invalid("Missing return destination") }
                caller.values[destination] = returned
                frame = caller
            }
            if exceedsValueBudget(frame, callers: callers) { return .init(outcome: .boundExceeded("values"), steps: step + 1) }
        }
        return .init(outcome: .boundExceeded("fuel"), steps: fuel)
    }

    private func bind(_ target: String, arguments: [String], frame: inout ExecutionFrame, function: IRFunction) throws {
        guard let block = function.blocks.first(where: { $0.id == target }), block.parameters.count == arguments.count else { throw invalid("Invalid branch") }
        var values: [IRValue] = []
        for id in arguments {
            guard let value = frame.values[id] else { throw invalid("Unbound branch argument") }
            values.append(value)
        }
        for (parameter, value) in zip(block.parameters, values) { frame.values[parameter.id] = value }
        frame.block = target
        frame.instruction = 0
    }

    private func nodeCount(_ value: IRValue, limit: Int) -> Int {
        guard limit > 0 else { return 0 }
        if case .integer(let integer) = value { return min(limit, integer.digitCount > maximumIntegerDigits ? maximumValueNodes + 1 : integer.digitCount) }
        if case .aggregate(let elements) = value {
            var count = 1
            for element in elements {
                count += nodeCount(element, limit: limit - count)
                if count >= limit { return limit }
            }
            return count
        }
        return 1
    }

    private func exceedsValueBudget(_ frame: ExecutionFrame, callers: [ExecutionFrame]) -> Bool {
        let cap = maximumValueNodes + 1
        var nodes = 0
        for value in frame.values.values {
            nodes += nodeCount(value, limit: cap - nodes)
            if nodes > maximumValueNodes { return true }
        }
        for caller in callers {
            for value in caller.values.values {
                nodes += nodeCount(value, limit: cap - nodes)
                if nodes > maximumValueNodes { return true }
            }
        }
        return false
    }

    private func invalid(_ message: String) -> FormalDiagnostic { FormalDiagnostic(.invalidManifest, message) }
}

private struct ExecutionFrame {
    let function: String
    var block: String
    var instruction: Int
    var values: [String: IRValue]
    let returnDestination: String?
}
