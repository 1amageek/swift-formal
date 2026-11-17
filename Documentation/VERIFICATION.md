# Verification checkpoint

Date: 2026-11-16. This is a multi-language scalar checkpoint, not v1 completion. The dependency-free package contract in DESIGN.md supersedes the imported specification's declaration-index requirements.

| Check | Evidence | Scope |
|---|---|---|
| Fresh dependency-free build | Build and tests use a new scratch directory | No cached third-party products; SwiftPM graph has no dependencies |
| Swift tests | 55 named tests passed across 8 targets | Contracts, integrity, syntax, scalar IR/lowering, emitted-data mutation |
| CLI integration | Passed | Actual executable: doctor, mismatch, removed-command rejection, tampering, strict unsupported commands, eight draft translations, no-clobber |
| Lean 4.35.0 | Actual generated package builds | Scalar runtime, program, properties |
| Lean finite execution | Four kernel-checked theorems | Subtraction, direct call, branch, wrapping endpoints |
| Lean independent decoding | Kernel data, shared-step, reachability equality | Separate decoder reads original scalar fixture; not a complete SIL step proof |
| Axiom audit | Data equality has no axioms; other checked theorems use only propext, Classical.choice, Quot.sound | Explicit allowlist; no sorryAx or custom axioms |
| Mutation | Arithmetic substitution rejected by kernel equality; output-data/wrapper changes rejected by restricted parser | Does not cover the full required mutation suite |
| Source frontend differential | Eight native compilers/runtimes agree with checked IR observations | Primitive scalar source subset; Rust checks enabled, C/C++ UBSan failure, Go wrapping |
| Source Lean kernel | 39 result theorems and axiom audit | All eight profiles, overflow outcomes and 40-digit inputs |
| Four frontend regressions | 19 positive results agree in native/IR/TLA+/Lean; 14 actual CLI rejection cases pass | Updates, Go constants/context conversion, AST depth, and C/C++ declaration visibility |
| Source TLC | 40 finite scenarios; DOT graph confirms expected terminal reachability | All eight profiles; 64-bit and arbitrary integers |
| SANY/TLC 1.7.4 | Actual TLA files parse; five scenarios complete | 64-bit subtraction, call, branch, wrap, overflow trap |

## Reproduce

```sh
python3 Tools/prepare-tools.py
python3 Tools/run-with-timeout.py --seconds 180 -- swift test
python3 Tools/run-with-timeout.py --seconds 90 -- python3 Tools/integration.py
python3 Tools/run-with-timeout.py --seconds 480 -- python3 Tools/verify-backends.py
python3 Tools/run-with-timeout.py --seconds 900 -- python3 Tools/verify-frontends.py
python3 Tools/run-with-timeout.py --seconds 900 -- python3 Tools/verify-regressions.py
```

Tool preparation is explicit and project-local. The external checks never install tools. Use FORMAL_TOOLS_ROOT when the project-local tools are stored in a shared workspace cache; see [Support](SUPPORT.md). Java 24.0.2, Rust 1.92.0 (2021 edition, checks enabled), Apple clang 21.0.0 (C11/C++20), Go 1.26.5, Node 24.19.0, TypeScript 5.9.3, and Python 3.12.8 were used. TLC uses a 16 MB Java stack for recursive bit arithmetic. The package host was Swift 6.4.1 release on arm64 macOS with SDK 27.2.

## Inputs

| Artifact | SHA-256 |
|---|---|
| Copied specification | 8540ef723ed78bcf317317f3fcd740a976b3f149059635992f039af3fc3c11f5 |
| Core canonical SIL | 47fc4b050cdeaffc0625faef5498666d196ce36495d3a96fa571ee71c03e289e |
| Inventory canonical SIL | 2e073ba62b52d6e4d892dbd8b152af2fa86ab2f37729a8000803e85bcc81ba19 |

The copied specification is byte-identical to the supplied document. Fixtures were emitted by the installed fixed Swift compiler with `-Onone -emit-sil`.

## Unverified requirements

Strict capture/generate/validate/coverage/replay, complete provenance/publication, full SIL reference semantics and state/stuttering correspondence, nominal wrapper identity, memory/inout, enum/throw, Actor/executor/coroutine/task models, general temporal-property scenario validation, and original-SIL counterexample replay remain unfinished. Actor SIL has been structurally parsed only. See [PROGRESS.md](../PROGRESS.md); no production semantic profile is certified.

## Four frontend regression checkpoint

