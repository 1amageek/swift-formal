namespace ActorIsolation

-- SPEC sections 8.4 and 17.1: an actor's non-suspending check/update is one step.
structure State where
  stock : Nat
  accepted : Nat

def reserve (state : State) : State :=
  match state.stock with
  | 0 => state
  | n + 1 => { stock := n, accepted := state.accepted + 1 }

theorem reservationConservesCapacity (state : State) :
    (reserve state).stock + (reserve state).accepted = state.stock + state.accepted := by
  cases state with
  | mk stock accepted =>
    cases stock <;> simp [reserve, Nat.add_comm, Nat.add_left_comm]

def run : Nat → State → State
  | 0, state => state
  | n + 1, state => run n (reserve state)

theorem arbitraryAtomicSchedule (n : Nat) (state : State) :
    (run n state).stock + (run n state).accepted = state.stock + state.accepted := by
  induction n generalizing state with
  | zero => rfl
  | succ n ih =>
    simp only [run]
    rw [ih, reservationConservesCapacity]

theorem noOverselling (n capacity : Nat) :
    (run n { stock := capacity, accepted := 0 }).accepted ≤ capacity := by
  have h := arbitraryAtomicSchedule n { stock := capacity, accepted := 0 }
  change (run n { stock := capacity, accepted := 0 }).stock +
    (run n { stock := capacity, accepted := 0 }).accepted = capacity at h
  omega

structure ReentrantState where
  stock : Int
  accepted : Nat
  firstPC : Nat
  secondPC : Nat
  firstObserved : Bool
  secondObserved : Bool
  deriving DecidableEq

inductive Action where
  | checkFirst | checkSecond | resumeFirst | resumeSecond

def transition (state : ReentrantState) : Action → Option ReentrantState
  | .checkFirst => if state.firstPC = 0 then
      some { state with firstPC := 1, firstObserved := decide (state.stock > 0) } else none
  | .checkSecond => if state.secondPC = 0 then
      some { state with secondPC := 1, secondObserved := decide (state.stock > 0) } else none
  | .resumeFirst => if state.firstPC = 1 then
      some { state with
        firstPC := 2
        stock := if state.firstObserved then state.stock - 1 else state.stock
        accepted := if state.firstObserved then state.accepted + 1 else state.accepted } else none
  | .resumeSecond => if state.secondPC = 1 then
      some { state with
        secondPC := 2
        stock := if state.secondObserved then state.stock - 1 else state.stock
        accepted := if state.secondObserved then state.accepted + 1 else state.accepted } else none

def initial : ReentrantState := ⟨1, 0, 0, 0, false, false⟩
def firstChecked : ReentrantState := ⟨1, 0, 1, 0, true, false⟩
def bothChecked : ReentrantState := ⟨1, 0, 1, 1, true, true⟩
def firstAccepted : ReentrantState := ⟨0, 1, 2, 1, true, true⟩
def bothAccepted : ReentrantState := ⟨-1, 2, 2, 2, true, true⟩

-- Each edge of the counterexample follows the specified transition function.
theorem reentrantCounterexample :
    transition initial .checkFirst = some firstChecked ∧
    transition firstChecked .checkSecond = some bothChecked ∧
    transition bothChecked .resumeFirst = some firstAccepted ∧
    transition firstAccepted .resumeSecond = some bothAccepted ∧
    bothAccepted.stock < 0 ∧ bothAccepted.accepted > 1 := by decide

#print axioms reservationConservesCapacity
#print axioms arbitraryAtomicSchedule
#print axioms noOverselling
#print axioms reentrantCounterexample
end ActorIsolation
