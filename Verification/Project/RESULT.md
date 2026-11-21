# Formal whole-project verification

The complete acceptance inventory is Documentation/SPEC.md section 17 (29 acceptance conditions) and section 19 (12 completion conditions), under root DESIGN.md's governing decisions. The original requirements were preserved. The whole-project result is **INCOMPLETE**, with exit code 6. All 41 requirements remain in the report.

| Assessment | Current evidence |
|---|---|
| Specification-derived verification | 3 of 41 conditions have scoped independent evidence: A12, A13 and A26. The remaining 38 are unverified. |
| Production-code verification | 182 of 182 production Swift files were captured with exact bytes and passed to the current Formal executable. 182 returned UNSUPPORTED_SOURCE_PROFILE; none returned SOURCE_PARSE_FAILED. No production model was generated, so zero implementation properties are verified. |
| Source correspondence | 0 of 41. The supported source-to-model paths currently retain UNVALIDATED. |
| Supporting regression evidence | All 134 Swift tests and the ten-language CLI integration passed. Previously retained SIL/backend checking, independent Lean decoding, five TLC scenarios and arithmetic mutation checks retain their original scope. These results do not replace production-code verification. |

The specification path checks the independent outcome protocol (126 reachable states, five invariants, four Lean theorems and three controls) and the Actor design. The reentrant Actor design produces the required two-reservation counterexample. The corrected design has four reachable states and preserves capacity. Four additional Lean theorems check arbitrary atomic reservation schedules and every transition of the concrete bad trace. Both are specification evidence with their explicit assumptions, not an implemented Actor lowering claim.

The production path uses the actual current 0.4.0 Formal binary, its compiled resource bundles and the verified pinned checker toolchain. Exact production source bytes are copied to private scratch inputs and independently submitted to the whole-function source profile. The whole-function scalar profile rejects production constructs: all 182 inputs receive UNSUPPORTED_SOURCE_PROFILE. The earlier 29 SOURCE_PARSE_FAILED diagnostics for optional types, strings and other excluded Swift syntax were a classification defect, now corrected and covered by native-valid and malformed-input controls. These diagnostics do not establish that valid package sources are invalid Swift. This identifies a verification capability gap and does not establish that the production code is logically false.

A full test invocation stalled in SwiftPM's test launcher after an exited child. The original run was interrupted and retained. Source inspection confirmed that these targets contain Swift Testing tests and no XCTest cases. The workflow now explicitly disables the empty XCTest adapter. The earlier full rerun passed 132 Swift Testing tests, and the backend verifier uses the same explicit test-library selection. The preserved diagnostic and original failed execution are linked in the report.

## Development flow

Requirements inventory and governing decisions -> independent TLA+/Lean specification checks -> exact production-code model/check attempts -> specification/code/correspondence review -> complete-inventory report. Each stage retains its original outcomes. Failures return to the owning requirement, formalization, implementation or execution layer. The report cannot complete a project from a successful subset, regression test or unvalidated translation.

The Invar plugin owns this workflow and the hash-checked receipt aggregation. Formal owns model semantics and verification. Explorer owns the generic report and Map presentation. All three requirement assessments are visible independently and remain unchanged by filtering or collapsed groups. The report's acceptance inventory must exactly equal the inventory extracted from the pinned specification sections.

## Reproduce

From the Formal root, use the current built executable with its verified sibling toolchain and run `python3 Tools/run-with-timeout.py --seconds 360 -- python3 Verification/verify-project.py --formal <current-formal-executable> --report-tool <Invar-root>/plugins/invar/scripts/project_report.py`. Each run retains a new immutable evidence directory. Exit 6 means the report is available and verification is incomplete. The current report is Verification/Project/Report.json. The Map binding is attached to the exact Explorer source snapshot after checking its source inputs.

## Complete acceptance matrix

