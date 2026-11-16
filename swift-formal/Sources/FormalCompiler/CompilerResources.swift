import Foundation

/// Locates the resources that must accompany a portable executable linked to this module.
public enum CompilerResources {
    public static var bundleURL: URL { Bundle.module.bundleURL }
}
