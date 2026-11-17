# formal

## Purpose and Scope
Command routing and environment diagnostics. Parent: [system/package](../../DESIGN.md). Children: Commands, Environment, Distribution.

## Responsibilities and Boundaries
General source semantic certification remains unavailable; finite generated-model checks follow the Verification contract.

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
Inputs and results are immutable Sendable values. Errors remain explicit. No module stores shared mutable state. Dependencies use public contracts only. General source semantic certification remains unavailable; finite generated-model checks follow the Verification contract.

## Verification and Change Impact
See the corresponding test target linked by the package design and executable integration tests. Recheck the package and direct consumers when changing public data or failure contracts.

Draft translation composes SourceCompiling, both emitters, and the independent actual-output decoder. [Commands](Commands/DESIGN.md) owns publication, draft status, limits, and failure cleanup.

## Packaged Verification Extension
Child: [Distribution](Distribution/DESIGN.md). Commands can now check finite generated-model outcomes, while general translation certification remains unavailable. Only install/package may acquire pinned dependencies; checks are offline.


## Structured evidence change impact
[Inspection](../FormalValidation/Inspection/DESIGN.md) and [SDK transition](../../Documentation/SDK-TRANSITION.md) define the target structured-output/correspondence/graph contract. Preserve this component's actual semantic and trust invariants. Update direct callers/results/resource audits in the same cutover; do not add legacy-report adapters. User Lean elaboration requires its explicit isolation capability; current trusted generated-model tooling is not evidence of safe arbitrary Lean execution.
