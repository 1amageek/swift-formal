// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "swift-formal",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "FormalCore", targets: ["FormalCore"]),
        .library(name: "FormalSIL", targets: ["FormalSIL"]),
        .library(name: "FormalIR", targets: ["FormalIR"]),
        .library(name: "FormalLowering", targets: ["FormalLowering"]),
        .library(name: "FormalLean", targets: ["FormalLean"]),
        .library(name: "FormalTLA", targets: ["FormalTLA"]),
        .library(name: "FormalValidation", targets: ["FormalValidation"]),
        .executable(name: "formal", targets: ["formal"]),
    ],
    dependencies: [],
    targets: [
        .target(name: "FormalCore", exclude: ["DESIGN.md", "Contracts/DESIGN.md", "Bundle/DESIGN.md"]),
        .target(name: "FormalSIL", dependencies: ["FormalCore"], exclude: ["DESIGN.md", "Syntax/DESIGN.md"]),
        .target(name: "FormalIR", dependencies: ["FormalCore"], exclude: ["DESIGN.md", "Program/DESIGN.md", "Execution/DESIGN.md"]),
        .target(name: "FormalLowering", dependencies: ["FormalCore", "FormalSIL", "FormalIR"], exclude: ["DESIGN.md", "Scalar/DESIGN.md"]),
        .target(name: "FormalLean", dependencies: ["FormalCore", "FormalIR"], exclude: ["DESIGN.md", "Emission/DESIGN.md"], resources: [.copy("Emission/Runtime.lean")]),
        .target(name: "FormalTLA", dependencies: ["FormalCore", "FormalIR"], exclude: ["DESIGN.md", "Emission/DESIGN.md"], resources: [.copy("Emission/SwiftFormalRuntime.tla")]),
        .target(name: "FormalValidation", dependencies: ["FormalCore", "FormalIR"], exclude: ["DESIGN.md", "ArtifactDecoder/DESIGN.md"]),
        .target(
            name: "FormalCLI",
            dependencies: ["FormalCore"],
            exclude: ["DESIGN.md", "Commands/DESIGN.md", "Environment/DESIGN.md"]
        ),
        .executableTarget(name: "formal", dependencies: ["FormalCLI"], exclude: ["DESIGN.md"]),
        .testTarget(name: "FormalCoreTests", dependencies: ["FormalCore"]),
        .testTarget(name: "FormalCLITests", dependencies: ["FormalCLI"]),
        .testTarget(name: "FormalSILTests", dependencies: ["FormalSIL"]),
        .testTarget(name: "FormalIRTests", dependencies: ["FormalIR"]),
        .testTarget(name: "FormalLoweringTests", dependencies: ["FormalLowering", "FormalSIL", "FormalIR"]),
        .testTarget(name: "FormalBackendTests", dependencies: ["FormalLean", "FormalTLA", "FormalLowering", "FormalSIL", "FormalIR"]),
        .testTarget(name: "FormalValidationTests", dependencies: ["FormalValidation", "FormalLean", "FormalTLA", "FormalLowering", "FormalSIL", "FormalIR"]),
    ]
)
