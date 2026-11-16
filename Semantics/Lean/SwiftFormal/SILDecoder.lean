import Lean
import SwiftFormal.Runtime

private def Option.toExcept {α : Type} (value : Option α) (message : String) : Except String α :=
  match value with
  | some result => .ok result
  | none => .error message

namespace SwiftFormal.Reference

abbrev Decode := Except String

private def punctuation (character : Char) : Bool :=
  ['(', ')', '[', ']', '{', '}', ',', ':', '='].contains character

private partial def quoted : List Char → String → Decode (String × List Char)
  | [], _ => .error "unterminated SIL string"
  | '\n' :: _, _ => .error "newline in SIL string"
  | '"' :: rest, value => .ok (value.push '"', rest)
  | '\\' :: character :: rest, value => quoted rest ((value.push '\\').push character)
  | character :: rest, value => quoted rest (value.push character)

private partial def word : List Char → String → String × List Char
  | [], value => (value, [])
  | characters@(character :: rest), value =>
    if character.isWhitespace || punctuation character || character == '"' then (value, characters)
    else if character == '/' && rest.head? == some '/' then (value, characters)
    else word rest (value.push character)

private partial def skipComment : List Char → List Char
  | [] => []
  | characters@('\n' :: _) => characters
  | _ :: rest => skipComment rest

private partial def lex : List Char → Array String → Decode (Array String)
  | [], tokens => .ok tokens
  | '\n' :: rest, tokens => lex rest (tokens.push "\n")
  | '/' :: '/' :: rest, tokens => lex (skipComment rest) tokens
  | '"' :: rest, tokens => do
    let (text, remaining) ← quoted rest "\""
    lex remaining (tokens.push text)
  | '-' :: '>' :: rest, tokens => lex rest (tokens.push "->")
  | character :: rest, tokens =>
    if character.isWhitespace then lex rest tokens
    else if punctuation character then lex rest (tokens.push (String.singleton character))
    else
      let (text, remaining) := word (character :: rest) ""
      if text.isEmpty then .error "invalid SIL token" else lex remaining (tokens.push text)

private def records (tokens : Array String) : Decode (Array (Array String)) := do
  let mut output := #[]
  let mut record := #[]
  let mut nesting : List String := []
  for token in tokens do
    if token == "\n" then
      if nesting.isEmpty && record.back? != some "," then
        if !record.isEmpty then output := output.push record
        record := #[]
    else
      if token == "(" || token == "[" then nesting := token :: nesting
      else if token == ")" || token == "]" then
        let opening := if token == ")" then "(" else "["
        if nesting.head? != some opening then throw "mismatched SIL delimiter"
        nesting := nesting.tail
      record := record.push token
  if !nesting.isEmpty then throw "unterminated SIL delimiter"
  if !record.isEmpty then output := output.push record
  return output

private structure RawFunction where
  symbol : String
  header : Array String
  body : Array (Array String)

