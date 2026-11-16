import Std

namespace SwiftFormal

inductive ValueType where
  | integer
  | bits (width : Nat)
  | aggregate (elements : List ValueType)
  | function (parameters : List ValueType) (result : ValueType)
  deriving Repr, BEq

structure Parameter where
  id : String
  type : ValueType
  deriving Repr, BEq

inductive Value where
  | integer (value : Int)
  | bits (width : Nat) (value : Nat)
  | aggregate (elements : List Value)
  | function (symbol : String)
  deriving Repr, BEq

inductive Operation where
  | signedAddOverflow | signedSubtractOverflow | signedMultiplyOverflow
  | unsignedAddOverflow | unsignedSubtractOverflow | unsignedMultiplyOverflow
  | signedLessThan | unsignedLessThan | equal | and | or | xor
  | numberAdd | numberSubtract | numberMultiply | numberDivide | numberRemainder | numberNegate | numberAbsolute | numberEqual | numberLessThan | numberLessEqual | numberSameValue | numberIsNaN | numberIsFinite | numberIsInteger | numberIsSafeInteger | numberTruthy
  deriving Repr, BEq

inductive IntegerOperation where
  | add | subtract | multiply | lessThan | equal
  deriving Repr, BEq

inductive FailureKind where
  | panic | undefinedBehavior
  deriving Repr, BEq

inductive Instruction where
  | integerLiteral (destination : String) (negative magnitude : Nat)
  | integerBinary (destination : String) (operation : IntegerOperation) (left right : String)
  | failIf (condition : String) (kind : FailureKind) (message : String)
  | literal (destination : String) (width value : Nat)
  | aggregate (destination : String) (elements : List String)
  | extract (destination source : String) (index : Nat)
  | binary (destination : String) (operation : Operation) (left right : String)
  | functionRef (destination symbol : String)
  | call (destination callee : String) (arguments : List String)
  | jump (block : String) (arguments : List String)
  | branch (condition thenBlock : String) (thenArguments : List String) (elseBlock : String) (elseArguments : List String)
  | trapIf (condition message : String)
  | returnValue (source : String)
  deriving Repr, BEq

structure Block where
  id : String
  parameters : List Parameter
  instructions : List Instruction
  deriving Repr, BEq

structure Function where
  moduleID : String
  symbol : String
  result : ValueType
  blocks : List Block
  deriving Repr, BEq

abbrev Program := List Function
abbrev Environment := List (String × Value)

structure Frame where
  function : String
  block : String
  pc : Nat
  values : Environment
  destination : Option String
  deriving Repr, BEq

inductive Status where
  | running | returned (value : Value) | trapped (message : String)
  | failed (kind : FailureKind) (message : String)
  deriving Repr, BEq

structure State where
  frames : List Frame
  status : Status
  deriving Repr, BEq

def lookup (values : Environment) (id : String) : Option Value :=
  (values.find? fun pair => pair.1 == id).map Prod.snd

def assign (values : Environment) (id : String) (value : Value) : Environment :=
  (id, value) :: values.filter (fun pair => pair.1 != id)

def arguments (values : Environment) (ids : List String) : Option (List Value) :=
  ids.mapM (lookup values)

def bind (values : Environment) (parameters : List Parameter) (actual : List Value) : Option Environment :=
  if parameters.length == actual.length then
    some (((parameters.map Parameter.id).zip actual).foldl (fun env pair => assign env pair.1 pair.2) values)
  else none

def signed (width value : Nat) : Int :=
  if value < 2 ^ (width - 1) then Int.ofNat value else Int.ofNat value - Int.ofNat (2 ^ width)

def flag (value : Bool) : Value := .bits 1 (if value then 1 else 0)

def numberAbs (a : Nat) : Nat := a % 9223372036854775808
def numberNaN (a : Nat) : Bool := numberAbs a > 9218868437227405312
def numberFinite (a : Nat) : Bool := numberAbs a < 9218868437227405312
def numberCanon (a : Nat) : Nat := if numberNaN a then 9221120237041090560 else a
def numberNeg (a : Nat) : Nat :=
  if numberNaN a then 9221120237041090560
  else if a < 9223372036854775808 then 9223372036854775808 + a else a % 9223372036854775808
