# Bundle

## Purpose and Scope
Read-only bundle inspection with a caller-owned ToolchainLock. Parent: [FormalCore](../DESIGN.md). No child components.

## Responsibilities and Boundaries
Check required files, bounded reads, schema, context, entry points, unique module IDs and paths, exact lock equality, safe relative paths after symlink resolution, and SHA-256. SIL is opaque bytes; success establishes integrity only. File mutation races are outside this inspection contract; future generation must consume its own immutable snapshot.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [FormalCore](../DESIGN.md) | parent | Module boundary | Owned implementation | Recheck consumer assumptions |

## Architecture
```text
Caller -> Bundle -> explicit value or error
```

## Contracts and Invariants
Check required files, bounded reads, schema, context, entry points, unique module IDs and paths, exact lock equality, safe relative paths after symlink resolution, and SHA-256. SIL is opaque bytes; success establishes integrity only. File mutation races are outside this inspection contract; future generation must consume its own immutable snapshot.

## State, Ownership, and Lifecycle
State belongs to a call; no global mutable storage. Data and temporary resources remain scoped to the invocation.

## Failure, Concurrency, and Constraints
Failure is propagated or converted to a typed diagnostic. Independent calls share no mutable resources. Limits are selected by the caller and must be positive.

## Verification and Change Impact
Behavior owner: [Tests/FormalCoreTests/BundleInspectorTests.swift](../../../Tests/FormalCoreTests/BundleInspectorTests.swift). Changes require rechecking the parent and its consuming CLI integration paths. Metadata verification never establishes semantic equivalence.
