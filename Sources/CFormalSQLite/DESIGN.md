# CFormalSQLite

## Purpose and Scope
Native SQLite system module; parent [Formal](../../DESIGN.md). No children.
## Responsibilities and Boundaries
Expose system sqlite3 declarations/linkage only. Evidence storage owns transactions and meaning.
## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Formal](../../DESIGN.md) | parent | Native module composition | System adapter | No external package |
| [GraphStore](../FormalEvidence/GraphStore/DESIGN.md) | used by | SQLite C API | Indexed bounded records | Caller owns handles |
## Architecture
```text
FormalEvidence.GraphStore -> CFormalSQLite -> system sqlite3
```
## Contracts and Invariants
No state, callbacks, allocation or schema policy owned here. macOS native linkage only.
## Verification and Change Impact
FormalEvidenceTests execute actual SQL, transactions and reopen/corruption paths. Recheck GraphStore if linkage changes.
