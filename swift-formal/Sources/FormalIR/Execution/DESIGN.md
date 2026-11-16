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

## Mathematical Integer Execution
The [Program](../Program/DESIGN.md) contract owns integer representation and operations. This runner counts decimal digits as value-budget units and enforces caller-selected maximumIntegerDigits (default 4096) before arithmetic allocation; prospective operands above half the smaller digit/value capacity return boundExceeded. This conservative budget is operational, not a source exception. Integer addition/subtraction use linear digit work and multiplication uses quadratic digit work. Immutable storage is retained through Swift value semantics; canonical serialization is an output-boundary copy. Formal runtimes do not inherit runner bounds. Panic and undefinedBehavior are failed outcomes, separate from traps, returns, and bounds.
