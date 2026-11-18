# Structured formal SDK transition

[Package DESIGN](../DESIGN.md) owns composition; leaf designs own semantics. This record owns implemented replacement/removal decisions. [PROGRESS](../PROGRESS.md) records actual behavioral evidence and pending cumulative task checks. Breaking development changes are intentional.

| Implemented responsibility | Contract owner | Removed interface |
|---|---|---|
| Immutable bounded graph/trace/value/document/origin records | [Records](../Sources/FormalEvidence/Records/DESIGN.md) | Inline summaries as a graph SDK |
| Content-addressed SQLite bundles and retained bounded readers | [GraphStore](../Sources/FormalEvidence/GraphStore/DESIGN.md) | Whole graph/log loading as navigation |
| Located compilation and layout2 artifacts | [Compiler](../Sources/FormalCompiler/DESIGN.md) | Bare IR-only compile results and SourceArtifact aggregate/generator |
| Actual SANY semantic structure, TLC states and Lean declaration/term extraction | [Inspection](../Sources/FormalValidation/Inspection/DESIGN.md) | Regex/name-derived proof graph substitution |
| Structured per-obligation results preserving independent checks | [Verification](../Sources/FormalValidation/Verification/DESIGN.md) | Summary-only public report returns |

```text
Exact source -> located compilation -> immutable layout2 artifacts
Actual tools -> independent audit -> evidence axes + original formal graph bundles
Consumers -> retained bounded readers -> original pages/roots/frontiers/origins
```

Artifact layout2, FormalEvidence bundle schema1 and semantic IR versions are independent. Old unsupported artifact layouts fail explicitly; no silent migration or legacy reader is retained. Default consumers keep structural projections separate from private source/values. Missing extraction is unavailable, never an empty successful proof graph.

Actual pinned SANY/TLC and Lean collectors have been built and executed. Lean declaration closure is independently kernel replayed; imported initializers and custom axioms are not accepted as checked proof. User-authored Lean elaboration is executable code, requires explicit caller authority and runs in an isolated bounded session. No downloading, Lake/plugin execution or runtime installation occurs during verification.

Generated-model source correspondence stays UNVALIDATED. Origin ranges describe recorded provenance and do not certify refinement. Ambiguous non-ASCII/tab Java collector columns remain unavailable rather than guessed. Graph scope, availability, paging/truncation and proof outcome remain independent. No general Actor/async semantic or GUI rendering claim follows from this SDK implementation.
