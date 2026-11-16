public struct ProjectMetadata: Codable, Sendable, Equatable {
    public struct Target: Codable, Sendable, Equatable {
        public let name: String
        public let moduleName: String
        public let sourceRoots: [String]
    }

    public let packageName: String
    public let targets: [Target]
    public let isCaptureBuildPlan: Bool

    init(packageName: String, targets: [Target]) {
        self.packageName = packageName
        self.targets = targets
        self.isCaptureBuildPlan = false
    }
}
