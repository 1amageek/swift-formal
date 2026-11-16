public struct IRFunction: Codable, Sendable, Equatable {
    public let moduleID: String
    public let symbol: String
    public let result: IRType
    public let blocks: [IRBlock]

    public init(moduleID: String, symbol: String, result: IRType, blocks: [IRBlock]) {
        self.moduleID = moduleID
        self.symbol = symbol
        self.result = result
        self.blocks = blocks
    }

    public var type: IRType {
        .function(parameters: blocks.first?.parameters.map(\.type) ?? [], result: result)
    }
}
