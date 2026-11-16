# Verification checkpoint

Date: 2026-11-16. This is a scalar-library checkpoint, not v1 completion. The dependency-free package contract in DESIGN.md supersedes the imported specification's declaration-index requirements.

| Check | Evidence | Scope |
|---|---|---|
| Fresh dependency-free build | Build and tests use a new scratch directory | No cached third-party products; SwiftPM graph has no dependencies |
| Swift tests | 33 named tests passed across 7 targets | Contracts, integrity, syntax, scalar IR/lowering, emitted-data mutation |
| CLI integration | Passed | Actual executable: doctor without index-tool metadata, mismatch, removed-command rejection, tampering, unsupported commands |
| Lean 4.35.0 | Actual generated package builds | Scalar runtime, program, properties |
| Lean finite execution | Four kernel-checked theorems | Subtraction, direct call, branch, wrapping endpoints |
| Lean independent decoding | Kernel data, shared-step, reachability equality | Separate decoder reads original scalar fixture; not a complete SIL step proof |
| Axiom audit | Data equality has no axioms; other checked theorems use propext | Explicit allowlist; no sorryAx or custom axioms |
| Mutation | Arithmetic substitution rejected by kernel equality; output-data/wrapper changes rejected by restricted parser | Does not cover the full required mutation suite |
| SANY/TLC 1.7.4 | Actual TLA files parse; five scenarios complete | 64-bit subtraction, call, branch, wrap, overflow trap |

## Reproduce

```sh
python3 Tools/prepare-tools.py
python3 Tools/run-with-timeout.py --seconds 180 -- swift test
python3 Tools/run-with-timeout.py --seconds 90 -- python3 Tools/integration.py
python3 Tools/run-with-timeout.py --seconds 480 -- python3 Tools/verify-backends.py
```

Tool preparation is explicit and project-local. The external checks never install tools. Java 24.0.2 was used. The package host was Swift 6.4.1 release on arm64 macOS with SDK 27.2.

## Inputs

| Artifact | SHA-256 |
|---|---|
| Copied specification | 8540ef723ed78bcf317317f3fcd740a976b3f149059635992f039af3fc3c11f5 |
| Core canonical SIL | 47fc4b050cdeaffc0625faef5498666d196ce36495d3a96fa571ee71c03e289e |
| Inventory canonical SIL | 2e073ba62b52d6e4d892dbd8b152af2fa86ab2f37729a8000803e85bcc81ba19 |

The copied specification is byte-identical to the supplied document. Fixtures were emitted by the installed fixed Swift compiler with `-Onone -emit-sil`.

## Unverified requirements

Strict capture/generate/validate/check/coverage/replay, complete provenance/publication, full SIL reference semantics and state/stuttering correspondence, nominal wrapper identity, memory/inout, enum/throw, Actor/executor/coroutine/task models, scenario validation, and original-SIL counterexample replay remain unfinished. Actor SIL has been structurally parsed only. See [PROGRESS.md](../PROGRESS.md); no production semantic profile is certified.
