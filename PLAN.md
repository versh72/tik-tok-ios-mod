# PLAN.md

## Where this stands

Stages 1–3 of the brief are done. Stage 4's documents and code are written.
**The Swift code has not been compiled** — see § "How to verify" first.

| Stage | Status |
|---|---|
| 1. Repository research | **DONE** — all four cloned and read. See [RESEARCH.md](RESEARCH.md) |
| 2. iOS architecture analysis | **DONE** — constraints verified against Apple docs. See [ARCHITECTURE.md](ARCHITECTURE.md) |
| 3. Diagnostic tool design | **DONE** — and implemented |
| 4. Documents + code + tests | **DONE** — 24 library source files + 1 entry point, 6 test files, 5 documents |
| Compilation | **NOT DONE** — no Swift toolchain on the authoring machine. Closable via CI, see [CI-BUILD.md](CI-BUILD.md) |
| On-device verification | **NOT DONE** — no device |

---

## What is built

```
├── RESEARCH.md, ARCHITECTURE.md, COMPATIBILITY.md, PLAN.md, README.md, CI-BUILD.md
├── .gitignore                    excludes build output and signing material
├── project.yml                   XcodeGen spec for the app target
├── .github/workflows/            cloud macOS build -> unsigned .ipa (no Mac needed)
├── App/                         @main entry point + Info.plist
├── NetDiag/                     Swift package
│   ├── Package.swift            4 targets
│   ├── Sources/NetDiagCore/     13 files — pure logic, no UI, no Network
│   ├── Sources/NetDiagEngine/   4 files — Network.framework
│   ├── Sources/NetDiagUI/       7 files — SwiftUI
│   └── Tests/NetDiagCoreTests/  6 files, 11 XCTestCase classes, 114 tests
└── Tools/verify-sources.mjs     84 static checks
```

4,376 lines of Swift in total.

### The implementation order, and why it was that order

1. **Models and protocols first** (`ProbeTarget`, `DNSReport`, `TLSReport`,
   `HTTPSReport`, `DNSResolving`/`TLSProbing`/`HTTPSProbing`). Defining the I/O
   boundaries before writing any I/O is what allowed every later stage to be
   tested with fakes.
2. **`FailureClassifier`.** The explanation table drives the whole UI. Writing it
   second meant the vocabulary of the failure states was settled before any
   screen referenced it.
3. **`Redactor`.** Built before the log and the report, not after. Retrofitting
   redaction is how secrets end up on disk once.
4. **`ProbeCoordinator`.** Orchestration is where the "first cause, not last
   cause" rule lives; encoding it in one testable place made it a unit test
   rather than a hope.
5. **`RunComparator`.** The reason the tool exists. Built with fakes before the
   engine so the comparison could be verified without a network.
6. **Engine.** `SystemDNSResolver`, `NetworkTLSProber`, `URLSessionHTTPSProber`,
   `NetworkPathObserver`.
7. **UI last**, against a finished vocabulary.
8. **Tests written alongside each unit**, not at the end — the coordinator tests
   existed before the coordinator's collaborators were real.

---

## How to verify

### Step 0 — no Mac? (the default case)

The owner of this project has no Mac, and Xcode is macOS-only, so a local
build is impossible. **The test suite can still be run**, on a hosted macOS
runner, for free in a public repository:

1. `git init && git add . && git commit` and push to a **public** GitHub repo.
2. The **Actions** tab runs `.github/workflows/build-ios.yml`, which executes
   `swift build` and `swift test` on a real Mac, builds an unsigned arm64
   `.ipa`, and uploads it.
3. Download the artifact, install with **Sideloadly** on Windows, turn on
   Developer Mode on the iPhone.

That first CI run closes the largest gap in this document: whether the Swift
compiles at all. Full walkthrough in [CI-BUILD.md](CI-BUILD.md).

### Step 1 — what can be checked here, now

```bash
node Tools/verify-sources.mjs
```

84 checks: package structure, layer boundaries, safety invariants (no ATS
relaxation, no interception, no jailbreak API, no VPN API, no `@main` in a
library), secret-shaped literals, test-to-source type coherence, disclaimer
presence, document presence, cloud-workflow correctness (including that no
Apple ID or password can reach CI), and repository hygiene.

This is **not** a substitute for a compiler. It reads text, not types. It was
built because the alternative was asserting "it builds" without evidence.

### Step 2 — the compile (any Mac, including a CI runner)

```bash
cd NetDiag
swift build          # builds the package (Core + Engine; UI needs a UI platform)
swift test           # runs the NetDiagCoreTests suite
```

