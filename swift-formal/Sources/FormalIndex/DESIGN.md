# FormalIndex

## Purpose and Scope
Optional source declarations and trusted SwiftPM target metadata using fixed swift-skeleton public APIs. Parent: [system/package](../../DESIGN.md). Children: SourceIndex, ProjectMetadata.

## Responsibilities and Boundaries
Never infer behavior, resolve SIL calls, or assign mangled-symbol identity from source names.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Package](../../DESIGN.md) | parent | Global truth and scope | Bootstrap composition | Do not promote metadata checks to semantic success |
| [SourceIndex](SourceIndex/DESIGN.md) | child | SourceIndex public contract | Internal responsibility owner | Recheck on contract changes |
| [ProjectMetadata](ProjectMetadata/DESIGN.md) | child | ProjectMetadata public contract | Internal responsibility owner | Recheck on contract changes |

## Architecture
```text
FormalIndex -> FormalCore, SkeletonIndexCore, SkeletonSwiftParser, SkeletonSwiftPMProjectSupport
```

## Contracts and Invariants
Inputs and results are immutable Sendable values. Errors remain explicit. No module stores shared mutable state. Dependencies use public contracts only. Never infer behavior, resolve SIL calls, or assign mangled-symbol identity from source names.

## Verification and Change Impact
See the corresponding test target linked by the package design and executable integration tests. Recheck the package and direct consumers when changing public data or failure contracts.
