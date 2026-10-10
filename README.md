# TikTok iOS Mod — research, and the part that is actually buildable

## The finding, up front

**A TikTok MOD for iPhone is not achievable.** Not "hard" — not achievable.
Three independent technical reasons, each confirmed from source or Apple
documentation:

| # | Blocker | Evidence |
|---|---|---|
| 1 | **iOS enforces that code signature matches content.** Modify any byte and the app will not launch | Apple Platform Security: *"require that all executable code be signed using an Apple-issued certificate… helps prevent third-party apps from loading unsigned code resources"*. Failure: `0xe8008017` |
| 2 | **Team ID is checked on every dylib load at launch.** Your code cannot load into TikTok | Same source: a library must carry *"the same team identifier in its code signature as the main executable"* |
| 3 | **The only working mechanism tops out at iOS 17.0. Current iOS is 27.0.1** | TrollStore README: *"16.7.x and 17.0.1+ will NEVER be supported"*. Both exploits it uses (CVE-2022-26766, CVE-2023-41991) are patched by Apple |

The working mechanism **is** a signature bypass via an exploit — which your
brief explicitly excludes (*«Не обходи проверки подписи, не используй эксплойты»*).

## The more important finding

Even if all of that were solved, **a mod would not give you a working feed.**

The most mature Android projects say so themselves:

> **HushFeed** (184★, GPL-3.0, active): *"It may not change your region, since
> TikTok also goes by your internet connection and account."*
>
> **tiktok-region-hook** (24★): *«本模块不能替代可用的国际网络环境；TikTok
> 服务端仍会结合 IP、账号和其他风控信号判断可用性。»* — this module cannot
> replace a working international network; TikTok's servers still judge
> availability by IP, account and other risk signals.
>
> **krolchonok/TiktokPatchXposed** (25★): observed failures lean toward
> *"账号或服务端风控"* — account- or server-side risk control.

I read the code of ten Android modding projects. **Not one contains a proxy, a
tunnelling library, or a hosts file.** Every mechanism works on three client-side
layers only:

1. System carrier APIs — `TelephonyManager`, `SubscriptionInfo`, `ServiceState`
2. System properties — `gsm.*`
3. TikTok's own request parameters — `f_global_*`, TTNet common params

None touches the network transport. The mechanism changes what the app *says it
is*. The server decides based on the *IP it sees*.

**So "a mod works without VPN" means without manually toggling a VPN — not
without a tunnel.** `免拔卡` means "no need to switch by hand". The instruction
in `i90O/tiktok-ios-ipa` step 5 still says: *"打开Shadowrocket添加节点，开启科学
上网"* — add a node, turn the proxy on.

---

## What is in this repository

| File | Contents |
|---|---|
| **[ANDROID_ANALYSIS.md](ANDROID_ANALYSIS.md)** | What Android mods actually do. 10 projects with real source, quoted code |
| **[IOS_ANALYSIS.md](IOS_ANALYSIS.md)** | iOS constraints, TrollStore ceiling, comparison table |
| **[ARCHITECTURE.md](ARCHITECTURE.md)** | Hypothesis/confirmation/limits/conclusion table + the buildable architecture |
| **[IMPLEMENTATION_PLAN.md](IMPLEMENTATION_PLAN.md)** | Implementation order, verification, next steps |
| **[RESEARCH.md](RESEARCH.md)** | Original four-repo analysis |
| **[COMPATIBILITY.md](COMPATIBILITY.md)** | Version matrix, CONFIRMED vs UNKNOWN |
| **[CI-BUILD.md](CI-BUILD.md)** | Building without a Mac |
| `NetDiag/` | Swift package: 24 source files, 114 unit tests |

### What was built, and why it is not a substitute

A **network diagnostic app**. It measures the network path from the device and
tells you what it found.

This does not replace the mod. It answers the question that decides whether a
mod would help at all: **is the empty feed a server-side regional policy, or is
the path broken?** Those need different responses, and no client-side patch
distinguishes them.

---

## Read this first: three things this tool will not tell you

Enforced by tests and by `Tools/verify-sources.mjs`.

