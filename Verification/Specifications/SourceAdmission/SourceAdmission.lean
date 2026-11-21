/- Requirements-derived source admission contract. Source classification is
   an assumption; this model does not implement or certify Swift parsing. -/
namespace SourceAdmission
inductive SourceKind where
  | supported | malformedScalar | outsideProfile
  deriving DecidableEq
inductive Outcome where
  | draft | parseFailed | unsupported
  deriving DecidableEq

def classify : SourceKind → Outcome × Nat
  | .supported => (.draft, 0)
  | .malformedScalar => (.parseFailed, 4)
  | .outsideProfile => (.unsupported, 3)

def commits (kind : SourceKind) : Bool := decide (kind = .supported)

theorem unsupportedIsDistinct : classify .outsideProfile = (.unsupported, 3) := rfl
theorem malformedIsDistinct : classify .malformedScalar = (.parseFailed, 4) := rfl
theorem rejectedCannotCommit (kind : SourceKind) (h : kind ≠ .supported) :
    commits kind = false := by simp [commits, h]
theorem successfulGenerationIsDraft (kind : SourceKind)
    (h : (classify kind).2 = 0) : (classify kind).1 = .draft := by
  cases kind <;> simp_all [classify]

#print axioms unsupportedIsDistinct
#print axioms malformedIsDistinct
#print axioms rejectedCannotCommit
#print axioms successfulGenerationIsDraft
end SourceAdmission
