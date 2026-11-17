# FormalEvidence

## Purpose and Scope
**Proposed SwiftPM library product/module; not declared in Package.swift and not implemented.** Own the public structured formal-evidence SDK. Parent: [Formal package](../../DESIGN.md). Children: [Records](Records/DESIGN.md), [GraphStore](GraphStore/DESIGN.md).

## Responsibilities and Boundaries
Provide immutable formal graph/origin/trace/claim records and bounded bundle queries. Dependencies: FormalCore only. Compiler and Validation produce records through this contract; neither Invar nor Explorer is imported. This module does not execute Lean/TLC, prove theorems or own application source indexes.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Formal package](../../DESIGN.md) | parent | Composition and semantic limits | New public SDK | No product advertised before implementation |
| [Records](Records/DESIGN.md) | child | Evidence semantics | Serialization authority | Provenance is not correspondence |
| [GraphStore](GraphStore/DESIGN.md) | child | Bounded retained-bundle queries | Data access authority | Partial view is not partial proof |
| [FormalCore](../FormalCore/DESIGN.md) | depends on | Diagnostics and artifact primitives | Stable lower types | No reverse dependency |
| [Compiler](../FormalCompiler/DESIGN.md) | used by | Compilation origins and model graphs | Generator output | Not independent proof |
| [Validation](../FormalValidation/DESIGN.md) | used by | Audited model/proof/trace evidence | Checking output | Must not import Compiler |
| [Invar evidence](../../../Invar/Sources/VerificationCore/Evidence/DESIGN.md) | used by | Content-addressed evidence catalogs | Integration consumer | Formal identifiers stay namespaced |

## Architecture
```text
FormalCompiler  -> FormalEvidence -> FormalCore
FormalValidation -> FormalEvidence
Invar adapters -> FormalEvidence public ports
```
The existing FormalIR dependency of Compiler/Validation remains; FormalEvidence does not reinterpret IR semantics. IR addresses include the exact program digest and are checked by producers against FormalIR.

## Contracts and Invariants
Children own all detailed schemas/query contracts. A catalog identifies its producers, profile, source/artifact digests, tool identities, scope, assumptions and availability. Only independently checked evidence can carry a checked proof claim. Layout, translation provenance and kernel checking never become synonyms.

## State, Ownership, and Lifecycle
Records are immutable; GraphStore owns actor-isolated readers and explicit shutdown. No target-specific synchronization branch. Tool workers, source inputs and retained bundles are owned by their callers.

## Failure, Concurrency, and Constraints
Unknown capabilities are explicit; a summary report, missing file or empty graph cannot stand in for extracted evidence. Readers honor caller budgets and bounded concurrency. Old serialized reports are not an alternate input format.

## Verification and Change Impact
[SDK transition](../../Documentation/SDK-TRANSITION.md) owns FE acceptance ordering and deletion gates. Current Lean/TLC design probes show available lower data, not implementation of this module. Recheck Compiler, Validation, CLI/distribution and Invar when either child contract changes.
