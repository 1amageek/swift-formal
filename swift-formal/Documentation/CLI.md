# CLI

Run `swift run formal --help` from the package directory. The [package design](../DESIGN.md#contracts-and-invariants) owns executable naming; the imported SPEC.md is an unchanged historical snapshot.

| Command | Current behavior |
|---|---|
| `--help`, `--version` | Describe the current release |
| `profiles` | List the eight versioned scalar source profiles and input assumptions |
| `translate --language <name> --source <file> --output <new-directory> --draft-unvalidated` | Write experimental TLA+, Lean, IR, source, and report after independent data comparison |
| `package --output <new-directory> [--cache <directory>]` | Create a self-contained portable distribution |
| `install --prefix <directory> [--cache <directory>]` | Install formal and its pinned tools |
| `toolchain` | Audit bundled tool inventory and report pinned versions |
| `check --language <name> --source <file> --scenario <json> --output <new-directory>` | Generate and verify finite model cases with bundled TLC and Lean |
| `check --artifact <directory> --scenario <json>` | Recheck audited generated artifacts offline |
| `doctor --toolchain-lock <path>` | Compare actual compiler version, tag, triple, and pointer width to the lock |
| `inspect-bundle --bundle <directory> --toolchain-lock <path>` | Check input records, safe paths, closure metadata, and module hashes |
| `capture`, `generate`, `validate`, `coverage`, `replay` | Fail with `UNSUPPORTED_OPERATION`, exit 3; create no artifacts |

`doctor` does not certify SDK or runtime semantics, TLA tools, or Lean. Bundle inspection does not parse SIL or check symbol resolution. The scalar libraries are available independently of the CLI. Neither operation implies GENERATED, VALIDATED, MODEL_CHECKED, or PROVED.

| Exit | Meaning |
|---|---|
| 0 | The requested implemented operation completed |
| 2 | Invalid arguments, metadata, or toolchain mismatch |
| 3 | Unsupported operation |
| 4 | Integrity or parsing mismatch |
| 5 | Counterexample or unproved expected outcome |
| 6 | Timeout, cancellation, computation/output bound; UNKNOWN |
| 7 | I/O or tool execution failure |

Future command behavior follows SPEC section 14, subject to the user corrections recorded in the package design. Declaration indexing is outside the package; `formal index` is rejected as an unknown command.

## Draft source translation

Languages: `swift`, `rust`, `c`, `cpp`, `go`, `typescript`, `javascript`, `python`. `--draft-unvalidated` is mandatory and last. The output directory must not exist; its parent must already exist. Failure does not replace prior output. The frontend never executes the input or downloads tools. See [source-profile contracts](../Sources/FormalCompiler/Frontends/DESIGN.md) for grammar, integer semantics, and input assumptions. Draft output is not accepted as a certified SIL bundle by the strict generation path. `report.json` records the source hash, profile assumptions, data equality, and absent semantic certification. No actual external verifier is run by translate.

Portable installation, scenario schema, resource limits, report scope and examples are documented in [DISTRIBUTION.md](DISTRIBUTION.md). `check` accepts optional `--timeout <seconds>`.
