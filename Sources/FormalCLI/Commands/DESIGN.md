# Commands

## Purpose and Scope
Parse commands, load bounded files, and map typed failures to documented exit codes. Parent: [FormalCLI](../DESIGN.md). No child components.

## Responsibilities and Boundaries
Implemented commands: help, version, doctor, inspect-bundle, index. Future capture/generate/validate/check/coverage/replay fail with UNSUPPORTED_OPERATION and exit 3. No output directory is written. Bad arguments use exit 2.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [FormalCLI](../DESIGN.md) | parent | Module boundary | Owned implementation | Recheck consumer assumptions |

## Architecture
```text
Caller -> Commands -> explicit value or error
```

## Contracts and Invariants
Implemented commands: help, version, doctor, inspect-bundle, index. Future capture/generate/validate/check/coverage/replay fail with UNSUPPORTED_OPERATION and exit 3. No output directory is written. Bad arguments use exit 2.

## State, Ownership, and Lifecycle
State belongs to a call; no global mutable storage. Data and temporary resources remain scoped to the invocation.

## Failure, Concurrency, and Constraints
Failure is propagated or converted to a typed diagnostic. Independent calls share no mutable resources. Limits are selected by the caller and must be positive.

## Verification and Change Impact
Behavior owner: [Tests/FormalCLITests/CommandTests.swift](../../../Tests/FormalCLITests/CommandTests.swift). Changes require rechecking the parent and its consuming CLI integration paths. Metadata verification never establishes semantic equivalence.
