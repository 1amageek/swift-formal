# CLI

Run `swift run formal --help` from the package directory. The [package design](../DESIGN.md#contracts-and-invariants) owns executable naming; the imported SPEC.md is an unchanged historical snapshot.

| Command | Current behavior |
|---|---|
| `--help`, `--version` | Describe the bootstrap release |
| `doctor --toolchain-lock <path>` | Compare actual compiler version, tag, triple, and pointer width to the lock |
| `inspect-bundle --bundle <directory> --toolchain-lock <path>` | Check input records, safe paths, closure metadata, and module hashes |
| `capture`, `generate`, `validate`, `check`, `coverage`, `replay` | Fail with `UNSUPPORTED_OPERATION`, exit 3; create no artifacts |

`doctor` does not certify SDK or runtime semantics, TLA tools, or Lean. Bundle inspection does not parse SIL or check symbol resolution. The scalar libraries are available independently of the CLI. Neither operation implies GENERATED, VALIDATED, MODEL_CHECKED, or PROVED.

| Exit | Meaning |
|---|---|
| 0 | The requested implemented operation completed |
| 2 | Invalid arguments, metadata, or toolchain mismatch |
| 3 | Unsupported operation |
| 4 | Integrity or parsing mismatch |
| 6 | Timeout or cancellation |
| 7 | I/O or tool execution failure |

Future command behavior follows SPEC section 14, subject to the user corrections recorded in the package design. Declaration indexing is outside the package; `formal index` is rejected as an unknown command.
