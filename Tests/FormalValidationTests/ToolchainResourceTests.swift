import Foundation
import FormalCore
import FormalValidation
import Testing

struct ToolchainResourceTests {
    @Test func bundledPolicyIsAStandaloneRegularResource() throws {
        let resource = try ToolchainPolicy.policyResourceURL()
        let attributes = try resource.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        #expect(attributes.isRegularFile == true)
        #expect(attributes.isSymbolicLink != true)
        let policy = try ToolchainPolicy.bundled()
        #expect(try ToolchainPolicy.resourceIdentity().count == 64)
        #expect(policy.schemaVersion == 1)
        #expect(policy.inventorySHA256.count == 64)
        #expect(!policy.allowedLeanAxioms.isEmpty)
    }
}
