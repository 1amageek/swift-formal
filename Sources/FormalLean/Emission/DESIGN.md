# Lean emission

## Purpose and Scope
Own deterministic Lean syntax and the scalar runtime. Parent: [FormalLean](../DESIGN.md). No children.

## Responsibilities and Boundaries
Serialize program data, preserve all state updates, and emit no fabricated proof. Does not certify its own output or establish original SIL correspondence.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [FormalLean](../DESIGN.md) | parent | Emission contract | Small-step backend | Current scalar slice is not v1 |

## Architecture
```text
IRProgram -> data constructors -> runtime Step relation -> output files
```

## Contracts and Invariants
Symbols are escaped as data. Artifact order is deterministic. No timestamps or absolute local paths. Integer bit patterns keep their widths. Terminal states are distinct from nonterminal deadlock. The runtime is a versioned semantics artifact, not a business-specific model.

## State, Ownership, and Lifecycle
Emission is pure and invocation-local. Output publication belongs to orchestration.

## Verification and Change Impact
[Backend tests](../../../Tests/FormalBackendTests), SANY, Lean kernel, and future independent decoding own verification. Output shape or runtime changes invalidate prior translation evidence.
