# FormalValidation

## Purpose and Scope
Own independent inspection of actual emitted artifacts. Parent: [package](../../DESIGN.md). Children: [ArtifactDecoder](ArtifactDecoder/DESIGN.md), [ToolExecution](ToolExecution/DESIGN.md), [Toolchain](Toolchain/DESIGN.md), [Verification](Verification/DESIGN.md), [Properties](Properties/DESIGN.md). A separate Lean SIL decoder and reference-semantics checker are also required; artifact equality alone is insufficient.

## Responsibilities and Boundaries
Reparse limited emitted TLA and Lean data, rejecting arbitrary code and changed fixed wrappers. Return validated program data for caller-owned equality comparison. Compose finite model checks and universally quantified interpreter proofs through separate verification contracts. Runtime byte identity is audited by Verification; independent general runtime semantics certification remains pending. Do not invoke generator lowering as the independent SIL validator.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Package](../../DESIGN.md) | parent | Strict correspondence | Validation boundary | Incomplete until independent SIL checking exists |
| [FormalIR](../FormalIR/DESIGN.md) | depends on | Data schema | Checked comparison target | IR equality alone does not prove SIL correctness |
| [ArtifactDecoder](ArtifactDecoder/DESIGN.md) | child | Restricted syntax | Actual output inspection | No arbitrary Lean compilation before audit |
| [Properties](Properties/DESIGN.md) | child | PropertyVerifying | All-input pre/postcondition proofs | Distinct from finite cases; translation remains uncertified |

## Architecture
```text
Actual .tla / .lean -> audited snapshot + restricted decoder -> common program data
Scenario + verified toolchain -> bounded ToolExecution -> finite TLC / Lean report
Property + audited snapshot -> bounded ToolExecution -> quantified Lean theorem / universal TLA specification
Explicit installation -> pinned archive acquisition -> verified portable toolchain
Original SIL -> separate Lean decoder/reference semantics -> kernel correspondence
```

## Contracts and Invariants
The decoder is independent of emitters and lowering. Fixed wrappers are checked token-for-token; dynamic program data is decoded structurally including all branches and operand IDs. Runtime resource identity and semantic auditing are not performed by this decoder. Translation remains UNVALIDATED until both artifact decoding and independent SIL/reference checking succeed.

## Verification and Change Impact
[Mutation tests](../../Tests/FormalValidationTests) must reject changed opcodes, operands, widths, branches, runtime expressions, and arbitrary Lean code. Changes affect strict generation and all prior certificates.

## Packaged Verification Extension
Children: [ToolExecution](ToolExecution/DESIGN.md), [Toolchain](Toolchain/DESIGN.md), [Verification](Verification/DESIGN.md). Offline concrete model verification is separate from general source semantic certification. Trusted runtime identity is audited before external tools execute. The decoder alone does not audit runtime semantics.

## Universal Property Extension
Child: [Properties](Properties/DESIGN.md). It consumes Verification’s internal ArtifactSnapshot and LeanProofAudit contracts to prove quantified interpreter obligations. Finite cases and universal proofs have distinct scopes; source translation remains UNVALIDATED.


## Target structured inspection SDK
Child [Inspection](Inspection/DESIGN.md) uses the [FormalEvidence](../FormalEvidence/DESIGN.md) dependency. Inspection owns actual formal-language declaration/state/proof extraction and source-origin data audit; Compiler is still not a dependency. Existing finite/quantified checking contracts keep their truth scope but return structured per-obligation evidence/bundle references at cutover. The [transition](../../Documentation/SDK-TRANSITION.md) removes old summary-only public reports and whole-DOT scanning as an SDK, without removing private forensic logs or independent trust checks. The implemented structured path is exercised by actual checker/inspection tests; graph availability does not alter original proof truth.
