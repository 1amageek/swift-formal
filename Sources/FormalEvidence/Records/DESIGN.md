# FormalEvidence.Records

## Purpose and Scope
Implemented component contract. Own immutable formal evidence, graph and correspondence schemas. Parent: [FormalEvidence](../DESIGN.md). No children. This contract is the sole owner of their serialized meaning.

## Responsibilities and Boundaries
Represent actual formal artifacts and observations. No source indexing, tool execution, UI layout, verification scheduling or interpretation of ArchitectureIR. Compiler provenance is distinct from checked semantic correspondence.

## Related Designs
| Design | Relationship | Contract Used | Summary | Cautions |
|---|---|---|---|---|
| [Module](../DESIGN.md) | parent | Public evidence boundary | Shared immutable data | No phantom production product |
| [Artifacts](../../FormalCompiler/Artifacts/DESIGN.md) | used by | Compilation artifact and origin production | Generator facts | Generator does not certify itself |
| [Inspection](../../FormalValidation/Inspection/DESIGN.md) | used by | Checked declarations and observations | Independent evidence | Absence of data is not an empty complete graph |
| [GraphStore](../GraphStore/DESIGN.md) | used by | Validated records | Paging and ownership | A page is not the entire graph |
| [Invar projection](../../../../Invar/Sources/VerificationExplorer/Publication/DESIGN.md) | used by | Versioned graph semantics | Rendering adaptation | No Explorer dependency here |

## Architecture
```text
source document -> compiler origin -> IR address -> generated document
                                                -> checked artifact
checked artifact -> specification / declaration graph
                 -> explored states and counterexample trace
                 -> Lean dependency graph and verification claims
```

## Contracts and Invariants
### Identity and data records
All IDs are opaque, domain-separated SHA-256 identities over canonical versioned identity records. Graph node identity uses its exact producer/artifact-local key and kind, rather than recursively hashing adjacency. Payload digests and the sealed graph catalog cover actual node/edge content, so cyclic graphs require no recursive hashing. The record identity field itself is excluded from its hashed body; references are validated separately before bundle sealing. Display names and filesystem locations are not identities. Canonical encoding preserves ordered trace steps, arguments and bit patterns; only declared sets are sorted. Distinct producers/profiles remain distinct.

| Record | Semantic responsibility |
|---|---|
| `ArtifactReference` | id, SHA-256, byte count, media type, schema/profile; root-relative private locator is held by the resource owner, not a public URL |
| `DocumentReference` | artifact id, original/generated role, language, byte digest and size; no mandatory whole-body string |
| `TextRange` | document id, half-open UTF-8 start/end byte offsets; `0 <= start <= end <= byteCount`, UTF-8 boundaries checked; line/column are derived presentation values |
| `IRAddress` | program artifact digest, function symbol, block id and optional instruction ordinal; validated against that exact IRProgram; not a cross-revision symbol identity |
| `OriginLink` | source range or explicit missing origin, IR address, generated range, producer/profile, origin kind and precision; one-to-many/many-to-one mappings allowed |
| `CorrespondenceClaim` | source/model artifact digests, relation, semantic profile, scope, assumptions and checked evidence references; `generationOrigin` never implies `semanticsPreserved` |
| `FormalGraphDescriptor` | graph id, graph kind, root artifact digests, producer/tool identity, scope, completeness, counts if known, extraction status and diagnostics |
| `FormalNode` | id, kind, label, typed payload, document/range references, claim ids and provenance; labels are plain text |
| `FormalEdge` | id, source/target node ids, kind, provenance and optional condition/action reference; unknown relation kinds are rejected or explicitly opaque, never recast as dependence |
| `StateValue` | tagged integer/Boolean/bitvector/string/sequence/record/set/opaque value; exact integer decimal strings and bit width/order retained; missing values differ from zero/empty |
| `FormalTrace` | trace id, ordered state/transition references, initial condition, final observation, optional loop-back index, violated obligation and completeness; never sorted as a set |
| `VerificationClaim` | obligation identity, proposition/interpretations, assumptions, domain, quantification/fuel, execution, logical outcome, translation status, tool identities and evidence/artifact references |
| `EvidenceCatalog` / `EvidenceBundleReference` | immutable catalog of documents, graphs, traces, origins and claims; record digests and index digests; extraction availability separate from logical truth |

### Graph kinds and relations
| Kind | Nodes | Permitted meanings |
|---|---|---|
| `tlaSpecification` | module, constant, variable, operator, action, invariant, temporal property | imports, defines, references; action/invariant roles come from analyzed specification/configuration, not capitalization |
| `tlaStateSpace` | observed state and explicit boundary | actual observed transition; action/condition only when provided by the tool; missing action metadata stays unknown |
| `counterexample` | ordered observed states and transitions | checked counterexample path, including loop closure when available; an exploration dump is not automatically a counterexample |
| `leanDeclarations` | module, definition, type, theorem, lemma, axiom, parameter | imports, typeUses, valueUses, transitive usesAxiom; dependencies come from elaborated types/values |
| `leanProofTerm` | actual checked expression nodes and explicit opaque boundaries | expression references and constructor/application structure; no inferred tactic execution timeline |
| `irControlFlow` | IR function, block and instruction | actual IR call/control-flow references; does not assert source-level correspondence |

Lean kernel theorem declarations do not distinguish the source keywords theorem/lemma; preserve such a label only with exact parsed source provenance, otherwise use the kernel theorem kind. Tool-local declaration/state identifiers are qualified by their exact artifact/exploration identity before entering a bundle.

A theorem with no available body has an opaque boundary, not zero dependencies. A failed tactic has no checked proof term and remains unproved/unknown. Proof status, extraction status, graph completeness and source applicability are separate. Renderer colors, coordinates and selection do not enter evidence identities.

Source correspondence is `unvalidated` by default. A validated relation requires the independent checker, exact source/model digests, semantic profile and proof scope. File provenance is useful even when instruction mapping is unavailable; unavailable precise mapping is explicit and never guessed by name or substring search.

### Public schemas
Target schemas are `formal-artifact`, `formal-origin`, `formal-graph`, `formal-trace` and `formal-claim`, with evidence schema major 1. Compilation layout major 2 and existing IRProgram schema major are independent. Unknown major versions fail. There is no reader translating legacy report JSON into invented graph records.

## Failure, Concurrency, and Constraints
Records are immutable Sendable values. Decoding has explicit byte/count/depth/string bounds from the negotiated policy. Malformed references, mixed artifact digests, invalid offsets, cyclic trace-index references and unknown required semantics produce typed errors. Mutual declaration dependencies may form SCCs; source graphs are not forced into a proof DAG.

## Verification and Change Impact
Planned `FormalEvidenceTests` cases **FE-01..04** reject tampered origins, Unicode/range errors, dangling references, precision inflation, reordered traces and fabricated proof status. A graph extracted from a deliberately changed checked term must change its dependency record. Recheck Artifacts, Inspection, GraphStore and Invar projection on schema changes. Shape checks alone do not establish a valid proof or semantic correspondence.

Graph descriptors carry producer-declared root node IDs. Empty roots mean no distinguished root was provided, never a name-based inference. Writers validate unique root identities and membership in the same graph before sealing. Compiler IR roots are function nodes; SANY reports its actual root module identity; TLC records observed initial states/first trace state; Lean declares the requested replayed declaration and actual expression root. Client projections use these roots with bounded neighborhoods instead of choosing arbitrary hash-sorted dependencies.
