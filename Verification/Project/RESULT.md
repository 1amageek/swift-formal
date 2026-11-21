# Formal whole-project verification

The complete acceptance inventory is Documentation/SPEC.md section 17 (29 acceptance conditions) and section 19 (12 completion conditions), under root DESIGN.md's governing decisions. The original requirements were preserved. The whole-project result is **INCOMPLETE**, with exit code 6. All 41 requirements remain in the report.

| Assessment | Current evidence |
|---|---|
| Specification-derived verification | 3 of 41 conditions have scoped independent evidence: A12, A13 and A26. The remaining 38 are unverified. |
| Production-code verification | 182 of 182 production Swift files were captured with exact bytes and passed to the current Formal executable. 153 returned UNSUPPORTED_SOURCE_PROFILE and 29 returned SOURCE_PARSE_FAILED. No production model was generated, so zero implementation properties are verified. |
| Source correspondence | 0 of 41. The supported source-to-model paths currently retain UNVALIDATED. |
| Supporting regression evidence | All 132 Swift tests passed. Actual SIL/backend checking, independent Lean decoding, five TLC scenarios, arithmetic mutation rejection and CLI integration passed. These results do not replace production-code verification. |

The specification path checks the independent outcome protocol (126 reachable states, five invariants, four Lean theorems and three controls) and the Actor design. The reentrant Actor design produces the required two-reservation counterexample. The corrected design has four reachable states and preserves capacity. Four additional Lean theorems check arbitrary atomic reservation schedules and every transition of the concrete bad trace. Both are specification evidence with their explicit assumptions, not an implemented Actor lowering claim.

The production path uses the actual current 0.4.0 Formal binary, its compiled resource bundles and the verified pinned checker toolchain. Exact production source bytes are copied to private scratch inputs and independently submitted to the whole-function source profile. The whole-function scalar profile rejects production constructs: 153 inputs receive UNSUPPORTED_SOURCE_PROFILE, while 29 receive SOURCE_PARSE_FAILED for syntax or operators this path cannot handle. These diagnostics do not establish that valid package sources are invalid Swift. This identifies a verification capability gap and does not establish that the production code is logically false.

A full test invocation stalled in SwiftPM's test launcher after an exited child. The original run was interrupted and retained. Source inspection confirmed that these targets contain Swift Testing tests and no XCTest cases. The workflow now explicitly disables the empty XCTest adapter. The full rerun passes 132 Swift Testing tests, and the backend verifier uses the same explicit test-library selection. The preserved diagnostic and original failed execution are linked in the report.

## Development flow

Requirements inventory and governing decisions -> independent TLA+/Lean specification checks -> exact production-code model/check attempts -> specification/code/correspondence review -> complete-inventory report. Each stage retains its original outcomes. Failures return to the owning requirement, formalization, implementation or execution layer. The report cannot complete a project from a successful subset, regression test or unvalidated translation.

The Invar plugin owns this workflow and the hash-checked receipt aggregation. Formal owns model semantics and verification. Explorer owns the generic report and Map presentation. All three requirement assessments are visible independently and remain unchanged by filtering or collapsed groups. The report's acceptance inventory must exactly equal the inventory extracted from the pinned specification sections.

## Reproduce

From the Formal root, use the current built executable with its verified sibling toolchain and run `python3 Tools/run-with-timeout.py --seconds 360 -- python3 Verification/verify-project.py --formal <current-formal-executable> --report-tool <Invar-root>/plugins/invar/scripts/project_report.py`. Each run retains a new immutable evidence directory. Exit 6 means the report is available and verification is incomplete. The current report is Verification/Project/Report.json. The Map binding is attached to the exact Explorer source snapshot after checking its source inputs.

## Complete acceptance matrix

| ID | Condition | Specification | Code | Correspondence |
|---|---|---|---|---|
| A01 | Fixed-width subtraction | notVerified | unknown | notVerified |
| A02 | Overflow and wrapping | notVerified | unknown | notVerified |
| A03 | Branches and payloads | notVerified | unknown | notVerified |
| A04 | SSA block arguments | notVerified | unknown | notVerified |
| A05 | Loops and recursion | notVerified | unknown | notVerified |
| A06 | Nontermination | notVerified | unknown | notVerified |
| A07 | Memory and inout | notVerified | unknown | notVerified |
| A08 | Direct calls | notVerified | unknown | notVerified |
| A09 | Throw and catch | notVerified | unknown | notVerified |
| A10 | Unresolved external calls | notVerified | unknown | notVerified |
| A11 | Unsupported instructions | notVerified | unknown | notVerified |
| A12 | Actor reentrancy counterexample | passed | unknown | notVerified |
| A13 | Actor isolation correction | passed | unknown | notVerified |
| A14 | Async call semantics | notVerified | unknown | notVerified |
| A15 | Executor identity | notVerified | unknown | notVerified |
| A16 | Terminal and deadlock | notVerified | unknown | notVerified |
| A17 | Artificial bounds | notVerified | unknown | notVerified |
| A18 | Module dependency closure | notVerified | unknown | notVerified |
| A19 | Missing debug locations | notVerified | unknown | notVerified |
| A20 | Missing source index | notVerified | unknown | notVerified |
| A21 | Translation tampering | notVerified | unknown | notVerified |
| A22 | Output-expression tampering | notVerified | unknown | notVerified |
| A23 | Admitted or custom axioms | notVerified | unknown | notVerified |
| A24 | Deterministic regeneration | notVerified | unknown | notVerified |
| A25 | Toolchain mismatch | notVerified | unknown | notVerified |
| A26 | Timeout and interruption | passed | unknown | notVerified |
| A27 | Deleted control-flow mutation | notVerified | unknown | notVerified |
| A28 | Shared IR mistranslation | notVerified | unknown | notVerified |
| A29 | Empty or contradictory scenarios | notVerified | unknown | notVerified |
| D01 | Both backends from supported SIL | notVerified | unknown | notVerified |
| D02 | Deterministic generation without inference | notVerified | unknown | notVerified |
| D03 | Complete semantic coverage | notVerified | unknown | notVerified |
| D04 | Explicit unsupported diagnostics | notVerified | unknown | notVerified |
| D05 | Actor fixtures in both backends | notVerified | unknown | notVerified |
| D06 | Automatic source/model correspondence | notVerified | unknown | notVerified |
| D07 | Separate generation and proof outcomes | notVerified | unknown | notVerified |
| D08 | Finite and universal scope distinction | notVerified | unknown | notVerified |
| D09 | Complete provenance | notVerified | unknown | notVerified |
| D10 | Generator and validator mutation suite | notVerified | unknown | notVerified |
| D11 | Reproducible output bytes | notVerified | unknown | notVerified |
| D12 | Dependency ownership boundary | notVerified | unknown | notVerified |

Current complete execution records are in Verification/Project/runs/20261121T000812563935Z/observations.json. Prior scoped and interrupted attempts remain separate histories. General SIL semantics, full source correspondence, memory/Actor lowering and the remaining original v1 requirements are not completed by this run.
