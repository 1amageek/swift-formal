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
Child environment is explicitly supplied. C strings live only through posix_spawn; file descriptors and spawn attributes are destroyed exactly once. Group kill and waitpid complete before return, including cancellation and timeout. Logs are capped per stream; optional workspace byte budgets are polled every 250 ms and checked again before returning; no pipes can block a writer. Workspace inspection tolerates only ENOENT for entries removed concurrently by the child, including TLC cleanup; other metadata errors remain failures. Deleted entries consume no current disk budget.

A caller may explicitly select inherited-group execution only when an external worker owner owns the current process group and its final group cleanup. The inherited runner kills/reaps its direct child; the enclosing owner stops all remaining members. No implicit environment flag changes ownership. Invar uses one isolated worker group and injects inherited-group runners into the formal verifiers, so nested proof tools cannot escape worker timeout cleanup.

Optional process limits sample group membership and aggregate resident memory every 25 ms. Limits include the leader and all group members; hitting a sample threshold is resource exhaustion. CPU is summed over live members and their reaped children, with final wait4 usage checked before success. These are monitored limits for trusted tools, not an OS sandbox or a guarantee against arbitrary group escape. Peak RSS is sampled, not a maximum allocation guarantee. Tests own process/memory exhaustion and nested group cancellation.

## Runtime Flows
Create exclusive stdout/stderr logs, configure spawn actions and a new process group, then spawn with explicit argv/environment. Poll cancellation, elapsed time, stream sizes and the optional workspace budget. Reap the leader and stop remaining group members before reading bounded logs. Every exit destroys native attributes/actions and closes owned descriptors.

## State, Ownership, and Lifecycle
Invocation-local immutable configuration and locally owned temporary files. No shared mutable state. Staging is removed on failure. Completed reports persist in the requested output.

## Failure, Concurrency, and Constraints
Typed errors preserve failure; deadlines, cancellation, and output limits never count as verification success.

## Verification and Change Impact
Tests/FormalValidationTests/ToolExecutionTests.swift owns nonzero exit, timeout, cancellation, output cap and descendant cleanup. Consumers are Toolchain and Verification.

An isolated-session option starts the child as session/group leader. Combined with an externally enforced no-fork sandbox, this prevents group/session escape. Group cleanup happens before wait4 reaps the leader and is performed exactly once, so a reused group ID is never killed afterwards. Kernel NOTE_TRACK is not used: the fixed macOS SDK explicitly documents it unsupported since 10.5. Native execution must add a durable launch journal and actual no-fork/session tests at the caller's isolation boundary.

A selected ToolLaunchJournal writes a private artifact-bound intent before spawn, starts the isolated-session leader suspended, publishes PID/start identity before SIGCONT, and records terminal cleanup. Exclusive service recovery checks that identity, or exact launcher argv/private artifact binding for an interrupted suspended spawn, before stopping a session. Record count/bytes and cleanup waiting are bounded. User code must be sandboxed without fork; an isolated session alone does not restrict filesystem/network access.

Each launch-record replacement fsyncs its file and parent directory before returning. Recovery rejects a mismatched record UUID/filename before any signal or journal rewrite, so corrupted metadata cannot select an output path.