def numberEq (a b : Nat) : Bool :=
  !numberNaN a && !numberNaN b && (a == b || (numberAbs a == 0 && numberAbs b == 0))
def numberLt (a b : Nat) : Bool :=
  !numberNaN a && !numberNaN b && !(numberAbs a == 0 && numberAbs b == 0) &&
    (if (a < 9223372036854775808) != (b < 9223372036854775808) then a ≥ 9223372036854775808
     else if a ≥ 9223372036854775808 then numberAbs b < numberAbs a else numberAbs a < numberAbs b)
def numberInteger (a : Nat) : Bool :=
  let e := a / 4503599627370496 % 2048
  numberFinite a && (if e < 1023 then numberAbs a == 0 else if e ≥ 1075 then true else a % 4503599627370496 % 2 ^ (1075 - e) == 0)
def numberExponent (a : Nat) : Int :=
  Int.ofNat (max 1 (a / 4503599627370496 % 2048)) - 1075
def numberMantissa (a : Nat) : Nat :=
  a % 4503599627370496 + if a / 4503599627370496 % 2048 == 0 then 0 else 4503599627370496
def numberRem (a b : Nat) : Nat :=
  if numberNaN a || numberNaN b || numberAbs a == 9218868437227405312 || numberAbs b == 0 then 9221120237041090560
  else if numberAbs b == 9218868437227405312 || numberAbs a == 0 then numberCanon a
  else
    let e := min (numberExponent a) (numberExponent b)
    let n := numberMantissa a * 2 ^ (numberExponent a - e).toNat
    let d := numberMantissa b * 2 ^ (numberExponent b - e).toNat
    let sign := if a < 9223372036854775808 then Float.Model.UnpackedFloat.Sign.positive else .negative
    let rounded := Float.Model.UnpackedFloat.round Float.Model.Format.binary64 sign (n % d) e
    numberCanon (Float.Model.pack rounded).toBits.toNat

inductive NumberArithmeticOperation where
  | add | subtract | multiply | divide | remainder
  deriving Repr, BEq

def numberArithmetic (op : NumberArithmeticOperation) (a b : Nat) : Nat :=
  let x := Float.ofBits (UInt64.ofNat a)
  let y := Float.ofBits (UInt64.ofNat b)
  match op with
  | .add => numberCanon (x + y).toBits.toNat
  | .subtract => numberCanon (x - y).toBits.toNat
  | .multiply => numberCanon (x * y).toBits.toNat
  | .divide => numberCanon (x / y).toBits.toNat
  | .remainder => numberRem a b

def numberBinary (op : Operation) (a b : Nat) : Option Value :=
  match op with
  | .numberNegate => some (.bits 64 (numberNeg a))
  | .numberAbsolute => some (.bits 64 (numberCanon (numberAbs a)))
  | .numberEqual => some (flag (numberEq a b))
  | .numberLessThan => some (flag (numberLt a b))
  | .numberLessEqual => some (flag (numberLt a b || numberEq a b))
  | .numberSameValue => some (flag ((numberNaN a && numberNaN b) || a == b))
  | .numberIsNaN => some (flag (numberNaN a))
  | .numberIsFinite => some (flag (numberFinite a))
  | .numberIsInteger => some (flag (numberInteger a))
  | .numberIsSafeInteger => some (flag (numberInteger a && numberAbs a ≤ 4845873199050653695))
  | .numberTruthy => some (flag (!numberNaN a && numberAbs a != 0))
  | .numberAdd => some (.bits 64 (numberArithmetic .add a b))
  | .numberSubtract => some (.bits 64 (numberArithmetic .subtract a b))
  | .numberMultiply => some (.bits 64 (numberArithmetic .multiply a b))
  | .numberDivide => some (.bits 64 (numberArithmetic .divide a b))
  | .numberRemainder => some (.bits 64 (numberArithmetic .remainder a b))
  | _ => none

theorem numberCanonBound (n : Nat) (h : n < 18446744073709551616) : numberCanon n < 18446744073709551616 := by
  unfold numberCanon
  split <;> omega
theorem numberRemBound (a b : Nat) (h : a < 18446744073709551616) : numberRem a b < 18446744073709551616 := by
  unfold numberRem
  split
  · omega
  · split
    · exact numberCanonBound a h
    · apply numberCanonBound
      exact UInt64.toNat_lt _
