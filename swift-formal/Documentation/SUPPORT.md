# Support

| Layer | Current support |
|---|---|
| Host package | macOS; Swift 6.4.1 build and runtime tests |
| Input contracts | JSON schema version 1, canonical SIL metadata, explicit context |
| Bundle inspection | Bounded regular files, relative paths, symlink containment, SHA-256 |
| Source metadata | Swift declarations through fixed swift-skeleton public APIs |
| SIL parser | Structural canonical parsing, including actual Actor fixture syntax; no semantic support implied |
| SIL lowering | Scalar thin functions, fixed-width bits/wrappers, tuples, branch, direct calls, trap |
| TLA+ / Lean emitters | Scalar library emitters; actual files pass SANY and Lean checks |
| Independent translation validator | Restricted program-data reparsing and separate Lean decoder/data equality; full semantic relation pending |
| Actor / async semantics | Not implemented |
| WASM / Embedded | Not a supported host target |

[Support matrix](../Semantics/Profiles/support-matrix.json) intentionally contains no supported semantic entries. Empty coverage does not mean 100% support.

Formal tool preparation is explicit: `python3 Tools/prepare-tools.py`. Versions and checksums are pinned in [toolchain-artifacts.lock.json](../Tools/toolchain-artifacts.lock.json). Generation/checking never downloads tools.
