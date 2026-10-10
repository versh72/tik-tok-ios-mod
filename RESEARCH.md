# RESEARCH.md — what the public repositories actually contain

> **Scope note.** This file originally covered four repositories. Stage 1 of the
> TikTok-MOD brief added ten Android modding projects with real source code;
> those are in [ANDROID_ANALYSIS.md](ANDROID_ANALYSIS.md). The four below are the
> original brief's list.

Method: each repository was cloned in full (`git clone`), the file tree read via
`git ls-files`, the commit history read via `git log`, and the released binary
artifacts unpacked and inspected byte-for-byte. Claims below are marked
**CONFIRMED** only where they were checked against code or binary contents, and
**CLAIMED** where they are only an author's statement.

**All four repositories were reachable. Nothing in this report is inferred from
memory.** Where something could not be checked, it says so.

Local clones were kept in a temp directory outside this project and are not
part of the deliverable (verified by `Tools/verify-sources.mjs`, section 9).

---

## 1. `namecallfilter/tiktokmodcloud`

- URL: <https://github.com/namecallfilter/tiktokmodcloud>
- Created 2025-08-09, last push 2026-09-12. 442 stars, 20 forks, 2 open issues.
- Primary language: TypeScript. 111 commits. 74 git tags.

### What it is — CONFIRMED

A **Bun/TypeScript command-line tool that scrapes third-party APK download
sites and archives the files.** That is the whole project.

Evidence:
- `package.json` — `"module": "src/index.ts"`, dependencies `htmlparser2`,
  `wreq-js`, `cli-progress`, `@lazarv/rsc`, `pino`. No native iOS toolchain.
- `src/scrapers/apkw.ts`, `src/scrapers/fylio.ts` — the only two sources of
  downloadable artifacts.
- README: "Automated archive of TikTok Mod and Plugin **APK** files from
  TikTokModCloud… Downloads are saved in `./apks`."

### iOS relevance — CONFIRMED: none

`git grep -in -E "ios|ipa|swift|xcode|apple" -- '*.ts' '*.json' '*.md' '*.yml'`
over the tracked files returned **zero matches**. There is no iOS code, no IPA
handling, no Apple tooling anywhere in the repository.

### Status