The original decrement counterexamples execute natively with result 8 and are now rejected by the restricted profile, rather than translated to result 9. Spaced unary-minus counterparts agree across native execution, IR, TLA+, and Lean. Go's original untyped-constant comparison now returns false across all four paths. Constant cancellation, unsigned contextual conversion, multiplication, negative constants, a precision-boundary constant, and typed wrapping are also checked. Unrepresentable contextual conversions are rejected by both native Go and the frontend.

The original 12,128-byte JavaScript source executes natively but exceeds the profile AST limit; the actual CLI now returns SOURCE_PARSE_FAILED and creates no output. An at-limit, 128-node-deep nested-chain counterpart matches across all four paths. Expression lowering, type hints, and call detection use explicit work stacks. Focused tests exercise binary/unary/call depth boundaries, near-limit Go constants, repeated Rust/Python unary minus, and nested-call argument order.

C/C++ forward-call counterexamples fail native compilation and frontend conversion. Earlier definitions and self-recursion match across all four paths. The common IR and backend runtimes were not modified. Existing eight-language native/IR/Lean/TLC checks and CLI integration pass after the frontend corrections. Independent semantic certification and Actor support remain outside this checkpoint.

## Portable verification checkpoint

See [DISTRIBUTION.md](DISTRIBUTION.md) for installation, scenario and proof scope.
65 named Swift tests and existing CLI integration pass. The release distribution
passes `Tools/verify-distribution.py`: eight source profiles, both actual verifiers,
wrong expectation, UNKNOWN fuel exhaustion, expected overflow, BigInt, tampering,
offline installation, relocation and PATH invocation with blocked host tools and
poisoned Java/Lean environment. The source installer was separately run with a
cache missing Java; it acquired the pinned JRE automatically. Checks took
5.3–8.1 seconds for the successful small scenarios on the current host. No native
source execution is performed by end-user checking. The earlier native/IR/TLA/Lean
regression evidence remains applicable because frontend and runtime semantics
were not changed.

```sh
python3 Tools/run-with-timeout.py --seconds 900 python3 Tools/verify-distribution.py --distribution /absolute/path/to/Formal-macos-arm64
```


## Universal property checkpoint

`formal check --properties` now checks quantified pre/postconditions on the actual
emitted Lean interpreter. This is an additional verification scope; the earlier
finite-case evidence is not used to infer universal validity. Source translation
remains `UNVALIDATED`.

| Check | Actual evidence | Proof scope |
|---|---|---|
| SwiftPM | 73 named tests across eight targets; debug tests and release build pass | Existing contracts plus typed properties, parser limits, graph bounds, witnesses and axiom rejection |
| Eight source profiles | `a - a == 0` proved for each profile | Every 64-bit pattern for fixed-width profiles; every `Int` for mathematical-integer profiles |
| Quantified positive suite | 17 property checks proved by bundled Lean 4.35.0 | Addition, preconditions, branches, direct calls, signed non-overflow, unsigned wrapping, Boolean operations, comparisons and zero-argument functions |
| Checked counterexamples | Signed maximum overflow and a 41-digit integer witness | IR violation, Lean negation of the same obligation, and actual TLC invariant violation |
| Incomplete search | A false property with a precondition excluding every searched tuple reports `UNPROVED`, exit 6 | No witness is not a proof |
| Cycles | Recursive entry reports `UNKNOWN`, exit 6 | No replacement of induction with sampled tests |
| Actual program mutation | Changing generated addition to subtraction makes the unchanged theorem fail | The proof is bound to actual program data rather than an independently reconstructed formula |
| Recheck and aggregation | Fresh artifact snapshot; one proved and one refuted property preserved separately | Existing runs preserved; mixed result uses exit 5 |
| TLA+ | Every universal specification passes SANY | Specification generation and semantic parsing, not universal TLC enumeration |
| Axiom audit | Only `propext`, `Classical.choice`, `Quot.sound` | No admissions or native compiler trust axioms |

Reproduce with an installed portable distribution:

```sh
python3 Tools/run-with-timeout.py --seconds 900 python3 Tools/verify-properties.py --formal /absolute/path/to/formal
```

The execution profile and limits are owned by
[Properties/DESIGN.md](../Sources/FormalValidation/Properties/DESIGN.md).
These checks do not certify source-to-model translation, loop invariants,
recursive termination, Actor/async behavior, or general equivalence of both
runtime semantics.

Tool-inventory hashing was also checked on the same pinned 3 GB toolchain:
the digest remained byte-identical while per-read autorelease scopes reduced
observed peak process RSS from 3,217,457,152 to 45,072,384 bytes. This is a
measurement on the current macOS host, not a general memory or speed guarantee.


