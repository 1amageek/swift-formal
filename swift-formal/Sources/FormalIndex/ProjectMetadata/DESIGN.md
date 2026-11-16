# ProjectMetadata

## Purpose and Scope
Resolve trusted SwiftPM project structure through SwiftPMProjectStructureResolver. Parent: [FormalIndex](../DESIGN.md). No child components.

## Responsibilities and Boundaries
Require explicit trustedProject input before manifest evaluation. Return nil for no package, propagate upstream errors, and report target names and source roots only. This is not a capture build plan. The upstream timeout and cleanup contract is inherited, not a sandbox guarantee.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [FormalIndex](../DESIGN.md) | parent | Module boundary | Owned implementation | Recheck consumer assumptions |

## Architecture
```text
Caller -> ProjectMetadata -> explicit value or error
```

## Contracts and Invariants
Require explicit trustedProject input before manifest evaluation. Return nil for no package, propagate upstream errors, and report target names and source roots only. This is not a capture build plan. The upstream timeout and cleanup contract is inherited, not a sandbox guarantee.

## State, Ownership, and Lifecycle
State belongs to a call; no global mutable storage. Data and temporary resources remain scoped to the invocation.

## Failure, Concurrency, and Constraints
Failure is propagated or converted to a typed diagnostic. Independent calls share no mutable resources. Limits are selected by the caller and must be positive.

## Verification and Change Impact
Behavior owner: [Tests/FormalIndexTests/SourceIndexerTests.swift](../../../Tests/FormalIndexTests/SourceIndexerTests.swift). Changes require rechecking the parent and its consuming CLI integration paths. Metadata verification never establishes semantic equivalence.
