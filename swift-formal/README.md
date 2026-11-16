# swift-formal

The CLI command is `formal`; the package is named `swift-formal`. It has no external SwiftPM dependencies.

A dependency-free Swift package for source/SIL → common IR → TLA+ and Lean translation. Five production modules separate core contracts, IR, compilation, independent inspection, and the `formal` executable. The requested v1 scope is defined in [SPEC.md](Documentation/SPEC.md); implementation progress is tracked in [PROGRESS.md](PROGRESS.md).

**The current package is experimental, not the completed v1 compiler.** It provides input contracts, SHA-256 bundle inspection, compiler identity diagnostics, a structural SIL parser, scalar lowering/IR execution, and TLA+/Lean library emitters. Scalar fixture outputs pass SANY, TLC, Lean finite proofs, and independent Lean decoding/data-correspondence checks. Eight scalar source frontends and draft CLI translation are implemented. Strict semantic certification, complete SIL semantic preservation, memory/exception coverage, and Actor translation remain unfinished.

```text
Swift / Rust / C / C++ / Go / TypeScript / JavaScript / Python
                            -> FormalCompiler -> FormalIR -> TLA+ / Lean
formal -> FormalValidation (independent actual-output data inspection)
Canonical Swift SIL -> scalar lowering -> same FormalIR
```

```sh
swift run formal profiles
swift run formal translate --language rust --source Fixtures/Sources/rust.source --output DraftRust --draft-unvalidated
```

Translation emits both backends, IR JSON, source bytes, and a profile/hash/assumptions report. Output is **DRAFT_UNVALIDATED**. The accepted scalar grammar and limitations are defined in [Frontends/DESIGN.md](Sources/FormalCompiler/Frontends/DESIGN.md). Python `int` and JS/TS `BigInt` preserve arbitrary precision; JS `Number`, general projects, classes, mutation, memory, exceptions, and async/Actors are outside the source profile.


Requires macOS 13 or later and Swift tools 6.2 or later to build. The currently tested compiler is exactly Swift 6.4.1 with macOS SDK 27.2; [toolchain.lock.json](toolchain.lock.json) records the host identity, not a certified SIL semantics profile.

```sh
swift build
swift run formal --help
swift run formal doctor --toolchain-lock ./toolchain.lock.json
python3 Tools/run-with-timeout.py --seconds 180 -- swift test
python3 Tools/run-with-timeout.py --seconds 90 -- python3 Tools/integration.py
python3 Tools/prepare-tools.py
python3 Tools/run-with-timeout.py --seconds 480 -- python3 Tools/verify-backends.py
python3 Tools/run-with-timeout.py --seconds 900 -- python3 Tools/verify-frontends.py
```

[CLI](Documentation/CLI.md) · [Architecture](DESIGN.md) · [Trust](Documentation/TRUST.md) · [Support](Documentation/SUPPORT.md)
