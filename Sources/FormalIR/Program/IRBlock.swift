public struct IRBlock: Codable, Sendable, Equatable {
    public let id: String
    public let parameters: [IRParameter]
    public let instructions: [IRInstruction]

    public init(id: String, parameters: [IRParameter], instructions: [IRInstruction]) {
        self.id = id
        self.parameters = parameters
        self.instructions = instructions
    }
}
