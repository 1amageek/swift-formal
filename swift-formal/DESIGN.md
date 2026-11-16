# swift-formal

## Purpose and Scope
This directory is both the system root and SwiftPM package root. The package provides input contracts, integrity inspection, scalar SIL/IR/backend libraries, and an honest CLI. The requested compiler is specified in [SPEC.md](Documentation/SPEC.md); P1 has partial behavioral evidence; P2–P4 remain future work. There is no parent design.

## Responsibilities and Boundaries
SIL is the execution-semantics input. Declaration indexing and source-project adapters are outside the current package. Package creation does not establish translation correctness. Scalar backend emission, restricted output-data decoding, and a separate Lean SIL decoder exist. Complete SIL step correspondence, trusted-runtime auditing, strict generation orchestration, and Actor semantics remain unimplemented.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [FormalCore](Sources/FormalCore/DESIGN.md) | child | Metadata and diagnostics | Shared contracts | Integrity is not semantic validation |
| [FormalIR](Sources/FormalIR/DESIGN.md) | child | Typed program and execution | Language-neutral semantics | Complete Core and Actor support pending |
| [FormalCompiler](Sources/FormalCompiler/DESIGN.md) | child | Frontends, lowering, emission | Compiler pipeline | Profiles require explicit semantics |
| [FormalValidation](Sources/FormalValidation/DESIGN.md) | child | Actual-output decoding | Independent inspection | Cannot import FormalCompiler |
| [formal](Sources/formal/DESIGN.md) | child | Commands and process entry | Executable composition | Unimplemented operations fail explicitly |

## Architecture
```text
formal -> FormalCompiler -> FormalIR -> FormalCore
       -> FormalValidation -> FormalIR
       -> FormalCore
FormalCompiler: language frontend -> common IR -> TLA+ / Lean
```
Five production SwiftPM targets enforce the boundaries above. Parsing, lowering, and emission are components inside FormalCompiler, not separate modules. Test target boundaries remain independently traceable.

## Contracts and Invariants
- The executable product, target, invocation, and source directory are `formal`, `formal`, `formal`, and `Sources/formal/`. The package identity remains `swift-formal`.
- This naming contract reflects the user's 2026-11-16 correction and supersedes the CLI name and executable directory in the immutable imported [specification snapshot](Documentation/SPEC.md).
- The package has no external SwiftPM dependencies. Toolchain identity is independent of declaration-index tools; the declaration-index module and CLI command are removed.
- This contract reflects the user's no-Skeleton requirement and supersedes all Skeleton dependencies, adapters, and revision requirements in the imported specification snapshot.
- No command claims GENERATED, VALIDATED, MODEL_CHECKED, or PROVED.
- A bootstrap lock does not authorize any SIL opcode.
- Missing metadata and mismatching hashes fail; host defaults never fill semantic input gaps.
- All state is invocation-local; no shared mutable state, callbacks, streams, or GPU paths exist.
- The host package is macOS-only. No WASM or Embedded support is claimed.

## Runtime Flows
`doctor -> bounded compiler probe -> exact lock comparison`; `inspect-bundle -> metadata and hash checks`; future semantic commands return exit 3 without writing artifacts.

## Failure, Concurrency, and Constraints
Inputs are bounded by caller-selected byte limits. Compiler probes have deadlines and bounded output. Current CLI commands do not evaluate SwiftPM manifests. No network or dependency installation occurs in CLI commands.

## Verification and Change Impact
[Core tests](Tests/FormalCoreTests) and [CLI tests](Tests/FormalCLITests) own local behavior. [integration.py](Tools/integration.py) exercises the actual executable, lock mismatch, bundle tampering, removed-command rejection, and fail-closed commands. Use [run-with-timeout.py](Tools/run-with-timeout.py) for all test processes. Any new semantic operation must update this design and the relevant lower contracts before implementation.
