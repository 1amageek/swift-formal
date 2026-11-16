# Semantics status and ownership

[The package design](../DESIGN.md) records current user overrides to the historical [specification](SPEC.md). No executable reference semantics or certified transformation rule exists yet.

| Representation | Authority | Completion condition |
|---|---|---|
| Original SIL | Exact compiler profile and input bytes | Independent decoding and verifier checks |
| FormalIR | Typed small-step semantics | Explicit frame, memory, error, and scheduler behavior |
| TLA+ | Limited generated syntax and runtime semantics | Reparse actual files and validate updates/enabledness |
| Lean | Deep embedding and independent reference checker | Kernel-checked correspondence and axiom audit |

A future FormalIR schema must encode module-qualified mangled IDs, types including fixed bit width and signedness, CFG and block arguments, instruction origins and rule IDs, and explicit unbounded call/memory state. Terminal return, throw, trap, undefined-behavior detection, and artificial bounds are distinct outcomes. Actor executor ownership survives synchronous calls; suspension and resumption preserve locals. The current scalar IR implements individual-instruction execution, fixed-width arithmetic, branch bindings, direct-call frames, trap, panic, undefined behavior, arbitrary precision integers, return, and explicit runner bounds. Memory, enum/exception, and Actor state remain required future work.

Fixture Swift code is compiled with the exact installed Swift 6.4.1 toolchain during investigation. Observed SIL includes arithmetic overflow builtins, SSA branch arguments, memory/access scopes, dynamic actor accessor dispatch, and coroutine tokens. Scalar fixtures now generate both formats and pass external syntax/type/finite-execution checks. A separate Lean decoder checks normalized scalar program data and common-runtime step equality; a complete independent SIL step relation and checked normalization/stuttering rules remain pending.

Source frontend profiles are experimental closed subsets; their authority is [Frontends/DESIGN.md](../Sources/FormalCompiler/Frontends/DESIGN.md). They do not establish whole-language equivalence.
