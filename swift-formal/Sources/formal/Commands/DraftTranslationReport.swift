import FormalCompiler

struct DraftTranslationReport: Encodable {
    let schemaVersion = 1
    let status = "DRAFT_UNVALIDATED"
    let sourceLanguage: SourceLanguage
    let profile: String
    let assumptions: [String]
    let sourceSHA256: String
    let functions: [String]
    let actualOutputDataMatchesIR = true
    let semanticValidationPerformed = false
    let externalToolsExecuted = false
}
