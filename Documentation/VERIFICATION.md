# Verification checkpoint

Date: 2026-11-16. This is a multi-language scalar checkpoint, not v1 completion. The dependency-free package contract in DESIGN.md supersedes the imported specification's declaration-index requirements.

| Check | Evidence | Scope |
|---|---|---|
| Fresh dependency-free build | Build and tests use a new scratch directory | No cached third-party products; SwiftPM graph has no dependencies |
| Swift tests | 55 named tests passed across 8 targets | Contracts, integrity, syntax, scalar IR/lowering, emitted-data mutation |
| CLI integration | Passed | Actual executable: doctor, mismatch, removed-command rejection, tampering, strict unsupported commands, eight draft translations, no-clobber |
| Lean 4.35.0 | Actual generated package builds | Scalar runtime, program, properties |
| Lean finite execution | Four kernel-checked theorems | Subtraction, direct call, branch, wrapping endpoints |
| Lean independent decoding | Kernel data, shared-step, reachability equality | Separate decoder reads original scalar fixture; not a complete SIL step proof |
| Axiom audit | Data equality has no axioms; other checked theorems use only propext, Classical.choice, Quot.sound | Explicit allowlist; no sorryAx or custom axioms |
| Mutation | Arithmetic substitution rejected by kernel equality; output-data/wrapper changes rejected by restricted parser | Does not cover the full required mutation suite |
| Source frontend differential | Eight native compilers/runtimes agree with checked IR observations | Primitive scalar source subset; Rust checks enabled, C/C++ UBSan failure, Go wrapping |
| Source Lean kernel | 39 result theorems and axiom audit | All eight profiles, overflow outcomes and 40-digit inputs |
| Four frontend regressions | 19 positive results agree in native/IR/TLA+/Lean; 14 actual CLI rejection cases pass | Updates, Go constants/context conversion, AST depth, and C/C++ declaration visibility |
| Source TLC | 40 finite scenarios; DOT graph confirms expected terminal reachability | All eight profiles; 64-bit and arbitrary integers |
| SANY/TLC 1.7.4 | Actual TLA files parse; five scenarios complete | 64-bit subtraction, call, branch, wrap, overflow trap |

## Reproduce

```sh
python3 Tools/prepare-tools.py
python3 Tools/run-with-timeout.py --seconds 180 -- swift test
python3 Tools/run-with-timeout.py --seconds 90 -- python3 Tools/integration.py
python3 Tools/run-with-timeout.py --seconds 480 -- python3 Tools/verify-backends.py
python3 Tools/run-with-timeout.py --seconds 900 -- python3 Tools/verify-frontends.py
python3 Tools/run-with-timeout.py --seconds 900 -- python3 Tools/verify-regressions.py
```

Tool preparation is explicit and project-local. The external checks never install tools. Use FORMAL_TOOLS_ROOT when the project-local tools are stored in a shared workspace cache; see [Support](SUPPORT.md). Java 24.0.2, Rust 1.92.0 (2021 edition, checks enabled), Apple clang 21.0.0 (C11/C++20), Go 1.26.5, Node 24.19.0, TypeScript 5.9.3, and Python 3.12.8 were used. TLC uses a 16 MB Java stack for recursive bit arithmetic. The package host was Swift 6.4.1 release on arm64 macOS with SDK 27.2.

## Inputs

| Artifact | SHA-256 |
|---|---|
| Copied specification | 8540ef723ed78bcf317317f3fcd740a976b3f149059635992f039af3fc3c11f5 |
| Core canonical SIL | 47fc4b050cdeaffc0625faef5498666d196ce36495d3a96fa571ee71c03e289e |
| Inventory canonical SIL | 2e073ba62b52d6e4d892dbd8b152af2fa86ab2f37729a8000803e85bcc81ba19 |

The copied specification is byte-identical to the supplied document. Fixtures were emitted by the installed fixed Swift compiler with `-Onone -emit-sil`.

## Unverified requirements

Strict capture/generate/validate/coverage/replay, complete provenance/publication, full SIL reference semantics and state/stuttering correspondence, nominal wrapper identity, memory/inout, enum/throw, Actor/executor/coroutine/task models, general temporal-property scenario validation, and original-SIL counterexample replay remain unfinished. Actor SIL has been structurally parsed only. See [PROGRESS.md](../PROGRESS.md); no production semantic profile is certified.

## Four frontend regression checkpoint

The original decrement counterexamples execute natively with result 8 and are now rejected by the restricted profile, rather than translated to result 9. Spaced unary-minus counterparts agree across native execution, IR, TLA+, and Lean. Go's original untyped-constant comparison now returns false across all four paths. Constant cancellation, unsigned contextual conversion, multiplication, negative constants, a precision-boundary constant, and typed wrapping are also checked. Unrepresentable contextual conversions are rejected by both native Go and the frontend.

The original 12,128-byte JavaScript source executes natively but exceeds the profile AST limit; the actual CLI now returns SOURCE_PARSE_FAILED and creates no output. An at-limit, 128-node-deep nested-chain counterpart matches across all four paths. Expression lowering, type hints, and call detection use explicit work stacks. Focused tests exercise binary/unary/call depth boundaries, near-limit Go constants, repeated Rust/Python unary minus, and nested-call argument order.

C/C++ forward-call counterexamples fail native compilation and frontend conversion. Earlier definitions and self-recursion match across all four paths. The common IR and backend runtimes were not modified. Existing eight-language native/IR/Lean/TLC checks and CLI integration pass after the frontend corrections. Independent semantic certification and Actor support remain outside this checkpoint.

## Portable verification checkpoint

See [DISTRIBUTION.md](DISTRIBUTION.md) for installation, scenario and proof scope.
65 named Swift tests and existing CLI integration pass. The release distribution
passes `Tools/verify-distribution.py`: eight source profiles, both actual verifiers,
wrong expectation, UNKNOWN fuel exhaustion, expected overflow, BigInt, tampering,
offline installation, relocation and PATH invocation with blocked host tools and
poisoned Java/Lean environment. The source installer was separately run with a
cache missing Java; it acquired the pinned JRE automatically. Checks took
5.3–8.1 seconds for the successful small scenarios on the current host. No native
source execution is performed by end-user checking. The earlier native/IR/TLA/Lean
regression evidence remains applicable because frontend and runtime semantics
were not changed.

```sh
python3 Tools/run-with-timeout.py --seconds 900 python3 Tools/verify-distribution.py --distribution /absolute/path/to/Formal-macos-arm64
```
