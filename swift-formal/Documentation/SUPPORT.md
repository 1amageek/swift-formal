# Support

| Layer | Current support |
|---|---|
| External SwiftPM dependencies | None |
| Host package | macOS; Swift 6.4.1 build and runtime tests |
| Input contracts | JSON schema version 1, canonical SIL metadata, explicit context |
| Bundle inspection | Bounded regular files, relative paths, symlink containment, SHA-256 |
| SIL parser | Structural canonical parsing, including actual Actor fixture syntax; no semantic support implied |
| SIL lowering | Scalar thin functions, fixed-width bits/wrappers, tuples, branch, direct calls, trap |
| Source frontends | Eight scalar-v1 profiles; [grammar and assumptions](../Sources/FormalCompiler/Frontends/DESIGN.md); experimental draft translation |
| TLA+ / Lean emitters | Scalar library emitters; actual files pass SANY and Lean checks |
| Independent translation validator | Restricted program-data reparsing and separate Lean decoder/data equality; full semantic relation pending |
| Actor / async semantics | Not implemented |
| WASM / Embedded | Not a supported host target |

[Support matrix](../Semantics/Profiles/support-matrix.json) intentionally contains no supported semantic entries. Empty coverage does not mean 100% support.

Formal tool preparation is explicit: `python3 Tools/prepare-tools.py`. Versions and checksums are pinned in [toolchain-artifacts.lock.json](../Tools/toolchain-artifacts.lock.json). Generation/checking never downloads tools.

Formal tools may live in a shared workspace cache selected explicitly with `FORMAL_TOOLS_ROOT=/absolute/path`. Both preparation and verification scripts use the same setting; default is package-local `.tools`. Frontend verification additionally requires project-local TypeScript 5.9.3 at `$FORMAL_TOOLS_ROOT/typescript/node_modules/typescript/bin/tsc`. Prepare it with `npm install --prefix "$FORMAL_TOOLS_ROOT/typescript" --ignore-scripts --no-audit --no-fund typescript@5.9.3`; native compilers/runtimes must already be available. No tool installation is performed by translation or verification. TLC tests use a 16 MB Java stack for recursive bit-vector arithmetic.
