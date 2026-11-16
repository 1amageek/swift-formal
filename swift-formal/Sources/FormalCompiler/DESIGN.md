# FormalCompiler

## Purpose and Scope
Own source-language frontends, checked lowering, and deterministic TLA+/Lean emission. Parent: [package](../../DESIGN.md). Children: [SIL](SIL/DESIGN.md), [Lowering](Lowering/DESIGN.md), [TLA](TLA/DESIGN.md), [Lean](Lean/DESIGN.md), [Frontends](Frontends/DESIGN.md).

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
[Frontends](Frontends/DESIGN.md) owns accepted source grammar, integer and failure semantics, limits, and assumptions. A frontend cannot certify its own translation. Compiler components use FormalIR contracts; independent validation remains a separate Swift module.

## Verification and Change Impact
Frontend tests own native/reference comparisons and rejection behavior. Both emitted languages must be checked with their actual tools. The consolidation-only checkpoint preserved existing output bytes; subsequent explicit semantic extensions change runtime artifacts. Source-language expansion requires independent validation work before production semantic certification.