The release distribution also passes packaging from a symlinked toolchain root,
offline installation, prefix relocation and PATH invocation with host
java/lean/lake/swift/swiftc/curl/zstd blocked and caller Java/Lean settings
poisoned. The moved installation proves the quantified monotone-addition
property and preserves the eight-language finite-case checks, expected overflow,
large integers, counterexamples, fuel exhaustion and tamper rejection. Packaging
copies the verifier-resolved tool tree, so its result does not retain a link to
the original tool location.


## Java and Bun checkpoint

| Check | Actual result | Scope |
|---|---|---|
| SwiftPM | 79 named tests across eight targets; release build passes | Ten source profiles, including Java widths/literals/grammar and Bun typed/untyped functions |
| Native differential | 18 input observations agree in native execution, IR, Lean and TLC | Java int32/int64 wrapping, Bun JS/TS large integers, branches/calls/locals, and both Boolean profiles |
| Quantified proofs | Six kernel-checked all-input theorems | Java 32/64-bit cancellation, Bun JS/TS monotone increment over Int, Java/Bun Boolean negation |
| Counterexamples | Two witnesses checked by IR, Lean and TLC and reproduced natively | Java int32 maximum increment wraps to minimum; Bun identity violates a property at a 41-digit integer |
| Rejection | Eight actual CLI failures create no artifacts | Literal-width conversions, minimum-literal parentheses, instance methods, Java names/signatures, Bun Number and updates |
| Existing profiles | Every generated artifact byte is unchanged for the eight original source fixtures | Existing frontend/runtime behavior is preserved for these fixtures |
| Portable distribution | Ten profiles checked after offline installation and prefix relocation with host javac/Bun blocked | No new end-user source runtime dependency |
| Offline universal checks | Java and Bun proofs succeed with missing host PATH and poisoned Java/Lean settings | Bundled tools are used exclusively |

Native checks used javac/JVM 24.0.2 and Bun 1.3.11. The portable proof toolchain
remains Lean 4.35.0, Temurin 21.0.13+9 and TLC 1.7.4. No runtime source, trusted
artifact hash, IR opcode, production target or external dependency changed.

```sh
python3 Tools/run-with-timeout.py --seconds 900 python3 Tools/verify-java-bun.py --formal /absolute/path/to/formal
python3 Tools/run-with-timeout.py --seconds 900 python3 Tools/verify-distribution.py --distribution /absolute/path/to/portable-directory
```

