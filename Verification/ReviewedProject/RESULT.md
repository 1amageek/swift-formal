# Complete verification-flow exercise — 2026-11-21

This existing-code audit exercised every stage of Invar's verify-project flow. Each stage has an explicit review over original inputs and checker receipts. The project is **incomplete**, not verified. The first return owner is specification.

```text
Original 41 requirements
    -> independent TLA+/Lean checking
    -> 134 package tests + actual backend/CLI regressions
    -> exact generation attempts for 182 production sources
    -> semantic-correspondence capability inspection
    -> six bound reviews covering five stages
    -> independent report rebuild through actual Invar MCP
    -> original Map subject / reviewed report in Explorer
```

## Observed checks and reviews

| Stage | Actual work | Gate result |
|---|---|---|
| requirements | All A01–A29 and D01–D12 preserved under governing SPEC/DESIGN; requirement review covers all 41. | passed |
| specification | VerificationOutcome, ActorIsolation and SourceAdmission executed with actual TLC/Lean and their negative/reachability controls. Three complete-inventory rows retain scoped evidence: A12/A13/A26. The other 38 have explicit review findings. | incomplete |
| implementation | 182 exact production sources attempted; all unsupported, zero production models. All 134 Swift tests passed. Fixture backend checks passed four Lean finite results, three independent decoder claims, mutation rejection and five TLC scenarios. Ten-language CLI integration passed. | blocked by specification; production property evidence also absent |
| correspondence | Actual strict validate command returned unsupported/3 with no artifact. Original lowerer, model-verification paths and fixture decoder were inspected. Production source/model semantics remain UNVALIDATED; fixture data/step equality does not establish full correspondence. | blocked; required correspondence evidence unavailable |
| integration | All 41 requirements, production input inventory, seven checker/regression receipts and all preceding reviews inspected. Six review records cover all five stages with current exact bindings. | blocked; earliest return owner specification |

All six recorded review input bindings validate. The specification review is split into three scoped accepted conditions and 38 incomplete conditions. Implementation, correspondence and integration reviews explicitly retain their findings; conducting a review does not make its gate pass. Supporting tests retain regression domains and supply no formal-phase claims.

The full checker execution is [the retained run](../Project/runs/20261121T055655636963Z/observations.json). It did not use --skip-supporting-tests. Original production/SPEC/DESIGN and executed script inputs were checked for mutation during execution. [The review manifest](../Project/ReviewSessions/20261121T055655636963Z/manifest.json) references that original evidence, source inventory and all reviews. Review assembly creates a new retained run without rewriting original receipts or rerunning their checkers.

## Actual MCP and Explorer path

The separately approved [reviewed configuration](../Project/reviewed-invar.json) binds 251 explicit contract/evidence inputs and the unchanged pinned builder. Verification/review-project.py assembles the reviewed manifest on the native backend's private sealed workspace; the backend independently rebuilds it from the raw references, compares verdict/exit, checks input immutability and archives the complete closure. This publication is a review-assembly execution, not a second execution of TLC, Lean or the Swift tests.

MCP used 299 captured files at snapshot 03C115B4-30C6-4BB9-9D1F-5A5A6B90EE70. Review files created a new source snapshot; the reused 182 production hashes are unchanged. Plan ad190a97b62840c4b40861ff359a3ba63fe1e4d6cb76205f15d1e42fd9da8b22 led to run 28E01F0D-4E3D-4F6B-8029-8394022A01DB and original operation 323f8ce5180b2d1d31304371e39f2787a65a7b2edc15382eae9cc1ebe1d302e5. Execution completed, applicability matchesInputs, outcome unknown, acceptedAtCompletion=false, publication committed/complete. MCP preparation through publication took 30.34 seconds; assembly worker CPU was 0.292837 seconds. Full checker execution time is separate.

Report artifact: 9de2eb09f32191b9a3e2bcf96b2d6d638691c1abd640fd527599ac2f8375c38e. Retained 253-file archive: b5a9f9f9a085d1bc9ef7b69098ed6f73296a9145bc639ea44b2bbfa017a7c661. Native retained manifest: runs/20261121T060054055721Z/manifest.json. [flow-result.json](flow-result.json) keeps the public operation/report/publication summaries.

The original swift-formal Map object's options open “Formal · Reviewed whole-project verification.” The destination/loading state appeared before diagram retrieval. Canvas preserves the full verdict while filtering blocked gates: specification 3/41, code 0/41, correspondence 0/41; zero complete requirements; Return to specification. Browser: http://127.0.0.1:61113/#canvas=39749314-C4A4-45AE-BD36-50BD9B0826E8. Screenshot: /tmp/formal-full-flow-explorer.jpg.

## Failure control and limits

A modified receipt digest was submitted to the actual review-assembly executable. It rejected the input before creating a run or replacing the previous report. The passing control and actual MCP publication exercise both assembly branches. Log: /tmp/formal-full-flow-review-rejection.log. Nineteen selected actual ledger records pass current shape validation; opaque namespaces remain unclaimed.

Source production code, model semantics, checker permissions, global AGENTS.md, Invar and Explorer source code were unchanged in this exercise. Only verification artifacts, an assembly helper/configuration and this verification design/record were added. No full-production proof or source-semantic guarantee follows from successful test fixtures, model checks or publication.

## Reproduction

Run the existing Verification/verify-project.py with the pinned Formal binary and Invar report builder under the repository timeout wrapper, omitting --skip-supporting-tests. Review exact receipts, save schema-1 stage decisions with current input hashes, and construct a schema-2 review manifest. The retained review manifest can be rechecked with Verification/review-project.py --manifest <repository-relative-manifest> --report-tool <pinned-builder>, under a timeout. Host-approved MCP planning/running uses Verification/Project/reviewed-invar.json. Incomplete assembly exits 6 and cannot satisfy the whole-project gate.
