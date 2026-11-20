/- Requirements: Documentation/SPEC.md sections 2.2, 15.1 and 17/A26.
   Properties/DESIGN.md defines the current quantified-result contract.
   This decision function specifies the contract independently of Swift. -/
namespace VerificationOutcome

inductive Outcome where
  | proved | unproved | unknown | integrityFailure
  deriving DecidableEq

def classify (audit sany lean axioms completed interrupted : Bool) : Outcome :=
  if interrupted then .unknown
  else if !audit then .integrityFailure
  else if !completed then .unknown
  else if sany && lean && axioms then .proved
  else .unproved

theorem proofRequiresEvidence (audit sany lean axioms completed interrupted : Bool)
    (h : classify audit sany lean axioms completed interrupted = .proved) :
    audit = true ∧ sany = true ∧ lean = true ∧ axioms = true ∧
      completed = true ∧ interrupted = false := by
  cases audit <;> cases sany <;> cases lean <;> cases axioms <;>
    cases completed <;> cases interrupted <;> simp_all [classify]

theorem interruptionIsUnknown (audit sany lean axioms completed : Bool) :
    classify audit sany lean axioms completed true = .unknown := by
  simp [classify]

theorem badAuditCannotProve (sany lean axioms completed interrupted : Bool) :
    classify false sany lean axioms completed interrupted ≠ .proved := by
  cases interrupted <;> simp [classify]

theorem incompleteCannotProve (audit sany lean axioms interrupted : Bool) :
    classify audit sany lean axioms false interrupted ≠ .proved := by
  cases interrupted <;> cases audit <;> simp [classify]

/- Positive and boundary witnesses keep the premises demonstrably satisfiable. -/
example : classify true true true true true false = .proved := rfl
example : classify true true true false true false = .unproved := rfl
example : classify true true true true true true = .unknown := rfl

#print axioms proofRequiresEvidence
#print axioms interruptionIsUnknown
#print axioms badAuditCannotProve
#print axioms incompleteCannotProve
end VerificationOutcome
