# Source-admission contract

Derived from the source-profile failure contract in FormalCompiler/Frontends/DESIGN.md and the original explicit-diagnostics requirement in Documentation/SPEC.md. The source kind is an assumption: these models do not decide arbitrary Swift syntax and do not satisfy the full A11 SIL opcode/attribute acceptance condition.

| Contract | Evidence |
|---|---|
| Outside-profile syntax is distinct from malformed supported syntax | TLC CorrectClassification; Lean unsupportedIsDistinct and malformedIsDistinct |
| Rejection cannot publish a generated artifact | TLC NoRejectedArtifact; Lean rejectedCannotCommit |
| Draft generation is not source proof | TLC NoFalseProof; Lean successfulGenerationIsDraft |
| The model can reject incorrect implementations | Misclassification and rejected-artifact mutations produce invariant violations |
| Success is reachable rather than vacuously excluded | DraftReachable is deliberately false and TLC produces a valid artifact trace |

Executed with the existing pinned Java/TLC/Lean toolchain. TLC explored all seven distinct states (zero queued), with no violation of the three positive invariants. Four Lean theorems checked: two have no axioms and two depend only on propext. No sorry or custom axiom was used. Every checker process has a 30-second timeout, and the driver was wrapped in a 150-second process-group timeout.

The initially written TLA model used a negative sentinel with Naturals; SANY rejected it. A pending string replaced the sentinel. The initial Lean-output audit expected four axiom-bearing theorems and rejected the two axiom-free results; the audit now checks both categories explicitly. Neither initial failure is acceptance evidence. The final positive and three control logs are retained alongside this file.

Before production edits, the new CLI regression failed on all ten valid Swift cases. Swift 6.4.1 accepted those cases in one actual native typecheck. After the lexer/parser correction, the ten unsupported cases return exit 3 and create no artifact, while five malformed scalar controls retain exit 4. The full package has 134 passing Swift tests, plus the actual ten-language CLI integration. These behavioral observations bind representative input cases to the contract; they are not a proof that every Swift program is classified completely.

Mutable parser/lexer state remains invocation-local value state. No shared mutable storage, isolation changes, Embedded/WASM branches, unsafe pointers or unchecked Sendable were added. Integer execution, lowering, emitted runtimes and validated-correspondence status are unchanged.

Reproduce with `python3 Verification/Specifications/SourceAdmission/verify.py --toolchain <pinned-toolchain>` under the repository's outer timeout wrapper. Complete-project results and MCP references are recorded in Verification/Project/RESULT.md.
