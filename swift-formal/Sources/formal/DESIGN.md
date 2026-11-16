# formal

## Purpose and Scope
Executable entry, stdout/stderr delivery, and process exit. Parent: [system/package](../../DESIGN.md). Children: none (composition entry point).

## Responsibilities and Boundaries
All command behavior belongs to FormalCLI. Executable naming is owned by the parent package design.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Package](../../DESIGN.md) | parent | Global truth and scope | Bootstrap composition | Do not promote metadata checks to semantic success |


## Architecture
```text
formal -> FormalCLI
```

## Contracts and Invariants
Inputs and results are immutable Sendable values. Errors remain explicit. No module stores shared mutable state. Dependencies use public contracts only. All command behavior belongs to FormalCLI. Executable naming is owned by the parent package design.

## Verification and Change Impact
See the corresponding test target linked by the package design and executable integration tests. Recheck the package and direct consumers when changing public data or failure contracts.
