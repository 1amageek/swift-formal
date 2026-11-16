import FormalIR

enum SourceNumberBuiltin {
    static func operation(_ name: String) -> IROperation? {
        switch name {
        case "Number.isNaN": .numberIsNaN
        case "Number.isFinite": .numberIsFinite
        case "Number.isInteger": .numberIsInteger
        case "Number.isSafeInteger": .numberIsSafeInteger
        case "Object.is": .numberSameValue
        case "Math.abs": .numberAbsolute
        default: nil
        }
    }
    static func arity(_ name: String) -> Int { name == "Object.is" ? 2 : 1 }
    static func reserved(_ name: String) -> Bool { ["Number", "Object", "Math", "NaN", "Infinity"].contains(name) }
}