`swift test` needs **no device and no simulator** — that is the payoff of
keeping `NetDiagCore` free of SwiftUI and Network.

Expected friction, in the order it is likely to appear:

| Symptom | Where | Fix |
|---|---|---|
| `tls_ciphersuite_name` unresolved | `NetworkTLSProber.evaluate` | Remove the call; the hex fallback already exists |
| `SecCertificateCopyValues` warning | `NetworkTLSProber.certificateValidity` | Expected. Suppress or accept |
| `Verdict.Grade(worst:)` ambiguous | `DiagnosticRun.swift` vs Swift's `max()` | The variadic overload is defined; if it collides, rename to `Verdict.Grade(combining:)` and update the 3 call sites |
| `@main` rejected | — | Should not happen: `@main` is in `App/`, outside the package. If Xcode complains, the file was added to the wrong target |

### Step 3 — the app, on a real iPhone

1. `brew install xcodegen`, then `xcodegen generate` in the project root
   (`project.yml` describes one iOS app target depending on the local package).
   Or create the target by hand: iOS App, SwiftUI, add
   `App/TikTokNetDiagApp.swift`, add the local package `NetDiag`, depend on
   `NetDiagUI`.
2. Signing: **Automatically manage signing**, team = Personal Team.
3. On the iPhone (iOS 16+): Settings → Privacy & Security → Developer Mode → on
   → restart → confirm.
4. Run. Reinstall every **7 days** — free profiles expire, and the app stops
   launching until you do.

### Step 4 — the experiment this tool exists for

1. Label the run **"VPN off"** and run it.
2. Connect the tunnel. Label the run **"VPN on"** and run it again.
3. Open **Compare**.

That comparison is the deliverable. Nothing else in this repository substitutes
for it.

---

## Test inventory

`swift test` will run 11 `XCTestCase` subclasses containing 114 test functions. Grouped by what they protect:

| File | Tests | Protects |
|---|---|---|
| `EndpointValidatorTests` | 30 | Bad input is rejected before it becomes a confusing network error; query strings never survive parsing |
| `ReportBuilderTests` + `VerdictTests` + `PathSnapshotTests` | 23 | Disclaimer always present; no secret in Markdown or JSON; byte-stable output; worst-grade-wins; VPN caveat in both languages |
| `FailureClassifierTests` | 21 | Failure buckets are correct, and unrecognised input is never guessed |
| `LogAndStoreTests` (log, comparator, store, presets) | 19 | Capacity, redaction on write, regression/improvement detection, in-memory ordering, preset validity |
| `RedactorTests` | 15 | Secrets never reach a log or an export |
| `ProbeCoordinatorTests` | 9 | Stage short-circuiting, first-cause reporting, never-throwing |

Highest-value cases, if only a handful are read:
`testQueryStringIsDiscardedAtParseTime`, `testDNSFailureStopsLaterStagesAndIsReportedAsDNS`,
`testSecretInTargetNoteNeverReachesTheReport`, `testSummaryIsHedgedEvenWhenEverythingPasses`,
`testUnrecognisedURLCodeIsNotGuessed`.

---

## What would come next, in priority order

1. **Build it.** Nothing below matters until the code compiles and the tests
   run. This is the only genuinely blocking item.
2. **Run the two-run comparison on a real device.** Validates the whole premise.
3. **DoH / DoT comparison.** The gap between `getaddrinfo` and an encrypted DNS
   query is the single most informative measurement still missing, and it would
   separate "DNS is being tampered with" from "the answer is genuinely absent".
   Uses public resolvers the person configures; no interception.
4. **Per-stage raw error capture.** `ProbeError` already carries a stage;
   surfacing per-stage detail in the UI is a small change.
5. **TTL-observed DNS comparison.** Would make "did the answer change between
   runs" a measurement rather than an inference.
6. **Localisation beyond EN/RU.** The `DiagnosticsExplainer` shape supports it;
   only the string tables would be added.

## What will not be built, and why

| Idea | Why not |
|---|---|
| TikTok modification of any kind | Requires a jailbreak, a decrypted IPA, or a device-wide root CA. None is free, and none is current. See RESEARCH.md |
| MITM / proxy | Would require a trusted root CA on the device, reducing TLS security for every app. The brief forbids it and it is bad engineering |
| TLS trust override | Would report "healthy" on exactly the broken path this tool detects. `verify-sources.mjs` fails the build if one appears |
| Reading TikTok's traffic | No public API. Attempting it would mean MITM, which is the previous row |
| Cloud sync of reports | Would create a data store to protect for zero benefit |
| Auto-upload of diagnostics | Same, plus a privacy problem |