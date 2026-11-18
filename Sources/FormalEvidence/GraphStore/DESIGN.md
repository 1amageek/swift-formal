# FormalEvidence.GraphStore

## Purpose and Scope
Implemented component contract. Own failure-atomic evidence-bundle storage and bounded graph/trace/artifact reads. Parent: [FormalEvidence](../DESIGN.md). No children.

## Responsibilities and Boundaries
Validate and store records produced by Compiler/Validation; serve fixed-bundle queries without loading an entire state space. No parsing of application sources, execution, truth assessment or Explorer serialization.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Module](../DESIGN.md) | parent | Library boundary | Resource composition | Implemented SDK |
| [Records](../Records/DESIGN.md) | depends on | Evidence record invariants | Data meaning | Store cannot upgrade evidence claims |
| [Inspection](../../FormalValidation/Inspection/DESIGN.md) | used by | Streaming bundle writer | Tool output publication | Seal only validated record sets |
| [Invar evidence](../../../../Invar/Sources/VerificationCore/Evidence/DESIGN.md) | used by | Retained artifact references | Shared evidence queries | Caller retains the bundle lease |

SQLite owns indexed bounded rows, adjacency and document chunks in one immutable sealed database. Rows retain independent payload digests; the published database has a complete digest checked once on open under its explicit budget. Each returned row/chunk is checked again. Queries do not reload the database into memory.

## Architecture
```text
bounded record batches -> staging + indexes -> digest validation -> atomic sealed bundle
sealed bundle lease -> catalog / roots / neighborhood / trace window / document range
```

## Contracts and Invariants
Public interfaces:
```swift
public protocol FormalEvidenceReading: Sendable {
    func catalog() async throws -> EvidenceCatalog
    func graph(_ query: FormalGraphQuery) async throws -> FormalGraphPage
    func trace(_ query: FormalTraceQuery) async throws -> FormalTracePage
    func origins(_ query: OriginQuery) async throws -> OriginPage
    func document(_ query: DocumentRangeQuery) async throws -> DocumentChunk
    func shutdown() async throws
}
public protocol FormalEvidenceOpening: Sendable {
    func open(_ reference: EvidenceBundleReference,
              budget: EvidenceReadBudget) async throws -> any FormalEvidenceReading
}
```
`LocalFormalEvidenceStore` opens the implemented retained reader; EvidenceBundleWriter owns publication. Identical immutable record writes converge; different content or parent under the same identity is rejected. A failed optional extraction can discard its entire graph (descriptor, nodes, edges and traces) before sealing, without changing other graphs or verification claims. Cursors are replayable within a bounded reader-owned LRU window; eviction yields invalidCursor and never resumes under a different query. A writer accepts bounded validated batches, finishes indexes/checksums, fsyncs data/directories and atomically publishes the manifest last. Failed extraction can retain a separately sealed partial bundle with diagnostics; it cannot label a complete graph. A caller asking for complete extraction receives a typed incomplete result/error.

Queries identify bundle/graph digests, root/focus, relation filters, direction, depth and page budget. Cursors bind the immutable bundle, query hash and position. Pages carry represented roots, frontier/omitted boundaries, counts if known, completeness and next cursor. Edges either include both endpoints or use explicit boundary nodes. Paging cannot silently drop cross-page relations. Trace windows preserve step indices and loop-back references even when endpoints are outside the window. `moreAvailable` is a query property, not an incomplete model-checking verdict.

Artifacts are accessed by catalog IDs and checked ranges, never arbitrary caller paths/URLs. No symlink traversal or executable artifacts are followed. A sealed digest-bound chunk index records offsets, sizes and per-chunk hashes. Opening validates the manifest/index; every returned range validates its affected chunks. Full-object hashing happens during publication or explicit integrity audit and is charged to its own budget, not repeated for every graph page. A missing range-integrity capability cannot claim a verified partial read. Sources and values are private by default; authorization/redaction belongs to the caller's delivery boundary.

## State, Ownership, and Lifecycle
The opener supplies an approved root and a retained bundle lease. The reader actor owns descriptors, small index/page caches and in-flight operations. `shutdown` rejects new reads, cancels/drains owned reads and closes descriptors before returning. A returned page owns its bounded value data; borrowed spans never outlive an explicit owner. Queues contain references, not source copies. Cache capacity is charged to the caller's memory budget; no global mutable cache.

## Failure, Concurrency, and Constraints
Effective limits are the minimum of caller budget, format caps, backend capabilities and remaining parent deadline. Bound page nodes/edges/bytes, depth, trace window, document chunk, index cache and concurrent reads. Checked arithmetic is used before allocation. Limit exhaustion returns frontier/next cursor when a valid partial page is possible; it never reports truncation as completeness. Unknown schema, corrupt index, expired lease, invalid cursor, missing body and permissions are distinct errors. No speculative operational defaults are frozen here; the host policy selects/persists them and must pass boundary/contention tests when changed.

## Verification and Change Impact
Planned `FormalEvidenceTests` **FE-05..07** cover multi-page edges, incomplete/large graph bounds, trace windows/loops, corrupt indexes, concurrent reads versus shutdown, lease release and input retention. Differential fixtures compare all paged records with an independent small reference graph. Recheck Records, Inspection and Invar client/projection consumers when query or lifetime contracts change.

Graph descriptors carry producer-declared root node IDs. Empty roots mean no distinguished root was provided, never a name-based inference. Writers validate unique root identities and membership in the same graph before sealing. Compiler IR roots are function nodes; SANY reports its actual root module identity; TLC records observed initial states/first trace state; Lean declares the requested replayed declaration and actual expression root. Client projections use these roots with bounded neighborhoods instead of choosing arbitrary hash-sorted dependencies.
