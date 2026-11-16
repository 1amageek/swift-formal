import FormalCore
import SkeletonSwiftPMProjectSupport

public struct SkeletonProjectMetadataResolver: ProjectMetadataResolving {
    public init() {}

    public func resolve(at path: String, trustedProject: Bool) throws -> ProjectMetadata? {
        guard trustedProject else {
            throw FormalDiagnostic(.invalidArguments, "SwiftPM metadata requires an explicitly trusted project.", path: path)
        }
        do {
            let structure = try SwiftPMProjectStructureResolver(timeoutSeconds: 15).resolve(scopeRoot: path)
            guard let structure else { return nil }
            let targets = structure.units.map {
                ProjectMetadata.Target(name: $0.name, moduleName: $0.moduleName, sourceRoots: $0.sourceRoots)
            }
            return ProjectMetadata(packageName: structure.packageIdentity, targets: targets)
        } catch {
            throw FormalDiagnostic(.toolFailure, "SwiftPM metadata resolution failed: \(error)", path: path)
        }
    }
}
