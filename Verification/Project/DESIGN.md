# Whole-project verification

The acceptance inventory is Documentation/SPEC.md section 17 (A01 through A29) and section 19 (twelve definition-of-done obligations). Root DESIGN.md owns the documented naming, dependency and current-support decisions. The original specification is preserved. The project report keeps the full inventory even where current Formal cannot produce an implementation model.

Run Verification/verify-project.py with the current built Formal executable and the Invar plugin's project_report.py path. The workflow records requirements-derived checking, all package tests, actual backend checking, actual CLI integration, and model-generation attempts over exact captured production Swift files. These are separate evidence domains. Successful regressions do not supply a production-model proof. A source-model generation success without a checked property remains unknown.

Each execution uses a new retained run directory and per-command deadlines. The original source hashes, checker inputs, outputs, commands, claims and unsupported diagnostics are retained. Changes to an observed input during execution abort publication. The complete-inventory report is rebuilt through Invar's receipt aggregator and imported into Explorer at its matching source snapshot. The published JSON can be replaced as a current projection, while prior run records remain immutable.

Whole-project success requires the required specification, implementation and correspondence assessments for the entire acceptance inventory. Current unsupported paths remain visible and block that conclusion. The previous VerificationOutcome model remains a scoped input to this workflow.

## Explorer execution

Verification/Project/invar.json binds the C4 subject to Invar's approved project-command profile. Invar executes Verification/verify-project.py on a private exact-input workspace, validates its returned receipt manifest through the pinned project report builder and publishes the complete report to that original subject/snapshot. The command emits repository-relative manifest and report paths. Runtime evidence stays in the attempt-owned immutable artifact store.

The GUI profile selects --skip-supporting-tests: independent TLA+/Lean checks and every production source-model attempt execute; unrelated supporting regression suites are not rerun by that command. Supporting tests remain a separate development gate and never replace either formal phase. The default CLI workflow still runs them. The unchanged acceptance inventory remains authoritative and missing correspondence prevents a complete verdict.

Source rejection has a separate requirements-derived SourceAdmission TLA+/Lean check. It distinguishes unsupported grammar from malformed scalar syntax and forbids artifacts/proof from rejection. The complete project workflow retains its receipt without attaching it to a whole acceptance claim: source admission alone does not satisfy the full SIL opcode/attribute contract A11. Per-file production outcomes are summarized from actual return values rather than a fixed unsupported explanation. A failed admission-contract check aborts publication.

## Reviewed workflow gates

The Invar verify-project skill owns orchestration and schema-2 records. This existing-code audit retains the original 41 requirements and every production source as a declared input. The source-generation receipt explicitly has activity modelGeneration and cannot supply a passed implementation check. The reviewed requirements record binds the governing SPEC and DESIGN. Missing specification, implementation, correspondence or integration reviews remain incomplete and block gate passage; diagnostic checks of existing code may still execute. The derived report identifies the earliest return stage rather than fabricating approval. New implementation still requires its necessary specification gate first.

## Completing an Agent review cycle

The Agent reviews the retained checker evidence after execution and saves hash-bound decisions for all five stages. Verification/review-project.py assembles those original receipts and decisions into a fresh Verification/ReviewedProject run. It performs no new checking and grants no new proof: the pinned Invar builder derives the outcome from the original evidence and reviews. A separate reviewed-invar.json configuration admits this assembly through the same native project backend, which independently rebuilds it, retains the receipt closure and publishes to the original C4 subject at its newly captured snapshot. Unchanged source and model hashes bind reused checker evidence; the snapshot change caused by review files is explicit. Missing/changed evidence rejects assembly before replacing the current report. This keeps checker execution and post-execution Agent review separate without mutating prior runs or accepting generation as proof.
