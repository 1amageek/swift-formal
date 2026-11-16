# Portable installation and verification

The supported distribution is macOS arm64. A portable folder contains the native
`formal` executable, its two SwiftPM resource bundles, Temurin JRE 21.0.13+9,
TLA+ tools 1.7.4 and Lean 4.35.0. It needs no Java, Lean, Lake, Python, package
manager, source-language compiler or Swift toolchain installation at runtime.
macOS system libraries and tools are used. Other OS/architecture distributions
are unsupported.

```text
Source build -- formal install --> private prefix/bin/formal
               downloads once       |
                                     +--> sibling Java / TLC / Lean
                                     +--> offline generation and checking
Portable folder -- formal install --> same layout, no downloads
```

## Install from source

A Swift toolchain is required to build the package itself:

```sh
swift build -c release
swift run -c release formal install --prefix "$PWD/InstalledFormal"
./InstalledFormal/bin/formal toolchain
```

Installation automatically downloads checksum-pinned archives. `--cache <path>`
overrides the default user cache at `~/Library/Caches/formal/downloads`.
A cache hit is rehashed; corrupted cached archives are rejected. No system-wide
installation or persistent environment change occurs. The destination version
and `bin/formal` must be absent. To replace an installation, use a fresh prefix.

## Prepare a binary distribution

```sh
swift run -c release formal package --output "$PWD/Formal-macos-arm64"
```

Distribute the entire output folder together. End users can run its `formal`
directly or run `./formal install --prefix /chosen/private/prefix`. This second
installation copies the bundled toolchain and works offline. Installed launchers
are relative symlinks, so moving the whole prefix preserves tool discovery.
`package` only creates local files; it does not publish a release or sign/notarize
binaries. Normal macOS downloaded-code policy still applies to distribution.

The uncompressed toolchain occupies about 3 GB; the downloaded ZIP/JRE archives
occupy about 1 GB. Preparation temporarily needs space for both. The full Lean
library is retained to avoid relying on an external installation. Upstream
licenses, notices and corresponding-source links accompany the distribution.
Pinned artifact policy and file inventory are in
[toolchain-artifacts.lock.json](../Tools/toolchain-artifacts.lock.json).

## Universal properties

Use `formal check --language <name> --source <file> --properties properties.json --output Checked` to prove a pre/postcondition for all typed inputs. See [PROPERTIES.md](PROPERTIES.md) for the quantified schema and proof scope. The same bundled tools are used; no additional installation is required.

## Generate and check

Create `cases.json` describing concrete inputs and expected observations:

```json
{
  "schemaVersion": 1,
  "fuel": 512,
  "cases": [
    {
      "name": "addition",
      "entry": "calculate",
      "arguments": ["2", "9"],
      "expected": { "status": "returned", "value": "11" }
    }
  ]
}
```

```sh
formal check --language python --source input.py --scenario cases.json --output Checked
formal check --artifact Checked --scenario cases.json --timeout 120
```

The first invocation generates both backends and runs both verifiers. The second
rechecks existing artifacts. The output parent must exist, and a new generated
output must not exist. A unique `verification/<run-id>/report.json` stores each
run together with actual stdout/stderr logs, proof source and TLC graph or
counterexample. An external verification failure preserves this evidence.

Argument and result values are strings. Integers use canonical decimal notation;
fixed-width bits also accept signed two's-complement notation within range;
booleans accept `true`, `false`, `0`, `1`. Scenarios currently accept scalar
integer and bit values only. `expected.status` is `returned`, `trapped`, `panic`
or `undefinedBehavior`. Only `returned` includes `expected.value`. Failure
expectations compare the kind, not the diagnostic message. Cases require unique
ASCII alphanumeric/underscore names and existing entry symbols. Unknown fields
are rejected. Limits: 32 cases, 128 arguments per case, 256 decimal digits,
4096 execution fuel. Per-tool timeout defaults to 120 seconds and accepts
1...3600. The runner caps each output stream at 8 MiB and kills the process group
on deadline, output limit or cancellation. Java heap is 512 MiB, stack 32 MiB;
Lean uses a 1024 MiB memory limit for finite checks and 2048 MiB for quantified properties, with a 1,000,000-heartbeat proof limit. Each tool workspace has a 512 MiB budget, polled every 250 ms and checked at completion. Resource exhaustion means UNKNOWN.

## Meaning of success

| Axis | Meaning |
|---|---|
| `artifactDataMatchesIR` | Independent decoders agree on actual emitted program data |
| `tlc: MODEL_CHECKED` | TLC completed exploration of the concrete generated-model case, checked the expectation, and reached a terminal state |
| `lean: PROVED` | Lean kernel checked the concrete generated-model outcome theorem using only the pinned standard axiom allowlist |
| `translation: UNVALIDATED` | General source-to-model semantic preservation is not certified |

Runtime hash auditing establishes file identity, not a new proof of runtime
semantics. Source subset assumptions remain in the draft report. These checks
cover supplied concrete cases; they do not prove arbitrary source inputs,
concurrency, Actor behavior or general program correctness. An expected failure
kind can pass verification. An unexpected outcome produces a TLC counterexample
and an unproved Lean theorem. Computation bounds never pass as terminal outcomes.

Exit codes are documented in [CLI.md](CLI.md). Checking performs no downloads and
never falls back to a Java or Lean discovered through PATH. `JAVA_HOME`, Java
option variables, `LEAN_PATH`, `LEAN_SYSROOT` and Elan settings from the caller
are not inherited by verification subprocesses.
