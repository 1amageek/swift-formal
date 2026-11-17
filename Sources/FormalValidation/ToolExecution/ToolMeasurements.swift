public struct ToolMeasurements: Sendable {
    public let sampledPeakResidentBytes: UInt64
    public let sampledPeakProcesses: Int
    public let cpuSeconds: Double
    public init(sampledPeakResidentBytes: UInt64 = 0, sampledPeakProcesses: Int = 0, cpuSeconds: Double = 0) {
        self.sampledPeakResidentBytes = sampledPeakResidentBytes
        self.sampledPeakProcesses = sampledPeakProcesses
        self.cpuSeconds = cpuSeconds
    }
}
