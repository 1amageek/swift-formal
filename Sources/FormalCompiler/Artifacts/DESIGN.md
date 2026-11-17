# Source Artifacts

## Purpose and Scope
Own the public source-to-artifact package composition within [FormalCompiler](../DESIGN.md). No children.

## Responsibilities and Boundaries
Compose SourceCompiling and both emitters into immutable generated artifacts and exact source provenance. Publish complete directories atomically. Do not import FormalValidation or claim independent output-data/semantic validation.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Compiler](../DESIGN.md) | parent | Frontend/emitter composition | Public SDK owner | No validation dependency |
| [Frontends](../Frontends/DESIGN.md) | depends on | SourceCompiling | Restricted source profiles | Unsupported syntax fails before writing |
| [Verification](../../FormalValidation/Verification/DESIGN.md) | used by | Audited artifact layout/provenance | Consumer audits generated data | Generation does not certify translation |
| [Commands](../../formal/Commands/DESIGN.md) | used by | SourceArtifactGenerating | CLI delegates composition | CLI performs independent data comparison |

## Architecture
```text
Exact source bytes -> bounded frontend -> IR -> Lean/TLA emitters
    -> immutable SourceArtifact -> failure-atomic new directory
```

## Contracts and Invariants
SourceArtifactGenerating.generate accepts explicit language, module identity and compiler configuration; source bytes are retained without normalization and SHA-256 identifies those exact bytes. Generation rejects invalid UTF-8, over-budget source, invalid IR or emitter failure. No directory is published until every artifact and provenance file has been written. Existing destinations are refused. Paths are controlled, relative and nontraversing. Reports retain DRAFT_UNVALIDATED, no semantic validation and no external tools; independent emitted-data equality is reported only by a validating consumer. Artifact layout remains compatible with the existing verification audit.

## State, Ownership, and Lifecycle
Generated values are immutable Sendable data. A write owns one sibling staging directory and removes it on failure; successful rename transfers ownership to the caller. No shared mutable state or target-specific synchronization.

## Failure, Concurrency, and Constraints
Source input is bounded by the configured frontend and one-million-byte composition cap. File I/O and cleanup failures propagate as typed diagnostics. Caller-owned workers provide outer deadlines/cancellation for synchronous generation. No tool installation or execution.

## Verification and Change Impact
ArtifactGenerationTests cover original byte identity, actual emitted-data decoding/IR execution, refusal of existing destinations, malformed/unsupported source and failure-atomic cleanup. Recheck CLI output-data validation and FormalValidation artifact audit compatibility; generated runtime semantics are unchanged.

The generation provenance reports actualOutputDataMatchesIR false because the generator performs no independent decoding. The CLI independently compares both emitted outputs and returns its existing true comparison report after that check. Verification always audits actual bytes rather than trusting either observational flag.

The public generator resource identity hashes the actual Lean/TLA runtime bytes. Consumers combine it with their executor binary and validation policy identities when sealing a plan. It is not evidence of semantic preservation.
