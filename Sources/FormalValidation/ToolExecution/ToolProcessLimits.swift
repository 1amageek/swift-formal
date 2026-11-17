public struct ToolProcessLimits: Sendable {
    public let maximumResidentBytes: UInt64
    public let maximumProcesses: Int
    public let maximumCPUSeconds: Double
    public init(maximumResidentBytes: UInt64, maximumProcesses: Int, maximumCPUSeconds: Double) {
        self.maximumResidentBytes = maximumResidentBytes
        self.maximumProcesses = maximumProcesses
        self.maximumCPUSeconds = maximumCPUSeconds
    }
}
