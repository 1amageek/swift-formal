public enum ToolProcessGroupOwnership: Sendable {
    case isolated
    /// Start a fresh session whose leader cannot change its process group.
    case isolatedSession
    /// An external owner must own and clean up the caller's complete process group.
    case inherited
}
