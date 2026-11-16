import FormalCore
import FormalIR

struct PropertyExecutionBound {
    private let program: IRProgram
    private var functions: [String: Int] = [:]
    private var activeFunctions: Set<String> = []
    private var activeBlocks: Set<[String]> = []
    private var blockBounds: [[String]: Int] = [:]
    private var depth = 0

    static func derive(_ program: IRProgram, entry: String) throws -> Int {
        var analysis = Self(program: program)
        let steps = try analysis.function(entry)
        guard steps < 4096 else { throw exhausted("Derived execution bound exceeds 4096") }
        return steps + 1
    }
    private mutating func function(_ symbol: String) throws -> Int {
        if let cached = functions[symbol] { return cached }
        guard depth < 128, activeFunctions.insert(symbol).inserted,
              let function = program.functions.first(where: { $0.symbol == symbol }), let first = function.blocks.first else {
            throw Self.exhausted("Recursive calls or excessive analysis depth require an inductive proof profile")
        }
        depth += 1
        defer { depth -= 1; activeFunctions.remove(symbol) }
        let result = try block(first.id, function: function)
        functions[symbol] = result
        return result
    }
    private mutating func block(_ id: String, function: IRFunction) throws -> Int {
        let key = [function.symbol, id]
        if let cached = blockBounds[key] { return cached }
        guard depth < 128, activeBlocks.insert(key).inserted, let block = function.blocks.first(where: { $0.id == id }) else {
            throw Self.exhausted("CFG cycles or excessive analysis depth require an inductive proof profile")
        }
        depth += 1
        defer { depth -= 1; activeBlocks.remove(key) }
        var references: [String: String] = [:]
        for candidate in function.blocks {
            for instruction in candidate.instructions {
                if case .functionRef(let destination, let symbol) = instruction { references[destination] = symbol }
            }
        }
        var count = 0
        for instruction in block.instructions {
            count += 1
            switch instruction {
            case .call(_, let callee, _):
                guard let symbol = references[callee] else { throw Self.exhausted("Indirect calls require an additional proof profile") }
                let child = try self.function(symbol)
                count += child
            case .jump(let target, _):
                let child = try self.block(target, function: function)
                count += child
            case .branch(_, let left, _, let right, _):
                let a = try self.block(left, function: function)
                let b = try self.block(right, function: function)
                count += max(a, b)
            default: break
            }
            guard count < 4096 else { throw Self.exhausted("Derived execution bound exceeds 4096") }
        }
        blockBounds[key] = count
        return count
    }
    private static func exhausted(_ message: String) -> FormalDiagnostic { FormalDiagnostic(.timeout, message) }
}
