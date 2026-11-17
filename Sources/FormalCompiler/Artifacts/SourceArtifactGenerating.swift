import Foundation

public protocol SourceArtifactGenerating: Sendable {
    func generate(_ source: Data, language: SourceLanguage, moduleID: String) throws -> SourceArtifact
}
