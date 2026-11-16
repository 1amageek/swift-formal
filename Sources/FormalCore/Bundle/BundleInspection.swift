public struct BundleInspection: Codable, Sendable, Equatable {
    public let profileID: String
    public let moduleCount: Int
    public let entryPointCount: Int
    public let integrityChecked: Bool
    public let semanticValidationPerformed: Bool

    init(profileID: String, moduleCount: Int, entryPointCount: Int) {
        self.profileID = profileID
        self.moduleCount = moduleCount
        self.entryPointCount = entryPointCount
        self.integrityChecked = true
        self.semanticValidationPerformed = false
    }
}
