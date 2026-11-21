# Commands

## Purpose and Scope
Parse commands, load bounded files, and map typed failures to documented exit codes. Parent: [formal](../DESIGN.md). No child components.

## Responsibilities and Boundaries
Implemented commands: help, version, doctor, inspect-bundle, profiles, translate. Future capture/generate/validate/coverage/replay fail with UNSUPPORTED_OPERATION and exit 3. Only explicit draft translation writes a new output directory. Bad arguments and the removed declaration-index command use exit 2.

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
Implemented commands: help, version, doctor, inspect-bundle, profiles, translate. Future capture/generate/validate/coverage/replay fail with UNSUPPORTED_OPERATION and exit 3. Only explicit draft translation writes a new output directory. Bad arguments and the removed declaration-index command use exit 2.

## State, Ownership, and Lifecycle
State belongs to a call; no global mutable storage. Data and temporary resources remain scoped to the invocation.

## Failure, Concurrency, and Constraints
Failure is propagated or converted to a typed diagnostic. Independent calls share no mutable resources. Limits are selected by the caller and must be positive.

## Verification and Change Impact
Behavior owner: [Tests/FormalCLITests/CommandTests.swift](../../../Tests/FormalCLITests/CommandTests.swift). Changes require rechecking the parent and its consuming CLI integration paths. Metadata verification never establishes semantic equivalence.

## Draft Translation
`translate --language <name> --source <file> --output <new-directory> --draft-unvalidated` invokes SourceCompiling, validates the IR, emits both backends, and independently reparses both actual program files before committing a new directory. Output includes program.json, source.txt, report.json, TLA+, and Lean. The report records exact profile, assumptions, source hash, DRAFT_UNVALIDATED, and no semantic certification. No successful translate command establishes VALIDATED or PROVED. Compilation and emission finish before filesystem mutation; a sibling staging directory is atomically renamed into the requested, previously absent output. Failure removes staging without changing an existing output. The input file is limited to 1 MB by a bounded file read. The draft flag is mandatory. A profiles command lists versioned language profiles. Tests own successful eight-language CLI conversion, no-clobber, missing draft flag, malformed source, and no-output failures.

Frontend SourceDiagnostic failures (including unsupported update operators, AST-depth limits, Go constant conversion failures, and C/C++ visibility) propagate as SOURCE_PARSE_FAILED with exit 4 before staging or publication. The Swift source profile's recognized unsupported declarations, tokens and types instead return UNSUPPORTED_SOURCE_PROFILE (exit 3), as owned by the [frontend classification contract](../../FormalCompiler/Frontends/DESIGN.md#swift-source-rejection-classification). No outside-profile rejection asserts that the input is invalid Swift. Native acceptance does not authorize draft artifact creation. Actual CLI tests cover each classification and no-output behavior.

## Integrated Check and Installation
`check --language <name> --source <file> --scenario <json> --output <new-directory>` generates then verifies. `check --artifact <directory> --scenario <json>` rechecks without generation. Optional `--timeout <seconds>` overrides the 120-second per-process default. Scenario bounds belong to [Verification](../../FormalValidation/Verification/DESIGN.md). The CLI composes independent owners and returns the report with its verification exit code. `package --output <new-directory> [--cache <directory>]` and `install --prefix <directory> [--cache <directory>]` own explicit acquisition. Source install defaults to the private user cache; bundled install needs no cache or network. `toolchain` audits installed files and reports pinned versions.

## Universal Properties
`check` accepts exactly one of `--properties <json>` and `--scenario <json>` in both source-generation and artifact-recheck forms. PropertyVerifying owns universal proof semantics, limits and statuses under [Properties](../../FormalValidation/Properties/DESIGN.md). Validate specification syntax before generation, then compose the audited proof pipeline. The scenario mode remains finite case checking.

Java and Bun are explicit `--language java` / `--language bun` selections for translate/check. Profiles list their source assumptions. Both compose existing finite and universal verification without running a Java source compiler or Bun runtime. The [frontend contract](../../FormalCompiler/Frontends/DESIGN.md#java-and-bun-profiles) owns supported syntax and integer widths.


JS-family profiles advance to scalar-v2 for inferred Number/BigInt types; check supports Number views. The 0.4.0 layout and runtime trust policy require regenerating older artifacts. [Frontend](../../FormalCompiler/Frontends/DESIGN.md) and [Number execution](../../FormalIR/Execution/DESIGN.md#binary64-number-contract) own grammar and semantics.
