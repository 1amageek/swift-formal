public struct IRParameter: Codable, Sendable, Equatable {
    public let id: String
    public let type: IRType

    public init(id: String, type: IRType) {
        self.id = id
        self.type = type
    }
}
