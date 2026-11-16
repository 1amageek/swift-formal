# FormalCompiler

## Purpose and Scope
Own source-language frontends, checked lowering, and deterministic TLA+/Lean emission. Parent: [package](../../DESIGN.md). Children: [SIL](SIL/DESIGN.md), [Lowering](Lowering/DESIGN.md), [TLA](TLA/DESIGN.md), [Lean](Lean/DESIGN.md), and source frontends when introduced.

## Responsibilities and Boundaries
Every language frontend must produce the same language-independent FormalIR. Language semantics and supported grammar belong to versioned frontend profiles. Runtime tools and source names must not supply guessed meaning. Independent validation remains outside this module.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Package](../../DESIGN.md) | parent | Composition and support policy | Compiler owner | No external SwiftPM dependencies |
| [FormalIR](../FormalIR/DESIGN.md) | depends on | Typed program and execution model | Shared backend input | Integer and failure meanings must be explicit |
| [FormalValidation](../FormalValidation/DESIGN.md) | coordinates with | Actual-output decoding | Independent inspection | Must not depend on this generator |

## Architecture
```text
Swift SIL / language source -> frontend -> FormalIR -> TLA+ / Lean
```

## Contracts and Invariants
Source frontend expansion is planned around scalar functions, arithmetic, conditional returns, immutable locals, and direct calls. Unsupported source constructs fail with source positions. Exact signed/unsigned overflow, panic, undefined behavior, integer domains, and input-domain assumptions remain explicit. A frontend must not report translation validation from its own output.

## Verification and Change Impact
Frontend tests own native/reference comparisons and rejection behavior. Both emitted languages must be checked with their actual tools. Consolidation preserves existing output bytes. Source-language expansion requires independent validation work before production semantic certification.