| ID | Condition | Specification | Code | Correspondence |
|---|---|---|---|---|
| A01 | Fixed-width subtraction | notVerified | unsupported | notVerified |
| A02 | Overflow and wrapping | notVerified | unsupported | notVerified |
| A03 | Branches and payloads | notVerified | unsupported | notVerified |
| A04 | SSA block arguments | notVerified | unsupported | notVerified |
| A05 | Loops and recursion | notVerified | unsupported | notVerified |
| A06 | Nontermination | notVerified | unsupported | notVerified |
| A07 | Memory and inout | notVerified | unsupported | notVerified |
| A08 | Direct calls | notVerified | unsupported | notVerified |
| A09 | Throw and catch | notVerified | unsupported | notVerified |
| A10 | Unresolved external calls | notVerified | unsupported | notVerified |
| A11 | Unsupported instructions | notVerified | unsupported | notVerified |
| A12 | Actor reentrancy counterexample | passed | unsupported | notVerified |
| A13 | Actor isolation correction | passed | unsupported | notVerified |
| A14 | Async call semantics | notVerified | unsupported | notVerified |
| A15 | Executor identity | notVerified | unsupported | notVerified |
| A16 | Terminal and deadlock | notVerified | unsupported | notVerified |
| A17 | Artificial bounds | notVerified | unsupported | notVerified |
| A18 | Module dependency closure | notVerified | unsupported | notVerified |
| A19 | Missing debug locations | notVerified | unsupported | notVerified |
| A20 | Missing source index | notVerified | unsupported | notVerified |
| A21 | Translation tampering | notVerified | unsupported | notVerified |
| A22 | Output-expression tampering | notVerified | unsupported | notVerified |
| A23 | Admitted or custom axioms | notVerified | unsupported | notVerified |
| A24 | Deterministic regeneration | notVerified | unsupported | notVerified |
| A25 | Toolchain mismatch | notVerified | unsupported | notVerified |
| A26 | Timeout and interruption | passed | unsupported | notVerified |
| A27 | Deleted control-flow mutation | notVerified | unsupported | notVerified |
| A28 | Shared IR mistranslation | notVerified | unsupported | notVerified |
| A29 | Empty or contradictory scenarios | notVerified | unsupported | notVerified |
| D01 | Both backends from supported SIL | notVerified | unsupported | notVerified |
| D02 | Deterministic generation without inference | notVerified | unsupported | notVerified |
| D03 | Complete semantic coverage | notVerified | unsupported | notVerified |
| D04 | Explicit unsupported diagnostics | notVerified | unsupported | notVerified |
| D05 | Actor fixtures in both backends | notVerified | unsupported | notVerified |
| D06 | Automatic source/model correspondence | notVerified | unsupported | notVerified |
| D07 | Separate generation and proof outcomes | notVerified | unsupported | notVerified |
| D08 | Finite and universal scope distinction | notVerified | unsupported | notVerified |
| D09 | Complete provenance | notVerified | unsupported | notVerified |
| D10 | Generator and validator mutation suite | notVerified | unsupported | notVerified |
| D11 | Reproducible output bytes | notVerified | unsupported | notVerified |
| D12 | Dependency ownership boundary | notVerified | unsupported | notVerified |

Current complete execution records are in Verification/Project/runs/20261121T000812563935Z/observations.json. Prior scoped and interrupted attempts remain separate histories. General SIL semantics, full source correspondence, memory/Actor lowering and the remaining original v1 requirements are not completed by this run.

## Source-admission correction — 2026-11-21

The independent SourceAdmission contract was checked before changing the lexer/parser: seven reachable states, three admission invariants, four Lean theorems and three negative/reachability controls. This is a source-admission specification, not a full A11 SIL-opcode/attribute proof, so it adds no whole acceptance claim. Its receipt remains in the project report. Ten excluded-grammar examples were accepted by Swift 6.4.1; the CLI now returns unsupported/3 with a location and no artifact. Five malformed scalar cases still return parse-failed/4. Existing accepted scalar languages still translate; model generation is still distinct from property proof.

The direct complete run is runs/20261121T044206067460Z/manifest.json. Its report retains all 41 requirements, four checker receipts and every production source hash. The original requirements are unchanged.

MCP run 33734A69-904D-4BE2-A2E9-C72EC58FDE9B used source snapshot 142C09D6-097D-495D-A933-262FF0395317 and 280 exact input files, including the explicit governing contracts. Operation e564d441fb505fdb9aca4dede33062e2e92c33618ae7d2ca8165e2598ffeb1d5 completed and its original-subject publication committed. Applicability was matchesInputs; acceptedAtCompletion was false. The worker recorded 6.976147 CPU seconds; prepare/run/report/publication took 36.633 seconds. Whole-project status remains incomplete, with specification 3/41, implementation 0/41 and validated correspondence 0/41.

The built-in-browser result is open at http://127.0.0.1:60307/#canvas=C2B5BD85-8893-4429-BF44-7C3DA5E50837. The A12 Inspector explicitly shows unsupported implementation (182 files), passed scoped specification evidence and unverified source correspondence. Screenshot: /tmp/formal-source-diagnostics-explorer.jpg. No Explorer code changed in this correction.
