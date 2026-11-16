# SourceIndex

## Purpose and Scope
Parse Swift sources through SwiftSkeletonParser and return declaration locations. Parent: [FormalIndex](../DESIGN.md). No child components.

## Responsibilities and Boundaries
Preserve private declarations, methods, and parse-error state. Do not turn a parser error into successful metadata. No execution semantics, mangled-symbol matching, or source-required SIL path. Missing source is a caller-visible error.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [FormalIndex](../DESIGN.md) | parent | Module boundary | Owned implementation | Recheck consumer assumptions |

## Architecture
```text
Caller -> SourceIndex -> explicit value or error
```

## Contracts and Invariants
Preserve private declarations, methods, and parse-error state. Do not turn a parser error into successful metadata. No execution semantics, mangled-symbol matching, or source-required SIL path. Missing source is a caller-visible error. The fixed upstream parser can omit same-line members; all results explicitly set completeDeclarationCoverage to false and report the limitation. Missing metadata must never remove SIL instructions.

## State, Ownership, and Lifecycle
State belongs to a call; no global mutable storage. Data and temporary resources remain scoped to the invocation.

## Failure, Concurrency, and Constraints
Failure is propagated or converted to a typed diagnostic. Independent calls share no mutable resources. Limits are selected by the caller and must be positive.

## Verification and Change Impact
Behavior owner: [Tests/FormalIndexTests/SourceIndexerTests.swift](../../../Tests/FormalIndexTests/SourceIndexerTests.swift). Changes require rechecking the parent and its consuming CLI integration paths. Metadata verification never establishes semantic equivalence.
