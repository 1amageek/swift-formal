# FormalValidation

## Purpose and Scope
Own independent inspection of actual emitted artifacts. Parent: [package](../../DESIGN.md). Child: [ArtifactDecoder](ArtifactDecoder/DESIGN.md). A separate Lean SIL decoder and reference-semantics checker are also required; artifact equality alone is insufficient.

## Responsibilities and Boundaries
Reparse limited emitted TLA and Lean data, rejecting arbitrary code and changed fixed wrappers. Return validated program data for caller-owned equality comparison. Trusted runtime auditing remains pending. Do not invoke generator lowering as the independent SIL validator.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Package](../../DESIGN.md) | parent | Strict correspondence | Validation boundary | Incomplete until independent SIL checking exists |
| [FormalIR](../FormalIR/DESIGN.md) | depends on | Data schema | Checked comparison target | IR equality alone does not prove SIL correctness |
| [ArtifactDecoder](ArtifactDecoder/DESIGN.md) | child | Restricted syntax | Actual output inspection | No arbitrary Lean compilation before audit |

## Architecture
```text
Actual .tla / .lean -> restricted decoder -> common program data
Original SIL -> separate Lean decoder/reference semantics -> kernel correspondence
```

## Contracts and Invariants
The decoder is independent of emitters and lowering. Fixed wrappers are checked token-for-token; dynamic program data is decoded structurally including all branches and operand IDs. Runtime resource identity and semantic auditing are not performed by this decoder. Translation remains UNVALIDATED until both artifact decoding and independent SIL/reference checking succeed.

## Verification and Change Impact
[Mutation tests](../../Tests/FormalValidationTests) must reject changed opcodes, operands, widths, branches, runtime expressions, and arbitrary Lean code. Changes affect strict generation and all prior certificates.
