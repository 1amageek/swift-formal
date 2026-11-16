# FormalSIL

## Purpose and Scope
Own lexical and structural decoding of canonical SIL emitted by the locked compiler. Parent: [FormalCompiler](../DESIGN.md). Child: [Syntax](Syntax/DESIGN.md). Typed semantic decoding is introduced separately; structural parsing never grants opcode support.

## Responsibilities and Boundaries
Preserve source locations, all function headers and bodies, and non-function top-level declarations. Reject malformed lexical structure, duplicate function bodies, mismatched delimiters, and noncanonical stage. Do not infer behavior from comments or declaration names.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [FormalCompiler](../DESIGN.md) | parent | Locked host and honesty | Compiler front end | Structural success is not semantic success |
| [Syntax](Syntax/DESIGN.md) | child | Lossless token structure | Lexing and function/CFG boundaries | No unsupported instruction is silently removed |
| [FormalCore](../../FormalCore/DESIGN.md) | depends on | Typed diagnostics | Error propagation | Source position belongs to SIL, not Swift |

## Architecture
```text
SIL UTF-8 -> lexer -> tokens with locations -> structural parser -> module syntax
```

## Contracts and Invariants
No regular expression extraction. Quoted strings, comments, balanced nested types, multiline instruction groups, and function/block delimiters are lexical grammar elements. Unknown opcode text remains unsupported syntax, not translated instructions.

## Verification and Change Impact
[Syntax tests](../../../Tests/FormalSILTests) cover multiline syntax, actual compiler output, malformed input, source positions, and unknown-opcode preservation. Future lowering must explicitly type-check every reachable node and attribute.
