# Formal verification outcome contracts

Checked on 2026-11-20 against the exact requirements and implementation references in inputs.json. This is a requirements-derived specification check of the verification-result protocol. It does not compile Formal itself into TLA+ or Lean, prove the Swift checker implementation, or complete the original v1 specification.

| Requirement | Evidence | Scope |
|---|---|---|
| SPEC 2.2, 15.1 and Properties/DESIGN.md | ProofRequiresEvidence | A successful model proof requires artifact audit, SANY, Lean and allowed-axiom audit success. |
| SPEC 17/A26 and Properties/DESIGN.md | InterruptedCannotProve | Deadline/cancellation before completion returns unknown, including after partial checker success. |
| SPEC 2.2 and root DESIGN.md | ModelProofIsNotSourceCertification | No source-semantic certificate is supplied by this model. Translation stays UNVALIDATED. |
| Commands/DESIGN.md, Draft Translation | ExistingOutputIsPreserved | Generation cannot replace an existing destination. |
| SPEC 15.2 | FailedGenerationIsAtomic | A failed generation leaves the published output unchanged. Generation/publication is modeled as atomic; crash, fsync and filesystem semantics are assumptions. |
| Properties/DESIGN.md | Lean proofRequiresEvidence, interruptionIsUnknown, badAuditCannotProve, incompleteCannotProve | Four theorems quantify all Boolean audit/check/completion/interruption combinations for the independently specified decision function. |

TLC completed breadth-first exploration: **158 generated states, 126 distinct states, depth 9, queue empty**, with five invariants. The model has one invocation, two initial output states, a clock 0..2, independently nondeterministic checker results and axiom audit, and cancellation before terminal return. Terminal states may stutter, so deadlock checking is disabled. No fairness, liveness or resource-cleanup guarantee is asserted. A verified returned result is immutable. Late external cancellation after return is outside the invocation.

Lean 4.35.0 checked four named theorems. Each uses only propext. Positive and boundary examples include a successful proof, failed axiom audit, and interruption after all tools succeeded. Lean.log retains the exact axiom audit.

Negative controls use disposable copies. reachable-success enables the deliberately false NeverProved invariant, showing a genuine success is reachable. missing-axiom-audit weakens the final proof gate and TLC finds ProofRequiresEvidence violated. timeout-as-success replaces the interruption outcome and TLC finds InterruptedCannotProve violated. The three logs retain the actual traces. The reviewed model is unchanged by these experiments.

## Implementation evidence

`python3 Tools/run-with-timeout.py --seconds 240 -- swift test --filter VerificationTests` passed **6 tests**. These execute actual scenario validation, compilation artifact creation and tampering rejection (layout, source, metadata, runtime, origin ranges/addresses and missing evidence), tool archive corruption rejection, inventory hashing, theorem admission/custom axiom rejection, and scalar range validation. This evidence is regression coverage for those exact implementation paths. It does not establish general refinement between the Swift implementation and the protocol or universal correctness of all supported compilers.

## Remaining work

The root DESIGN.md explicitly retains UNVALIDATED source translation and incomplete general SIL/source correspondence and Actor semantics. This run does not check parser/lowering correctness, numeric semantics, arbitrary Lean isolation, process cleanup, concurrent publication, crashes, resource exhaustion, or all 29 original acceptance criteria. Full v1 completion remains open. The existing support/progress documents own those capabilities.

## Reproduce

Use the repository's ignored `.tools/formal-portable-v03-verified/toolchain` with Temurin 21.0.13+9, TLA tools release 1.7.4 (TLC 2.19, rev 5a47802), and Lean 4.35.0. Both checkers have a 60-second timeout. TLC's working directory and standard-module extraction directory must be a fresh temporary directory. From this directory run `python3 verify.py --toolchain ../../../.tools/formal-portable-v03-verified/toolchain`. This reruns the unchanged main model, all Lean theorems and the three controls. Run the six implementation tests separately from the repository root as above.

## Architecture evidence

ARCHITECTURE.dsl was reviewed from README, Package.swift, the CLI entry point, actual checker invocations and evidence storage. Invar's inventory command rejected custom excludes in the native package manifest, so the reviewed declaration was authored directly under the documented Invar Map profile. Explorer's actual Structurizr-profile parser accepted the context and container views, including all groups and explicitly declared connections. A full standalone Structurizr CLI validator was unavailable. In-process library targets remain source-index modules. Runtime traffic has not been observed.

The source index also reports unsupported Swift syntax in Sources/FormalValidation/Inspection/BoundedRecordLines.swift and Sources/FormalValidation/Properties/PropertyWitnessSearch.swift. Those files compiled in the focused test run, so these are Explorer syntax-index limitations. They limit source navigation coverage and do not alter the separately checked protocol model.
