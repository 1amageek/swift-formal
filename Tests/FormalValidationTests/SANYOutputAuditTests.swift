import Foundation
import FormalCore
@testable import FormalValidation
import Testing

struct SANYOutputAuditTests {
    @Test(.timeLimit(.minutes(1)))
    func normalModuleProcessingAcceptsErrorInPaths() throws {
        for path in ["/tmp/error-directory/CaseModel.tla", "/tmp/ERROR handling/CaseModel.tla"] {
            let output = "Parsing file \(path)\nSemantic processing of module Naturals\nSemantic processing of module CaseModel\n"
            try SANYOutputAudit.check(output, module: "CaseModel")
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func completionDoesNotHideActualDiagnostics() throws {
        let completion = "Semantic processing of module CaseModel\n"
        for diagnostic in ["Semantic errors:\n\n*** Errors: 1\nUnknown operator: MissingOperator.",
                           "***Parse Error***\nWas expecting a definition.",
                           "Fatal errors:\nCannot find module.",
                           "  *** Errors: 1\nInvalid expression.",
                           "Exception in thread main: java.lang.IllegalStateException"] {
            #expect(throws: FormalDiagnostic.self) {
                try SANYOutputAudit.check(completion + diagnostic, module: "CaseModel")
            }
        }
        if let path = ProcessInfo.processInfo.environment["FORMAL_SANY_DIAGNOSTIC_FIXTURE"] {
            let output = try String(contentsOfFile: path, encoding: .utf8)
            #expect(output.contains("Semantic processing of module Invalid"))
            #expect(throws: FormalDiagnostic.self) { try SANYOutputAudit.check(output, module: "Invalid") }
        }
    }

    @Test(.timeLimit(.minutes(1)))
    func exactRequestedModuleCompletionIsRequired() throws {
        for output in ["", "Parsing file /tmp/CaseModel.tla\n", "Semantic processing of module Other\n",
                       "Semantic processing of module CaseModelSuffix\n"] {
            #expect(throws: FormalDiagnostic.self) { try SANYOutputAudit.check(output, module: "CaseModel") }
        }
    }
}
