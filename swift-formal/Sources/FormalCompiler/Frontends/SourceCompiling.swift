import FormalIR

public protocol SourceCompiling: Sendable {
    func compile(_ source: String, language: SourceLanguage, moduleID: String) throws -> IRProgram
}
