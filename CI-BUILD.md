# Building and installing without a Mac

You said you don't have a Mac. This is the honest map of what that means and
what still works.

## The blocker, stated plainly

**Xcode runs only on macOS.** Not a preference, not a limitation of this
project — every Xcode release lists "Supported macOS Versions" and the App Store
listing reads "Only for Mac"
([developer.apple.com/xcode/system-requirements](https://developer.apple.com/xcode/system-requirements)).

**Swift Playgrounds does not run on iPhone.** The App Store listing's
compatibility field lists iPad only — there is no iPhone entry
([apps.apple.com — Swift Playground](https://apps.apple.com/us/app/swift-playground/id908519492)).
So the "write Swift on the phone" route needs an iPad, not an iPhone.

There is no third option. Anyone who tells you otherwise is selling something.

## What still works

| Route | macOS needed | Cost | Gives you |
|---|---|---|---|
| **A. Cloud build → Sideloadly** | No | Free | **The real app**, with DNS / TLS / HTTPS timing |
| **B. Shortcuts** | No | Free | Reachability + end-to-end timing, no phase breakdown |
| **C. Free App Store tools** | No | Free | Ping, DNS lookup, cert details, VPN detection |
| D. Borrow or rent a Mac | Yes | — | Easiest, but needs the hardware |

Route A is the one that gets you what was actually built. Routes B and C work
today with nothing set up.

---

## Route A — build in the cloud, sign on your own PC

The workflow `.github/workflows/build-ios.yml` is already written. It runs on a
GitHub-hosted macOS runner, which is **free for a public repository**.

```
    ┌──────────────┐   push    ┌──────────────────────┐
    │  your PC     │ ────────▶ │ GitHub Actions       │
    │  (Windows/   │           │ macOS runner         │
    │   Linux)     │           │ swift test + build   │
    └──────────────┘           └──────────┬───────────┘
                                           │ unsigned .ipa
    ┌──────────────┐   download             ▼
    │  your PC     │ ◀────────────  NetDiag-unsigned.ipa
    │  Sideloadly  │  signs with your own Apple ID, installs over USB
    └──────────────┘
```

**The split that matters:** the build is unsigned and your Apple ID never goes
anywhere near the cloud. Signing happens locally in Sideloadly on your own
machine. No credential is ever a repository secret.

### 1. Push to a public GitHub repository

```bash
git init
git add .
git commit -m "NetDiag"
git remote add origin https://github.com/<you>/<repo>.git
git push -u origin main
```

**Make it public** so the macOS runner is free. In a private repository macOS
minutes are charged at a 10× multiplier.

### 2. Watch the build

Actions tab → the workflow runs. It does four things, in this order:

1. `swift build` + `swift test` — the real test suite, on a real Mac.
   **This is the verification that could not be done anywhere else.**
2. Builds the iOS app for arm64 with code signing switched off.
3. Confirms the binary really is arm64 and really is unsigned.
4. Zips it and uploads it as an artifact called `NetDiag-unsigned-ipa`.

If step 1 fails, you will finally get real compiler errors. `PLAN.md` § "How to
verify" lists the three most likely ones and the fix for each.

### 3. Get iTunes and iCloud on your PC

Sideloadly's own requirement: the **web/Apple versions**, not the Microsoft
Store versions. If the Store ones are installed, uninstall them first.

### 4. Install Sideloadly

Free, runs on Windows/macOS/Linux, no jailbreak needed
([sideloadly.io](https://sideloadly.io/)).

1. Connect the iPhone by USB, unlock it, tap **Trust**.
2. Sideloadly → drag in `NetDiag-unsigned.ipa`.
3. Enter your Apple ID.
4. **Start**.

### 5. Turn on Developer Mode on the iPhone

Sideloaded apps need this on iOS 16+:

**Settings → Privacy & Security → Developer Mode → on → restart → confirm**

### 6. Run the actual experiment

1. Scenario field → `VPN off` → **Run check**
2. Connect the tunnel. Scenario → `VPN on` → **Run check**
3. Open the **Compare** tab

That comparison is the deliverable.

### The 7-day tax

Apple's free personal-team profiles **expire 7 days after issuance**
([developer.apple.com/help/account/basics/about-your-developer-account](https://developer.apple.com/help/account/basics/about-your-developer-account)):
10 App IDs, 3 devices, 3 apps per device. When it expires the app stops
launching.

Sideloadly has a background daemon that re-signs automatically every few days,
which usually hides this. When it doesn't: re-run the GitHub workflow, download
the fresh `.ipa`, install again.

### If Route A fails

| Symptom | Cause | Fix |
|---|---|---|
| Workflow fails at `swift test` | A real compile error | The log names the file and line. Check `PLAN.md` § "Step 2" |
| Workflow fails at `xcodebuild` | `project.yml` / SwiftPM resolution | The error text is in the log |
| Sideloadly rejects the `.ipa` | Some Sideloadly versions want a signed IPA | Re-run the build with signing enabled on your Mac instead, or use AltStore |
| App installs then won't open | Developer Mode off, or profile expired | Re-check § 5 above |
| `codesign` error on the Mac | Nothing — signing is off in CI | Expected; ignore |

---

## Route B — Shortcuts, works in ten minutes, no build at all

iOS has Shortcuts built in. It cannot give you a DNS/TCP/TLS breakdown, but it
gives you reachability, end-to-end HTTPS timing, and enough context to tell two
network configurations apart.

Build one shortcut with these actions in this order:

| # | Action | Setting |
|---|---|---|
| 1 | **Get Device Details** | `Device Model` |
| 2 | **Get Device Details** | `System Version` |
| 3 | **Get Network Details** | `Wi-Fi` → `Network Name` |
| 4 | **Get Network Details** | `Cellular` → `Carrier Name` |
| 5 | **Get Current IP Address** | `External`, `IPv4` |
| 6 | **Date** | → Set Variable `start` |
| 7 | **Get Contents of URL** | `Advanced` on, method `GET`, your target URL |
| 8 | **Date** | |
| 9 | **Get Time Between Dates** | Get Time From: `Other` = `start`, In: `Seconds` |
| 10 | **Text** | concatenate everything |
| 11 | **Show Result** → **Share** | |

Run it once with the tunnel off, once with it on, and diff the two.

### Limits, known in advance

- **No timeout on `Get Contents of URL`.** If a target hangs, the shortcut hangs
  with it. Pick targets you expect to answer.
- **Timing is wall-clock and coarse.** Sub-second numbers are not trustworthy.
  It is fine for "0.3 s vs 4.2 s", useless for "312 ms vs 340 ms".
- **No DNS-only, TCP-only or TLS-only timing.** No such action exists.
- **No certificate inspection.**
- **No VPN detection.** `Get Current IP Address → External` is a weak proxy: if
  the external IP changes between runs, something is rerouting you. It is
  evidence, not proof.

---

## Route C — free App Store apps, zero setup

All of these are **active probes**. None of them intercepts other apps'
traffic, and none needs a root certificate.

| App | What it uniquely gives you |
|---|---|
| **Network Utility** (`573021799`) | DIG with a **selectable DNS server** — the cleanest way to A/B two resolvers. Ping with a real timeout control. |
| **ManageEngine Ping Tool** (`460362949`) | **SSL certificate details**, ping with TTL, min/max/avg, PDF report |
| **Netti** (`1595456600`) | Shows **whether a VPN or Private Relay is actually engaged** — the single most important fact for your A/B test |
| **Net Optimizer** (`1568708059`) | DNS-resolver latency comparison across providers |
| **Speedtest by Ookla** (`300704847`) | Ping measured in three phases (idle / download / upload), plus jitter |

The combination worth having, in priority order for your specific problem:

1. **Netti** — is the tunnel actually engaged, or is the VPN app lying about it?
2. **ManageEngine Ping Tool** — does a TLS handshake to a known host succeed,
   and whose certificate do you get?
3. **Network Utility DIG** — does the answer change when you change resolver?

If the answer to 1 is "the VPN shows connected but no external IP change", the
problem is the VPN, not TikTok. That single check can end the investigation
before anything else matters.

---

## What I would do

Start with **Route C, Netti**, right now. It is free, takes two minutes, and it
answers the question that determines whether any of this is worth continuing:
*is the tunnel actually carrying traffic?*

Then set up **Route A** in the background. It is the only path that gives you
the real per-stage timings, and its first run also runs the Swift test suite on
a real Mac — which is the verification this project has been missing since it
was written.