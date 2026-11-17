# Structured formal SDK transition

This document owns implementation sequencing and removal gates. [Package DESIGN](../DESIGN.md) owns composition; leaf designs own data/API semantics. The user explicitly permits breaking development changes. New interfaces below are designs, not implemented products. Existing finite/quantified semantics, independent audits and source UNVALIDATED status remain requirements.

## Confirmed current facts and feasibility
| Fact | Original implementation / behavior |
|---|---|
| Source locations are insufficient | SourceToken/SILToken retain line/column only; ParsedSourceFunction/SourceFunction retain a start token; IR instructions have no source range. Read Frontends/SourceToken.swift, SourceLowering.swift and SIL/Syntax/SILToken.swift |
| Artifact output is source/IR/files/report | SourceArtifactGenerator composes public emitters; no origin or formal-graph catalog exists |
| TLC data exists | ModelVerifier invokes pinned TLC with `-dump dot trace.dot`; actual prior integration artifacts contain states/edges; report exposes only count/status |
| Lean report is not a proof graph | VerificationReport/PropertyVerificationReport carry axioms/status/witness summaries. LeanProofAudit checks actual axiom output; it does not collect type/body dependency graphs |
| Lean extraction primitive works | A bounded design probe on pinned Lean 4.35.0 kernel-checked graphRoot via graphLemma, then inspected its environment: root type references graphBase and value references graphLemma; no axioms were introduced |
| SANY source data | Pinned 1.7.4 SANY successfully parses and semantically analyzes a module with a variable, Init, Next and TypeOK. Its `-d` switch opens an interactive console, not a machine-readable SDK dump; that transport is rejected. The typed collector remains unimplemented and unverified |

No compiler/extractor result is inferred from declarations alone. Existing real TLC/Lean/backend tests remain evidence for their original paths; they do not certify a new graph SDK.

## Target implementation order and deletion
| Stage / acceptance | Owner and new behavior | Remove at the same gate |
|---|---|---|
| F1 / FE-01..02/05 | FormalEvidence Records + GraphStore bundle writer; located source/SIL tokens, syntax, lowering and tracked emission | Bare compile-returning-only-IR API, GeneratedFile contents-only emitter interface and old SourceArtifact/SourceArtifactReport/generator signatures; update all actual callers/tests together |
| F2 / FE-03..04 | Controlled generated-profile SANY/TLC/Lean extraction and origin audit; exact per-obligation claims | Status/count-only public checker results and ad hoc graph inference from report text; raw tool logs remain private forensic artifacts |
| F3 / FE-06..07 | Bounded indexed reader, traces, origins, documents, leases and shutdown | Whole-DOT String scanning as public graph interface; unbounded array export and arbitrary artifact path access |
| F4 / FE-08..09 | Formal CLI, distribution and Invar adapters use only new artifacts/results | Old artifact/report readers, CLI-only duplicate composition, compatibility aliases and format migration paths |

These are dependency-ordered work gates, not promises of a separately usable product release at each row. Implementation of a stage starts only after the lower contracts it consumes pass their tests. User-authored Lean inspection remains unavailable until FE-09 passes. Remove old callable paths when the replacement works; do not add no-op/new-name wrappers. During this design task the existing executable source is retained because its replacement is not implemented. A retained path is transitional, not a second supported SDK. Delete its superseded design text now; keep a precise current-source inventory here until deletion.

Artifact layout 2 rejects layout 1 explicitly; Evidence schema 1 is independent. Semantic IR schema need not change for a location sidecar. Old public method signatures are removed, not deprecated indefinitely. Installed old evidence is never silently rewritten or discarded; an explicit new state/artifact root is required where old format is unsupported. No legacy reader is part of the new runtime.

## Behavioral acceptance
| IDs | Required evidence |
|---|---|
| FE-01..02 | Exact UTF-8 source/generated ranges across Unicode, comments, branching/calls and synthetic instructions; changed offsets cannot retain a false precise link; file-only mapping stays file-only |
| FE-03 | Actual TLA module/operator references, actual TLC state/transition/loop data and ordered checked witness; missing action/trace capability is explicit |
| FE-04 | Actual Lean type/value/axiom dependencies, changed proof term, opaque boundary, unproved theorem, sorry/custom-axiom rejection and no fabricated tactic steps |
| FE-05 | Writer publication/rollback, immutable conflict, complete index/chunk integrity and crash boundaries reject unpublished or corrupt bundles |
| FE-06..07 | Whole small reference graph equals all bounded pages; giant/cyclic graphs obey budgets; corrupt cursor/index/digest rejected; concurrent read/shutdown and retention work |
| FE-08 | New compilation/checker/CLI/distribution pipeline on actual pinned tools, mixed failure/partial extraction and unchanged finite/quantified truth scope |
| FE-09 | Real sandbox denial of project scripts/network/outside roots/fork for user Lean inspection; permission refusal precedes elaboration; no runtime download |

## Resource and compatibility decisions
No new numeric performance defaults are guessed by this design. Policy owners select effective budgets from explicit user limits, existing supported profiles, measured peaks and receiving caps. Every changed default requires representative cold-start/steady-state/boundary verification. Pinned collector resources join the inventory and trust audit. No ArchitectureExplorer, Invar, Web or Skeleton dependency is introduced into Formal.

## Delivery status
Design only. The new FormalEvidence product, located compiler APIs, structured inspector, schema files and behavioral acceptance tests are not implemented. The lower capability probes and original behavior checks are recorded separately; none is counted as FE acceptance success.

## Design probe scope
On the pinned offline toolchain, a trusted temporary Lean module imported Lean, defined `graphBase : Nat := 3`, proved `graphLemma : graphBase = 3 := rfl`, and proved `graphRoot : graphBase = 3 := graphLemma`. A command elaborator queried `getEnv`, `ConstantInfo.type.getUsedConstants` and `value? (allowOpaque := true)` followed by `Expr.getUsedConstants`. Actual output included `graphRoot` type dependency `graphBase`, value dependency `graphLemma`, and `#print axioms graphRoot` reported no axioms. This checks the extraction primitive on a genuinely checked theorem; no packaged inspector or arbitrary-user isolation was exercised. Lean 4.35.0 completed within the 30-second probe deadline.

SANY 1.7.4 parsed/semantically processed the trusted temporary module and Naturals. The first `-d` attempt with EOF entered a repeated console-output loop and hit its 30-second deadline; it is a rejected approach. Repeating with explicit `quit` input, a 10-second deadline and 64 KiB output cap exited successfully (391 output bytes). Only semantic analysis was confirmed, not structured graph extraction. A version-pinned collector must supply and test that missing capability before FE-03 passes.
