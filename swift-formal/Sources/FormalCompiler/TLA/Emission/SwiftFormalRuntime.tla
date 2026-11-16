------------------------- MODULE SwiftFormalRuntime -------------------------
EXTENDS Integers, Sequences, FiniteSets, TLC

Elements(sequence) == {sequence[i] : i \in 1..Len(sequence)}
Bits(width, value) == [tag |-> "bits", width |-> width, bits |-> value]
Aggregate(values) == [tag |-> "aggregate", elements |-> values]
FunctionValue(symbol) == [tag |-> "function", symbol |-> symbol]
Unit == Aggregate(<<>>)
Flag(condition) == Bits(1, <<IF condition THEN 1 ELSE 0>>)
Zeros(count) == [i \in 1..count |-> 0]
Ones(count) == [i \in 1..count |-> 1]
BVNot(value) == [i \in 1..Len(value) |-> 1 - value[i]]
RECURSIVE AddPrefix(_, _, _)
AddPrefix(left, right, count) ==
  IF count = 0 THEN [value |-> <<>>, carry |-> 0]
  ELSE LET prior == AddPrefix(left, right, count - 1)
           sum == left[count] + right[count] + prior.carry
       IN [value |-> Append(prior.value, sum % 2), carry |-> sum \div 2]
BVAdd(left, right) == AddPrefix(left, right, Len(left))
BVOne(width) == <<1>> \o Zeros(width - 1)
BVNegate(value) == BVAdd(BVNot(value), BVOne(Len(value))).value
BVSubtract(left, right) == BVAdd(left, BVNegate(right)).value
Sign(value) == value[Len(value)]
RECURSIVE BVLess(_, _, _)
BVLess(left, right, count) ==
  IF count = 0 THEN FALSE
  ELSE IF left[count] # right[count] THEN left[count] < right[count]
       ELSE BVLess(left, right, count - 1)
BVUnsignedLess(left, right) == BVLess(left, right, Len(left))
BVSignedLess(left, right) ==
  IF Sign(left) # Sign(right) THEN Sign(left) = 1 ELSE BVUnsignedLess(left, right)
ShiftLeft(value, count) ==
  [i \in 1..Len(value) |-> IF i <= count THEN 0 ELSE value[i - count]]
RECURSIVE MultiplyPrefix(_, _, _)
MultiplyPrefix(left, right, count) ==
  IF count = 0 THEN Zeros(Len(left))
  ELSE LET prior == MultiplyPrefix(left, right, count - 1)
       IN IF right[count] = 0 THEN prior ELSE BVAdd(prior, ShiftLeft(left, count - 1)).value
BVMultiply(left, right) == MultiplyPrefix(left, right, Len(right))
SignExtend(value) == value \o [i \in 1..Len(value) |-> Sign(value)]
Low(value, width) == SubSeq(value, 1, width)
High(value, width) == SubSeq(value, width + 1, Len(value))
Overflow(width, value, condition) == Aggregate(<<Bits(width, value), Flag(condition)>>)
Bitwise(operation, left, right) ==
  [i \in 1..Len(left) |-> CASE operation = "and" -> left[i] * right[i]
                          [] operation = "or" -> IF left[i] + right[i] > 0 THEN 1 ELSE 0
                          [] OTHER -> (left[i] + right[i]) % 2]

