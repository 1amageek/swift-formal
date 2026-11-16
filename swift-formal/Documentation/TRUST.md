# Trust boundaries

## Current evidence
The operational CLI performs metadata and byte-integrity inspection only. Experimental libraries additionally parse scalar SIL, lower to IR, and emit both backends. SHA-256 does not establish SIL correctness or semantic equivalence. The package has no external SwiftPM dependencies. Toolchain identity contains compiler/runtime metadata only. Declaration indexing and source-project metadata adapters are outside this package.

Compiler probing invokes `swiftc -print-target-info` through an argument array. Probe processes have a deadline and bounded output files. This runner is not an isolation mechanism for arbitrary Lean code or untrusted build tools. No current CLI command evaluates SwiftPM manifests.

All mutable implementation state is invocation-local. No shared state, unchecked Sendable conformance, Embedded branch, GPU execution, daemon, or AsyncStream exists.

## Required v1 guarantee
The completed compiler must independently read original SIL, validate all lowering rules, reparse actual TLA+ output, and kernel-check Lean certificates without admitted proofs or unauthorized axioms. Both backends must preserve the same supported semantics, including Actor scheduling. Current tests establish scalar output well-formedness, five finite TLC scenarios, four Lean execution proofs, independent Lean decoding/data equality, and restricted actual-output decoding. They do not establish the full input-SIL step relation or Actor semantics. Strict generation remains disabled.

The future TCB includes the fixed Swift compiler, independent SIL decoder, reference semantics, Lean kernel and explicit axiom allowlist, runtime models, and the limited TLA syntax semantics/decoder. TLC finite checking must remain distinct from a general proof. See SPEC section 11 for the authoritative requirements.

## State and isolation review

| Owner | Mutable storage | Reachability and lifetime | Isolation contract |
|---|---|---|---|
| Canonical parser reader and scalar token cursor | Local arrays, cursor, maps | Created inside one parse/lower invocation; never escapes | No shared state |
| IR interpreter frames and environments | Local frames, caller stack, value dictionaries | Owned by one synchronous run; no callbacks or tasks | No shared state |
| Compiler probe | One Process and temporary output handles | Owned by one async invocation with deferred cleanup | Concurrent probes use separate instances and UUID paths |
| Public library configurations and program values | Immutable Sendable records | May cross task boundaries | Mutation creates independent value state |

No conditional synchronization or target-dependent Sendable branches exist. These facts establish the current macOS path only; WASM/Embedded runtime behavior is not tested or claimed.
