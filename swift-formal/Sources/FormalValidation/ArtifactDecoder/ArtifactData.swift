indirect enum ArtifactData: Equatable {
    case text(String)
    case bigNumber(String)
    case number(UInt64)
    case list([ArtifactData])
    case record([String: ArtifactData])
    case constructor(String, [ArtifactData])
}
