public enum ToolResourceLimit: String, Error, Sendable, CustomStringConvertible {
    case memory, processes, cpu, output, workspace
    public var description: String { "Tool exceeded its " + rawValue + " resource budget" }
}