The first command requires developer-native javac/java and Bun for differential
execution. End-user translation and model verification require neither. The
[frontend contract](../Sources/FormalCompiler/Frontends/DESIGN.md#java-and-bun-profiles)
owns the exact source subset and rejection rules. Translation remains
`UNVALIDATED`; these results do not certify arbitrary Java/Bun applications or
extend Actor, memory, loop-invariant or source-semantic certification support.


## Number checkpoint

Date: 2026-11-17. Version 0.4.0 adds IEEE binary64 Number to the JS/TS/Bun
scalar-v2 profiles. Other source profiles retain their integer semantics.
This checkpoint supersedes the earlier BigInt-only JS-family restriction.

| Check | Evidence | Scope |
|---|---|---|
| Swift tests and release build | 94 named tests and the macOS arm64 release build passed with Swift 6.4.1 | All eight test targets; Number parsing, operators, inference, views and failure paths |
| Number arithmetic | 400 vectors agree in Node, Bun, Swift IR, Lean kernel reductions and TLC | 16 operations across 25 boundary and seeded-random pairs; NaN, infinities, signed zero, subnormals, rounding, precision and extrema |
| Number source execution | 35 observations agree in Node/Bun, IR, Lean and TLC | JS/TS/Bun source, division/remainder, truthiness, short-circuiting, classification, logical not, inequality and NaN comparison |
| Quantified Number proofs | Five kernel-checked theorems and universal TLA specifications parsed by SANY | Identity, irreflexive ordering, reflexivity excluding NaN, addition and negation over every 64-bit input pattern |
| Number counterexamples | Four Lean refutations and TLC witness traces; each native result is independently rechecked by IR/Lean/TLC | Decimal rounding, NaN cancellation, NaN reflexivity and addition at the integer-precision boundary |
| Actual-model mutation | Replacing generated Number addition with subtraction prevents the unchanged quantified theorem from checking | Proofs execute actual generated Program data |
| Existing universal suite | 23 checks have the expected statuses: 19 proofs, two counterexamples, one UNKNOWN and one UNPROVED | All ten source profiles; bounds and failed search still cannot imply validity |
| Java/Bun compatibility | 18 native/IR/Lean/TLC observations, six all-input proofs, two counterexamples and eight no-output rejections pass | Java widths, BigInt, Boolean and source-profile restrictions |
| Original frontend regressions | 19 native/IR/TLA/Lean results and CLI rejection checks pass | Go constants, lexical updates, depth and C/C++ visibility |
| Portable checking | Offline installation, linked-toolchain copying, prefix relocation, ten source profiles, Number rounding and all-input Number sum pass with host tools poisoned | Bundled Java/TLC/Lean only; no host Bun, Node or javac is required by formal |
| Concurrency and cleanup | Concurrent Number source checks pass; transient child-file cleanup regression passes | Private Java temporary directories and workspace inspection tolerant of deleted entries |
| Artifact integrity | Runtime/tool tampering is rejected; both runtime hashes are pinned | Regenerate artifacts from older runtime versions |

Native Number observations used Node 24.19.0 and Bun 1.3.11. Verification used
bundled Lean 4.35.0, TLC 1.7.4 and Temurin 21.0.13+9. The kernel axiom allowlist
remains `propext`, `Classical.choice`, and `Quot.sound`; no native proof reduction
or additional axiom is accepted. Mathematical-real substitution is not used.

The current runtime identities are:

| Runtime | SHA-256 |
|---|---|
| Lean | `2e2002013cfd2ab19b2ca8dd76d86b1bdf47546e4fded4359baa0d314c448267` |
| TLA+ | `c75b5f2484bb23d24dfe4bc854cf6275c835d1bd28f6bf0e972d108e97ae67b6` |

Reproduction uses a fresh output directory and an installed portable executable:

```sh
python3 Tools/run-with-timeout.py --seconds 240 swift test
python3 Tools/run-with-timeout.py --seconds 240 swift build -c release
python3 Tools/run-with-timeout.py --seconds 1200 python3 Tools/verify-numbers.py --formal /absolute/path/to/formal --output .tools/number-checkpoint
python3 Tools/run-with-timeout.py --seconds 900 python3 Tools/verify-java-bun.py --formal /absolute/path/to/formal
python3 Tools/run-with-timeout.py --seconds 1200 python3 Tools/verify-distribution.py --distribution /absolute/path/to/distribution
```

Runtime vectors, finite scenarios, universal model proofs and native observations
have distinct scopes. General source-to-model semantic preservation remains
UNVALIDATED; arbitrary projects, Actor/async and the original complete v1 scope
remain unfinished. [Number verification](NUMBERS.md) describes supported source
syntax, views, migration and automatic-proof limits.


## Three-finding regression checkpoint

Date: 2026-11-17. The CR lexer, SANY diagnostic audit and unary-plus inference
findings are fixed. The focused red run reproduced seven failures before the
frontend fixes. The final Swift test run passes 99 named tests across eight
targets; the release build and ten-language CLI integration also pass.

| Finding | Regression evidence | Verified scope |
|---|---|---|
| CR return boundaries | Six JS/TS/Bun sources return undefined in both Node and Bun; translate and check reject all six before publishing any artifact | Both raw CR and CR inside a block comment; 12 CLI rejection paths |
| Accepted CRLF and Number unary plus | 74 observations agree between Node, Bun, IR execution, actual TLC and Lean | Three source profiles; CRLF, direct plus, local aliases, calls, negative zero, NaN, infinity and finite values; BigInt unresolved default does not override plus constraints |
| SANY path independence | All model-check outputs live under a path containing error; explicit error-directory and uppercase/spaced ERROR handling cases pass | Actual finite checking, including module parsing, terminal-state reachability and kernel proofs |
| Shared universal audit | Value-preserving unary plus is PROVED for every Number bit pattern; numeric reflexivity produces a NaN counterexample checked by Lean and TLC | Both Universal and Witness specifications pass SANY through the shared audit; source translation remains UNVALIDATED |
| Zero-exit SANY error | Pinned SANY processes an invalid module, reports a semantic error and exits zero; the actual transcript is rejected by SANYOutputAuditTests | Success-marker presence and exit zero cannot hide a semantic diagnostic |

Native observations used Node 24.19.0 and Bun 1.3.11. Verifier versions, backend
runtime bytes, arithmetic semantics and trusted hashes are unchanged from the
Number checkpoint. Its runtime-vector evidence remains applicable. These
changes do not add undefined to the IR: unsupported undefined-returning sources
are rejected rather than mapped to a numeric result.

```sh
python3 Tools/run-with-timeout.py --seconds 240 swift test
python3 Tools/run-with-timeout.py --seconds 1200 python3 Tools/verify-number-regressions.py --formal /absolute/path/to/formal --output .tools/number-regression-checkpoint
```

Use a fresh output directory. The differential script retains native results,
exact cases, generated artifacts, verifier reports and the real SANY error
transcript when an output directory is supplied. Older artifacts generated from
sources with isolated CR should be regenerated; artifact rechecking audits the
existing generated model and does not reparse its source.
