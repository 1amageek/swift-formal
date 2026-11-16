# FormalCore

## Purpose and Scope
Immutable input contracts, stable diagnostics, deterministic JSON, and bundle integrity. Parent: [system/package](../../DESIGN.md). Children: Contracts, Bundle.

## Responsibilities and Boundaries
No SIL parsing, interpretation, or semantic validation.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Package](../../DESIGN.md) | parent | Global truth and scope | Bootstrap composition | Do not promote metadata checks to semantic success |
| [Contracts](Contracts/DESIGN.md) | child | Contracts public contract | Internal responsibility owner | Recheck on contract changes |
| [Bundle](Bundle/DESIGN.md) | child | Bundle public contract | Internal responsibility owner | Recheck on contract changes |

## Architecture
```text
FormalCore -> Foundation, CryptoKit
```

## Contracts and Invariants
Inputs and results are immutable Sendable values. Errors remain explicit. No module stores shared mutable state. Dependencies use public contracts only. No SIL parsing, interpretation, or semantic validation.

## Verification and Change Impact
See the corresponding test target linked by the package design and executable integration tests. Recheck the package and direct consumers when changing public data or failure contracts.
