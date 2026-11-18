# FormalValidation.Inspection

## Purpose and Scope
Implemented component contract. Own extraction of actual TLA+/Lean structures and checked formal evidence. Parent: [Validation](../DESIGN.md). No children.

## Responsibilities and Boundaries
Inspect exact audited artifacts, record tool observations and write FormalEvidence bundles. Source/model origin validation checks bytes/ranges, not semantic preservation. No application source parsing, Invar scheduling, Explorer rendering or Compiler import.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Validation](../DESIGN.md) | parent | Independent checking | Semantic authority | Preserve independence |
| [FormalEvidence](../../FormalEvidence/DESIGN.md) | depends on | Typed records and bundle writer | Structured SDK | Must be implemented first |
| [ArtifactDecoder](../ArtifactDecoder/DESIGN.md) | depends on | Actual-output data audit | Generated profile admission | Graph extraction does not bypass audits |
| [Verification](../Verification/DESIGN.md) | coordinates with | Finite cases and actual TLC/Lean | Method evidence | Named finite scope |
| [Properties](../Properties/DESIGN.md) | coordinates with | Quantified properties | Checked theorem/witness | Unproved is not false |
| [ToolExecution](../ToolExecution/DESIGN.md) | depends on | Owned limits/cancellation | Isolated tooling | Process groups alone are not sandboxing |

## Architecture
```text
artifact manifest + explicit inspection profile
  -> independent audit -> controlled SANY / TLC / Lean worker
  -> typed declaration/state/dependency records + verification claims
  -> validated indexes -> sealed evidence bundle
```

## Contracts and Invariants
`FormalInspecting.inspect(FormalInspectionRequest) async throws -> FormalInspectionResult` selects an explicit capability profile and returns bundle reference, extraction coverage and diagnostics. Finite/quantified checker results use `FormalVerificationResult` with per-obligation claims and evidence bundle references; raw aggregate JSON/run-directory strings cease to be SDK authority. Execution, logical outcome, scope, translation and extraction availability remain independent.

### TLA profiles
- Specification structure is obtained from SANY's analyzed module graph using a version-pinned collector. Modules, constants, variables, operators and references are parser facts. Init/Next/invariant/temporal roles require the actual configuration or explicit checked role declarations. Operator names alone establish no temporal role.
- Generated profile extraction validates the existing audited wrappers/data and generation-origin sidecar. The collector itself is packaged as a hashed tool resource, compiled against the pinned tla2tools artifact; verification does not require javac or download a JDK.
- State-space extraction consumes actual TLC exploration output. A bounded parser for the pinned DOT dialect may provide observed nodes/edges/value representations; completeness comes from actual TLC completion and resource/audit results, not successful DOT parsing. Labels are data, never executable markup. Preserve exact escaped values and signed state IDs; do not coerce values through floating point.
- Action/condition labels are emitted only if recorded by the pinned tool/collector. Missing transition metadata remains unknown. Preserve stuttering, duplicate observations, SCCs and liveness loop-back information when available.
- A checked counterexample has its obligation and ordered tool witness. An unordered exploration dump is not a counterexample trace. When the installed tool does not provide a required ordered trace, return unsupported extraction for that feature; do not choose an arbitrary shortest path and label it an observed counterexample.
- User-authored TLA modules require an explicit import manifest and pinned standard modules. A controlled classpath excludes workspace Java overrides. Analysis-only structure and actual model checking are different operations and capabilities.

### Lean profiles
The collector loads captured `.olean` data using pinned Lean's `withImportModules` with extensions/initializers disabled, then replays the complete root dependency closure (including mutual inductive families, constructors and recursors) into a fresh kernel environment before extracting dependencies. This follows the actual [Lean 4.35.0 import contract](https://github.com/leanprover/lean4/blob/v4.35.0/src/Lean/Environment.lean) and [kernel replay implementation](https://github.com/leanprover/lean4/blob/v4.35.0/src/LeanChecker.lean). Elaboration of user source is separately sandboxed/authorized; its stdout is never an axiom/proof oracle. Only the trusted collector's independently replayed environment supplies that data.

