# ToolExecution

## Purpose and Scope
Run bounded offline subprocesses. Parent: FormalValidation. No children.

## Responsibilities and Boundaries
Own process groups, stdout/stderr files, deadline and cancellation. No shell interpretation or dependency acquisition.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Parent](../DESIGN.md) | parent | Component composition | Owns consumers | Recheck failures and limits |
| [FormalCore](../../FormalCore/DESIGN.md) | depends on | Typed diagnostics | Explicit failures | Deadline and cancellation are not success |
| [Verification](../Verification/DESIGN.md) | used by | Bounded invocation | Runs Lean and Java | Preserve process group cleanup |
| [Toolchain](../Toolchain/DESIGN.md) | used by | Bounded invocation | Runs curl and tar during explicit installation | No shell |

## Architecture
```text
Invocation -> posix_spawn process group -> bounded logs -> exit status
```

## Contracts and Invariants
Child environment is explicitly supplied. C strings live only through posix_spawn; file descriptors and spawn attributes are destroyed exactly once. Group kill and waitpid complete before return, including cancellation and timeout. Logs are capped per stream; optional workspace byte budgets are polled every 250 ms and checked again before returning; no pipes can block a writer.

## State, Ownership, and Lifecycle
Invocation-local immutable configuration and locally owned temporary files. No shared mutable state. Staging is removed on failure. Completed reports persist in the requested output.

## Failure, Concurrency, and Constraints
Typed errors preserve failure; deadlines, cancellation, and output limits never count as verification success.

## Verification and Change Impact
Tests/FormalValidationTests/ToolExecutionTests.swift owns nonzero exit, timeout, cancellation, output cap and descendant cleanup. Consumers are Toolchain and Verification.
