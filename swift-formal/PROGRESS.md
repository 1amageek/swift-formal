# Implementation progress

The requested completion scope is the entire v1 specification, including Actor support. Current work is incomplete; scalar-library evidence alone does not satisfy the request.

| Phase | Required result | Current evidence |
|---|---|---|
| P0 | Locked inputs, schemas, trust boundary, Skeleton public adapter | Host lock, input records, bundle checks, source and project adapters implemented/tested; certified semantics profile pending |
| P1 | Arithmetic, branches, calls; both backends; independent validation | Scalar SIL -> IR -> both outputs works. SANY, TLC, Lean finite execution, separate Lean decoder and kernel data/step equality pass. Full SIL step relation, runtime audit, verifier orchestration, and complete mutation suite pending |
| P2 | Memory, loops, recursion, enums, exceptions, dependency closure | IR loops/recursion execute and report fuel/stack bounds. Reachable scalar calls are closed. SIL memory/enum/exception lowering pending |
| P3 | Actor and async with both backends and replay | Actual Swift 6.4.1 fixture SIL inspected and structurally parsed; semantic translation/replay not implemented |
| P4 | All CLI operations, support matrix, provenance, acceptance/mutation suite | Operational bootstrap commands only; strict generation/verification commands fail explicitly |

## Verified paths

- Fixed swift-skeleton revision resolves/builds without local overrides.
- Swift contract, bundle containment/tampering, source indexing, parser malformed-input, scalar arithmetic/CFG/calls, and artifact mutation tests pass.
- Real canonical SIL fixtures cover subtraction, wrapping, branch, direct call, memory loops, and Actor accessors/coroutines. Scalar lowering currently rejects memory and Actor operations.
- Four-bit arithmetic exhaustively matches independent mathematical expected results. Fixed 64-bit signed/unsigned overflow endpoints remain distinct.
- Lean 4.35.0 compiles actual emitted files and kernel-checks subtraction, call, branch, and wrapping results. Audited dependencies: propext.
- Separate Lean SIL decoding yields the same scalar program data as emitted Lean; kernel equality and shared-runtime step/reachability correspondence check. Arithmetic mutation is rejected.
- TLA tools 1.7.4 SANY checks actual outputs. TLC completes five scalar 64-bit scenarios (subtract, call, branch, wrap, trap). TLA uses bit sequences to avoid TLC's bounded integer representation.
- None of these establishes the entire source-SIL/reference-semantics relation or the Actor contract. Production semantic coverage remains empty; strict generation is disabled.

## Important remaining proof work

Independent Lean decoding currently normalizes scalar SIL directly into the common runtime's instruction data. Kernel data equality is useful but is not a proof of each SIL opcode's small-step semantics, debug stuttering, and state/observation mapping. A separate SIL reference relation and complete rule evidence are still required before translation can be VALIDATED. The TLA runtime and wrappers also require a completed independent audit contract. The experimental scalar lowering currently represents standard integer/Bool wrappers as aggregates and erases nominal identity; this is explicitly marked incomplete and must be corrected before certification.

## Environment

Swift 6.4.1 release, SDK 27.2, Java 24.0.2. Lean 4.35.0 and TLA tools 1.7.4 are installed under ignored .tools. Lean archive SHA-256 matches the upstream release digest. No system-wide installation, remote publication, or deployment occurred.
