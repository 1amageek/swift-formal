# swift-formal

## Purpose and Scope
System and SwiftPM package master; no parent. Provide explicit scalar source/canonical SIL profiles, common IR, TLA+/Lean generation and independent checking. The [original specification](Documentation/SPEC.md) remains a functional baseline. General SIL/source correspondence and Actor semantics remain incomplete. The new structured evidence SDK is **design-only**, with [transition and removal gates](Documentation/SDK-TRANSITION.md).

## Responsibilities and Boundaries
Formal owns semantic profiles, exact generated artifacts, independent trust audits, actual formal-language structure and verification evidence. Application declaration indexing, Agent/change ownership, daemon scheduling and UI rendering belong outside this package. There is no ArchitectureExplorer, Invar, Skeleton or external SwiftPM dependency.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [FormalCore](Sources/FormalCore/DESIGN.md) | child | Metadata, contracts and diagnostics | Shared values | Integrity is not semantic validation |
| [FormalIR](Sources/FormalIR/DESIGN.md) | child | Validated program and interpreter semantics | Common semantic boundary | Actor/general runtime support pending |
| [FormalCompiler](Sources/FormalCompiler/DESIGN.md) | child | Located compilation and tracked emission | Generated model/artifacts | Origin is not semantic certification |
| [FormalValidation](Sources/FormalValidation/DESIGN.md) | child | Independent audit and checking | Actual observations | Cannot import Compiler |
| [FormalEvidence](Sources/FormalEvidence/DESIGN.md) | proposed child | Structured records and bounded readers | TLA+/Lean visualization SDK | Not a production product yet |
| [formal](Sources/formal/DESIGN.md) | child | CLI and distribution | Executable composition | Unsupported commands fail explicitly |
| [Invar](../Invar/DESIGN.md) | used by | Public Compiler/Validation/Evidence SDKs | Workflow integration | No reverse source dependency |

## Architecture
```text
formal -> FormalCompiler -> FormalIR -> FormalCore
       -> FormalValidation -> FormalIR
       -> FormalCore
Target additional dependencies:
  FormalCompiler / FormalValidation -> FormalEvidence -> FormalCore
Invar -> Compiler / Validation / Evidence public SDKs
ArchitectureExplorer remains a generic renderer with no Formal dependency
```
The five existing production targets remain until implemented replacements pass their gates. The proposed Evidence module follows native SwiftPM boundaries; add it only with code/tests. Frontends/lowering/emission remain components of Compiler. Validation consumes actual output and never reuses Compiler lowering as an independent oracle.

## Contracts and Invariants
- Executable/product/target/source directory remain `formal` and `Sources/formal/`; the package identity remains swift-formal. Root Package.swift is directly consumable. These existing decisions supersede conflicting names/layout/Skeleton dependencies in the original snapshot.
- Source translation remains DRAFT_UNVALIDATED. Model checking/kernel proofs retain their finite/quantified model domain; no graph or provenance link promotes them to source-level correctness.
- Missing semantic metadata, unsupported instructions/profiles, hash mismatch and unavailable isolation fail explicitly. A bootstrap/tool lock grants no semantic capability.
- Exact source/IR/generated correspondence and formal graph meanings are owned by [Artifacts](Sources/FormalCompiler/Artifacts/DESIGN.md) and [Evidence Records](Sources/FormalEvidence/Records/DESIGN.md). Actual inspection/auditing belongs to [Inspection](Sources/FormalValidation/Inspection/DESIGN.md).
- Compilation layout 2 replaces layout 1 without legacy readers/aliases. Evidence and semantic IR schemas have separate versions; a location sidecar alone need not change IR meaning. Old private artifacts are not silently rewritten/deleted.
- Package host support is native macOS. No WASM/Embedded/GPU capability is added by this design.

## Runtime Flows
```text
owned exact source/profile -> located parsing/lowering -> IR + origin links
 -> tracked Lean/TLA generation -> immutable compilation artifact
 -> independent artifact audit -> bounded actual tool execution
 -> per-obligation claims + actual formal graph extraction -> sealed evidence bundle
 -> bounded graph / trace / origin / document queries
```
Existing finite checking, [quantified properties](Sources/FormalValidation/Properties/DESIGN.md) and independent runtime/data audits remain requirements. Extraction availability and proof outcome are independent. Failed optional graph extraction can coexist with valid proof evidence. Generated proofs and arbitrary user-authored Lean elaboration have different execution/isolation profiles.

## State, Ownership, and Lifecycle
Compiler parsing/lowering is invocation-local. ToolExecution owns process groups, limits, journals and complete cleanup. The proposed GraphStore reader actor owns retained bundle leases, descriptors, bounded caches and in-flight reads until explicit shutdown. Immutable data crosses module boundaries; no unowned background tasks are created for UI sessions.

## Failure, Concurrency, and Constraints
Child owners define byte/token/depth/graph/output/process/time budgets and typed failures. Remaining ancestor deadline and cleanup cost apply throughout. Checking is offline; only explicit install/package operations may acquire pinned tools. Controlled user Lean inspection requires a verified import closure and enforced isolation; unsupported capability never falls back to unrestricted execution. Current generated-model tests do not certify that new profile.

## Verification and Change Impact
[SDK transition](Documentation/SDK-TRANSITION.md) owns FE-01..09 behavior, current implementation facts and exact deletion order. Existing [integration](Tools/integration.py), frontend, IR, backend and Validation tests retain their original proof scope. The [frontend regression contract](Sources/FormalCompiler/Frontends/DESIGN.md#four-finding-regression-ownership) and [binary64 Number semantics](Sources/FormalIR/Execution/DESIGN.md#binary64-number-contract) remain lower authority. New API/result/resource changes update Compiler, Validation, CLI/distribution and Invar callers coherently. Run all test processes through [run-with-timeout](Tools/run-with-timeout.py). Document/manifest checks do not establish semantic or extraction correctness.