private def functions (input : Array (Array String)) : Decode (List RawFunction) := do
  let mut output := []
  let mut current : Option RawFunction := none
  for record in input do
    match current with
    | some function =>
      if record == #["}"] then
        if output.any (fun prior => prior.symbol == function.symbol) then throw "duplicate SIL body"
        output := output ++ [function]
        current := none
      else current := some { function with body := function.body.push record }
    | none =>
      if record[0]? == some "sil" && record.back? == some "{" then
        let colon ← record.findIdx? (fun token => token == ":") |>.toExcept "missing SIL function type"
        if colon == 0 then throw "missing SIL symbol"
        let symbol ← record[colon - 1]?.toExcept "missing SIL symbol"
        if !symbol.startsWith "@" then throw "invalid SIL symbol"
        current := some { symbol := symbol.drop 1 |>.toString, header := record, body := #[] }
  if current.isSome then throw "unterminated SIL function"
  return output

private structure Cursor where
  tokens : Array String
  position : Nat := 0

private abbrev Parser := StateT Cursor Decode

private def take : Parser String := do
  let cursor ← get
  let token ← cursor.tokens[cursor.position]?.toExcept "unexpected SIL record end"
  set { cursor with position := cursor.position + 1 }
  return token

private def peek : Parser (Option String) := do
  let cursor ← get
  return cursor.tokens[cursor.position]?

private def accept (token : String) : Parser Bool := do
  if (← peek) == some token then
    let _ ← take
    return true
  return false

private def expect (token : String) : Parser Unit := do
  let actual ← take
  if actual != token then throw s!"expected {token}, found {actual}"

private def endRecord : Parser Unit := do
  if (← peek).isSome then throw "unexpected trailing SIL tokens"

private def unwrapDollar (text : String) : String :=
  if text.startsWith "$" then text.drop 1 |>.toString else text

private partial def parseType : Parser ValueType := do
  let _ ← accept "$"
  if (← accept "(") then
    let mut elements := []
    if !(← accept ")") then
      elements := [← parseType]
      while (← accept ",") do elements := elements ++ [← parseType]
      expect ")"
    return .aggregate elements
  let name := unwrapDollar (← take)
  if name.startsWith "Builtin.Int" then
    let width ← (name.drop "Builtin.Int".length).toString.toNat? |>.toExcept "invalid bit width"
    if width == 0 || width > 64 then throw "unsupported bit width"
    return .bits width
  let widths := [("Bool", 1), ("Int8", 8), ("UInt8", 8), ("Int16", 16), ("UInt16", 16),
                 ("Int32", 32), ("UInt32", 32), ("Int64", 64), ("UInt64", 64)]
  let (_, width) ← widths.find? (fun pair => pair.1 == name) |>.toExcept s!"unsupported type {name}"
  return .aggregate [.bits width]

private def functionType : Parser (List ValueType × ValueType) := do
  expect "$@convention"
  expect "("
  expect "thin"
  expect ")"
  expect "("
  let mut parameters := []
  if !(← accept ")") then
    parameters := [← parseType]
    while (← accept ",") do parameters := parameters ++ [← parseType]
    expect ")"
  expect "->"
  let result ← parseType
  return (parameters, result)

private def valueID : Parser String := do
  let value ← take
  if !value.startsWith "%" || value.length < 2 || !(value.drop 1).toString.toNat?.isSome then
    throw "invalid SSA operand"
  return value

private def valueList : Parser (List String) := do
  expect "("
  let mut values := []
  if !(← accept ")") then
    values := [← valueID]
    while (← accept ",") do values := values ++ [← valueID]
    expect ")"
  return values

private def unquote (text : String) : Decode String := do
  match Lean.Json.parse text with
  | .ok (.str value) => return value
  | _ => throw "unsupported SIL quoted string"

private def operation (name : String) : Decode Operation :=
  match name with
  | "sadd_with_overflow" => .ok .signedAddOverflow
  | "ssub_with_overflow" => .ok .signedSubtractOverflow
  | "smul_with_overflow" => .ok .signedMultiplyOverflow
  | "uadd_with_overflow" => .ok .unsignedAddOverflow
  | "usub_with_overflow" => .ok .unsignedSubtractOverflow
  | "umul_with_overflow" => .ok .unsignedMultiplyOverflow
  | "cmp_slt" => .ok .signedLessThan
  | "cmp_ult" => .ok .unsignedLessThan
  | "cmp_eq" => .ok .equal
  | "and" => .ok .and
  | "or" => .ok .or
  | "xor" => .ok .xor
  | _ => .error s!"unsupported builtin {name}"

private def parseInstruction (record : Array String) : Decode (Option Instruction) := do
  let parser : Parser (Option Instruction) := do
    let hasResult := record[0]?.any (fun text => text.startsWith "%")
    let destination ← if hasResult then valueID else pure ""
    if hasResult then expect "="
    let opcode ← take
    if opcode == "debug_value" then
      if hasResult then throw "debug metadata has result"
      return none
    let instruction ← match opcode with
    | "integer_literal" => do
      if !hasResult then throw "literal needs result"
      let .bits width ← parseType | throw "literal needs bits"
      expect ","
      let text ← take
      let value ← text.toInt?.toExcept "invalid integer literal"
      if value < -(Int.ofNat (2^(width - 1))) || value >= Int.ofNat (2^width) then
        throw "integer literal outside declared width"
      pure (.literal destination width (value % Int.ofNat (2^width)).toNat)
    | "struct" => do
      let .aggregate _ ← parseType | throw "unsupported struct"
      pure (.aggregate destination (← valueList))
    | "tuple" => pure (.aggregate destination (← valueList))
    | "struct_extract" => do
      let source ← valueID
      expect ","
      let field ← take
      if !field.startsWith "#" || !field.endsWith "._value" then throw "unsupported nominal field"
      pure (.extract destination source 0)
    | "tuple_extract" => do
      let source ← valueID
      expect ","
      let index ← (← take).toNat?.toExcept "invalid tuple projection"
      pure (.extract destination source index)
    | "builtin" => do
      let name ← unquote (← take)
      let parts := name.splitOn "_"
      let widthText ← parts.getLast?.toExcept "missing builtin width"
      if !widthText.startsWith "Int" then throw "unsupported builtin type"
      let width ← (widthText.drop 3).toString.toNat?.toExcept "invalid builtin width"
      if width == 0 || width > 64 then throw "unsupported builtin width"
      let op ← operation (String.intercalate "_" parts.dropLast)
      let values ← valueList
      let overflow := name.contains 'o' && (name.splitOn "_").contains "overflow"
      if values.length != (if overflow then 3 else 2) then throw "builtin arity mismatch"
      expect ":"
      let _ ← parseType
      let left ← values[0]?.toExcept "missing left operand"
      let right ← values[1]?.toExcept "missing right operand"
      pure (.binary destination op left right)
    | "function_ref" => do
      let symbol ← take
      if !symbol.startsWith "@" then throw "invalid function reference"
      expect ":"
      let _ ← functionType
      pure (.functionRef destination (symbol.drop 1 |>.toString))
    | "apply" => do
      let callee ← valueID
      let values ← valueList
      expect ":"
      let _ ← functionType
      pure (.call destination callee values)
    | "cond_fail" => do
      if hasResult then throw "trap has result"
      let condition ← valueID
      expect ","
      pure (.trapIf condition (← unquote (← take)))
    | "br" => do
      if hasResult then throw "branch has result"
      let target ← take
      let values ← if (← peek) == some "(" then valueList else pure []
      pure (.jump target values)
    | "cond_br" => do
      if hasResult then throw "branch has result"
      let condition ← valueID
      expect ","
      let thenBlock ← take
      let thenArguments ← if (← peek) == some "(" then valueList else pure []
      expect ","
      let elseBlock ← take
      let elseArguments ← if (← peek) == some "(" then valueList else pure []
      pure (.branch condition thenBlock thenArguments elseBlock elseArguments)
    | "return" => do
      if hasResult then throw "return has result"
      pure (.returnValue (← valueID))
    | _ => throw s!"unsupported SIL opcode {opcode}"
    endRecord
    return some instruction
  return (← parser.run { tokens := record }).1

private def parameters (record : Array String) : Decode (String × List Parameter) := do
  let parser : Parser (String × List Parameter) := do
    let id ← take
    let mut parameters := []
    if (← accept "(") then
      if !(← accept ")") then
        repeat
          let value ← valueID
          expect ":"
          let type ← parseType
          parameters := parameters ++ [{ id := value, type := type }]
          if !(← accept ",") then break
        expect ")"
    expect ":"
    endRecord
    return (id, parameters)
  return (← parser.run { tokens := record }).1

private def decodeFunction (raw : RawFunction) (moduleID : String) : Decode Function := do
  let headerParser : Parser (List ValueType × ValueType) := do
    expect "sil"
    expect ("@" ++ raw.symbol)
    expect ":"
    let result ← functionType
    expect "{"
    endRecord
    return result
  let ((parameterTypes, result), _) ← headerParser.run { tokens := raw.header }
  let mut blocks : List Block := []
  let mut current : Option Block := none
  for record in raw.body do
    if record[0]?.any (fun token => token.startsWith "bb") && record.back? == some ":" then
      if let some block := current then blocks := blocks ++ [block]
      let (id, parameters) ← parameters record
      current := some { id := id, parameters := parameters, instructions := [] }
    else
      let block ← current.toExcept "instruction outside block"
      let instruction ← parseInstruction record
      if let some instruction := instruction then
        current := some { block with instructions := block.instructions ++ [instruction] }
  if let some block := current then blocks := blocks ++ [block]
  let initial ← blocks.head?.toExcept "empty function"
  if initial.parameters.map Parameter.type != parameterTypes then throw "SIL function parameter mismatch"
  return { moduleID := moduleID, symbol := raw.symbol, result := result, blocks := blocks }

partial def decode (source moduleID : String) (entries : List String) : Decode Program := do
  if source.utf8ByteSize > 16777216 then throw "SIL byte limit exceeded"
  let tokens ← lex source.toList #[]
  let records ← records tokens
  if records[0]? != some #["sil_stage", "canonical"] then throw "canonical SIL required"
  let rawFunctions ← functions records
  let mut pending := entries
  let mut output : Program := []
  while !pending.isEmpty do
    let symbol := pending.head!
    pending := pending.tail
    if output.any (fun function => function.symbol == symbol) then continue
    if output.length >= 10000 then throw "dependency closure bound exceeded"
    let raw ← rawFunctions.find? (fun function => function.symbol == symbol) |>.toExcept s!"unsupported external {symbol}"
    let function ← decodeFunction raw moduleID
    output := output ++ [function]
    for block in function.blocks do
      for instruction in block.instructions do
        if let .functionRef _ symbol := instruction then pending := symbol :: pending
  return output

end SwiftFormal.Reference
