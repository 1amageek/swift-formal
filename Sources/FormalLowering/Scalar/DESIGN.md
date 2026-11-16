# Scalar lowering

## Purpose and Scope
Own initial scalar type and opcode decoding. Parent: [FormalLowering](../DESIGN.md). No children.

## Responsibilities and Boundaries
Decode thin synchronous functions with fixed-width Builtin integers, locked standard-library integer/Bool wrappers, and tuples. Detect unsupported attributes and forms explicitly. Debug metadata alone may be removed as an unobservable instruction.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [FormalLowering](../DESIGN.md) | parent | Fail-closed translation | Scalar rule owner | No independently validated generation yet |

## Architecture
```text
Selected function tokens -> typed scalar rules -> IR instructions + origin evidence
```

## Contracts and Invariants
SSA IDs and block bindings remain explicit. Overflow builtins produce both wrapped bits and an overflow flag; cond_fail stays a trap. Direct calls include the exact callee. Unknown semantic attributes, generic substitutions, unsupported integers, memory, Actor, async, and unresolved externals fail. No silent fallback or arbitrary values.

## Failure, Concurrency, and Constraints
All state is invocation-local. Closure work is bounded by finite input functions and an explicit function limit. Input syntax token bounds belong to FormalSIL. The fixed standard-library wrapper mapping is provisional: it currently erases nominal identity into aggregates. This is an explicit incomplete implementation, and production generation remains disabled until nominal types, provenance, and independent reference validation are complete.

## Verification and Change Impact
[Tests](../../../Tests/FormalLoweringTests) own this slice. Any type/opcode expansion requires both backends, reference semantics, rule evidence, and mutation tests before publication as semantic support.
