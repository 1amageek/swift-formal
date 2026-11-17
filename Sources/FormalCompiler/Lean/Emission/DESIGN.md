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
Symbols are escaped as data. Artifact order is deterministic. No timestamps or absolute local paths. Integer bit patterns keep their widths. Terminal states are distinct from nonterminal deadlock. The runtime is a versioned semantics artifact, not a business-specific model. Its canonical bytes are the regular package resource in this directory; the Semantics development tree refers to it by repository-local symlink, so consuming packages receive self-contained bundles.

## State, Ownership, and Lifecycle
Emission is pure and invocation-local. Output publication belongs to orchestration.

## Verification and Change Impact
[Backend tests](../../../../Tests/FormalBackendTests), SANY, Lean kernel, and future independent decoding own verification. Output shape or runtime changes invalidate prior translation evidence.

Mathematical integer instructions use Lean Int or canonical sign/magnitude bit sequences in TLA+, avoiding TLC machine-integer overflow. Panic and undefined behavior are distinct terminal states. Finite external-tool tests own these paths.


Number operations are emitted as dedicated operation constructors using the [IR Number contract](../../../FormalIR/Execution/DESIGN.md#binary64-number-contract). The runtime implements logical IEEE semantics; trusted bytes and finite/universal evidence must be updated together.


## Target tracked emission
The [Artifacts owner](../../Artifacts/DESIGN.md) replaces contents-only GeneratedFile output with tracked generated documents and origin links. Segment byte ranges are recorded while emitting actual text, validated against that text's digest. This does not alter the meaning of IR operations or certify source semantics. Independent decoder/runtime audits must still pass; changing emission/resources requires the actual Lean/TLC regression and range-mutation tests.
