public func subtract(_ lhs: Int64, _ rhs: Int64) -> Int64 { lhs - rhs }
public func wrappingSubtract(_ lhs: Int64, _ rhs: Int64) -> Int64 { lhs &- rhs }
public func choose(_ value: Int64) -> Int64 { value > 0 ? value : -value }
public func call(_ lhs: Int64, _ rhs: Int64) -> Int64 { subtract(lhs, rhs) }
public func loop(_ count: Int64) -> Int64 {
    var total: Int64 = 0
    var index: Int64 = 0
    while index < count { total &+= index; index &+= 1 }
    return total
}
