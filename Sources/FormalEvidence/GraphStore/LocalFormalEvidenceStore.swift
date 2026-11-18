import Foundation

public struct LocalFormalEvidenceStore: FormalEvidenceOpening {
    public let root: URL
    public init(root: URL) { self.root = root }
    public func open(_ reference: EvidenceBundleReference, budget: EvidenceReadBudget) async throws -> any FormalEvidenceReading {
        try Task.checkCancellation()
        return try EvidenceBundleReader(root: root, reference: reference, budget: budget)
    }
}
