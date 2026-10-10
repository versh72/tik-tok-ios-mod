# COMPATIBILITY.md

Every row is either **CONFIRMED** (checked against source, binary, or Apple's
documentation during this work) or **UNKNOWN** (not checked — no device, no
toolchain, no ability to run the app).

Nothing in the UNKNOWN column is a claim. It is a hole.

---

## A. This project's own build

| Item | Value | Status | How it was established |
|---|---|---|---|
| Authoring platform | Windows, no Swift toolchain | CONFIRMED | `swift`, `xcodebuild`, `xcrun` all absent; `C:\Program Files\Swift` absent |
| Source compiles | — | **UNKNOWN** | Never built. See PLAN.md § "How to verify" |
| `swift test` passes | — | **UNKNOWN** | Never run |
| `Tools/verify-sources.mjs` | 56 checks | CONFIRMED | Executed; result recorded in README |
| Package manifest | swift-tools-version 5.9 | CONFIRMED | Read from `NetDiag/Package.swift` |
| Deployment target | iOS 16.0 | CONFIRMED | `Package.swift` `platforms: [.iOS(.v16)]` |
| App entry point builds | — | **UNKNOWN** | `@main` file written but never compiled |

### Framework availability (from Apple's documentation)

| API | Minimum | Status | Source |
|---|---|---|---|
| `Network` framework | iOS 12.0 | CONFIRMED | developer.apple.com/documentation/network |
| `NWPathMonitor` | iOS 12.0 | CONFIRMED | /network/nwpathmonitor |
| `NWConnection` | iOS 12.0 | CONFIRMED | /network/nwconnection |
| `NWConnectionGroup` | iOS 14.0 | CONFIRMED | /network/nwconnectiongroup — **not used**; deployment target is 16 |
| `URLSessionTaskMetrics` | iOS 10.0 | CONFIRMED | /foundation/urlsessiontaskmetrics |
| `SecTrustEvaluateWithError` | iOS 12.0 | CONFIRMED | /security |
| `SecTrustCopyResult` | iOS 15.0 | CONFIRMED | /security — guarded by `if #available` |
| `ISO8601DateFormatter` | iOS 10.0 | CONFIRMED | /foundation |
| `ShareLink` | iOS 16.0 | CONFIRMED | /swiftui — at the deployment target floor |

### Known build risk

| Item | Status | Detail |
|---|---|---|
| `SecCertificateCopyValues` | **UNKNOWN** | Used to read the certificate validity window. Apple has marked it deprecated; whether it still compiles warning-free on the current SDK was not checked. Isolated in one function, `NetworkTLSProber.certificateValidity`. |
| `tls_ciphersuite_name(_:)` | **UNKNOWN** | Used for the cipher-suite label with a hex fallback. Availability on the current SDK was not verified. |
| `Verdict.Grade(worst:)` variadic overload | CONFIRMED | Defined in this project; `swift build` was not run to confirm it is unambiguous against the `max()` inside. |

---

## B. Free iOS device provisioning

| Limit | Value | Status | Source |
|---|---|---|---|
| Provisioning profile validity | **7 days** | CONFIRMED | developer.apple.com/help/account/basics/about-your-developer-account |
| Registered devices | **3** | CONFIRMED | same |
| Apps per device | **3** | CONFIRMED | same |
| Paid account required to run on own device | **No** | CONFIRMED | /documentation/xcode/running-your-app-on-simulated-or-physical-devices |
| Developer Mode required | iOS 16+ | CONFIRMED | /documentation/xcode/enabling-developer-mode-on-a-device |
| UDID must be looked up manually | No — Xcode registers it | CONFIRMED | /help/account/devices/register-a-single-device |

**Consequence:** this project is free to build and run, but the install expires
every 7 days and must be reinstalled. That is Apple's design for the free tier,
not a limitation of this code.

### Capabilities

| Capability | Free tier | Status | Source |
|---|---|---|---|
| Network Extensions | **Not available** | CONFIRMED | /help/account/reference/supported-capabilities-ios — the "Network extensions" row has no checkmark in the free column |
| Packet Tunnel | Not available | CONFIRMED | same |
| App Proxy | Not available | CONFIRMED | same |

---

## C. The four researched projects

### `namecallfilter/tiktokmodcloud`

