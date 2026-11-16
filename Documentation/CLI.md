# CLI

| Command | Current behavior |
|---|---|
| `--help`, `--version` | Describe the bootstrap release |
| `doctor --toolchain-lock <path>` | Compare actual compiler version, tag, triple, and pointer width to the lock |
| `inspect-bundle --bundle <directory> --toolchain-lock <path>` | Check input records, safe paths, closure metadata, and module hashes |
| `index --source <path>` | Parse optional Swift declaration locations, including private methods |
| `capture`, `generate`, `validate`, `check`, `coverage`, `replay` | Fail with `UNSUPPORTED_OPERATION`, exit 3; create no artifacts |

`doctor` does not certify SDK or runtime semantics, TLA tools, or Lean. Bundle inspection does not parse SIL or check symbol resolution. The scalar libraries are available independently of the CLI. Neither operation implies GENERATED, VALIDATED, MODEL_CHECKED, or PROVED.

| Exit | Meaning |
|---|---|
| 0 | The requested implemented operation completed |
| 2 | Invalid arguments, metadata, or toolchain mismatch |
| 3 | Unsupported operation |
| 4 | Hash mismatch or source parser error |
| 6 | Timeout or cancellation |
| 7 | I/O or tool execution failure |

Future commands and result meanings remain specified in SPEC section 14.
