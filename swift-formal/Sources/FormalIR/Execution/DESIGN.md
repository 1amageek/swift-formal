# Execution

## Purpose and Scope
Fixed-width arithmetic and a bounded small-step reference runner for differential tests. Parent: [FormalIR](../DESIGN.md). No children.

## Responsibilities and Boundaries
Own this contract only. No SIL decoding or backend formatting. No shared mutable state.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [FormalIR](../DESIGN.md) | parent | Common semantics | Backend-independent model | Recheck all semantic consumers |

## Architecture
```text
Validated input -> Execution -> explicit result or typed failure
```

## Contracts and Invariants
Widths are 1...64 in the initial executable slice. Literals are bit patterns, not host Int values. Arithmetic wraps at the declared width, reports signed/unsigned overflow separately, and comparisons return one bit. Program counters point to individual instructions. Calls preserve caller SSA state; block assignment is simultaneous. Future memory/Actor operations require new explicit state and rules.

## State, Ownership, and Lifecycle
Program values are immutable Sendable records. Execution state belongs to a runner invocation. No raw pointers, actor-owned global state, or target-specific synchronization branches exist.

## Failure, Concurrency, and Constraints
Malformed programs fail validation. The runner enforces caller-selected fuel, stack, and value budgets and returns BOUND_EXCEEDED rather than success. A single task is modeled in this initial slice; Actor support remains pending.

## Verification and Change Impact
[Tests](../../../Tests/FormalIRTests) own behavioral evidence. Recheck parent, lowering, both emitters, and validator whenever instruction or state meaning changes.
