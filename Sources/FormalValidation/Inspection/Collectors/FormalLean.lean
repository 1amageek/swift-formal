import Lean
import Lean.Replay
open Lean

private def formalKind : ConstantInfo → String
  | .thmInfo _ => "theorem"
  | .axiomInfo _ => "axiom"
  | .defnInfo _ => "definition"
  | .opaqueInfo _ => "opaque"
  | .inductInfo _ => "type"
  | .ctorInfo _ => "constructor"
  | .recInfo _ => "recursor"
  | .quotInfo _ => "quotient"

private def expressionKind : Expr → String
  | .app _ _ => "application"
  | .lam .. => "lambda"
  | .forallE .. => "forall"
  | .letE .. => "let"
  | .const .. => "constant"
  | .bvar _ => "boundVariable"
  | .fvar _ => "freeVariable"
  | .mvar _ => "metavariable"
  | .sort _ => "sort"
  | .lit _ => "literal"
  | .mdata .. => "metadata"
  | .proj .. => "projection"

private def children : Expr → Array Expr
  | .app f a => #[f,a]
  | .lam _ a b _ | .forallE _ a b _ => #[a,b]
  | .letE _ t v b _ => #[t,v,b]
  | .mdata _ e | .proj _ _ e => #[e]
  | _ => #[]

private def expressionLabel : Expr → String
  | .const name _ => name.toString
  | .bvar index => toString index
  | .lit (.natVal value) => toString value
  | .lit (.strVal value) => value
  | value => expressionKind value

-- The trusted script imports only Lean. Target .olean files are loaded as data
-- with extensions/initializers disabled, then independently replayed by the kernel.
-- No imported Environment/Expr value escapes withImportModules' resource lifetime.
unsafe def main (arguments : List String) : IO UInt32 := do
  let [sysroot,inputRoot,moduleName,rootName,limitText,termLimitText] := arguments |
    throw <| IO.userError "Expected sysroot, captured input root, module, declaration and two budgets"
  let some maximum := limitText.toNat? | throw <| IO.userError "Invalid dependency budget"
  let some termMaximum := termLimitText.toNat? | throw <| IO.userError "Invalid expression budget"
  if maximum == 0 || termMaximum == 0 then throw <| IO.userError "Empty inspection budget"
  initSearchPath ⟨sysroot⟩
  searchPathRef.modify fun paths => ⟨inputRoot⟩ :: paths
  if ← isInitializerExecutionEnabled then throw <| IO.userError "Imported initializer execution must be disabled"
  withImportModules #[{module := moduleName.toName}] {} fun env => do
    let root := rootName.toName
    let some rootInfo := env.find? root | throw <| IO.userError "Missing checked declaration"
    if rootInfo.isUnsafe || rootInfo.isPartial then
      throw <| IO.userError "Unsafe/partial declaration has no checked kernel replay capability"
    -- Replay only the complete kernel dependency closure. Inductive families and
    -- their constructors must be included together for Lean.Replay's consistency
    -- checks; unrelated imported tactic declarations are outside this claim.
    let mut replayPending := #[root]
    let mut replayConstants : Std.HashMap Name ConstantInfo := {}
    let mut replayPosition := 0
    while replayPosition < replayPending.size do
      let name := replayPending[replayPosition]!
      replayPosition := replayPosition + 1
      if replayConstants.contains name then continue
      if replayConstants.size >= maximum then throw <| IO.userError "Kernel dependency budget exhausted"
      let some info := env.find? name | throw <| IO.userError "Missing kernel dependency"
      replayConstants := replayConstants.insert name info
      for dependency in info.getUsedConstantsAsSet do
        if !replayConstants.contains dependency then replayPending := replayPending.push dependency
      match info with
      | .inductInfo value =>
        for dependency in value.all ++ value.ctors do
          if !replayConstants.contains dependency then replayPending := replayPending.push dependency
      | .ctorInfo value =>
        if !replayConstants.contains value.induct then replayPending := replayPending.push value.induct
      | _ => pure ()
    let empty ← mkEmptyEnvironment
    let replayed ← empty.toKernelEnv.replay replayConstants
    let some checkedRoot := replayed.find? root | throw <| IO.userError "Root was not kernel replayed"
    if checkedRoot.type != rootInfo.type then throw <| IO.userError "Replayed root type mismatch"
    let mut pending := #[root]
    let mut seen : NameSet := {}
    let mut records : Array Json := #[]
    let mut axioms : Array String := #[]
    let mut position := 0
    while position < pending.size do
      let name := pending[position]!
      position := position + 1
      if seen.contains name then continue
      if seen.size >= maximum then throw <| IO.userError "Formal dependency budget exhausted"
      seen := seen.insert name
      let some info := env.find? name | throw <| IO.userError "Missing dependency"
      let typeUses := info.type.getUsedConstants
      let value := info.value? (allowOpaque := true)
      let valueUses := value.map Expr.getUsedConstants |>.getD #[]
      if formalKind info == "axiom" then axioms := axioms.push name.toString
      records := records.push <| Json.mkObj [
        ("name",toJson name.toString),("kind",toJson (formalKind info)),
        ("typeUses",toJson (typeUses.map Name.toString)),
        ("valueUses",toJson (valueUses.map Name.toString)),
        ("bodyAvailable",toJson value.isSome)]
      for dependency in typeUses ++ valueUses do
        if !seen.contains dependency then pending := pending.push dependency
    let mut termPending : Array (Expr × String) := #[]
    if let some value := rootInfo.value? (allowOpaque := true) then termPending := #[(value,"0")]
    let mut terms : Array Json := #[]
    let mut index := 0
    while index < termPending.size do
      if index >= termMaximum then throw <| IO.userError "Formal expression budget exhausted"
      let (expression,path) := termPending[index]!
      index := index + 1
      let descendants := children expression
      let mut ids : Array String := #[]
      for childIndex in [:descendants.size] do
        let childPath := path ++ "." ++ toString childIndex
        ids := ids.push childPath
        termPending := termPending.push (descendants[childIndex]!,childPath)
      terms := terms.push <| Json.mkObj [
        ("id",toJson path),("kind",toJson (expressionKind expression)),
        ("label",toJson (expressionLabel expression)),("children",toJson ids)]
    let output := Json.mkObj [
      ("schemaVersion",toJson (1 : Nat)),("root",toJson root.toString),
      ("kernelReplayed",toJson true),("axioms",toJson axioms),
      ("records",toJson records),("terms",toJson terms)]
    IO.println ("FORMAL_GRAPH_JSON " ++ output.compress)
    return 0
