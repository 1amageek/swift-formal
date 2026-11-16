public protocol ProjectMetadataResolving: Sendable {
    func resolve(at path: String, trustedProject: Bool) throws -> ProjectMetadata?
}