| Item | Value | Status |
|---|---|---|
| Platform | Android (APK) | CONFIRMED — `git grep -iE "ios\|ipa\|swift\|xcode\|apple"` returns zero matches |
| Last push | 2026-09-12 | CONFIRMED — GitHub API |
| Commits / tags | 111 / 74 | CONFIRMED — `git rev-list --count`, `git tag` |
| iOS relevance | None | CONFIRMED |

### `tuxi/TikTok-Tweaks`

| Item | Value | Status |
|---|---|---|
| Target TikTok version | 29.7.0 | CONFIRMED — `LatestBuild`, README, last commit |
| Loader | MonkeyDev | CONFIRMED — `MONKEYDEV_INSERT_DYLIB` etc. in `project.pbxproj` |
| Build host | macOS + Xcode 14.3, iOS 16 | CONFIRMED — README (Chinese) |
| Needs decrypted IPA | Yes | CONFIRMED — `quick-resign.sh` copies `TargetApp/`, README links a Baidu Pan IPA |
| GitHub releases | None | CONFIRMED — API returns empty |
| Last push | 2023-05-31 | CONFIRMED |
| Works on current TikTok | **No** | CONFIRMED — issue #24 "注入后无法登录" (cannot log in after injection), TikTok 34 |
| Works without a proxy | **No** | CONFIRMED — author's own README: "观看视频还需要挂梯子" |
| SSL bypass still functions | **UNKNOWN** | Code exists and is read; no test, no capture, no reproduction in repo |
| "effective for Douyin" | CLAIMED only | Author's statement about a different app; not a test result |

### `haoict/tiktok-god`

| Item | Value | Status |
|---|---|---|
| Architectures | arm64 + arm64e | CONFIRMED — fat header read from the unpacked `.deb` |
| Filename says `iphoneos-arm` | Theos naming convention, not a slice statement | CONFIRMED — header says otherwise |
| Install path | `/Library/MobileSubstrate/DynamicLibraries/` | CONFIRMED — contents of the unpacked `.deb` |
| Requires jailbreak | Yes | CONFIRMED — that path does not exist on a stock device |
| Last push | 2022-02-17 | CONFIRMED |
| Archived | Yes | CONFIRMED — GitHub API `archived: true` |
| Rootless jailbreak support | **No** | CONFIRMED — issue #153 "Rootless support", open since 2023-04-14, no reply |
| Works on iOS 15+ | No | **UNKNOWN** | No issue or commit addresses it; inferred from #153 but not directly stated |
| README claim "iOS 12–14" | CLAIMED | Contradicted by #138 ("only up to v23.2.0") and the rootless gap |
| Region change | Rewrites the **reported** carrier code locally | CONFIRMED — `CTCarrier` hooks in `Tweak.xm` |

### `i90O/tiktok-ios-ipa`

| Item | Value | Status |
|---|---|---|
| Contains an IPA | **No** | CONFIRMED — `ios/tiktok` is 18 bytes of UTF-8 text: `tiktok ios免拔卡\r\n` |
| Contains code | **No** | CONFIRMED — the tree is `README.md`, `ios/ios16.png`, `ios/tiktok` |
| Method | Shadowrocket MITM + URL rewrite | CONFIRMED — README `[MITM]` / `[URL Rewrite]` block |
| Requires a trusted third-party root CA | Yes | CONFIRMED — README installs and enables the generated CA |
| Blast radius | All apps on the device | CONFIRMED — a device-wide root CA, not app-scoped |
| Still works | **No** | CONFIRMED — README: "最新版的TikTok暂时不支持免拔卡使用" |
| Last push | 2022-10-28 | CONFIRMED — note this **precedes** the 2023-03-28 creation date; history was rewritten |

---

## D. The claim this tool is built to disprove

| Claim | Status |
|---|---|
| A successful HTTPS probe to a control host proves TikTok will load | **FALSE** — stated in the UI, embedded in every report, asserted by `testSummaryIsHedgedEvenWhenEverythingPasses` |
| A third-party iOS app can read another app's traffic | **FALSE** — sandbox docs + App Store Review Guidelines 2.5.2 |
| A free-tier app can detect a VPN | **FALSE** — `NEVPNManager` needs a paid entitlement; stated in `PathSnapshot.vpnCaveat` |
| Raw UDP port 53 is blocked for third-party iOS apps | **UNKNOWN** — searched Apple documentation and forums; **no source found either way**. Not asserted anywhere in this project. The app uses `getaddrinfo`, which avoids the question entirely. |

