# Source Frontends

## Purpose and Scope
Versioned scalar source conversion for Swift, Rust, C, C++, Go, TypeScript, JavaScript, and Python. Parent: [FormalCompiler](../DESIGN.md). No children.

## Responsibilities and Boundaries
Own tokenization, restricted grammar, type checking, and lowering. SourceCompiling is the public boundary. SourceLanguage exposes the versioned profile identity and input assumptions; this contract owns integer and overflow policy. No external parser, Skeleton, source execution, or language inference participates in conversion.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Compiler](../DESIGN.md) | parent | Frontend composition | Produces common IR | Experimental output only |
| [IR](../../FormalIR/DESIGN.md) | depends on | Typed scalar instructions | Language-independent output | Failures retain their kind |

## Architecture
```text
Source request -> bounded lexer -> language grammar -> typed expressions/CFG -> IR validation
```

## Contracts and Invariants
The scalar-v1 profile accepts ASCII standalone pure functions, explicitly typed integer/Boolean parameters and results (JavaScript parameters and results are BigInt), decimal literals, immutable locals, +, -, *, comparisons, direct positional calls, returns, and conditional returns. Branches must both return; all functions require explicit return. Expressions and signatures are single-line; only function/block boundaries span lines. Contiguous ++/-- are recognized and rejected as unsupported update operators in C/C++, JS/TS, Go, and Swift; whitespace-separated unary minuses retain their meaning. Python and Rust retain their distinct repeated-unary-minus grammar. No language is accepted through another language's parser accidentally: signatures, literal suffixes, declarations, and statement boundaries are language-specific. C/C++ accept only int64_t/uint64_t, bool, and standard integer/Boolean includes; arithmetic literals require LL/ULL suffixes to avoid integer promotions. C/C++ function visibility starts at each function definition, includes self-recursion, and includes earlier definitions. Forward declarations/prototypes remain outside the profile; later definitions do not authorize earlier calls. C/C++ calls in arithmetic operands or call arguments are rejected to avoid unspecified evaluation order. Go requires a package declaration. Python requires int/bool annotations and spaces-only indentation. JS/TS accept BigInt and Boolean literals; Number, dynamic coercion, mutation, objects, imports, async, and exceptions are rejected. Rust overflow checks must be enabled; signed and unsigned overflow panic. [Go constant semantics](https://go.dev/ref/spec#Constants) distinguish untyped constant evaluation from typed arithmetic. Go typed integer arithmetic wraps. Untyped Go constant subexpressions are evaluated exactly before contextual conversion; conversion to int64/uint64 requires representability and never wraps. Constant-only comparisons preserve arbitrary-precision meaning before producing Boolean values. This source profile bounds each constant intermediate to 76 decimal digits, within Go's guaranteed minimum 256-bit constant precision; exceeding that profile budget is a diagnostic, never a fabricated result. Go short declarations still require a typed operand or a Boolean result, rather than introducing the excluded default int type. Swift arithmetic traps. C/C++ signed overflow is undefined behavior; unsigned wraps. Python int and JS/TS BigInt use arbitrary integers, not narrowed machine words. Rust/C/Go mixed integer types are rejected. Swift/Rust/Go local inference requires a typed operand or explicit annotation; default platform integer types are outside the profile. Swift argument labels are outside this source profile; the existing SIL path remains available.

Input assumptions: JS callable arguments are primitive BigInts; Python annotations describe exact built-in int/bool inputs, excluding subclasses; C data model is 64-bit int64_t/uint64_t, C++ has no overloads or user declarations. These assumptions are emitted in the draft report. This is a closed source subset, not an arbitrary-project compiler. Nested/chained comparisons are rejected. Unsupported syntax and types fail with a source position before artifact writing. No independent source-to-IR proof is claimed.

## State, Ownership, and Lifecycle
Parser and lowering state are invocation-local values. Maximum source bytes, tokens, parser recursion, total expression-tree depth, and integer digits bound host work. Each AST constructor carries its computed depth; the parser checks the prospective parent depth before creating it. Parentheses retain the child depth. No AST consumer receives an expression above maximumNesting. Type hints, call detection, and expression lowering use invocation-local explicit work stacks, so accepted left-deep expressions do not consume host call-stack depth. Constant evaluation remains depth-bounded by the same AST contract. Interpreter limits are operational failures, not source results.

## Failure, Concurrency, and Constraints
SourceDiagnostic carries language and token position for syntax errors; semantic errors are anchored to the owning function declaration. Duplicate names, unknown calls, missing returns, mixed types, and unsupported syntax fail explicitly. No global mutable state or subprocess exists in frontends.

## Verification and Change Impact
[Frontend tests](../../../Tests/FormalFrontendTests) own positive and negative grammar, overflow, calls, branches, and output decoding. Native tool differential checks and Lean/TLC execution check finite cases. New instructions require IR, both runtimes, emitters, and independent output decoders to change together. Source-to-IR semantic certification remains pending.

### Four-finding Regression Ownership
| Finding | Owner | Negative acceptance | Positive evidence |
|---|---|---|---|
| Update operators split into subtraction | SourceLexer | Prefix/postfix -- and ++ fail before lowering | Spaced double negation matches native, IR, TLA+, and Lean |
| Go untyped constants narrowed early | GoConstantEvaluator and SourceLowering | Unrepresentable contextual conversions and precision-budget exhaustion fail | Constant comparison, cancellation, mixed typed/constant expressions, and typed wrapping agree across all four paths |
| Parser recursion limit did not bound AST depth | SourceParser | The 12,128-byte nested-chain counterexample returns SourceDiagnostic, never a signal | At-limit nested chains remain valid; over-limit binary/unary/call nodes fail |
| C/C++ forward calls accepted without declarations | SourceLowering | A later definition does not satisfy an earlier call | Earlier definitions and self-recursion remain valid and agree across all four paths |

[FrontendRegressionTests](../../../Tests/FormalFrontendTests/FrontendRegressionTests.swift) own rejection, boundaries, and IR observations. [verify-regressions.py](../../../Tools/verify-regressions.py) owns actual CLI no-output checks, native compiler/runtime behavior, and actual emitted TLA+/Lean execution. Rejected input produces no IR or backend artifacts; positive counterparts establish output behavior. Existing backend runtimes and IR contracts are unchanged.
