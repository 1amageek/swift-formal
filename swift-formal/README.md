# swift-formal

The CLI command is `formal`; the package is named `swift-formal`.

A Swift package under development for deterministic SIL → TLA+ and Lean translation through a shared FormalIR. The requested v1 scope is defined in [SPEC.md](Documentation/SPEC.md); implementation progress is tracked in [PROGRESS.md](PROGRESS.md).

**The current package is a bootstrap, not the completed compiler.** It provides input contracts, SHA-256 bundle inspection, optional Swift declaration indexing, compiler identity diagnostics, a structural SIL parser, scalar lowering/IR execution, and TLA+/Lean library emitters. Scalar fixture outputs pass SANY, TLC, Lean finite proofs, and independent Lean decoding/data-correspondence checks. Strict CLI generation, complete SIL semantic preservation, memory/exception coverage, and Actor translation remain unfinished.

```text
Current: SIL -> scalar lowering -> FormalIR -> TLA+ / Lean
                    |                           |
               Swift runner          restricted artifact reparsing
Original SIL -> independent Lean decoder -> data/step equality checks
Pending: complete reference-SIL semantics, strict orchestration, memory, exceptions, Actor
```

Requires macOS 13 or later and Swift tools 6.2 or later to build. The currently tested compiler is exactly Swift 6.4.1 with macOS SDK 27.2; [toolchain.lock.json](toolchain.lock.json) records the host identity, not a certified SIL semantics profile.

```sh
swift build
swift run formal --help
swift run formal doctor --toolchain-lock ./toolchain.lock.json
swift run formal index --source ./Fixtures/Swift/Inventory.swift
python3 Tools/run-with-timeout.py --seconds 180 -- swift test
python3 Tools/run-with-timeout.py --seconds 90 -- python3 Tools/integration.py
python3 Tools/prepare-tools.py
python3 Tools/run-with-timeout.py --seconds 480 -- python3 Tools/verify-backends.py
```

[CLI](Documentation/CLI.md) · [Architecture](DESIGN.md) · [Trust](Documentation/TRUST.md) · [Support](Documentation/SUPPORT.md)
