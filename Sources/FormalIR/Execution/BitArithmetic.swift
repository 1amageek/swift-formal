import FormalCore

public enum BitArithmetic {
    public static func evaluate(_ operation: IROperation, _ left: BitPattern, _ right: BitPattern) throws -> IRValue {
        guard left.width == right.width else {
            throw FormalDiagnostic(.invalidManifest, "Arithmetic operand widths differ.")
        }
        if operation.isNumber {
            guard left.width == 64 else { throw FormalDiagnostic(.invalidManifest, "Number operands require 64 bits") }
            let result = try Binary64.evaluate(operation, left.bits, right.bits)
            return try bitValue(width: result.boolean ? 1 : 64, bits: result.bits)
        }
        let a = left.bits
        let b = right.bits
        let mask = left.mask
        let sign = left.signBit
        let result: UInt64
        let overflow: Bool
        switch operation {
        case .signedAddOverflow, .unsignedAddOverflow:
            let sum = a.addingReportingOverflow(b)
            result = sum.partialValue & mask
            overflow = operation == .signedAddOverflow
                ? (~(a ^ b) & (a ^ result) & sign) != 0
                : sum.overflow || sum.partialValue > mask
        case .signedSubtractOverflow, .unsignedSubtractOverflow:
            result = (a &- b) & mask
            overflow = operation == .signedSubtractOverflow ? ((a ^ b) & (a ^ result) & sign) != 0 : a < b
        case .signedMultiplyOverflow:
            let product = left.signedValue.multipliedReportingOverflow(by: right.signedValue)
            result = UInt64(bitPattern: product.partialValue) & mask
            if left.width == 64 { overflow = product.overflow }
            else {
                let limit = Int64(1) << (left.width - 1)
                overflow = product.overflow || product.partialValue < -limit || product.partialValue >= limit
            }
        case .unsignedMultiplyOverflow:
            let product = a.multipliedFullWidth(by: b)
            result = product.low & mask
            overflow = product.high != 0 || product.low > mask
        case .signedLessThan:
            return try bitValue(width: 1, bits: left.signedValue < right.signedValue ? 1 : 0)
        case .unsignedLessThan:
            return try bitValue(width: 1, bits: a < b ? 1 : 0)
        case .equal:
            return try bitValue(width: 1, bits: a == b ? 1 : 0)
        case .and: return try bitValue(width: left.width, bits: a & b)
        case .or: return try bitValue(width: left.width, bits: a | b)
        case .xor: return try bitValue(width: left.width, bits: a ^ b)
        default: throw FormalDiagnostic(.invalidManifest, "Invalid arithmetic operation")
        }
        let value = try BitPattern(width: left.width, bits: result)
        let flag = try BitPattern(width: 1, bits: overflow ? 1 : 0)
        return .aggregate([.bits(value), .bits(flag)])
    }

    private static func bitValue(width: Int, bits: UInt64) throws -> IRValue {
        let value = try BitPattern(width: width, bits: bits)
        return .bits(value)
    }
}
