# Implementation progress

The requested completion scope is the entire v1 specification, including Actor support. Current work is incomplete; scalar-library evidence alone does not satisfy the request.

| Phase | Required result | Current evidence |
|---|---|---|
| P0 | Locked inputs, schemas, trust boundary, dependency-free package | Host lock, input records, bundle checks implemented/tested; certified semantics profile pending |
| P1 | Arithmetic, branches, calls; both backends; independent validation | Scalar SIL -> IR -> both outputs works. SANY, TLC, Lean finite execution, separate Lean decoder and kernel data/step equality pass. Full SIL step relation, general runtime semantic audit and complete semantic mutation suite pending |
| P2 | Memory, loops, recursion, enums, exceptions, dependency closure | IR loops/recursion execute and report fuel/stack bounds. Reachable scalar calls are closed. SIL memory/enum/exception lowering pending |
| P3 | Actor and async with both backends and replay | Actual Swift 6.4.1 fixture SIL inspected and structurally parsed; semantic translation/replay not implemented |
| P4 | All CLI operations, support matrix, provenance, acceptance/mutation suite | Portable installation and finite generated-model checking available; strict SIL certification remains disabled |

## Multi-language consolidation checkpoint

Five production modules now separate FormalCore, FormalIR, FormalCompiler, FormalValidation, and formal. The consolidation checkpoint preserved all nine existing emitted files byte-for-byte. Eight source scalar-v1 profiles feed the common IR; source language contracts and limitations are authoritative in [Frontends/DESIGN.md](Sources/FormalCompiler/Frontends/DESIGN.md). Both backends and the independent data decoder support arbitrary integers, panic, and detected undefined behavior. The explicit draft CLI writes DRAFT_UNVALIDATED output with source bytes/hash, profile assumptions, IR, both backends, and data-comparison results.

55 named Swift tests across eight targets and actual CLI integration pass. Native tools agree with IR on the checked normal/large-integer cases; Swift/Rust overflow fails, C/C++ UBSan detects signed overflow, and Go wraps. Source-generated outputs pass 39 finite Lean kernel result checks and 40 TLC scenarios including terminal reachability. These finite checks do not complete the original v1/Actor request or establish general source semantic preservation. Strict certification remains disabled.

## Verified paths

- The user's no-Skeleton requirement supersedes the imported specification. External SwiftPM dependencies, source-index adapters, their CLI command, and index-tool lock metadata are removed.
- Swift contract, bundle containment/tampering, parser malformed-input, scalar arithmetic/CFG/calls, and artifact mutation tests pass.
- Real canonical SIL fixtures cover subtraction, wrapping, branch, direct call, memory loops, and Actor accessors/coroutines. Scalar lowering currently rejects memory and Actor operations.
- Four-bit arithmetic exhaustively matches independent mathematical expected results. Fixed 64-bit signed/unsigned overflow endpoints remain distinct.
- Lean 4.35.0 compiles actual emitted files and kernel-checks subtraction, call, branch, and wrapping results. Audited dependencies remain within propext, Classical.choice, and Quot.sound.
- Separate Lean SIL decoding yields the same scalar program data as emitted Lean; kernel equality and shared-runtime step/reachability correspondence check. Arithmetic mutation is rejected.
- TLA tools 1.7.4 SANY checks actual outputs. TLC completes five scalar 64-bit scenarios (subtract, call, branch, wrap, trap). TLA uses bit sequences to avoid TLC's bounded integer representation.
- None of these establishes the entire source-SIL/reference-semantics relation or the Actor contract. Production semantic coverage remains empty; strict generation is disabled.

## Important remaining proof work

Independent Lean decoding currently normalizes scalar SIL directly into the common runtime's instruction data. Kernel data equality is useful but is not a proof of each SIL opcode's small-step semantics, debug stuttering, and state/observation mapping. A separate SIL reference relation and complete rule evidence are still required before translation can be VALIDATED. The TLA runtime and wrappers also require a completed independent audit contract. The experimental scalar lowering currently represents standard integer/Bool wrappers as aggregates and erases nominal identity; this is explicitly marked incomplete and must be corrected before certification.

## Environment

Swift 6.4.1 release, SDK 27.2, Java 24.0.2. Lean 4.35.0 and TLA tools 1.7.4 are installed under ignored .tools. Lean archive SHA-256 matches the upstream release digest. No system-wide installation, remote publication, or deployment occurred.

## Four frontend regression corrections

The four reviewed defects are corrected under the [frontend contract](Sources/FormalCompiler/Frontends/DESIGN.md#four-finding-regression-ownership). Regression evidence covers 19 positive observations in native execution, IR, TLA+, and Lean, plus 14 CLI rejection scenarios with no artifacts. The original 12 KB stack-overflow counterexample now fails diagnostically. Bounded nonrecursive expression lowering also preserves nested-call argument order. Existing eight-language external verification and package/CLI integration remain green. See [Verification](Documentation/VERIFICATION.md#four-frontend-regression-checkpoint) for the exact proof scope and remaining limitations.

## Portable verification checkpoint

`formal install` acquires pinned Temurin JRE 21.0.13+9, Lean 4.35.0 and TLC 1.7.4 automatically into a private prefix. `formal package` creates a relocatable folder with all runtime tools, resource bundles and notices. Java and Lean need no separate user installation; a distributed binary needs no Swift toolchain at runtime. Checks are offline and use audited sibling tools exclusively. The current distribution platform is macOS arm64.

`formal check` generates and checks explicit scalar scenarios, or rechecks existing generated artifacts. Runtime byte identity and actual program data are audited before controlled Lean compilation and TLC execution. Reports distinguish finite MODEL_CHECKED/PROVED outcomes, COUNTEREXAMPLE/UNPROVED and UNKNOWN from UNVALIDATED source translation. The Lean proof audit permits only propext, Classical.choice and Quot.sound and records actual dependencies. Bounds, cancellation, malformed scenarios and modified files fail explicitly. Process groups, logs and workspaces have enforced limits.

65 named Swift tests and existing CLI integration pass. The real portable-distribution test passes eight language checks, a wrong-expectation counterexample, a fuel bound, expected checked overflow, arbitrary integer arithmetic, runtime/tool tampering, offline installation, no-clobber, moved prefixes and PATH invocation. Host java/lean/lake/swift/swiftc/curl/zstd are blocked and caller Java/Lean settings are poisoned. Source installation was also exercised with no cached JRE: formal downloaded and installed it itself. Mach-O inspection of 55 executable/library files found no absolute dependency outside macOS system paths. Small successful checks took 5.3–8.1 seconds including full tool inventory hashing on this machine; no general performance guarantee is implied.

This checkpoint does not complete general source semantic preservation, arbitrary temporal properties, full v1, or Actor support. The imported specification remains byte-for-byte unchanged.
