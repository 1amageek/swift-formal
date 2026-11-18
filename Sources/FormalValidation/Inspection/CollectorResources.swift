import Foundation
import FormalCore

public enum CollectorResources {
    public static func file(_ name: String,_ ext: String) throws -> URL {
        guard let url = Bundle.module.url(forResource: name,withExtension: ext) else { throw FormalDiagnostic(.ioFailure,"Missing formal collector resource") }
        return url
    }
    public static func identity() throws -> String {
        var hashes: [String: String] = [:]
        for (name,ext) in [("FormalSANY","class"),("FormalLean","lean")] { hashes[name + "." + ext] = try FileDigest.sha256(file(name,ext)) }
        return FileDigest.sha256(try ArtifactJSON.encode(hashes))
    }
}
