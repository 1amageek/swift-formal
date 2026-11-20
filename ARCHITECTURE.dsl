workspace "swift-formal" {
    !impliedRelationships false
    model {
        group "Verification users" {
            // Source: README.md:11 sha256=a967c9c329102fd91874e3956c55b79ac8b356856664624a1ef3457506f4d54f
            caller = person "Developer / agent" "Defines verification conditions and inspects bounded evidence"
        }
        group "Local verification" {
            // Source: README.md:5 sha256=a967c9c329102fd91874e3956c55b79ac8b356856664624a1ef3457506f4d54f
            formal = softwareSystem "swift-formal" "Generates TLA+ and Lean models from supported source and checks explicit contracts" {
                // Source: Sources/formal/FormalEntryPoint.swift:4 sha256=659b7ea44b65ebaaf34ac594e167f69c474a9d8efde412a07df7571733989aad
                // Entry: type 33..<557 sha256=659b7ea44b65ebaaf34ac594e167f69c474a9d8efde412a07df7571733989aad Sources/formal/FormalEntryPoint.swift
                cli = container "formal CLI" "Compiles supported source and orchestrates audited verification" "Swift" "worker"
                // Source: Sources/FormalEvidence/GraphStore/EvidenceDatabase.swift:10 sha256=ff77f84699f12f7bb988dc4157c6b349b9b76d4ad48dbe19846207229ce06600
                bundles = container "Evidence bundles" "Stores immutable models, provenance, claims and queryable formal graphs" "SQLite and files" "database"
            }
        }
        group "Verification tools" {
            // Source: Sources/FormalValidation/Properties/PropertyVerifier.swift:28 sha256=656b31b75e05a0e4c855abe4bb8cb26c3d5052e9c4b8900efa0284eab2c21ac3
            lean = softwareSystem "Lean kernel" "Checks generated interpreter theorems and their axiom dependencies"
            // Source: Sources/FormalValidation/Properties/PropertyVerifier.swift:67 sha256=656b31b75e05a0e4c855abe4bb8cb26c3d5052e9c4b8900efa0284eab2c21ac3
            tla = softwareSystem "TLA+ tools" "SANY checks modules and TLC explores finite scenarios or confirms counterexamples"
        }
        // Source: README.md:11 sha256=a967c9c329102fd91874e3956c55b79ac8b356856664624a1ef3457506f4d54f
        caller -> formal "Requests source-model checks and reads scoped outcomes"
        // Source: Sources/formal/FormalEntryPoint.swift:7 sha256=659b7ea44b65ebaaf34ac594e167f69c474a9d8efde412a07df7571733989aad
        caller -> cli "Invokes formal commands"
        // Source: Sources/FormalValidation/Properties/PropertyVerifier.swift:28 sha256=656b31b75e05a0e4c855abe4bb8cb26c3d5052e9c4b8900efa0284eab2c21ac3
        formal -> lean "Checks generated-model theorems"
        // Source: Sources/FormalValidation/Properties/PropertyVerifier.swift:67 sha256=656b31b75e05a0e4c855abe4bb8cb26c3d5052e9c4b8900efa0284eab2c21ac3
        formal -> tla "Checks modules and bounded state spaces"
        // Source: Sources/FormalValidation/Properties/PropertyVerifier.swift:28 sha256=656b31b75e05a0e4c855abe4bb8cb26c3d5052e9c4b8900efa0284eab2c21ac3
        cli -> lean "Runs pinned Lean and audits theorem dependencies"
        // Source: Sources/FormalValidation/Properties/PropertyVerifier.swift:67 sha256=656b31b75e05a0e4c855abe4bb8cb26c3d5052e9c4b8900efa0284eab2c21ac3
        cli -> tla "Runs SANY and TLC with resource limits"
        // Source: Sources/FormalCompiler/Artifacts/CompilationArtifact.swift:16 sha256=ac8149fda707d7aba094a79925d334f9f1a33e32e7da0c4c867b41c318293e8e
        cli -> bundles "Publishes immutable compilation and verification evidence"
    }
    views {
        systemContext formal "FormalContext" {
            include *
        }
        container formal "FormalContainers" {
            include *
        }
    }
}
