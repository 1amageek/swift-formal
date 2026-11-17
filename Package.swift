// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "swift-formal",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "FormalCore", targets: ["FormalCore"]),
        .library(name: "FormalIR", targets: ["FormalIR"]),
        .library(name: "FormalCompiler", targets: ["FormalCompiler"]),
        .library(name: "FormalValidation", targets: ["FormalValidation"]),
        .executable(name: "formal", targets: ["formal"]),
    ],
    dependencies: [],
    targets: [
        .target(name: "FormalCore", exclude: ["DESIGN.md", "Contracts/DESIGN.md", "Bundle/DESIGN.md"]),
        .target(name: "FormalIR", dependencies: ["FormalCore"], exclude: ["DESIGN.md", "Program/DESIGN.md", "Execution/DESIGN.md"]),
        .target(name: "FormalCompiler", dependencies: ["FormalCore", "FormalIR"],
                exclude: ["DESIGN.md", "Frontends/DESIGN.md", "Artifacts/DESIGN.md", "SIL/DESIGN.md", "SIL/Syntax/DESIGN.md", "Lowering/DESIGN.md", "Lowering/Scalar/DESIGN.md", "Lean/DESIGN.md", "Lean/Emission/DESIGN.md", "TLA/DESIGN.md", "TLA/Emission/DESIGN.md"],
                resources: [.copy("Lean/Emission/Runtime.lean"), .copy("TLA/Emission/SwiftFormalRuntime.tla")]),
        .target(name: "FormalValidation", dependencies: ["FormalCore", "FormalIR"], exclude: ["DESIGN.md", "ArtifactDecoder/DESIGN.md", "ToolExecution/DESIGN.md", "Toolchain/DESIGN.md", "Verification/DESIGN.md", "Properties/DESIGN.md", "Inspection/DESIGN.md"], resources: [.copy("Toolchain/toolchain-artifacts.lock.json"), .copy("Verification/trusted-artifacts.json")]),
        .executableTarget(name: "formal", dependencies: ["FormalCore", "FormalIR", "FormalCompiler", "FormalValidation"],
                          exclude: ["DESIGN.md", "Commands/DESIGN.md", "Environment/DESIGN.md", "Distribution/DESIGN.md"]),
        .testTarget(name: "FormalFrontendTests", dependencies: ["FormalCompiler", "FormalIR", "FormalValidation"]),
        .testTarget(name: "FormalCoreTests", dependencies: ["FormalCore"]),
        .testTarget(name: "FormalIRTests", dependencies: ["FormalIR"]),
        .testTarget(name: "FormalCLITests", dependencies: ["formal"]),
        .testTarget(name: "FormalSILTests", dependencies: ["FormalCompiler"]),
        .testTarget(name: "FormalLoweringTests", dependencies: ["FormalCompiler", "FormalIR"]),
        .testTarget(name: "FormalBackendTests", dependencies: ["FormalCompiler", "FormalIR"]),
        .testTarget(name: "FormalValidationTests", dependencies: ["FormalValidation", "FormalCompiler", "FormalIR"]),
    ]
)
