import FormalCore

public struct IRProgram: Codable, Sendable, Equatable {
    public let schemaVersion: Int
    public let functions: [IRFunction]

    public init(functions: [IRFunction]) {
        self.schemaVersion = 1
        self.functions = functions
    }

    public func validate() throws {
        guard schemaVersion == 1, !functions.isEmpty,
              Set(functions.map(\.symbol)).count == functions.count else { throw invalid("Invalid program schema or duplicate symbols") }
        for function in functions { try validate(function) }
    }

    private func validate(_ function: IRFunction) throws {
        guard !function.moduleID.isEmpty, !function.symbol.isEmpty, function.result.isValid(),
              !function.blocks.isEmpty, Set(function.blocks.map(\.id)).count == function.blocks.count else {
            throw invalid("Invalid function or duplicate blocks")
        }
        let blocks = Dictionary(uniqueKeysWithValues: function.blocks.map { ($0.id, $0) })
        var predecessors: [String: Set<String>] = [:]
        var definitions: [String: String] = [:]
        var types: [String: IRType] = [:]
        for block in function.blocks {
            guard !block.id.isEmpty, let last = block.instructions.last, last.isTerminator,
                  !block.instructions.dropLast().contains(where: \.isTerminator) else { throw invalid("Invalid block terminator") }
            for parameter in block.parameters {
                guard !parameter.id.isEmpty, parameter.type.isValid(), definitions[parameter.id] == nil else { throw invalid("Invalid or duplicate SSA parameter") }
                definitions[parameter.id] = block.id
                types[parameter.id] = parameter.type
            }
            for instruction in block.instructions {
                if let destination = instruction.destination {
                    guard !destination.isEmpty, definitions[destination] == nil else { throw invalid("Duplicate SSA definition") }
                    definitions[destination] = block.id
                }
            }
            for successor in successors(last) {
                guard blocks[successor] != nil else { throw invalid("Unknown branch destination") }
                predecessors[successor, default: []].insert(block.id)
            }
        }
        let entry = function.blocks[0].id
        var reachable: Set<String> = [entry]
        var pending = [entry]
        while let id = pending.popLast() {
            guard let block = blocks[id], let last = block.instructions.last else { throw invalid("Unknown block") }
            for next in successors(last) where reachable.insert(next).inserted { pending.append(next) }
        }
        var dominators: [String: Set<String>] = [:]
        for block in function.blocks {
            dominators[block.id] = block.id == entry || !reachable.contains(block.id) ? [block.id] : reachable
        }
        var changed = true
        while changed {
            changed = false
            for block in function.blocks where reachable.contains(block.id) && block.id != entry {
                let incoming = (predecessors[block.id] ?? []).filter { reachable.contains($0) }
                var next = reachable
                for predecessor in incoming { next.formIntersection(dominators[predecessor] ?? []) }
                next.insert(block.id)
                if next != dominators[block.id] { dominators[block.id] = next; changed = true }
            }
        }
        let ordered = function.blocks.sorted { (dominators[$0.id]?.count ?? 0) < (dominators[$1.id]?.count ?? 0) }
        for block in ordered {
            var available = Set(definitions.compactMap { id, owner in
                owner != block.id && (dominators[block.id]?.contains(owner) ?? false) ? id : nil
            })
            available.formUnion(block.parameters.map(\.id))
            func type(_ id: String) throws -> IRType {
                guard available.contains(id), let type = types[id] else { throw invalid("SSA value does not dominate use: \(id)") }
                return type
            }
            func checkBranch(_ destination: String, _ arguments: [String]) throws {
                guard let target = blocks[destination], target.parameters.count == arguments.count else { throw invalid("Branch argument count mismatch") }
                for (argument, parameter) in zip(arguments, target.parameters) {
                    let argumentType = try type(argument)
                    guard argumentType == parameter.type else { throw invalid("Branch argument type mismatch") }
                }
            }
            for instruction in block.instructions {
                let result: IRType?
                switch instruction {
                case .integerLiteral: result = .integer
                case .integerBinary(_, let operation, let left, let right):
                    let a = try type(left)
                    let b = try type(right)
                    guard a == .integer, b == .integer else { throw invalid("Expected mathematical integers") }
                    result = operation.isComparison ? .bits(width: 1) : .integer
                case .literal(_, let value): result = .bits(width: value.width)
                case .aggregate(_, let elements):
                    var elementTypes: [IRType] = []
                    for element in elements {
                        let elementType = try type(element)
                        elementTypes.append(elementType)
                    }
                    result = .aggregate(elementTypes)
                case .extract(_, let source, let index):
                    let sourceType = try type(source)
                    guard case .aggregate(let elements) = sourceType, elements.indices.contains(index) else { throw invalid("Invalid aggregate projection") }
                    result = elements[index]
                case .binary(_, let operation, let left, let right):
                    let leftType = try type(left)
                    let rightType = try type(right)
                    guard case .bits(let width) = leftType, rightType == leftType else { throw invalid("Binary operand types differ") }
                    if operation.returnsOverflow { result = .aggregate([leftType, .bits(width: 1)]) }
                    else if [.signedLessThan, .unsignedLessThan, .equal].contains(operation) { result = .bits(width: 1) }
                    else { result = .bits(width: width) }
                case .functionRef(_, let symbol):
                    guard let target = functions.first(where: { $0.symbol == symbol }) else { throw invalid("Unresolved callee") }
                    result = target.type
                case .call(_, let callee, let arguments):
                    let calleeType = try type(callee)
                    guard case .function(let parameters, let output) = calleeType, parameters.count == arguments.count else { throw invalid("Invalid call signature") }
                    for (argument, parameter) in zip(arguments, parameters) {
                        let argumentType = try type(argument)
                        guard argumentType == parameter else { throw invalid("Call argument type mismatch") }
                    }
                    result = output
                case .jump(let target, let arguments): try checkBranch(target, arguments); result = nil
                case .branch(let condition, let thenBlock, let thenArguments, let elseBlock, let elseArguments):
                    let conditionType = try type(condition)
                    guard conditionType == .bits(width: 1) else { throw invalid("Branch condition must be one bit") }
                    try checkBranch(thenBlock, thenArguments)
                    try checkBranch(elseBlock, elseArguments)
                    result = nil
                case .trapIf(let condition, _), .failIf(let condition, _, _):
                    let conditionType = try type(condition)
                    guard conditionType == .bits(width: 1) else { throw invalid("Trap condition must be one bit") }
                    result = nil
                case .returnValue(let value):
                    let valueType = try type(value)
                    guard valueType == function.result else { throw invalid("Return type mismatch") }
                    result = nil
                }
                if let destination = instruction.destination, let result {
                    guard result.isValid() else { throw invalid("Intermediate value type exceeds supported nesting") }
                    types[destination] = result
                    available.insert(destination)
                }
            }
        }
    }

    private func successors(_ instruction: IRInstruction) -> [String] {
        switch instruction {
        case .jump(let target, _): [target]
        case .branch(_, let thenBlock, _, let elseBlock, _): [thenBlock, elseBlock]
        default: []
        }
    }

    private func invalid(_ message: String) -> FormalDiagnostic { FormalDiagnostic(.invalidManifest, message) }
}
