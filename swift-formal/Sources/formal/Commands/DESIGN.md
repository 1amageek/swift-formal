# Commands

## Purpose and Scope
Parse commands, load bounded files, and map typed failures to documented exit codes. Parent: [formal](../DESIGN.md). No child components.

## Responsibilities and Boundaries
Implemented commands: help, version, doctor, inspect-bundle, profiles, translate. Future capture/generate/validate/check/coverage/replay fail with UNSUPPORTED_OPERATION and exit 3. Only explicit draft translation writes a new output directory. Bad arguments and the removed declaration-index command use exit 2.

The executable name is owned by the [package naming contract](../../../DESIGN.md#contracts-and-invariants). Help, version, and diagnostic hints use that invocation.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [formal](../DESIGN.md) | parent | Module boundary | Owned implementation | Recheck consumer assumptions |

## Architecture
```text
Caller -> Commands -> explicit value or error
```

## Contracts and Invariants
Implemented commands: help, version, doctor, inspect-bundle, profiles, translate. Future capture/generate/validate/check/coverage/replay fail with UNSUPPORTED_OPERATION and exit 3. Only explicit draft translation writes a new output directory. Bad arguments and the removed declaration-index command use exit 2.

## State, Ownership, and Lifecycle
State belongs to a call; no global mutable storage. Data and temporary resources remain scoped to the invocation.

## Failure, Concurrency, and Constraints
Failure is propagated or converted to a typed diagnostic. Independent calls share no mutable resources. Limits are selected by the caller and must be positive.

## Verification and Change Impact
Behavior owner: [Tests/FormalCLITests/CommandTests.swift](../../../Tests/FormalCLITests/CommandTests.swift). Changes require rechecking the parent and its consuming CLI integration paths. Metadata verification never establishes semantic equivalence.

## Draft Translation
`translate --language <name> --source <file> --output <new-directory> --draft-unvalidated` invokes SourceCompiling, validates the IR, emits both backends, and independently reparses both actual program files before committing a new directory. Output includes program.json, source.txt, report.json, TLA+, and Lean. The report records exact profile, assumptions, source hash, DRAFT_UNVALIDATED, and no semantic certification. No successful translate command establishes VALIDATED or PROVED. Compilation and emission finish before filesystem mutation; a sibling staging directory is atomically renamed into the requested, previously absent output. Failure removes staging without changing an existing output. The input file is limited to 1 MB by a bounded file read. The draft flag is mandatory. A profiles command lists versioned language profiles. Tests own successful eight-language CLI conversion, no-clobber, missing draft flag, malformed source, and no-output failures.
