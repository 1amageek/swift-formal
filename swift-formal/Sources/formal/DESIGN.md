# formal

## Purpose and Scope
Command routing and environment diagnostics. Parent: [system/package](../../DESIGN.md). Children: Commands, Environment.

## Responsibilities and Boundaries
No command can certify translations or properties in the bootstrap release.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Package](../../DESIGN.md) | parent | Global truth and scope | Bootstrap composition | Do not promote metadata checks to semantic success |
| [Commands](Commands/DESIGN.md) | child | Commands public contract | Internal responsibility owner | Recheck on contract changes |
| [Environment](Environment/DESIGN.md) | child | Environment public contract | Internal responsibility owner | Recheck on contract changes |

## Architecture
```text
formal -> FormalCore, FormalCompiler, FormalValidation
```

## Contracts and Invariants
Inputs and results are immutable Sendable values. Errors remain explicit. No module stores shared mutable state. Dependencies use public contracts only. No command can certify translations or properties in the bootstrap release.

## Verification and Change Impact
See the corresponding test target linked by the package design and executable integration tests. Recheck the package and direct consumers when changing public data or failure contracts.

Draft translation composes SourceCompiling, both emitters, and the independent actual-output decoder. [Commands](Commands/DESIGN.md) owns publication, draft status, limits, and failure cleanup.
