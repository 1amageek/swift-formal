# Contracts

## Purpose and Scope
Versioned Codable records for locks, contexts, manifests, diagnostics, and three independent result axes. Parent: [FormalCore](../DESIGN.md). No child components.

## Responsibilities and Boundaries
Decoding checks shape; explicit validate methods check supported schema, required values, and bootstrap constraints. Exact toolchain identity must match. JSON keys are sorted; timestamps are absent. No semantic success record is produced.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [FormalCore](../DESIGN.md) | parent | Module boundary | Owned implementation | Recheck consumer assumptions |

## Architecture
```text
Caller -> Contracts -> explicit value or error
```

## Contracts and Invariants
Decoding checks shape; explicit validate methods check supported schema, required values, and bootstrap constraints. Exact toolchain identity must match. JSON keys are sorted; timestamps are absent. No semantic success record is produced.

Toolchain locks require compiler/runtime metadata only. The removed declaration-index revision is neither decoded into identity nor validated. Schema version 1 is retained: existing metadata remains readable through the decoder's unknown-field behavior, and newly encoded locks omit unrelated index-tool metadata.

## State, Ownership, and Lifecycle
State belongs to a call; no global mutable storage. Data and temporary resources remain scoped to the invocation.

## Failure, Concurrency, and Constraints
Failure is propagated or converted to a typed diagnostic. Independent calls share no mutable resources. Limits are selected by the caller and must be positive.

## Verification and Change Impact
Behavior owner: [Tests/FormalCoreTests/BundleInspectorTests.swift](../../../Tests/FormalCoreTests/BundleInspectorTests.swift). Changes require rechecking the parent and its consuming CLI integration paths. Metadata verification never establishes semantic equivalence.
