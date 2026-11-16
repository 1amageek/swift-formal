# Distribution

## Purpose and Scope
Create and install relocatable macOS arm64 CLI distributions. Parent: formal. No children.

## Responsibilities and Boundaries
Compose toolchain acquisition and public compiler/validation resource locations. No release or external publication.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Parent](../DESIGN.md) | parent | Component composition | Owns consumers | Recheck failures and limits |
| [Toolchain](../../FormalValidation/Toolchain/DESIGN.md) | depends on | Prepare and verify | Bundled tool ownership | Private installation only |
| [FormalCompiler](../../FormalCompiler/DESIGN.md) | depends on | CompilerResources.bundleURL | Copies complete resource bundle | Resource bytes unchanged |
| [Commands](../Commands/DESIGN.md) | used by | Package and install | CLI entry | No publishing |

## Architecture
```text
formal package -> new portable directory -> formal install --prefix -> prefix/bin/formal symlink
```

## Contracts and Invariants
Versioned layout is prefix/libexec/formal/0.2.0 with executable, exact SwiftPM resource bundles, toolchain and notices. Install and package refuse existing destinations and bin/formal. Publication uses sibling staging and atomic rename. Source installations fetch pinned tools automatically; a bundled executable installs offline using its verified sibling toolchain. Resolving executable symlinks makes prefix moves valid. Checks never download tools.

## Runtime Flows
Resolve the running executable through Foundation, stage it and both explicit resource bundles, then acquire tools or copy an already verified sibling toolchain. Verify copied tools, write notices, and atomically publish the portable directory. Installation publishes into the versioned prefix and finally creates a relative launcher; launcher failure removes only the newly published version.

## State, Ownership, and Lifecycle
Invocation-local immutable configuration and locally owned temporary files. No shared mutable state. Staging is removed on failure. Completed reports persist in the requested output.

## Failure, Concurrency, and Constraints
Typed errors preserve failure; deadlines, cancellation, and output limits never count as verification success.

## Verification and Change Impact
Tools/verify-distribution.py owns installation from source build, subsequent offline installation, relocation, poisoned host PATH and no-clobber. All package/module consumers must retain model-only verification scope.