| Claim | Reality |
|---|---|
| "The probe passed, so TikTok will work." | **No.** A passing probe proves one host was reachable on one path at one moment |
| "This app can tell whether your VPN is on." | **No.** `NEVPNManager` needs a paid Apple entitlement |
| "This app can see what TikTok is doing." | **No.** iOS sandboxes every app |

The first disclaimer is on the main screen, embedded in every exported report,
and repeated wherever a result could be over-read.

---

## What it actually does

```
DNS  →  TLS  →  HTTPS
```

- **DNS** — `getaddrinfo`, so the answer is the one the rest of the device gets,
  including any tunnel's DNS settings.
- **TLS** — real `NWConnection` handshake. **The system trust evaluation is not
  overridden.** If a tunnel terminates TLS with its own certificate, this fails —
  and that failure is the finding.
- **HTTPS** — `HEAD`, falling back to `GET`. Status, TTFB, total time, redirects.

**Stages short-circuit on the first cause.** If DNS fails, TLS will fail too, and
reporting "TLS failed" sends you to the wrong problem. The report says "DNS".

### The comparison — the actual deliverable

```
Run A  "VPN off"   example.com → DNS ✓  TLS ✓  HTTPS 200
Run B  "VPN on"    example.com → DNS ✓  TLS ✗  (untrusted root)
                   ────────────────────────────────────────────────
                   changed: passed → failed, tlsCertificateRejected
```

One run cannot separate "the device is broken" from "this path is broken".
Two runs can.

---

## The two-minute check, no build required

Open in Safari, twice: with the tunnel off, then on.

**A** (needs DNS): `https://www.cloudflare.com/cdn-cgi/trace`
**B** (IP literal, no DNS): `https://1.1.1.1/cdn-cgi/trace`

| A | B | Conclusion |
|---|---|---|
| ✗ | ✗ | The tunnel is not carrying traffic |
| ✗ | ✓ | **DNS is broken** |
| ✓ | ✓ | The tunnel works — the problem is elsewhere |

Compare `ip=` and `loc=` between runs. If the VPN app says "United States" and
`loc=RU`, the tunnel connected but is not routing.

If your App Store is region-restricted, the free diagnostic apps may be missing
there too. The Safari check above needs nothing.

---

## Read this first: three things this tool will not tell you

They are also enforced by tests and by `Tools/verify-sources.mjs`.

| Claim | Reality |
|---|---|
| "The probe passed, so TikTok will work." | **No.** A passing probe proves one host was reachable on one path at one moment. It says nothing about any other host, and nothing about what any application can reach. |
| "This app can tell whether your VPN is on." | **No.** `NEVPNManager` needs a paid Apple entitlement. The app reports the interface it can see and says plainly that the VPN question is outside what an ordinary app can observe. |
| "This app can see what TikTok is doing." | **No.** iOS sandboxes every app. No third-party app can read another's traffic. |

The app shows the first disclaimer on its main screen, embeds all three in every
exported report, and repeats them wherever a result could be over-read.

---

## What it actually does

For each target you enter, three independent stages:

```
DNS  →  TLS  →  HTTPS
```

- **DNS** — `getaddrinfo`, so the answer is the one the rest of the device would
  get, including any tunnel's DNS settings. A hand-rolled UDP query would give a
  different, misleading answer.
- **TLS** — real `NWConnection` handshake. **The system trust evaluation is not
  overridden.** If a tunnel terminates TLS with its own certificate, this fails
  — and that failure is the finding. A tool that accepts every certificate would
  report "healthy" on exactly the path it exists to detect.
- **HTTPS** — `HEAD`, falling back to `GET`. Status, time-to-first-byte, total
  time, redirect count, byte count.

**Stages short-circuit on the first cause.** If DNS fails, TLS will fail too —
and reporting "TLS failed" would send you to the wrong problem. The report says
"DNS failed".

### The comparison

The reason it takes two runs:

```
Run A  "VPN off"   example.com → DNS ✓  TLS ✓  HTTPS 200
Run B  "VPN on"    example.com → DNS ✓  TLS ✗  (untrusted root)
                   ────────────────────────────────────────────────
                   changed: passed → failed, tlsCertificateRejected
```

One run cannot separate "the device is broken" from "this path is broken". Two
runs can. **That comparison is the deliverable.**

---

## Requirements — no Mac needed