Binary(operation, left, right) ==
  LET width == left.width
      a == left.bits
      b == right.bits
  IN CASE operation \in {"signedAddOverflow", "unsignedAddOverflow"} ->
         LET sum == BVAdd(a, b)
             overflow == IF operation = "signedAddOverflow"
                         THEN Sign(a) = Sign(b) /\ Sign(a) # Sign(sum.value)
                         ELSE sum.carry = 1
         IN Overflow(width, sum.value, overflow)
       [] operation \in {"signedSubtractOverflow", "unsignedSubtractOverflow"} ->
         LET difference == BVSubtract(a, b)
             overflow == IF operation = "signedSubtractOverflow"
                         THEN Sign(a) # Sign(b) /\ Sign(a) # Sign(difference)
                         ELSE BVUnsignedLess(a, b)
         IN Overflow(width, difference, overflow)
       [] operation = "signedMultiplyOverflow" ->
         LET product == BVMultiply(SignExtend(a), SignExtend(b))
             low == Low(product, width)
             high == High(product, width)
         IN Overflow(width, low, high # [i \in 1..width |-> Sign(low)])
       [] operation = "unsignedMultiplyOverflow" ->
         LET product == BVMultiply(a \o Zeros(width), b \o Zeros(width))
         IN Overflow(width, Low(product, width), High(product, width) # Zeros(width))
       [] operation = "signedLessThan" -> Flag(BVSignedLess(a, b))
       [] operation = "unsignedLessThan" -> Flag(BVUnsignedLess(a, b))
       [] operation = "equal" -> Flag(a = b)
       [] operation \in {"and", "or", "xor"} -> Bits(width, Bitwise(operation, a, b))

RECURSIVE Trim(_)
Trim(bits) == IF Len(bits) = 0 THEN <<>>
              ELSE IF bits[Len(bits)] = 0 THEN Trim(SubSeq(bits, 1, Len(bits) - 1)) ELSE bits
Pad(bits, width) == bits \o Zeros(width - Len(bits))
Integer(negative, magnitude) == [tag |-> "integer", negative |-> negative /\ Len(Trim(magnitude)) > 0, magnitude |-> Trim(magnitude)]
MagnitudeLess(a, b) == IF Len(a) # Len(b) THEN Len(a) < Len(b) ELSE BVUnsignedLess(a, b)
MagnitudeAdd(a, b) == LET width == IF Len(a) > Len(b) THEN Len(a) + 1 ELSE Len(b) + 1
                      IN Trim(BVAdd(Pad(a, width), Pad(b, width)).value)
MagnitudeSubtract(a, b) == Trim(BVSubtract(a, Pad(b, Len(a))))
MagnitudeMultiply(a, b) == LET width == Len(a) + Len(b)
                           IN Trim(BVMultiply(Pad(a, width), Pad(b, width)))
IntegerNegate(a) == Integer(~a.negative, a.magnitude)
IntegerAdd(a, b) ==
  IF a.negative = b.negative THEN Integer(a.negative, MagnitudeAdd(a.magnitude, b.magnitude))
  ELSE IF MagnitudeLess(a.magnitude, b.magnitude)
       THEN Integer(b.negative, MagnitudeSubtract(b.magnitude, a.magnitude))
       ELSE Integer(a.negative, MagnitudeSubtract(a.magnitude, b.magnitude))
IntegerLess(a, b) == IF a.negative # b.negative THEN a.negative
                    ELSE IF a.negative THEN MagnitudeLess(b.magnitude, a.magnitude)
                    ELSE MagnitudeLess(a.magnitude, b.magnitude)
IntegerBinary(operation, a, b) ==
  CASE operation = "add" -> IntegerAdd(a, b)
    [] operation = "subtract" -> IntegerAdd(a, IntegerNegate(b))
    [] operation = "multiply" -> Integer(a.negative # b.negative, MagnitudeMultiply(a.magnitude, b.magnitude))
    [] operation = "lessThan" -> Flag(IntegerLess(a, b))
    [] operation = "equal" -> Flag(a = b)
DecimalDigit(character) == CHOOSE n \in 0..9: character = <<"0", "1", "2", "3", "4", "5", "6", "7", "8", "9">>[n+1]
DigitBits(n) == Trim(<<n % 2, (n \div 2) % 2, (n \div 4) % 2, n \div 8>>)
RECURSIVE ParseMagnitude(_, _)
ParseMagnitude(text, count) ==
  IF count = 0 THEN <<>>
  ELSE MagnitudeAdd(MagnitudeMultiply(ParseMagnitude(text, count - 1), <<0, 1, 0, 1>>), DigitBits(DecimalDigit(SubSeq(text, count, count))))
ParseInteger(text) == IF SubSeq(text, 1, 1) = "-" THEN Integer(TRUE, ParseMagnitude(SubSeq(text, 2, Len(text)), Len(text) - 1))
                      ELSE Integer(FALSE, ParseMagnitude(text, Len(text)))

FindFunction(program, symbol) == CHOOSE function \in Elements(program): function.symbol = symbol
FindBlock(function, id) == CHOOSE block \in Elements(function.blocks): block.id = id
EmptyEnvironment == [id \in {} |-> Unit]
SetValue(environment, id, value) ==
  [key \in DOMAIN environment \cup {id} |-> IF key = id THEN value ELSE environment[key]]
Arguments(environment, ids) == [i \in 1..Len(ids) |-> environment[ids[i]]]
Bind(environment, parameters, actual) ==
  LET names == {parameters[i].id : i \in 1..Len(parameters)}
  IN [key \in DOMAIN environment \cup names |->
       IF key \in names THEN actual[CHOOSE i \in 1..Len(parameters): parameters[i].id = key]
       ELSE environment[key]]
Frame(program, symbol, actual, destination) ==
  LET function == FindFunction(program, symbol)
      block == function.blocks[1]
  IN [function |-> symbol, block |-> block.id, pc |-> 1,
      environment |-> Bind(EmptyEnvironment, block.parameters, actual), destination |-> destination]
Initial(program, symbol, actual) ==
  [frames |-> <<Frame(program, symbol, actual, "")>>, status |-> "running", result |-> Unit, message |-> ""]
Terminal(state) == state.status \in {"returned", "trapped", "panic", "undefinedBehavior"}
Advance(state, destination, value) ==
  [state EXCEPT !.frames[1].environment = SetValue(@, destination, value), !.frames[1].pc = @ + 1]
Jump(function, frame, destination, arguments) ==
  LET block == FindBlock(function, destination)
      values == Arguments(frame.environment, arguments)
  IN [frame EXCEPT !.block = destination, !.pc = 1, !.environment = Bind(@, block.parameters, values)]

Step(program, before, after) ==
  /\ before.status = "running"
  /\ LET frame == Head(before.frames)
         function == FindFunction(program, frame.function)
         block == FindBlock(function, frame.block)
         instruction == block.instructions[frame.pc]
         environment == frame.environment
     IN CASE instruction.op = "integerLiteral" ->
          after = Advance(before, instruction.destination, ParseInteger(instruction.decimal))
       [] instruction.op = "integerBinary" ->
          after = Advance(before, instruction.destination, IntegerBinary(instruction.operation, environment[instruction.left], environment[instruction.right]))
       [] instruction.op = "failIf" ->
          IF environment[instruction.condition].bits = <<1>>
          THEN after = [before EXCEPT !.status = instruction.kind, !.message = instruction.message]
          ELSE after = [before EXCEPT !.frames[1].pc = @ + 1]
       [] instruction.op = "literal" ->
          after = Advance(before, instruction.destination, Bits(instruction.width, instruction.value))
       [] instruction.op = "aggregate" ->
          after = Advance(before, instruction.destination, Aggregate(Arguments(environment, instruction.elements)))
       [] instruction.op = "extract" ->
          after = Advance(before, instruction.destination, environment[instruction.source].elements[instruction.index + 1])
       [] instruction.op = "binary" ->
          after = Advance(before, instruction.destination,
            Binary(instruction.operation, environment[instruction.left], environment[instruction.right]))
       [] instruction.op = "functionRef" ->
          after = Advance(before, instruction.destination, FunctionValue(instruction.symbol))
       [] instruction.op = "call" ->
          LET symbol == environment[instruction.callee].symbol
              actual == Arguments(environment, instruction.arguments)
              child == Frame(program, symbol, actual, instruction.destination)
              caller == [frame EXCEPT !.pc = @ + 1]
          IN after = [before EXCEPT !.frames = <<child, caller>> \o Tail(@)]
       [] instruction.op = "jump" ->
          after = [before EXCEPT !.frames[1] = Jump(function, frame, instruction.block, instruction.arguments)]
       [] instruction.op = "branch" ->
          LET chosen == environment[instruction.condition].bits = <<1>>
              destination == IF chosen THEN instruction.thenBlock ELSE instruction.elseBlock
              actual == IF chosen THEN instruction.thenArguments ELSE instruction.elseArguments
          IN after = [before EXCEPT !.frames[1] = Jump(function, frame, destination, actual)]
       [] instruction.op = "trapIf" ->
          IF environment[instruction.condition].bits = <<1>>
          THEN after = [before EXCEPT !.status = "trapped", !.message = instruction.message]
          ELSE after = [before EXCEPT !.frames[1].pc = @ + 1]
       [] instruction.op = "returnValue" ->
          LET returned == environment[instruction.source]
          IN IF Len(before.frames) = 1
             THEN after = [before EXCEPT !.frames = <<>>, !.status = "returned", !.result = returned]
             ELSE LET caller == before.frames[2]
                      updated == [caller EXCEPT !.environment = SetValue(@, frame.destination, returned)]
                  IN after = [before EXCEPT !.frames = <<updated>> \o Tail(Tail(@))]
       [] OTHER -> FALSE

RECURSIVE ValueHasType(_, _)
ValueHasType(value, type) ==
  CASE type.kind = "integer" ->
    /\ value.tag = "integer" /\ value.magnitude \in Seq({0, 1}) /\ Trim(value.magnitude) = value.magnitude
    /\ value.negative \in BOOLEAN /\ (Len(value.magnitude) = 0 => ~value.negative)
  [] type.kind = "bits" ->
    /\ value.tag = "bits" /\ value.width = type.width /\ value.bits \in Seq({0, 1}) /\ Len(value.bits) = type.width
  [] type.kind = "aggregate" ->
    /\ value.tag = "aggregate" /\ Len(value.elements) = Len(type.elements)
    /\ \A i \in 1..Len(type.elements): ValueHasType(value.elements[i], type.elements[i])
  [] type.kind = "function" -> value.tag = "function"

InputTypesMatch(program, symbol, actual) ==
  LET parameters == FindFunction(program, symbol).blocks[1].parameters
  IN /\ Len(parameters) = Len(actual)
     /\ \A i \in 1..Len(parameters): ValueHasType(actual[i], parameters[i].type)
=============================================================================
