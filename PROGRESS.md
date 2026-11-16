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


## Universal property checkpoint

`formal check --properties` accepts typed `requires`/`ensures` expressions and
kernel-checks a theorem for every input satisfying the precondition. The theorem
executes the actual audited generated program. Mathematical integers have no
finite input bound; fixed-width inputs include every bit pattern. Normal return
within an acyclic control-flow/call bound is part of the theorem. Candidate
search can establish only checked counterexamples, never validity.

73 named Swift tests and the release build pass. Real bundled tools prove 17
positive properties across all eight profiles, preconditions, branches, direct
calls, overflow-safe signed arithmetic, unsigned wrapping and Booleans. Signed
boundary and huge-integer counterexamples are checked by IR, Lean and TLC.
Recursion reports `UNKNOWN`; a failed proof with no searched witness reports
`UNPROVED`. Changing actual generated program data invalidates the unchanged
theorem. Rechecking preserves previous runs and records mixed results separately.
See [verification evidence](Documentation/VERIFICATION.md#universal-property-checkpoint).

Universal TLA+ specifications are generated and parsed with SANY. Lean owns the
all-input proof; no universal TLC enumeration or completed source semantic
certification is claimed. The original v1/Actor work remains incomplete.


The 0.3.0 release build's portable package passes offline installation and moved
prefix checking with host Java/Lean/Swift tools blocked. Quantified addition is
proved through that installed binary; existing finite checks still pass.
Packaging from a symlinked toolchain now copies the verified real tree, and
inventory hashing keeps per-chunk buffers bounded. No release tag was created.


## Java and Bun source profiles

Java static scalar methods and Bun JS/TS functions now feed the common IR.
Java int32/int64 arithmetic wraps; literal widths are preserved and implicit
width conversions are rejected. Bun supports BigInt/Boolean with explicit
assumptions for unannotated JS parameters/results. Number and runtime APIs remain
outside the source profile. No production target, dependency or backend runtime
was added.

79 Swift tests, ten-profile CLI conversion and the release build pass. The new
native differential suite checks 18 observations across Java/Bun, IR, Lean and
TLC; six universal properties and two natively reproduced counterexamples pass.
The original eight source fixtures retain byte-identical output. Portable
installation and moved-prefix checks pass with host javac/Bun blocked, and
Java/Bun universal checks use only bundled tools under a missing host PATH.
See [verification evidence](Documentation/VERIFICATION.md#java-and-bun-checkpoint).
The project still reports UNVALIDATED source translation and remains incomplete
for the original v1/Actor scope.


## IEEE Number support

2026-11-17: Version 0.4.0 adds Number to JavaScript, TypeScript and Bun scalar-v2.
This supersedes the BigInt-only restriction in the preceding checkpoint.
Dedicated binary64 operations preserve rounding, NaN, infinities, subnormals and
signed zero through Swift IR, exact TLA bit arithmetic and Lean's logical Float
model. Inference handles Number/BigInt/Boolean; unresolved numeric types default
to Number and may select BigInt explicitly. Number scenario/property views,
short-circuit logical operations and documented pure numeric builtins are
available. No production target or external SwiftPM dependency was added.

94 Swift tests, the release build and ten-language CLI integration pass. The
Number suite checks 400 native/IR/Lean/TLC vectors and 35 source observations,
proves five all-input properties, confirms four counterexamples against native
execution and rejects a mutated actual generated program. Existing universal,
Java/Bun and frontend regression suites pass. Portable offline installation and
relocation checks include Number rounding and a quantified Number sum with
host verification tools blocked. Private Java temporary directories and a
workspace cleanup regression protect concurrent checks.

See [Number evidence](Documentation/VERIFICATION.md#number-checkpoint) and the
[Number guide](Documentation/NUMBERS.md). Source translation remains
UNVALIDATED, automatic proof search remains bounded and incomplete, and the
original full v1/Actor scope is still unfinished.
