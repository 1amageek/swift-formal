# Whole-project verification

The acceptance inventory is Documentation/SPEC.md section 17 (A01 through A29) and section 19 (twelve definition-of-done obligations). Root DESIGN.md owns the documented naming, dependency and current-support decisions. The original specification is preserved. The project report keeps the full inventory even where current Formal cannot produce an implementation model.

Run Verification/verify-project.py with the current built Formal executable and the Invar plugin's project_report.py path. The workflow records requirements-derived checking, all package tests, actual backend checking, actual CLI integration, and model-generation attempts over exact captured production Swift files. These are separate evidence domains. Successful regressions do not supply a production-model proof. A source-model generation success without a checked property remains unknown.

Each execution uses a new retained run directory and per-command deadlines. The original source hashes, checker inputs, outputs, commands, claims and unsupported diagnostics are retained. Changes to an observed input during execution abort publication. The complete-inventory report is rebuilt through Invar's receipt aggregator and imported into Explorer at its matching source snapshot. The published JSON can be replaced as a current projection, while prior run records remain immutable.

Whole-project success requires the required specification, implementation and correspondence assessments for the entire acceptance inventory. Current unsupported paths remain visible and block that conclusion. The previous VerificationOutcome model remains a scoped input to this workflow.