---

## E. Explicitly not verified

| Item | Why |
|---|---|
| Any build or test run of Swift code | No Swift toolchain on the authoring machine. **Closable via Route A** — see [CI-BUILD.md](CI-BUILD.md) |
| Behaviour on a physical iPhone | No device |
| Behaviour on iOS 16, 17, 18, 26 | No device, no simulator |
| Real-world probe results under any network condition | Requires a device |
| Whether TikTok currently loads under any specific VPN | Not measured here, and not measurable from an independent iOS app |
| `MonkeyDev` still functioning on any current iOS version | Last push 2022-07-09; no iOS ≥16 verification possible without a Mac |
| Whether Sideloadly accepts a fully unsigned `.ipa` | Not testable here. The workflow deliberately produces an unsigned build; if a Sideloadly version rejects it, use AltStore, or build signed on a Mac |

---

## F. Building without a Mac

| Item | Value | Status | Source |
|---|---|---|---|
| Xcode runs on non-macOS | **No** | CONFIRMED | developer.apple.com/xcode/system-requirements — every release lists required macOS; App Store listing says "Only for Mac" |
| Swift Playgrounds on iPhone | **No** | CONFIRMED | apps.apple.com — the compatibility field lists iPad only, no iPhone entry |
| Swift Playgrounds on iPad | Yes | CONFIRMED | developer.apple.com/swift-playground/release-notes — SwiftUI app support added in 4.0 |
| `Network` framework in Playgrounds | Probably yes | **UNKNOWN** | Community reports only. Apple publishes no framework matrix |
| `Security` / `SecTrustEvaluateWithError` in Playgrounds | — | **UNKNOWN** | No source found either way |
| Entitlements in a Playgrounds app | No | CONFIRMED (reasoned) | A Playgrounds project has no App ID, so no entitlement can be granted |
| GitHub Actions macOS runner | `macos-latest` = Apple Silicon | CONFIRMED | docs.github.com/en/actions/reference/runners |
| Cost in a public repository | Free | CONFIRMED | docs.github.com/en/billing/reference/actions-runner-pricing |
| Cost in a private repository | 10× minute multiplier | CONFIRMED | same |
| Published rate, macOS M1 | $0.062/min | CONFIRMED | same |
| Cloud build can produce a device-arm64 IPA | Yes | CONFIRMED | Runner is Apple Silicon, so the device slice is arm64 |
| Sideloadly runs on Windows | Yes, free, no jailbreak | CONFIRMED | sideloadly.io — "No payment required" |
| Sideloadly prerequisite | Web/Apple iTunes + iCloud, not Microsoft Store versions | CONFIRMED | sideloadly.io |
| SideStore wireless refresh after first install | Yes, via a local VPN | CONFIRMED | docs.sidestore.io/docs/faq — "no computer after the initial install" |
| Free profile expiry | 7 days | CONFIRMED | developer.apple.com/help/account/basics/about-your-developer-account |
| Developer Mode required for sideloaded apps (iOS 16+) | Yes | CONFIRMED | developer.apple.com/support/install-beta |
| Shortcuts `Get Contents of URL` has a timeout setting | **No** | CONFIRMED | The action's parameter list contains no timeout field |
| Shortcuts can measure elapsed time | Yes, via `Date` + `Get Time Between Dates` | CONFIRMED | docs.scpl.dev action definitions |
| Shortcuts gives DNS / TCP / TLS phase timings | **No** | CONFIRMED (absence) | No such action exists in the built-in set |
| Shortcuts can read the system resolver config | **No** | CONFIRMED (absence) | No action exposes it |
| Shortcuts can detect a VPN | **No** | CONFIRMED (absence) | Only the third-party **Actions** app ships an `Is Connected to VPN` action |
| The ~25 s Shortcuts network ceiling | — | **UNKNOWN** | Widely reported in forums; found in no Apple document. Not relied on anywhere here |

### Route A decision

The cloud workflow builds **unsigned on purpose**. Signing a free personal-team
build inside CI would require the Apple Account password as a repository secret,
which is not acceptable in any repository, public or private. Signing therefore
happens locally in Sideloadly, where the Apple ID stays on the owner's machine.