theorem numberArithmeticBound (op : NumberArithmeticOperation) (a b : Nat) (h : a < 18446744073709551616) : numberArithmetic op a b < 18446744073709551616 := by
  cases op <;> unfold numberArithmetic
  all_goals first | exact numberRemBound a b h | (apply numberCanonBound; exact UInt64.toNat_lt _)
theorem numberArithmeticFits (op : NumberArithmeticOperation) (a b : Nat) (h : a < 18446744073709551616) : ¬ (18446744073709551616 ≤ numberArithmetic op a b) := by
  have bound := numberArithmeticBound op a b h
  omega

theorem numberNegBound (a : Nat) (h : a < 18446744073709551616) : numberNeg a < 18446744073709551616 := by
  unfold numberNeg
  split
  · omega
  · split
    · omega
    · have bound := Nat.mod_lt a (by decide : 0 < 9223372036854775808)
      omega

theorem numberNegFits (a : Nat) (h : a < 18446744073709551616) : ¬ (18446744073709551616 ≤ numberNeg a) := by
  have bound := numberNegBound a h
  omega

def overflowResult (width : Nat) (mathematical : Int) (isSigned : Bool) : Value :=
  let modulus := Int.ofNat (2 ^ width)
  let wrapped := (mathematical % modulus).toNat
  let overflow := if isSigned then
    decide (mathematical < -(Int.ofNat (2 ^ (width - 1))) ∨ mathematical ≥ Int.ofNat (2 ^ (width - 1)))
    else decide (mathematical < 0 ∨ mathematical ≥ modulus)
  .aggregate [.bits width wrapped, flag overflow]

def binary (operation : Operation) (left right : Value) : Option Value := do
  let .bits width a := left | none
  let .bits otherWidth b := right | none
  if width == 0 || width != otherWidth || a ≥ 2 ^ width || b ≥ 2 ^ width then none else
    match operation with
    | .signedAddOverflow => some (overflowResult width (signed width a + signed width b) true)
    | .signedSubtractOverflow => some (overflowResult width (signed width a - signed width b) true)
    | .signedMultiplyOverflow => some (overflowResult width (signed width a * signed width b) true)
    | .unsignedAddOverflow => some (overflowResult width (Int.ofNat a + Int.ofNat b) false)
    | .unsignedSubtractOverflow => some (overflowResult width (Int.ofNat a - Int.ofNat b) false)
    | .unsignedMultiplyOverflow => some (overflowResult width (Int.ofNat a * Int.ofNat b) false)
    | .signedLessThan => some (flag (decide (signed width a < signed width b)))
    | .unsignedLessThan => some (flag (a < b))
    | .equal => some (flag (a == b))
    | .and => some (.bits width (Nat.land a b))
    | .or => some (.bits width (Nat.lor a b))
    | .xor => some (.bits width (Nat.xor a b))
    | .numberAdd | .numberSubtract | .numberMultiply | .numberDivide | .numberRemainder | .numberNegate | .numberAbsolute | .numberEqual | .numberLessThan | .numberLessEqual | .numberSameValue | .numberIsNaN | .numberIsFinite | .numberIsInteger | .numberIsSafeInteger | .numberTruthy => if width == 64 then numberBinary operation a b else none

def integerBinary (operation : IntegerOperation) (left right : Value) : Option Value := do
  let .integer a := left | none
  let .integer b := right | none
  pure (match operation with
    | .add => .integer (a + b)
    | .subtract => .integer (a - b)
    | .multiply => .integer (a * b)
    | .lessThan => flag (decide (a < b))
    | .equal => flag (a == b))

def findFunction (program : Program) (symbol : String) : Option Function :=
  program.find? (fun function => function.symbol == symbol)

def findBlock (function : Function) (id : String) : Option Block :=
  function.blocks.find? (fun block => block.id == id)

def jump (function : Function) (frame : Frame) (target : String) (ids : List String) : Option Frame := do
  let block ← findBlock function target
  let actual ← arguments frame.values ids
  let values ← bind frame.values block.parameters actual
  pure { frame with block := target, pc := 0, values := values }

