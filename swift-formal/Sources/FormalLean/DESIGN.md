# FormalLean

## Purpose and Scope
Mechanically emit Lean from the common typed scalar IR. Parent: [package](../../DESIGN.md). Child: [Emission](Emission/DESIGN.md).

## Responsibilities and Boundaries
Render the shared program as data and apply an explicit small-step runtime. No source-name inference, optimization, proof admission, or property-success claims. Generated files are unvalidated until independent translation validation succeeds.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Package](../../DESIGN.md) | parent | Common input and strict validation | Formal backend | Scalar slice only |
| [FormalIR](../FormalIR/DESIGN.md) | depends on | Typed program and opcode semantics | Shared execution meaning | Cannot add backend-only support |
| [Emission](Emission/DESIGN.md) | child | Deterministic files | Data and runtime formatting | Actual files require external checking |

## Architecture
```text
Validated IR -> program data + small-step runtime -> unvalidated Lean files
```

## Contracts and Invariants
Preserve every instruction and branch, fixed widths, overflow flags, call frames, trap, and normal return. Unbounded frame stacks are mathematical state; bounded checking is separate. No fairness is silently added. No application property is asserted as proved.

## Verification and Change Impact
[Backend tests](../../Tests/FormalBackendTests) own data emission. Actual Lean kernel and TLA SANY/TLC runtime checks are required as integration evidence. Any semantic change requires independent validator and both backend updates.
