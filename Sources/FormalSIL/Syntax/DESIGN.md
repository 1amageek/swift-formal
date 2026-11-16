# SIL syntax

## Purpose and Scope
Lossless lexical and structural canonical SIL input. Parent: [FormalSIL](../DESIGN.md). No children.

## Responsibilities and Boundaries
Track tokens and SIL positions; parse functions, blocks, instructions, and top-level records. Preserve unknown opcodes for later explicit rejection. Semantic support is not decided here.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [FormalSIL](../DESIGN.md) | parent | Structural input boundary | Versioned SIL grammar | Later layers own typed semantics |

## Architecture
```text
Source -> token stream -> function/block/instruction syntax
```

## Contracts and Invariants
Strings and comments cannot create instruction boundaries. Delimiters must balance. Duplicate function definitions or blocks fail. A body must have block labels and nonempty instruction sequences. Input byte and token counts have explicit caller-selected limits. Full SIL validity still requires the locked compiler verifier.

## Failure, Concurrency, and Constraints
All parser state is invocation-local. Maximum nesting and tokens are explicit limits; exhaustion fails. Missing or unknown semantic metadata never becomes a default semantic value.

## Verification and Change Impact
[Tests](../../../Tests/FormalSILTests) own structural behavior. Changes affect future typed decoding and independent validator input compatibility.