- A pinned Lean helper reads the actual elaborated environment. `ConstantInfo.type` and `value?` supply expression dependencies; `Expr.getUsedConstants` supplies referenced declarations. Distinguish typeUses/valueUses and actual transitive axiom dependencies. Available checked expression structure may be a proof-term graph, not an invented tactic timeline.
- Imported modules and opaque/unavailable bodies have explicit boundaries. Missing body data never means no dependencies. Theorems/obligations that failed elaboration remain unproved nodes with diagnostics; there is no checked proof term for them.
- Kernel success and the approved axiom audit remain necessary for a checked proof. Dependency visualization does not replace LeanProofAudit's trust invariant. Sorry/custom/native-reduction axioms cannot be hidden by a pretty graph.
- Controlled generated proofs reuse the existing finite/quantified scopes. User Lean elaboration is a separate execution capability: macros, initializers and #eval can execute code. It requires explicit authority, immutable import closure, verified compiled dependencies and a sandbox profile denying network/unapproved reads/writes/fork. Never run project lakefiles, plugins or package resolution during inspection. If that isolation/import closure is unsupported, fail explicitly rather than using unrestricted Lean.
- Arbitrary recursion/Actor source semantics and source/model correspondence remain unsupported until their lower semantic profiles exist. Visualizing a Lean/TLA artifact does not create those semantics.

### Independent origin and result audit
Check every origin's artifact digest, range and IR address against the actual audited program/generated files; never import compiler lowering for this check. Provenance-valid links remain unvalidated semantic correspondence. Per-case theorem names are qualified by bundle/case identity to distinguish repeated `checkedCase` names.

Actual proof evidence remains immutable if optional graph extraction fails: report checked logical outcome with unavailable/partial visualization, never fabricate a graph or rewrite proof success to falsehood. A caller requiring complete visualization receives incomplete extraction. Persist artifacts and diagnostics even on tool failure, within reserved failure headroom.

## State, Ownership, and Lifecycle
The worker owns tools and temporary output until publication. A retained bundle is handed to the caller; shutdown/cancellation drains and reaps tools before releasing admission. No background tool is owned by a reader or UI session. Lean collector/SANY bridge resources participate in toolchain/executor identity and distribution manifests.

## Failure, Concurrency, and Constraints
Separate immutable limits for import files/bytes, parser/expression depth, graph/trace records, tool CPU/RSS/process/output/workspace and whole operation deadline. Enforce minimum remaining ancestor budget. Graph records stream to the bundle writer; a giant state space never becomes an unbounded in-memory String/Array. Distinct typed failures cover unsupported profile/isolation, input mutation, import gap, tool failure, kernel rejection, unknown/bound outcome, graph corruption and extraction budget exhaustion.

## Verification and Change Impact
Planned **FE-03/04/08/09** use actual pinned SANY/TLC/Lean for declaration dependencies, mutated terms, theorem admissions, opaque boundaries, finite counterexamples, liveness loops, traces truncated by limits, unsupported metadata, source-range tampering and sandbox denials. The design probe confirms direct Lean type/body references and SANY semantic data only; it does not validate this extractor. Recheck Artifacts, Evidence schemas/store, trusted resources, finite/quantified checkers, packaging and Invar on changes.

The macOS adapter permits root-directory traversal plus explicitly approved runtime reads. A measured pinned-JRE bootstrap requires only `com.apple.system.opendirectoryd.libinfo` Mach lookup; that capability is granted only to the pinned Java executable, not user Lean. Network and fork stay denied. Input copies and sealed dependency outputs are outside each elaboration step’s writable directory. Integration tests execute the actual sandbox rather than a host fallback.

### Generated artifact collection
`GeneratedEvidenceCollector` consumes only the independently audited generated model and controlled checker workspaces. It streams bounded DOT lines into graph batches; ordered counterexample states come only from matching TLC message frames. Terminal reachability is audited with the same structured state decoder, never a label substring. Declaration and proof-term extraction uses the actual checked `.olean` in a separate pinned Lean invocation. Each optional graph is either retained whole or discarded and replaced by an unavailable descriptor; claims are not rewritten by extraction failures. The caller supplies output root, budgets and remaining whole-operation deadline.

The replay closure follows pinned [Lean.Replay](https://github.com/leanprover/lean4/blob/v4.35.0/src/Lean/Replay.lean) and `ConstantInfo.getUsedConstantsAsSet`, not only display graph edges. Unsafe/partial roots are refused; the root must exist with the original type in the fresh kernel. Unrelated imported tactic declarations are not part of the root claim.

SANY module closure includes the external module table, recursively nested modules and INSTANCE targets, as well as EXTENDS. Each recorded INSTANCE has its own semantic UID and source location and an `instantiates` edge to the analyzed target. Scope completion is emitted only after this bounded closure and actual operator-body references have been traversed. An external-only or EXTENDS-only scan cannot claim complete extraction.