def tick (program : Program) (state : State) : Option State := do
  if state.status != .running then none else do
    let frame :: rest := state.frames | none
    let function ← findFunction program frame.function
    let block ← findBlock function frame.block
    let instruction ← block.instructions[frame.pc]?
    let advance (id : String) (value : Value) : State :=
      { state with frames := { frame with pc := frame.pc + 1, values := assign frame.values id value } :: rest }
    match instruction with
    | .integerLiteral destination negative magnitude =>
      if negative > 1 then none else
        pure (advance destination (.integer (if negative == 1 then -(Int.ofNat magnitude) else Int.ofNat magnitude)))
    | .integerBinary destination operation left right =>
      let a ← lookup frame.values left
      let b ← lookup frame.values right
      let value ← integerBinary operation a b
      pure (advance destination value)
    | .failIf condition kind message =>
      let .bits 1 bit ← lookup frame.values condition | none
      if bit > 1 then none else if bit == 1 then pure { state with status := .failed kind message }
      else pure { state with frames := { frame with pc := frame.pc + 1 } :: rest }
    | .literal destination width value =>
      if width == 0 || value ≥ 2 ^ width then none else pure (advance destination (.bits width value))
    | .aggregate destination ids =>
      let values ← arguments frame.values ids
      pure (advance destination (.aggregate values))
    | .extract destination source index =>
      let .aggregate values ← lookup frame.values source | none
      let value ← values[index]?
      pure (advance destination value)
    | .binary destination operation left right =>
      let a ← lookup frame.values left
      let b ← lookup frame.values right
      let value ← binary operation a b
      pure (advance destination value)
    | .functionRef destination symbol =>
      let _ ← findFunction program symbol
      pure (advance destination (.function symbol))
    | .call destination callee ids =>
      let .function symbol ← lookup frame.values callee | none
      let target ← findFunction program symbol
      let initial ← target.blocks.head?
      let actual ← arguments frame.values ids
      let values ← bind [] initial.parameters actual
      let caller := { frame with pc := frame.pc + 1 }
      let child : Frame := { function := symbol, block := initial.id, pc := 0, values := values, destination := some destination }
      pure { state with frames := child :: caller :: rest }
    | .jump target ids =>
      let next ← jump function frame target ids
      pure { state with frames := next :: rest }
    | .branch condition thenBlock thenArguments elseBlock elseArguments =>
      let .bits 1 bit ← lookup frame.values condition | none
      if bit > 1 then none else do
        let next ← if bit == 1 then jump function frame thenBlock thenArguments else jump function frame elseBlock elseArguments
        pure { state with frames := next :: rest }
    | .trapIf condition message =>
      let .bits 1 bit ← lookup frame.values condition | none
      if bit > 1 then none else if bit == 1 then pure { state with status := .trapped message }
      else pure { state with frames := { frame with pc := frame.pc + 1 } :: rest }
    | .returnValue source =>
      let returned ← lookup frame.values source
      match rest with
      | [] => pure { frames := [], status := .returned returned }
      | caller :: ancestors =>
        let destination ← frame.destination
        pure { state with frames := { caller with values := assign caller.values destination returned } :: ancestors }

def initial (program : Program) (entry : String) (actual : List Value) : Option State := do
  let function ← findFunction program entry
  let block ← function.blocks.head?
  let values ← bind [] block.parameters actual
  let frame : Frame := { function := entry, block := block.id, pc := 0, values := values, destination := none }
  pure { frames := [frame], status := .running }

inductive Step (program : Program) : State → State → Prop where
  | execute {before after : State} : tick program before = some after → Step program before after

inductive Reachable (program : Program) (start : State) : State → Prop where
  | initial : Reachable program start start
  | next {before after : State} : Reachable program start before → Step program before after → Reachable program start after

def InfiniteExecution (program : Program) (states : Nat → State) : Prop :=
  ∀ n, Step program (states n) (states (n + 1))

inductive Evaluation where
  | terminal (state : State)
  | outOfFuel (state : State)
  | stuck (state : State)
  deriving Repr, BEq

def evaluate (program : Program) : Nat → State → Evaluation
  | 0, state => .outOfFuel state
  | fuel + 1, state =>
    if state.status != .running then .terminal state else
    match tick program state with
    | some next => evaluate program fuel next
    | none => .stuck state

end SwiftFormal
