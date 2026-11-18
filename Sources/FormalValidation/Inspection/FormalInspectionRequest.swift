import Foundation
import FormalEvidence

public struct FormalInspectionRequest: Sendable {
    public enum Language: String, Codable, Sendable { case tla, lean }
    public let language: Language
    public let inputRoot: URL
    public let files: [InspectionInputFile]
    public let modules: [String]
    public let declaration: String?
    public let output: URL
    public let toolchain: BundledToolchain
    public let timeout: Double
    public let budget: EvidenceReadBudget
    public let executionLimits: ToolProcessLimits
    public let userCodeAuthorized: Bool
    public init(language: Language,inputRoot: URL,files: [InspectionInputFile],modules: [String],declaration: String? = nil,output: URL,toolchain: BundledToolchain,timeout: Double,budget: EvidenceReadBudget,executionLimits: ToolProcessLimits,userCodeAuthorized: Bool = false) {
        self.language = language; self.inputRoot = inputRoot; self.files = files; self.modules = modules; self.declaration = declaration
        self.output = output; self.toolchain = toolchain; self.timeout = timeout; self.budget = budget; self.executionLimits = executionLimits; self.userCodeAuthorized = userCodeAuthorized
    }
}
