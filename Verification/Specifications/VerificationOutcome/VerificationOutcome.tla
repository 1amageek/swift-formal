---------------------- MODULE VerificationOutcome ----------------------
EXTENDS Naturals

\* Requirements: Documentation/SPEC.md sections 2.2, 15.1, 15.2, 17/A26.
\* Current owners: FormalValidation/Properties and formal/Commands DESIGN.md.
\* This is a requirements-derived protocol, not a model of Swift execution.
VARIABLES phase, original, artifact, audit, sany, lean, axioms,
          result, interrupted, clock, translation
vars == <<phase, original, artifact, audit, sany, lean, axioms,
          result, interrupted, clock, translation>>

Init == /\ phase = "generate"
        /\ original \in {"absent", "existing"}
        /\ artifact = original
        /\ audit = "pending"
        /\ sany = "pending"
        /\ lean = "pending"
        /\ axioms = "pending"
        /\ result = "notRequested"
        /\ interrupted = FALSE
        /\ clock = 0
        /\ translation = "UNVALIDATED"

Generate == /\ phase = "generate"
            /\ original = "absent"
            /\ phase' = "audit"
            /\ artifact' = "new"
            /\ UNCHANGED <<original, audit, sany, lean, axioms, result,
                           interrupted, clock, translation>>

RejectGeneration == /\ phase = "generate"
                    /\ phase' = "done"
                    /\ result' = "generationFailed"
                    /\ UNCHANGED <<original, artifact, audit, sany, lean,
                                   axioms, interrupted, clock, translation>>

Audit == /\ phase = "audit"
         /\ \E ok \in BOOLEAN:
              /\ audit' = IF ok THEN "passed" ELSE "failed"
              /\ phase' = IF ok THEN "check" ELSE "done"
              /\ result' = IF ok THEN result ELSE "integrityFailure"
         /\ UNCHANGED <<original, artifact, sany, lean, axioms,
                        interrupted, clock, translation>>

CheckSANY == /\ phase = "check" /\ sany = "pending"
             /\ sany' \in {"passed", "failed"}
             /\ UNCHANGED <<phase, original, artifact, audit, lean, axioms,
                            result, interrupted, clock, translation>>

CheckLean == /\ phase = "check" /\ lean = "pending"
             /\ lean' \in {"passed", "failed"}
             /\ UNCHANGED <<phase, original, artifact, audit, sany, axioms,
                            result, interrupted, clock, translation>>

AuditAxioms == /\ phase = "check" /\ lean = "passed" /\ axioms = "pending"
               /\ axioms' \in {"passed", "failed"}
               /\ UNCHANGED <<phase, original, artifact, audit, sany, lean,
                              result, interrupted, clock, translation>>

Finish == /\ phase = "check"
          /\ sany # "pending" /\ lean # "pending"
          /\ (lean = "failed" \/ axioms # "pending")
          /\ phase' = "done"
          /\ result' = IF sany = "passed" /\ lean = "passed" /\ axioms = "passed"
                        THEN "proved" ELSE "unproved"
          /\ UNCHANGED <<original, artifact, audit, sany, lean, axioms,
                         interrupted, clock, translation>>

Tick == /\ phase # "done" /\ clock < 2
        /\ clock' = clock + 1
        /\ UNCHANGED <<phase, original, artifact, audit, sany, lean, axioms,
                       result, interrupted, translation>>

Interrupt == /\ phase # "done"
             /\ interrupted' = TRUE
             /\ result' = "unknown"
             /\ phase' = "done"
             /\ UNCHANGED <<original, artifact, audit, sany, lean, axioms,
                            clock, translation>>

\* At the modeled deadline only interruption is enabled. Cancellation may
\* occur earlier. Terminal stuttering represents return to the caller.
Next == \/ (clock < 2 /\ (Generate \/ RejectGeneration \/ Audit \/ CheckSANY
                          \/ CheckLean \/ AuditAxioms \/ Finish \/ Tick))
        \/ Interrupt
Spec == Init /\ [][Next]_vars

ProofRequiresEvidence == result = "proved" =>
    audit = "passed" /\ sany = "passed" /\ lean = "passed" /\ axioms = "passed"
InterruptedCannotProve == interrupted => result = "unknown"
ModelProofIsNotSourceCertification == translation = "UNVALIDATED"
ExistingOutputIsPreserved == original = "existing" => artifact = "existing"
FailedGenerationIsAtomic == result = "generationFailed" => artifact = original

\* A deliberately false probe, enabled only in a disposable configuration,
\* demonstrates that the successful branch is reachable.
NeverProved == result # "proved"
=======================================================================
