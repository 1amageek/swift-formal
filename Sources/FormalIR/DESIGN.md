# FormalIR

## Purpose and Scope
Own the typed, backend-independent small-step program and state. Parent: [package](../../DESIGN.md). Children: [Program](Program/DESIGN.md), [Execution](Execution/DESIGN.md).

## Responsibilities and Boundaries
Represent instructions and their effects without recovering high-level Swift intent. The first executable slice handles fixed-width bits, aggregates, SSA block arguments, direct calls, branch, return, and trap. Other cases remain unsupported; this is not the complete Core or Actor profile.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Package](../../DESIGN.md) | parent | Common semantics | Shared backend input | Partial implementation is not v1 |
| [Program](Program/DESIGN.md) | child | Typed static structure | Functions, blocks, instructions | No source-name inference |
| [Execution](Execution/DESIGN.md) | child | Small-step observation | Test/reference runner | Fuel exhaustion is not termination |

## Architecture
```text
Typed SIL -> Program -> shared small-step relation -> TLA / Lean
                         -> bounded Swift runner (differential test only)
```

## Contracts and Invariants
Bit widths and operations are explicit. Call frames retain local environments. Branch operands bind simultaneously to destination block arguments. Return, trap, and exhausted execution budgets are distinct outcomes. Mathematical semantics permit unbounded stack; the Swift runner's resource limits report bounds.

## Verification and Change Impact
[IR tests](../../Tests/FormalIRTests) own arithmetic endpoints, branch bindings, calls, traps, and fuel exhaustion. Any operation change requires lowering, both backends, and independent validation changes before semantic support is advertised.

## Extended Integer Contracts
[Program](Program/DESIGN.md#mathematical-integers-and-failures) owns arbitrary integer and failure representation. [Execution](Execution/DESIGN.md#mathematical-integer-execution) owns host capacity and execution. Both backend runtimes consume those contracts; changing them requires backend/decoder and frontend regression checks.


The [Binary64 Number contract](Execution/DESIGN.md#binary64-number-contract) adds IEEE operations to existing 64-bit data. This extends the operation set without introducing a new value encoding; signed/unsigned integer semantics remain separate.
