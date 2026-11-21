------------------------- MODULE SourceAdmission -------------------------
EXTENDS Naturals
\* Derived from SPEC.md A11 and the source-profile failure contract.
\* Source kind is an explicit assumption, not a Swift syntax oracle.
VARIABLES kind, phase, outcome, exitCode, artifact, translation
vars == <<kind, phase, outcome, exitCode, artifact, translation>>
Init == /\ kind \in {"supported", "malformedScalar", "outsideProfile"}
        /\ phase = "parse" /\ outcome = "pending" /\ exitCode = "pending"
        /\ artifact = FALSE /\ translation = "UNVALIDATED"
Classify == /\ phase = "parse"
            /\ phase' = IF kind = "supported" THEN "emit" ELSE "done"
            /\ outcome' = CASE kind = "outsideProfile" -> "unsupported"
                              [] kind = "malformedScalar" -> "parseFailed"
                              [] OTHER -> "draft"
            /\ exitCode' = CASE kind = "outsideProfile" -> 3
                               [] kind = "malformedScalar" -> 4
                               [] OTHER -> 0
            /\ UNCHANGED <<kind, artifact, translation>>
Commit == /\ phase = "emit" /\ phase' = "done" /\ artifact' = TRUE
          /\ UNCHANGED <<kind, outcome, exitCode, translation>>
Next == Classify \/ Commit
Spec == Init /\ [][Next]_vars
CorrectClassification == phase # "parse" =>
    /\ (kind = "outsideProfile" => outcome = "unsupported" /\ exitCode = 3)
    /\ (kind = "malformedScalar" => outcome = "parseFailed" /\ exitCode = 4)
NoRejectedArtifact == kind # "supported" => ~artifact
NoFalseProof == translation = "UNVALIDATED" /\ outcome # "proved"
DraftReachable == ~artifact
===========================================================================
