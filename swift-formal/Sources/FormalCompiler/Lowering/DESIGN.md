# FormalLowering

## Purpose and Scope
Translate explicitly supported typed SIL into common IR. Parent: [FormalCompiler](../DESIGN.md). Child: [Scalar](Scalar/DESIGN.md). The initial slice is scalar arithmetic, tuple/wrapper construction, conditional branches, and direct thin calls.

## Responsibilities and Boundaries
Resolve every selected function_ref by complete symbol, include its body, validate each operand and type, and preserve every selected CFG edge and trap. Reject all unsupported opcodes, attributes, types, call conventions, external functions, and dynamic calls. This is not yet the complete Core/Actor profile or an independently validated translator.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Package](../../../DESIGN.md) | parent | Strict generation | No premature success | Current output is unvalidated IR only |
| [FormalSIL](../SIL/DESIGN.md) | depends on | Structural syntax | Original tokens and locations | Parse success is not type validity |
| [FormalIR](../../FormalIR/DESIGN.md) | depends on | Typed instructions and validation | Shared semantics | Preserve fixed-width operations |
| [Scalar](Scalar/DESIGN.md) | child | Scalar lowering | Explicit supported grammar | Unsupported paths fail |

## Architecture
```text
Canonical SIL syntax + explicit entry symbols -> dependency closure -> typed rules -> IR validation
```

## Contracts and Invariants
No name/comment heuristics, missing-callee fallback, or instruction deletion except known debug metadata. Each lowering rule carries the original SIL location; conversion evidence remains unvalidated until the independent checker exists.

## Verification and Change Impact
[Tests](../../../Tests/FormalLoweringTests) compile/read actual fixture SIL, compare interpreter results with expected arithmetic/branch/call behavior, and mutate instructions, types, externals, and branch arguments. Backend and validator work is required before these rules grant generation success.
