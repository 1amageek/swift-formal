# Support

| Layer | Current support |
|---|---|
| External SwiftPM dependencies | None |
| Host package | macOS; Swift 6.4.1 build and runtime tests |
| Input contracts | JSON schema version 1, canonical SIL metadata, explicit context |
| Bundle inspection | Bounded regular files, relative paths, symlink containment, SHA-256 |
| SIL parser | Structural canonical parsing, including actual Actor fixture syntax; no semantic support implied |
| SIL lowering | Scalar thin functions, fixed-width bits/wrappers, tuples, branch, direct calls, trap |
| Source frontends | Ten scalar-v1 profiles (including Java and Bun); [grammar and assumptions](../Sources/FormalCompiler/Frontends/DESIGN.md); experimental draft translation |
| TLA+ / Lean emitters | Scalar library emitters; actual files pass SANY and Lean checks |
| Independent translation validator | Restricted program-data reparsing and separate Lean decoder/data equality; full semantic relation pending |
| Universal model properties | Scalar pre/postconditions over every typed input, kernel-checked Lean theorems; [scope and limits](PROPERTIES.md) |
| TLA+ universal specification | All typed initial inputs; SANY checked; exhaustive universal TLC verification is not claimed |
| Actor / async semantics | Not implemented |
| WASM / Embedded | Not a supported host target |

[Support matrix](../Semantics/Profiles/support-matrix.json) intentionally contains no supported semantic entries. Empty coverage does not mean 100% support.

Formal tool preparation is explicit: `python3 Tools/prepare-tools.py`. Versions and checksums are pinned in [toolchain-artifacts.lock.json](../Tools/toolchain-artifacts.lock.json). Generation/checking never downloads tools.

Formal tools may live in a shared workspace cache selected explicitly with `FORMAL_TOOLS_ROOT=/absolute/path`. Both preparation and verification scripts use the same setting; default is package-local `.tools`. Frontend verification additionally requires project-local TypeScript 5.9.3 at `$FORMAL_TOOLS_ROOT/typescript/node_modules/typescript/bin/tsc`. Prepare it with `npm install --prefix "$FORMAL_TOOLS_ROOT/typescript" --ignore-scripts --no-audit --no-fund typescript@5.9.3`; native compilers/runtimes must already be available. No tool installation is performed by translation or verification. TLC tests use a 16 MB Java stack for recursive bit-vector arithmetic.

Source profile boundaries and Go constant precision are owned by [Frontends/DESIGN.md](../Sources/FormalCompiler/Frontends/DESIGN.md). `Tools/verify-regressions.py` checks the four reported frontend counterexamples and their accepted counterparts through the actual CLI, native tools, IR observations, TLA+, and Lean. Unsupported updates, over-depth trees, and C/C++ undeclared calls produce diagnostics and no generated artifacts.

## End-user distribution
[Portable installation](DISTRIBUTION.md) provides Java, TLC and Lean automatically for macOS arm64. The native compiler and TypeScript setup above is required only for developer differential tests that execute original languages; end-user model checking does not execute original source.


Java accepts one class of static `int`/`long`/`boolean` methods, with 32/64-bit
wrapping and explicit literal widths. Bun accepts the scalar JS/TS BigInt and
Boolean surface. See [profile contracts](../Sources/FormalCompiler/Frontends/DESIGN.md#java-and-bun-profiles).
Neither javac nor Bun is required by end-user translation/model verification;
developer native differential checks require those source tools separately.
