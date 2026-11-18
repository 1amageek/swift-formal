import Foundation

public struct SourceCompilationRequest: Sendable {
    public let source: Data
    public let language: SourceLanguage
    public let moduleID: String
    public let defaultNumeric: SourceNumericDefault?
    public init(source: Data, language: SourceLanguage, moduleID: String, defaultNumeric: SourceNumericDefault? = nil) {
        self.source = source; self.language = language; self.moduleID = moduleID; self.defaultNumeric = defaultNumeric
    }
}