**You do not need a Mac at all.** Xcode is macOS-only and Swift
Playgrounds is iPad-only, so neither works from a Windows or Linux machine. A
GitHub-hosted macOS runner builds the app for free (public repo), and Sideloadly
on your own PC signs and installs it. Full walkthrough in
[CI-BUILD.md](CI-BUILD.md).

| Route | macOS needed | Cost | Gives you |
|---|---|---|---|
| **A. Cloud build → Sideloadly** | No | Free | **The real app**, with DNS / TLS / HTTPS timing |
| **B. iOS Shortcuts** | No | Free | Reachability + end-to-end timing |
| **C. Free App Store tools** | No | Free | Ping, DNS lookup, cert details, VPN detection |

| Requirement | Detail |
|---|---|
| To build the package by hand | macOS + Swift 5.9 toolchain (Xcode 15+) |
| To run unit tests by hand | macOS only. **No device, no simulator needed** |
| To run the app on an iPhone | iPhone on **iOS 16+**, an Apple Account, and one of routes A–C |
| Paid Apple Developer account | **Not required** |
| Jailbreak | **Not required** |

### The 7-day catch

Free "Personal Team" profiles **expire after 7 days**, with a limit of **3
devices** and **3 apps per device**
([Apple](https://developer.apple.com/help/account/basics/about-your-developer-account)).
When it expires, reinstall and it runs again. That is Apple's design for the
free tier, not a limitation of this code. Sideloadly re-signs automatically
every few days, which usually hides this.

---

## Running it

### 0. No Mac? Start here

**The two-minute check that may end the whole investigation:** install **Netti**
(`1595456600`) from the App Store and run it with the tunnel off and then on.
If the external IP does not change, the VPN is not carrying your traffic, and
the reason TikTok's feed is empty is the VPN — not TikTok, and not anything this
app could fix.

Then set up [CI-BUILD.md](CI-BUILD.md) → Route A for the full tool.

### 1. Run the tests (no device needed)

```bash
cd NetDiag
swift test
```

11 test classes, 114 test functions. The suite touches only `NetDiagCore`, which
imports no UI or networking framework — that is what keeps it runnable without a
simulator.

### 2. Run the static verification (works anywhere Node runs)

```bash
node Tools/verify-sources.mjs
```

84 checks over the sources: package structure, layer boundaries, safety
invariants, secret literals, test-to-source type coherence, disclaimer presence.
It reads text, not types — it is **not** a compiler, and `swift build` is still
the real check.

### 3. Build the app

**Option A — Cloud, no Mac needed (see [CI-BUILD.md](CI-BUILD.md)):**

Push to a **public** GitHub repo. `.github/workflows/build-ios.yml` runs on a
hosted macOS runner (free), executes `swift test`, builds an **unsigned**
arm64 `.ipa`, and uploads it as an artifact. Install it with **Sideloadly** on
your own PC using your own Apple ID — the Apple ID never reaches the cloud.

**Option B — XcodeGen, on a Mac:**

```bash
brew install xcodegen
xcodegen generate
open TikTokNetDiag.xcodeproj
```

**Option C — by hand, on a Mac:** new iOS App target, SwiftUI, then

1. add `App/TikTokNetDiagApp.swift` to the target
2. File → Add Package Dependencies → Add Local → select the `NetDiag` folder
3. add `NetDiagUI` to **Frameworks, Libraries, and Embedded Content**
4. Signing & Capabilities → **Automatically manage signing**, team = your
   Personal Team

### 4. Run on your iPhone

Sideloaded apps need Developer Mode on iOS 16+:
**Settings → Privacy & Security → Developer Mode** → on → restart → confirm.

For the cloud route, connect by USB and install with Sideloadly. For the Xcode
route, select the device and press **Run**. Reinstall every 7 days either way.

### 5. Do the actual experiment

1. Scenario field → `VPN off` → **Run check**.
2. Connect the tunnel. Scenario → `VPN on` → **Run check**.
3. Open the **Compare** tab.

Targets default to generic public reference endpoints (Apple, Cloudflare DNS,
Wikipedia, GitHub, IANA). They are **not** application endpoints and carry no
account data. Delete any you don't want, or add your own.

---

## Project layout

```
RESEARCH.md            What the four repositories contain, with evidence
ARCHITECTURE.md        Design, platform constraints, privacy properties
COMPATIBILITY.md       Version table, CONFIRMED vs UNKNOWN
PLAN.md                Implementation order, test inventory, next steps
CI-BUILD.md            Building and installing without a Mac
project.yml            XcodeGen spec for the iOS app target
.github/workflows/     Cloud macOS build -> unsigned .ipa (no Mac needed)
App/                   @main entry point + Info.plist (outside the package)
NetDiag/
  Package.swift        4 targets: Core, Engine, UI, CoreTests
  Sources/NetDiagCore/     13 files — pure logic, no SwiftUI, no Network, no UIKit
  Sources/NetDiagEngine/    4 files — Network.framework + URLSession
  Sources/NetDiagUI/        7 files — SwiftUI screens + ViewModel
  Tests/NetDiagCoreTests/   6 files, 11 XCTestCase classes, 114 test functions
Tools/verify-sources.mjs   84 static checks
```

24 library source files plus one app entry point, 4,376 lines of Swift in total.

`NetDiagCore` holding no I/O is the load-bearing decision: it is why the whole
test suite runs without a device.

---

## Privacy

| Property | How |
|---|---|
| Nothing leaves the device | No analytics, no telemetry, no crash reporting, no upload |
| No cookies or credentials | `URLSessionConfiguration.ephemeral`, cookies disabled, `urlCache = nil` |
| No headers recorded | Only status, timing, byte count are read. Header dictionaries are never touched |
| No response bodies | Read to a 4 KiB cap to count bytes, then discarded |
| Query strings dropped at parse time | `EndpointValidator` strips `?…` before a target exists |
| Free text redacted before writing | Tokens, credentials, e-mails, opaque blobs masked |
| No VPN config read | `NEVPNManager` is never imported |
| Nothing persisted | History is in-memory and dies with the process |

Redaction has its own tests: `testSecretsAreRedactedOnTheWayIn`,
`testSecretInTargetNoteNeverReachesTheReport`,
`testSecretInScenarioNeverReachesTheReport`.

The hash in `Redactor` is FNV-1a, **explicitly not cryptographic**. It exists so
two different tokens can be told apart in a report without either being
recoverable. Nothing secret is protected by it.

---

## Status, stated plainly

| | |
|---|---|
| Repository research | **Done.** All four cloned and read |
| Platform analysis | **Done.** Verified against Apple documentation |
| Code written | **Done.** 24 library source files + 1 app entry point, 6 test files |
| **Code compiled** | **NOT DONE.** No Swift toolchain on the authoring machine |
| **`swift test` executed** | **NOT DONE.** Same reason |
| **Run on a device** | **NOT DONE.** No device available |
| `verify-sources.mjs` | **Done.** 84 checks, all passing |

**Nothing in this repository has been compiled or run on a device.** The design
decisions and the research are verified; the Swift is unverified. Run
`swift test` first — it is the single highest-value next step.

Two build risks are flagged in [COMPATIBILITY.md](COMPATIBILITY.md) § A:
`SecCertificateCopyValues` is deprecated by Apple, and `tls_ciphersuite_name(_:)`
availability was not checked. Both are isolated to one function each, and the
cipher lookup already has a hex fallback.

---

## What was researched, in one table

| Repository | Platform | Requires | Status | Useful for iOS diagnosis? |
|---|---|---|---|---|
| [tiktokmodcloud](https://github.com/namecallfilter/tiktokmodcloud) | Android (APK) | Bun | Active, 2026 | **No** — zero iOS content |
| [TikTok-Tweaks](https://github.com/tuxi/TikTok-Tweaks) | iOS | macOS + Xcode + decrypted IPA, MonkeyDev | Abandoned 2023 | **No** — injections no longer authenticate (its own issue #24) |
| [tiktok-god](https://github.com/haoict/tiktok-god) | iOS | **Jailbreak** | Archived 2022 | **No** — no rootless support |
| [tiktok-ios-ipa](https://github.com/i90O/tiktok-ios-ipa) | iOS | Shadowrocket + device-wide root CA | Abandoned | **No** — contains an 18-byte text file, not an IPA |

Full detail, including what each one claims versus what its code does, is in
[RESEARCH.md](RESEARCH.md).