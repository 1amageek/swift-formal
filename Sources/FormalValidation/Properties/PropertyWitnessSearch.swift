import FormalCore
import FormalIR

struct PropertyWitnessSearch {
    func find(_ property: BoundProperty, program: IRProgram, bound: Int) throws -> PropertyWitness? {
        let one = try MathematicalInteger("1")
        var constants = property.precondition.constants + property.postcondition.constants
        for constant in constants {
            let value = try MathematicalInteger(constant, maximumDigits: 256)
            constants += [value.adding(one).description, value.adding(one.negated()).description]
        }
        var candidates: [[IRValue]] = []
        for (index, type) in property.inputTypes.enumerated() {
            var values: [IRValue] = []
            switch type {
            case .integer:
                for text in ["0", "1", "-1"] + constants {
                    let value = IRValue.integer(try MathematicalInteger(text, maximumDigits: 257))
                    if !values.contains(value) { values.append(value) }
                    if values.count >= 12 { break }
                }
            case .bits(let width) where property.specification.inputViews[index] == .number:
                let raw: [UInt64] = [0, 0x8000000000000000, Binary64.canonicalNaN, 0x7ff0000000000000, 0xfff0000000000000,
                    0x3ff0000000000000, 0xbff0000000000000, 1, 0x7fefffffffffffff, 0x4340000000000000] + property.precondition.numberConstants + property.postcondition.numberConstants
                for bits in raw.prefix(32) {
                    let pattern = try BitPattern(width: width, bits: Binary64.canonical(bits))
                    let value = IRValue.bits(pattern)
                    if !values.contains(value) { values.append(value) }
                }
            case .bits(let width):
                let mask = width == 64 ? UInt64.max : (UInt64(1) << width) - 1
                let sign = UInt64(1) << (width - 1)
                var raw = [UInt64(0), 1, mask, sign - 1, sign]
                for text in constants {
                    if let value = UInt64(text), value <= mask { raw.append(value) }
                    else if property.specification.inputViews[index] == .signed, let value = Int64(text), value < 0,
                            width == 64 || value >= -(Int64(1) << (width - 1)) { raw.append(UInt64(bitPattern: value) & mask) }
                }
                for bits in raw {
                    let value = IRValue.bits(try BitPattern(width: width, bits: bits))
                    if !values.contains(value) { values.append(value) }
                    if values.count >= 12 { break }
                }
            default: throw PropertySpecification.invalid("Nonscalar witness input")
            }
            candidates.append(values)
        }
        let baseline = candidates.map { $0[0] }
        var tuples = [baseline]
        for index in candidates.indices {
            for value in candidates[index].dropFirst() where tuples.count < 64 {
                var tuple = baseline; tuple[index] = value
                if !tuples.contains(tuple) { tuples.append(tuple) }
            }
        }
        var counters = [Int](repeating: 0, count: candidates.count)
        while tuples.count < 64 && !candidates.isEmpty {
            var carry = true
            for index in candidates.indices.reversed() {
                counters[index] += 1
                if counters[index] < candidates[index].count { carry = false; break }
                counters[index] = 0
            }
            if carry { break }
            let tuple = candidates.indices.map { candidates[$0][counters[$0]] }
            if !tuples.contains(tuple) { tuples.append(tuple) }
        }
        for arguments in tuples {
            var observed: [PropertyScalar] = []
            for (argument, view) in zip(arguments, property.specification.inputViews) { observed.append(try PropertyScalar(argument, view: view)) }
            let precondition = try property.precondition.evaluate(arguments: observed, result: nil)
            guard try precondition.boolean else { continue }
            let execution = try IRInterpreter(fuel: bound, maximumStackDepth: 128, maximumValueNodes: 100_000, maximumIntegerDigits: 4096)
                .run(program, entry: property.specification.entry, arguments: arguments)
            switch execution.outcome {
            case .returned(let value):
                let result = try PropertyScalar(value, view: property.specification.resultView)
                let postcondition = try property.postcondition.evaluate(arguments: observed, result: result)
                if try !postcondition.boolean { return PropertyWitness(arguments: arguments, outcome: execution.outcome, views: property.specification.inputViews) }
            case .trapped, .failed: return PropertyWitness(arguments: arguments, outcome: execution.outcome, views: property.specification.inputViews)
            case .boundExceeded: continue
            }
        }
        return nil
    }
}
