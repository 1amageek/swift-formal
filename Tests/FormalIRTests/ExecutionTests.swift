import FormalIR
import Testing

struct ExecutionTests {
    @Test(.timeLimit(.minutes(1)))
    func branchArgumentsBindSimultaneously() throws {
        let type = IRType.bits(width: 8)
        let function = IRFunction(moduleID: "Test", symbol: "swap", result: .aggregate([type, type]), blocks: [
            IRBlock(id: "entry", parameters: [.init(id: "a", type: type), .init(id: "b", type: type)], instructions: [
                .jump(block: "loop", arguments: ["a", "b"]),
            ]),
            IRBlock(id: "loop", parameters: [.init(id: "x", type: type), .init(id: "y", type: type)], instructions: [
                .aggregate(destination: "pair", elements: ["y", "x"]), .returnValue("pair"),
            ]),
        ])
        let a = try BitPattern(width: 8, bits: 2)
        let b = try BitPattern(width: 8, bits: 3)
        let result = try IRInterpreter().run(IRProgram(functions: [function]), entry: "swap", arguments: [.bits(a), .bits(b)])
        #expect(result.outcome == .returned(.aggregate([.bits(b), .bits(a)])))
    }

    @Test(.timeLimit(.minutes(1)))
    func directCallPreservesCallerValues() throws {
        let type = IRType.bits(width: 8)
        let callee = IRFunction(moduleID: "Test", symbol: "identity", result: type, blocks: [
            .init(id: "entry", parameters: [.init(id: "input", type: type)], instructions: [.returnValue("input")]),
        ])
        let caller = IRFunction(moduleID: "Test", symbol: "caller", result: .aggregate([type, type]), blocks: [
            .init(id: "entry", parameters: [.init(id: "a", type: type), .init(id: "b", type: type)], instructions: [
                .functionRef(destination: "fn", symbol: "identity"),
                .call(destination: "result", callee: "fn", arguments: ["b"]),
                .aggregate(destination: "pair", elements: ["a", "result"]), .returnValue("pair"),
            ]),
        ])
        let a = try BitPattern(width: 8, bits: 5)
        let b = try BitPattern(width: 8, bits: 9)
        let result = try IRInterpreter().run(IRProgram(functions: [caller, callee]), entry: "caller", arguments: [.bits(a), .bits(b)])
        #expect(result.outcome == .returned(.aggregate([.bits(a), .bits(b)])))
    }

    @Test(.timeLimit(.minutes(1)))
    func overflowTrapIsNotAnInputAssumption() throws {
        let type = IRType.bits(width: 8)
        let function = IRFunction(moduleID: "Test", symbol: "subtract", result: type, blocks: [
            .init(id: "entry", parameters: [.init(id: "a", type: type), .init(id: "b", type: type)], instructions: [
                .binary(destination: "pair", operation: .signedSubtractOverflow, left: "a", right: "b"),
                .extract(destination: "flag", source: "pair", index: 1),
                .trapIf(condition: "flag", message: "overflow"),
                .extract(destination: "result", source: "pair", index: 0), .returnValue("result"),
            ]),
        ])
        let minimum = try BitPattern(width: 8, bits: 128)
        let one = try BitPattern(width: 8, bits: 1)
        let result = try IRInterpreter().run(IRProgram(functions: [function]), entry: "subtract", arguments: [.bits(minimum), .bits(one)])
        #expect(result.outcome == .trapped("overflow"))
    }

    @Test(.timeLimit(.minutes(1)))
    func infiniteLoopAndRecursionReportBounds() throws {
        let loop = IRFunction(moduleID: "Test", symbol: "loop", result: .aggregate([]), blocks: [
            .init(id: "entry", parameters: [], instructions: [.jump(block: "entry", arguments: [])]),
        ])
        let result = try IRInterpreter(fuel: 10).run(IRProgram(functions: [loop]), entry: "loop", arguments: [])
        #expect(result.outcome == .boundExceeded("fuel"))
        let recursion = IRFunction(moduleID: "Test", symbol: "recursive", result: .aggregate([]), blocks: [
            .init(id: "entry", parameters: [], instructions: [
                .functionRef(destination: "fn", symbol: "recursive"),
                .call(destination: "out", callee: "fn", arguments: []), .returnValue("out"),
            ]),
        ])
        let recursive = try IRInterpreter(maximumStackDepth: 2).run(IRProgram(functions: [recursion]), entry: "recursive", arguments: [])
        #expect(recursive.outcome == .boundExceeded("stack"))
    }

    @Test(.timeLimit(.minutes(1)))
    func rejectsUseOfNonDominatingDefinition() throws {
        let type = IRType.bits(width: 1)
        let bit = try BitPattern(width: 1, bits: 1)
        let function = IRFunction(moduleID: "Test", symbol: "bad", result: type, blocks: [
            .init(id: "entry", parameters: [.init(id: "condition", type: type)], instructions: [
                .branch(condition: "condition", thenBlock: "yes", thenArguments: [], elseBlock: "no", elseArguments: []),
            ]),
            .init(id: "yes", parameters: [], instructions: [.literal(destination: "onlyYes", value: bit), .returnValue("onlyYes")]),
            .init(id: "no", parameters: [], instructions: [.returnValue("onlyYes")]),
        ])
        #expect(throws: (any Error).self) { try IRProgram(functions: [function]).validate() }
    }
    @Test(.timeLimit(.minutes(1)))
    func inputValuesRespectTheBudgetBeforeReturn() throws {
        let function = IRFunction(moduleID: "Test", symbol: "identity", result: .bits(width: 8), blocks: [
            .init(id: "entry", parameters: [.init(id: "value", type: .bits(width: 8))], instructions: [.returnValue("value")]),
        ])
        let program = IRProgram(functions: [function])
        let value = try BitPattern(width: 8, bits: 7)
        let result = try IRInterpreter(maximumValueNodes: 1).run(program, entry: "identity", arguments: [.bits(value)])
        #expect(result.outcome == .returned(.bits(value)))
        let aggregate = IRFunction(moduleID: "Test", symbol: "aggregate", result: .aggregate([.bits(width: 8)]), blocks: [
            .init(id: "entry", parameters: [.init(id: "value", type: .aggregate([.bits(width: 8)]))], instructions: [.returnValue("value")]),
        ])
        let limited = try IRInterpreter(maximumValueNodes: 1).run(IRProgram(functions: [aggregate]), entry: "aggregate", arguments: [.aggregate([.bits(value)])])
        #expect(limited.outcome == .boundExceeded("values"))
        #expect(limited.steps == 0)
    }

}
