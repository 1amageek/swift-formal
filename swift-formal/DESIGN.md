# swift-formal

## Purpose and Scope
This directory is both the system root and SwiftPM package root. The package provides input contracts, integrity inspection, optional source indexing, scalar SIL/IR/backend libraries, and an honest CLI. The requested compiler is specified in [SPEC.md](Documentation/SPEC.md); P1 has partial behavioral evidence; P2–P4 remain future work. There is no parent design.

## Responsibilities and Boundaries
SIL is the only future execution-semantics input. Source indexing is presentation metadata. Package creation does not establish translation correctness. Scalar backend emission, restricted output-data decoding, and a separate Lean SIL decoder exist. Complete SIL step correspondence, trusted-runtime auditing, strict generation orchestration, and Actor semantics remain unimplemented.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [FormalCore](Sources/FormalCore/DESIGN.md) | child | Input and diagnostic contracts | Immutable metadata and integrity inspection | Integrity is not semantic validation |
| [FormalIndex](Sources/FormalIndex/DESIGN.md) | child | Optional declaration metadata | Fixed upstream public APIs | No mangled-symbol identity or semantics |
| [FormalCLI](Sources/FormalCLI/DESIGN.md) | child | Commands and exit status | Operational interface | Future operations fail explicitly |
| [Executable](Sources/formal/DESIGN.md) | child | Process entry point | I/O and exit | No conversion logic |
| [FormalSIL](Sources/FormalSIL/DESIGN.md) | child | Structural canonical SIL parsing | Lossless lexical and CFG boundaries | No semantic support implied |
| [FormalIR](Sources/FormalIR/DESIGN.md) | child | Common typed program and small-step semantics | Initial scalar execution slice | Full Core and Actor support pending |
| [FormalLowering](Sources/FormalLowering/DESIGN.md) | child | Checked scalar lowering | Explicit type/opcode rules | Full SIL translation validation pending |
| [FormalTLA](Sources/FormalTLA/DESIGN.md) | child | Scalar TLA emission | Bit-vector runtime and program data | Independent full correspondence pending |
| [FormalLean](Sources/FormalLean/DESIGN.md) | child | Scalar Lean emission | Typed deep embedding and step relation | Does not imply application proofs |
| [FormalValidation](Sources/FormalValidation/DESIGN.md) | child | Restricted actual-output decoding | Preserves all scalar program data | Runtime audit and complete SIL relation pending |
| [FormalLean](Sources/FormalLean/DESIGN.md) | child | Lean scalar emission | Deep embedding | Independent validation pending |
| [FormalTLA](Sources/FormalTLA/DESIGN.md) | child | TLA+ scalar emission | Parametric transition system | Independent validation pending |

## Architecture
```text
Executable -> FormalCLI -> FormalCore
                       -> FormalIndex -> FormalCore
                                      -> swift-skeleton (fixed revision)
Future: SIL -> FormalIR -> TLA / Lean -> independent validation
```
The future modules in SPEC section 16 are not empty Swift targets. They are introduced when they own implemented behavior.

## Contracts and Invariants
- The executable product, target, invocation, and source directory are `formal`, `formal`, `formal`, and `Sources/formal/`. The package identity remains `swift-formal`.
- This naming contract reflects the user's 2026-11-16 correction and supersedes the CLI name and executable directory in the immutable imported [specification snapshot](Documentation/SPEC.md).
- No command claims GENERATED, VALIDATED, MODEL_CHECKED, or PROVED.
- A bootstrap lock does not authorize any SIL opcode.
- Missing metadata and mismatching hashes fail; host defaults never fill semantic input gaps.
- All state is invocation-local; no shared mutable state, callbacks, streams, or GPU paths exist.
- The host package is macOS-only. No WASM or Embedded support is claimed.

## Runtime Flows
`doctor -> bounded compiler probe -> exact lock comparison`; `inspect-bundle -> metadata and hash checks`; `index -> source parser`; future semantic commands return exit 3 without writing artifacts.

## Failure, Concurrency, and Constraints
Inputs are bounded by caller-selected byte limits. Compiler probes have deadlines and bounded output. SwiftPM metadata evaluates trusted manifests only. No network or dependency installation occurs in CLI commands.

## Verification and Change Impact
[Core tests](Tests/FormalCoreTests), [Index tests](Tests/FormalIndexTests), and [CLI tests](Tests/FormalCLITests) own local behavior. [integration.py](Tools/integration.py) exercises the actual executable, lock mismatch, bundle tampering, indexing, and fail-closed commands. Use [run-with-timeout.py](Tools/run-with-timeout.py) for all test processes. Any new semantic operation must update this design and the relevant lower contracts before implementation.
