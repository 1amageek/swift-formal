# Artifact decoder

## Purpose and Scope
Reparse actual scalar backend program data with a restricted independent grammar. Parent: [FormalValidation](../DESIGN.md). No children.

## Responsibilities and Boundaries
Recognize only emitted string/number/list/record/constructor grammar, fixed module wrappers, and trusted runtime templates. Never execute arbitrary generated code. Do not reuse emitter formatting or generator lowering.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [FormalValidation](../DESIGN.md) | parent | Artifact audit | Independent syntax boundary | Not original-SIL correspondence by itself |

## Architecture
```text
Bytes -> restricted lexical grammar -> structural data -> typed IR program comparison
```

## Contracts and Invariants
Every byte outside permitted whitespace, fixed wrappers, and parsed data is rejected. No unknown constructors, import, theorem, axiom, eval directive, or runtime mutation is accepted. Widths and every state-changing operand must survive decoding. Input bounds and positive nesting limits are explicit.

## Failure, Concurrency, and Constraints
All state is invocation-local. Parse or comparison mismatches fail with diagnostics. No subprocess is launched by this component.

## Verification and Change Impact
[Tests](../../../Tests/FormalValidationTests) own artifact tampering checks. Runtime changes require reference semantics review and external behavioral evidence, not merely a new accepted hash.

The restricted data grammar also decodes integer types, decimal integer literals, integer operations, and explicit failure kinds. Every field and constructor arity is checked; arbitrary source code remains rejected. Decoding round trips do not establish source semantics.


Number instructions reuse restricted operation data; IR validation enforces width/result types. [IR execution](../../FormalIR/Execution/DESIGN.md#binary64-number-contract) owns semantics. Updated runtime hashes require regeneration of older artifacts.
