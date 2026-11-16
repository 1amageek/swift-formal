# Program

## Purpose and Scope
Immutable typed functions, blocks, SSA IDs, origins, and opcode-specific operands. Parent: [FormalIR](../DESIGN.md). No children.

## Responsibilities and Boundaries
Own this contract only. No SIL decoding or backend formatting. No shared mutable state.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [FormalIR](../DESIGN.md) | parent | Common semantics | Backend-independent model | Recheck all semantic consumers |

## Architecture
```text
Validated input -> Program -> explicit result or typed failure
```

## Contracts and Invariants
Widths are 1...64 in the initial executable slice. Literals are bit patterns, not host Int values. Arithmetic wraps at the declared width, reports signed/unsigned overflow separately, and comparisons return one bit. Program counters point to individual instructions. Calls preserve caller SSA state; block assignment is simultaneous. Future memory/Actor operations require new explicit state and rules.

## State, Ownership, and Lifecycle
Program values are immutable Sendable records. Execution state belongs to a runner invocation. No raw pointers, actor-owned global state, or target-specific synchronization branches exist.

## Failure, Concurrency, and Constraints
Malformed programs fail validation. The runner enforces caller-selected fuel, stack, and value budgets and returns BOUND_EXCEEDED rather than success. A single task is modeled in this initial slice; Actor support remains pending.

## Verification and Change Impact
[Tests](../../../Tests/FormalIRTests) own behavioral evidence. Recheck parent, lowering, both emitters, and validator whenever instruction or state meaning changes.

## Mathematical Integers and Failures
IRType.integer and IRValue.integer are separate from fixed-width bits. IRIntegerOperation has add/subtract/multiply/lessThan/equal. Integer literals serialize canonically as signed decimal strings; zero has no sign or leading zero. MathematicalInteger is the immutable host owner. IR validation requires integer operands and returns one bit for comparisons. IRFailureKind distinguishes panic and undefinedBehavior; the existing trap instruction remains distinct. A failed computation never becomes a returned value. [Execution](../Execution/DESIGN.md) owns bounded host execution, while formal runtimes model unbounded integers. Backend and decoder consumers must change with this contract. [Frontend tests](../../../Tests/FormalFrontendTests) own language composition; [IR tests](../../../Tests/FormalIRTests) own static validity and instruction behavior.
