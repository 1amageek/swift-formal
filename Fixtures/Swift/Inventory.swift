public actor Inventory {
    public var stock: Int64
    public init(stock: Int64) { self.stock = stock }
    public func reserveBuggy() async -> Bool {
        if stock > 0 {
            await Task.yield()
            stock -= 1
            return true
        }
        return false
    }
    public func reserveFixed() async -> Bool {
        if stock > 0 {
            stock -= 1
            return true
        }
        return false
    }
}
