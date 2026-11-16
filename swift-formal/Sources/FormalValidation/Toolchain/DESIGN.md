# Toolchain

## Purpose and Scope
Prepare and verify the pinned macOS arm64 Java, TLC and Lean toolchain. Parent: FormalValidation. No children.

## Responsibilities and Boundaries
Acquisition is permitted only by explicit install/package commands. Checking uses sibling bundled tools with no host PATH fallback.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Parent](../DESIGN.md) | parent | Component composition | Owns consumers | Recheck failures and limits |
| [ToolExecution](../ToolExecution/DESIGN.md) | depends on | Bounded invocation | Archive acquisition and extraction | Installation only |
| [Verification](../Verification/DESIGN.md) | used by | Verified tool paths and policy | Offline verification | No host PATH fallback |
| [Distribution](../../formal/Distribution/DESIGN.md) | used by | Prepare and verify | Packages pinned tools | Preserve inventory and notices |

## Architecture
```text
Pinned artifact policy -> checksum-verified archives -> staged extraction -> pinned file inventory -> portable toolchain
```

## Contracts and Invariants
Archive URLs, SHA-256 and deterministic extracted file inventory digest are trusted package resources. Every tool file, symlink and executable mode is verified against the pinned inventory before execution. Symlinks must resolve inside the toolchain. No system-wide install. Existing cache bytes are rehashed. Only macOS arm64 is supported. Installation preserves upstream licenses and source links. Inventory generation is deterministic and streaming; a modified file or extra executable fails closed.

## State, Ownership, and Lifecycle
Invocation-local immutable configuration and locally owned temporary files. No shared mutable state. Staging is removed on failure. Completed reports persist in the requested output.

## Failure, Concurrency, and Constraints
Typed errors preserve failure; deadlines, cancellation, and output limits never count as verification success.

## Verification and Change Impact
Offline relocation integration owns absent host tools and altered tool rejection. Package preparation owns corrupted archive rejection and no-clobber publication. Changing policy requires rebuilding inventory and rerunning actual bundled Java/Lean/TLC paths.