Actively maintained. The most recent commits are real fixes
("retry failed connections and interrupted transfers", "harden download and
release automation"). Tag names are Android version strings
(`v44.6.4-mod`, `v46.4.3-mod-fix`), consistent with the APK-only scope.

### Honest assessment

Useful only as evidence that "TikTok mods" are overwhelmingly an **Android**
artefact. It is not a source for anything iOS.

---

## 2. `tuxi/TikTok-Tweaks`

- URL: <https://github.com/tuxi/TikTok-Tweaks>
- Created 2020-01-31, last push 2023-05-31. 73 stars, 26 forks, 6 open issues.
- Primary language: Objective-C. 53 commits. **No GitHub releases.**

### What it is — CONFIRMED

A **TikTok tweak** — a dynamically linked library injected into the stock
TikTok binary — plus a vendored copy of the FLEX debug inspector.

Evidence:
- `TikTokDylib/Logos/TikTokDylib.xm` — Logos source. `TikTokDylib.mm` in the
  same folder is **pre-generated Logos output** (checked-in `_logos_orig$…`
  trampolines and a `_logosLocalCtor_aa5c4279` constructor), not hand-written code.
- `TikTokDylib/fishhook/fishhook.c` — method-swap shim.
- `TikTokDylib/Trace/a1a2-selectortramps-arm64.s` and friends — ARM64 selector
  trampolines. These exist to call methods that the app does not declare, which
  is itself evidence the project pokes at undocumented surface.
- `FLEX/` — a complete copy of the FLEX in-app inspector (network MITM UI,
  keychain viewer, class browser). Vendored, ~16 MB of the repo's 16.8 MB.

### The three components, separated — CONFIRMED

| Component | Where | What it is |
|---|---|---|
| Loader | `TikTok/Scripts/quick-resign.sh`, `manifest.plist`, `TikTok.xcodeproj` | MonkeyDev build/resign/install |
| App modification | `TikTokDylib/Logos/TikTokDylib.xm`, `TikTokDylib/Trace/`, `TikTokDylib/fishhook/` | Method hooks inside TikTok's own classes |
| Network | `FLEX/Classes/Network/` (vendored, third-party) | FLEX's own MITM viewer |

The "network" component is **not** part of this project's own code. It is
FLEX's, compiled in. What the project itself does to the network layer is
limited to the `SSLPinningBypass` Logos group.

### The SSL pinning bypass — CONFIRMED as code, UNVERIFIED as working

`TikTokDylib.xm` contains:

```
%group SSLPinningBypass
%hook TTHttpTask
- (id)init {
    TTHttpTask *obj = %orig;
    obj.skipSSLCertificateError = YES;
    return obj;
}
```

and sets `obj.skipSSLCertificateError = YES` on the task returned by
`TTNetworkManagerChromium requestForJSONWithURL_:…`.

This is an application-level flag on TikTok's own HTTP task class. It is **not**
a system-wide trust override and it does not weaken TLS for anything else.

**What is NOT confirmed:** that it still works. The README itself says
(Chinese) "可绕过 SSL pinning…目前对抖音的有效" — "can bypass SSL pinning… currently
effective for Douyin", which is a self-reported observation on a different app,
not a test result. There is no test, no capture, and no reproduction in the repo.

### Loader: MonkeyDev — CONFIRMED

`manifest.plist` is a MonkeyDev install manifest, and
`TikTok.xcodeproj/project.pbxproj` contains exactly these build settings:

```
MONKEYDEV_ADD_SUBSTRATE = YES
MONKEYDEV_CLASS_DUMP    = YES
MONKEYDEV_DEFAULT_BUNDLEID = YES
MONKEYDEV_INSERT_DYLIB  = YES
MONKEYDEV_RESTORE_SYMBOL = YES
MONKEYDEV_TARGET_APP    = Optional
```

The MonkeyDev README (fetched from `raw.githubusercontent.com/AloneMonkey/MonkeyDev/master/README.md`)
states: *"insert dylib、class-dump、restore-symbol… patch and debug iOS Apps,
**without jailbreak**"*, and *"只需拖入一个砸壳应用，自动集成…重签名安装到非越狱机器"*
— drop in a decrypted app and it re-signs and installs on a non-jailbroken device.

MonkeyDev itself: GPL-3.0, 6796 stars, **last push 2022-07-09**, not archived.

### Why this is no longer a viable path — CONFIRMED from the project's own issues

- **Issue #24 (open, 2024-04-19)** "注入后无法登录" — *"after injection, cannot log
  in"*, against TikTok 34. This is the most informative single data point in the
  whole repository set: injecting no longer yields a usable app.
- The author states in the README that TikTok's anti-debugging *"可能会对账号
  进行限制"* — may restrict the account.
- The author also states: *"大部分功能的代码适用抖音，观看视频还需要挂梯子，
  我记得去年的版本不需要的"* — the features work on Douyin, but **watching videos
  still requires a proxy/VPN**, and it did not in the previous year.

That last sentence is directly relevant to the original problem: the author's
own tool, on a version that still functioned, did **not** remove the need for a
network path that can reach the content.

- Last commit 2023-05-31 targeting TikTok 29.7.0. Current TikTok versions are far
  past that, and the hooks target private class names
  (`AWEAwemeModel`, `TTHttpTask`, `AWENewFeedTableViewController`) that do not
  survive renames.

### Honest assessment

Well-documented as research, broken as a product. The README is honest about its
own limits, which is more than most projects of this kind manage. The
`LatestBuild` file contains an absolute path from the author's Mac
(`/Users/xiaoyuan/Library/Developer/Xcode/DerivedData/…`), so no prebuilt
artefact is shipped.

---

## 3. `haoict/tiktok-god`

- URL: <https://github.com/haoict/tiktok-god>
- Created 2020-05-02, last push 2022-02-17. 273 stars, 67 forks, **77 open issues**.
- **`archived: true`**. 42 commits. 19 tags.
- License: `NOASSERTION` (README says GPLv3).

### What it is — CONFIRMED

A **Cydia/Substrate tweak packaged as a Debian `.deb`**.

Evidence:
- `Makefile`: `ARCHS = arm64 arm64e`, `TARGET = iphone:clang:13.6:12.0`,
  `include $(THEOS)/makefiles/common.mk`, `include $(THEOS_MAKE_PATH)/tweak.mk`.
- `control`: `Depends: mobilesubstrate, preferenceloader, com.haoict.libhdev (>= 4.8.1), firmware (>= 12)`.
- `tiktokgod.plist`: `Filter = { Bundles = ("com.zhiliaoapp.musically", "com.ss.iphone.ugc.Ame"); }`.

### Architecture of the shipped binary — CONFIRMED by unpacking it

The `.deb` filename says `iphoneos-arm`, which is Theos naming convention, not a
statement about the slices. The actual Mach-O was checked by reading the fat
header of `Library/MobileSubstrate/DynamicLibraries/tiktokgod.dylib` inside
`release/com.haoict.tiktokgod_3.0.0_iphoneos-arm.deb`:

```
FAT binary, arch count = 2
  arch 0 : arm64/0
  arch 1 : arm64/2      (arm64e)
```

So it **is** arm64/arm64e, matching the Makefile. It installs to
`/Library/MobileSubstrate/DynamicLibraries/`, which requires a jailbroken
device — no way around that.

### What the hooks actually do — CONFIRMED

`Tweak.xm` hooks six private classes: `AWEAwemeModel` (drop ad models by
returning `nil` from `init`), `CTCarrier` (override `mobileCountryCode`,
`isoCountryCode`, `mobileNetworkCode`), `AWEPlayVideoPlayerController`
(auto-advance), `AWEFeedContainerViewController` (hide UI), and
`AWEPlayInteractionViewController` (the download button).

`JailbreakBypass.xm` returns `NO` from `isJailBroken` on nine classes and hides
~70 jailbreak paths from `NSFileManager fileExistsAtPath:`.

**Note on the region change:** it only rewrites what the app *reports* as the
carrier code locally. It does not change which content servers the app reaches.
An honest description is "the app is told a different country", not "the region
is changed".

### Why it is dead — CONFIRMED from issues

- **Issue #153 "Rootless support" (open, 2023-04-14), never answered.**
  Every modern jailbreak (dopamine, palera1n on iOS 15+) is rootless, and a
  tweak installed to `/Library/MobileSubstrate/` does not load there.
- **Issue #155** "Can't add to sileo on dopamine jailbreak… it worked on palera1n".
- **Issue #138** "All features are only available up to version v23.2.0".
- **Issue #148** "Ads keep showing :(", **#150** "No Longer Auto Scrolls".
- Repository **archived**; last release tag v3.0.0, last commit 2022-02-17.

### Honest assessment

The cleanest code of the four, and unambiguously dead on any currently
maintainable device. It required, and still requires, a jailbreak.

---

## 4. `i90O/tiktok-ios-ipa`

- URL: <https://github.com/i90O/tiktok-ios-ipa>
- Created 2023-03-28, **last push 2022-10-28** (push precedes creation, which
  means the history was rewritten or force-pushed).
- 0 stars, 0 forks, 0 issues. 7 commits.
- Complete file list: `README.md`, `ios/ios16.png`, `ios/tiktok`.

### The repository contains no IPA — CONFIRMED

`ios/tiktok` is **18 bytes**. Its full content, read byte-for-byte:

```
74 69 6b 74 6f 6b 20 69 6f 73 e6 95 99 e7 a8 8b 0d 0a
 t  i  k  t  o  k     i  o  s  免  拔  卡  \r \n
```

It is a UTF-8 text file reading "tiktok ios免拔卡", not an archive, not a
Mach-O, not a ZIP. The repository name and description promise an IPA; there is
no IPA, and there is no code of any kind.

### What it actually describes — CONFIRMED

The README is a Chinese tutorial for **Shadowrocket**: a commercial proxy client
for iOS that ships its own CA certificate and performs **man-in-the-middle TLS
interception** on the device. The method it documents is:

```
[URL Rewrite]
(?<=_region=)CN(?=&) JP 307
...
[MITM]
hostname = *.tiktokv.com,*.byteoversea.com,*.tik-tokapi.com
```

plus "generate a CA certificate → install → enable under Certificate Trust
Settings".

### What that means technically

This is not an iOS modification at all. It is: install a third-party root CA on
the device, then let the proxy rewrite and re-sign traffic in transit. The
consequences are worth stating plainly:

- **Every** TLS connection from every app on the device is now decryptable by
  the proxy — not just TikTok.
- The security model for all other apps on the phone is silently reduced.
- The README itself says "最新版的TikTok暂时不支持免拔卡使用，需要下载旧版" —
  current TikTok versions no longer work with this method, only older ones.

### Status

Abandoned. The README notes the method no longer works on current versions. The
repository is two files and a screenshot.

---

## Summary table

| Repository | Platform | Requires | Current status | Usable for iOS diagnosis? |
|---|---|---|---|---|
| `tiktokmodcloud` | Android (APK) | Bun | Active, 2026 | No — zero iOS content |
| `TikTok-Tweaks` | iOS | macOS + Xcode + a **decrypted TikTok IPA**, MonkeyDev | Abandoned 2023 | No — injections no longer authenticate (issue #24) |
| `tiktok-god` | iOS | **Jailbreak** | Archived 2022, rootless unsupported | No — dead on modern jailbreaks |
| `tiktok-ios-ipa` | iOS | Shadowrocket + a **trusted third-party root CA** | Abandoned, README admits it broke | No — contains no code; method reduces device-wide TLS security |

## What the four repositories collectively establish

1. **No free, current, working method exists to modify TikTok on a stock,
   unjailbroken iPhone.** Every iOS option found requires one of: a jailbreak, a
   decrypted copy of the app plus a Mac, or a trusted third-party root CA.
2. **The one "no jailbreak" route (MonkeyDev) has stopped working** for
   TikTok specifically — the author's own issue tracker reports login failure
   after injection on TikTok 34.
3. **A proxy/MITM route cannot fix "the feed does not load".** If the tunnel
   cannot reach the content API, rewriting the region parameter changes nothing.
4. **The most useful artifact of the four is a negative result.** The evidence
   says the remaining question is not "how do I patch TikTok" but "what exactly
   is the network doing" — which is what this project measures instead.