# Environment

## Purpose and Scope
Probe swiftc target information with an invocation-scoped subprocess. Parent: [FormalCLI](../DESIGN.md). No child components.

## Responsibilities and Boundaries
Arguments are arrays. stdout/stderr go to temporary files to avoid pipe deadlock. Timeout, cancellation, output limit, nonzero exit, and invalid JSON are failures. Process cleanup and file deletion are scoped; only the compiler probe is supported, not an arbitrary external checker runner.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [FormalCLI](../DESIGN.md) | parent | Module boundary | Owned implementation | Recheck consumer assumptions |

## Architecture
```text
Caller -> Environment -> explicit value or error
```

## Contracts and Invariants
Arguments are arrays. stdout/stderr go to temporary files to avoid pipe deadlock. Timeout, cancellation, output limit, nonzero exit, and invalid JSON are failures. Process cleanup and file deletion are scoped; only the compiler probe is supported, not an arbitrary external checker runner.

## State, Ownership, and Lifecycle
State belongs to a call; no global mutable storage. Data and temporary resources remain scoped to the invocation.

## Failure, Concurrency, and Constraints
Failure is propagated or converted to a typed diagnostic. Independent calls share no mutable resources. Limits are selected by the caller and must be positive.

## Verification and Change Impact
Behavior owner: [Tests/FormalCLITests/CommandTests.swift](../../../Tests/FormalCLITests/CommandTests.swift). Changes require rechecking the parent and its consuming CLI integration paths. Metadata verification never establishes semantic equivalence.
