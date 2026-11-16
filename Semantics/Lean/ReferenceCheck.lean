import SwiftFormal.SILDecoder

open SwiftFormal

private def certificate (program : Program) : String :=
  "import Generated.Program\n\nopen SwiftFormal\nnamespace ReferenceCheck\n\n" ++
  "def referenceProgram : Program :=\n  " ++
  (reprStr program).replace "\n" "\n  " ++ "\n\n" ++
  "theorem programDataEquality : referenceProgram = Generated.program := by rfl\n\n" ++
  "theorem stepEquality (before after : State) :\n" ++
  "  Step referenceProgram before after ↔ Step Generated.program before after := by\n" ++
  "  rw [programDataEquality]\n\n" ++
  "theorem reachabilityEquality (start finish : State) :\n" ++
  "  Reachable referenceProgram start finish ↔ Reachable Generated.program start finish := by\n" ++
  "  rw [programDataEquality]\n\n" ++
  "end ReferenceCheck\n\n" ++
  "#print axioms ReferenceCheck.programDataEquality\n" ++
  "#print axioms ReferenceCheck.stepEquality\n" ++
  "#print axioms ReferenceCheck.reachabilityEquality\n"

def main (arguments : List String) : IO UInt32 := do
  let sourcePath :: moduleID :: outputPath :: entries := arguments
    | do IO.eprintln "expected SIL path, module ID, certificate path, and entry symbols"; return 2
  if entries.isEmpty then
    IO.eprintln "explicit entry symbols are required"
    return 2
  let source ← IO.FS.readFile sourcePath
  match SwiftFormal.Reference.decode source moduleID entries with
  | .error error => IO.eprintln error; return 3
  | .ok program =>
    IO.FS.writeFile outputPath (certificate program)
    return 0
