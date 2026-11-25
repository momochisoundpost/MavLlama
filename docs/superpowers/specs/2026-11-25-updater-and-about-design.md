# MavLlama v1.1 Design: Global Inference Notice, GitHub Releases Updater + Markdown Viewer, and About Page

**Date:** 2026-11-25  
**Target Platform:** OS X 10.9.0–10.9.5 Mavericks (`-mmacosx-version-min=10.9 -march=core2`, Objective-C / Cocoa ARC)  
**Repository:** `momochisoundpost/MavLlama`

---

## 1. Intent & Why

MavLlama (`v1.0.0`) already turns any OS X 10.9 Mavericks Mac into a zero-compiler local LLM server, but three polish and lifecycle pieces are missing as new releases roll out:

1. **Honest, universal hardware expectations:** Currently, only Mac Pro users see the CPU-only inference reminder (`macProBannerLabel`), even though *every* Mavericks Mac runs CPU-only without OpenCL or Metal. Meanwhile, Mac Pro owners deserve a friendly, tongue-in-cheek nudge that booting Linux on their workstation hardware yields **10–20×** faster inference depending on the model.
2. **Self-updating with rich release notes:** Users on Mavericks cannot rely on modern browser TLS or Electron auto-updaters. MavLlama needs a built-in **Updates** tab that reads `momochisoundpost/MavLlama` GitHub Releases, renders full GitHub-flavored Markdown release notes (prioritizing **images/GIFs**, **embedded MP4 videos**, **tables**, and **badges**), and updates `MavLlama.app` in place in its application folder.
3. **Creator identity & About page:** MavLlama needs an **About** tab modeled after Caitlyn Momochi's VRemind `About` screen—featuring the official `llama.cpp` macOS app icon, version, tagline (*"MavLlama — So I put local LLMs on Mavericks because nobody did it."*), social links, and storage paths—plus bundling the `llama.cpp` icon as `MavLlama.app`'s Finder/Dock/About icon.

---

## 2. Goals, Non-Goals, and Anti-Goals

### Goals
- Show a global inference capability reminder on **all** Macs in `System Check & Engine`:
  - Haswell (`hasAVX2 == YES`, non-Mac Pro): `Mavericks inference is CPU-only (no OpenCL, no Metal).`
  - Pre-Haswell (`hasAVX2 == NO`, non-Mac Pro): `Mavericks inference is CPU-only (no AVX2, no OpenCL, no Metal).`
  - Mac Pro (`isMacPro == YES`): Greet the Mac Pro (`RAM restrictions lifted!`), include the CPU-only string (`no OpenCL, no Metal` if `hasAVX2`, else `no AVX2, no OpenCL, no Metal`), and casually remind the user they're better off running Linux since it yields **10–20×** the speed depending on the model used.
- Add an **Updates** tab (4th tab) + `Check for Updates...` menu bar item that:
  - Fetches releases from `https://api.github.com/repos/momochisoundpost/MavLlama/releases` via MavLlama's bundled TLS 1.3 `curl`.
  - Lets the user view rich Markdown release notes (with a selector to browse any published release, defaulting to the latest) rendered into styled HTML inside an OS X 10.9 `WebView` (`WebKit.framework`), with remote **images/GIFs**, **embedded MP4s**, and **badges** pre-fetched via bundled `curl` so they never fail Mavericks' 2013 TLS stack.
  - Compares the installed `CFBundleShortVersionString` against the latest non-draft, non-prerelease tag (with optional prerelease visibility in the release dropdown) and performs a safe **in-place `.app` replacement** + relaunch when an update is installed.
- Add an **About** tab (5th tab) + `About MavLlama` menu bar item modeled on the VRemind Settings `About` screenshot, with the official `llama.cpp` icon, version, tagline card, four social link buttons, and live storage path footer.
- Bundle the official `llama.cpp` macOS icon (`ggml-org/llama-brand`) as both `AppIcon.icns` (Finder bundle icon) and `llama-icon.png` (About tab artwork).

### Non-Goals
- Automatic silent background updates without user confirmation.
- Arbitrary third-party JavaScript execution or iframe embeds (e.g., YouTube `<iframe>` players, which require modern WebKit + TLS inside the webview) inside the release notes viewer. Links to YouTube or external pages open cleanly in the user's chosen default browser.
- Updating `llama-server` engine binaries automatically during an app update (`EngineManager` already manages tailored engine binaries separately in `~/Library/Application Support/MavLlama/engine`).

### Anti-Goals (Failure Conditions Even If Technically Functional)
- Breaking OS X `10.9.0`–`10.9.5` or Core 2 Duo (`-march=core2`) compatibility by linking non-10.9 frameworks (`WKWebView`, `JavaScriptCore` post-10.9 APIs) or MacPorts runtime dylibs outside `Contents/Frameworks`.
- Letting `WebView` make direct `https://` requests for release images/badges/MP4s and silently showing broken image icons because Apple's 2013 `SecureTransport` fails TLS 1.3 handshakes with `githubusercontent.com`, `github.com/user-attachments`, or `img.shields.io`.
- Deleting or corrupting the existing `MavLlama.app` if a download or unzip fails mid-update, or leaving `llama-server` orphaned during app replacement.

---

## 3. OS X 10.9 Mavericks Constraints

1. **Compiler & ABI Baseline:** `/usr/bin/clang -fobjc-arc -O2 -Wall -Wextra -Werror -mmacosx-version-min=10.9 -march=core2`, linking only Apple 10.9 system frameworks (`-framework Cocoa -framework WebKit`). Note: `WebView` (`<WebKit/WebKit.h>`) is part of OS X 10.9's public `WebKit.framework` (deprecated in 10.14+, fully native and warning-free with `-mmacosx-version-min=10.9`).
2. **TLS 1.3 Divide:** OS X 10.9's `NSURLSession`/`WebView` cannot negotiate TLS 1.3 with modern CDNs. All network fetches (`api.github.com`, release `.zip` assets, badges, images/GIFs, MP4s) **must** go through `DownloadManager`'s bundled `curl` + OpenSSL 3 + `ca-bundle.crt`.
3. **HTML5 Media in 10.9 `WebView`:** Mavericks WebKit1 natively renders:
   - PNG, JPEG, animated GIF, and static/shields SVG `<img>` tags from `file://` URLs.
   - H.264/AAC `.mp4` videos via `<video controls preload="metadata">` backed by OS X 10.9 AVFoundation/QuickTime when loaded from a local `file://` path with a `.mp4` extension. (WebM/AV1 are not supported by 10.9 QuickTime; non-playable video formats get a clean fallback link to open in the default browser.)
4. **Menu-Bar Accessory App (`LSUIElement = true`):** Because MavLlama runs as an `NSApplicationActivationPolicyAccessory` app, Finder icon updates apply to `MavLlama.app` on disk and in the About tab. Widening the main window slightly if needed (`780 × 500`, up from `780 × 520`—let's check current window size: currently `MainWindowController` creates the window and `NSTabView` comfortably fits 5 tabs: `System Check & Engine`, `Model Marketplace`, `Settings`, `Updates`, `About`).

---

## 4. Approaches Considered

### Markdown + Media Viewer
1. **Picked — Local C/ObjC GFM Parser + Bundled `curl` Media Cache -> `WebView`:**
   - Parse GitHub-flavored Markdown in pure C/Objective-C into clean semantic HTML5 + embedded dark/light CSS, prefetch remote media (`img`, `gif`, `mp4`, badges) via bundled `curl` into `~/Library/Caches/MavLlama/release-media/`, rewrite media URLs to local `file://` URLs, and render in `WebView`.
   - *Tradeoff:* Zero external dependencies, works on stock 10.9.0 without TLS errors, supports tables, badges, GIFs, and MP4 `<video>`, at the cost of writing/bundling a compact GFM converter (~400–500 lines of ObjC/C) and media cache pass.
2. **Rejected — Native `NSTextView` (`NSAttributedString`):**
   - Cannot play inline `<video>` MP4s, struggles with animated GIFs, GFM tables, and shields.io SVG badges on 10.9.
3. **Rejected — Rendering via external JS library (e.g., `marked.js`) + direct remote URLs in `WebView`:**
   - Remote images/MP4s/badges break immediately on stock 10.9 due to TLS 1.3 failures in `WebView`.

### UI Placement for Updates & About
1. **Picked — 4th (`Updates`) & 5th (`About`) Tabs in `MainWindowController` + Menu Bar Shortcuts:**
   - Keeps everything unified in MavLlama's single tabbed window while adding `Check for Updates...` and `About MavLlama` items in the `NSStatusItem` menu that jump straight to those tabs.
2. **Rejected — Separate Standalone Windows for Updates & About:**
   - Adds extra window lifecycle management without clear benefit in an app that already uses `NSTabView` as its control center.

---

## 5. Detailed Design

### 5.1 Global Inference Notice & Mac Pro Reminder (`MainWindowController.m`)
- Rename/repurpose `macProBannerLabel` into a **always-visible** `inferenceNoticeLabel` (`[self.inferenceNoticeLabel setHidden:NO]`) positioned between the browser check row and the horizontal separator in `System Check & Engine`.
- **Copy rules (decided with user):**
  - Build `cpuCaps`:
    - If `self.hardware.hasAVX2`: `@"no OpenCL, no Metal"`
    - Else: `@"no AVX2, no OpenCL, no Metal"`
  - **Non-Mac Pro (`!self.hardware.isMacPro`):**
    - Text: `[NSString stringWithFormat:@"Note: Mavericks inference is CPU-only (%@).", cpuCaps]`
    - Subtle warm/secondary styling (`11.5pt` bold, dark amber/slate text).
  - **Mac Pro (`self.hardware.isMacPro`):**
    - Text: `[NSString stringWithFormat:@"Hey Mac Pro (%@) — RAM restrictions lifted! Mavericks inference is CPU-only (%@). Honestly, on this machine you're better off running Linux, which yields 10–20x the speed depending on the model used.", self.hardware.modelIdentifier, cpuCaps]`
    - Warm amber highlight styling (`11.5pt` bold).

### 5.2 Official `llama.cpp` Icon Integration (`resources/` & `scripts/build-app.sh`)
- Download `https://raw.githubusercontent.com/ggml-org/llama-brand/master/logo/png/app/apple/macos-1024x1024-dark.png` into `resources/llama-icon.png` (committed to repo so offline builds remain reproducible).
- In `scripts/build-app.sh`:
  - Copy `resources/llama-icon.png` into `$APP_DIR/Contents/Resources/llama-icon.png`.
  - Generate `$ROOT_DIR/build/AppIcon.iconset` using `/usr/bin/sips` (`16x16`, `16x16@2x`, `32x32`, `32x32@2x`, `128x128`, `128x128@2x`, `256x256`, `256x256@2x`, `512x512`, `512x512@2x`) and compile `$APP_DIR/Contents/Resources/AppIcon.icns` via `/usr/bin/iconutil -c icns` (both `sips` and `iconutil` ship natively on OS X 10.9).
- In `resources/Info.plist`:
  - Add `<key>CFBundleIconFile</key><string>AppIcon</string>`.
- Keep the existing crisp monochrome chip `NSBezierPath` template icon for the `18×18` menu bar status item (`createMenuBarIcon`), since macOS menu bar items require small monochrome template glyphs. *(Builder call.)*

### 5.3 GitHub Releases Updater (`UpdateManager.h/.m` & `MarkdownRenderer.h/.m`)

#### Data Model (`MavReleaseInfo`)
- Fields parsed from `https://api.github.com/repos/momochisoundpost/MavLlama/releases`:
  - `tagName` (e.g., `"v1.1.0"`), `name` (release title), `body` (raw Markdown), `htmlURL`, `publishedAt`, `prerelease` (`BOOL`), `draft` (`BOOL`).
  - `appZipAssetName`, `appZipDownloadURL`, `appZipSizeBytes` (first asset whose `name` matches `MavLlama*.zip`, preferring `*-Mavericks.zip`).
  - `checksumsDownloadURL` (optional `checksums.txt` asset in the same release; if present, `UpdateManager` fetches it and parses the expected SHA-256 for `appZipAssetName` before installing!).

#### HTTP Headers in `DownloadManager`
- Enhance `DownloadManager` (`+fetchDataFromURL:headers:error:` or default `-A "MavLlama/<version>"`) so requests to `api.github.com` include `User-Agent: MavLlama` and `Accept: application/vnd.github+json`.

#### Version Comparison & Background Check *(Builder Calls)*
- Normalize versions by stripping a leading `v`/`V` and comparing numeric dot-separated components (`1.0.0` < `1.0.1` < `1.1.0` < `1.10.0`). Any pre-release suffix (`-beta.1`) sorts lower than the same base release (`1.1.0-beta.1` < `1.1.0`).
- Current version is read from `[[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"]`.
- **Default selection & install button behavior *(Builder call)*:**
  - On load, the release dropdown defaults to the highest non-draft, non-prerelease release (`latestStable`).
  - The action button reflects the currently selected release in the dropdown:
    - If `selected > installed` (and `!selected.prerelease`): enabled as **`Update to <tag> & Relaunch`**.
    - If `selected == installed`: disabled as **`Up to Date (<tag>)`**.
    - If `selected.prerelease` or `selected < installed`: enabled as **`Install Pre-release <tag> & Relaunch`** or **`Downgrade to <tag> & Relaunch`**, requiring a confirmation `NSAlert` before downloading so browsing older changelogs never triggers an accidental rollback.
    - If the selected release has no `MavLlama*.zip` asset: disabled as **`No App Bundle in This Release`**.
- **Launch check & rate-limit caching *(Builder call)*:**
  - Cache the raw GitHub Releases JSON response in `~/Library/Caches/MavLlama/releases-cache.json` with a timestamp.
  - On app launch, perform one quiet background check *only* if the cached response is older than **6 hours** (protecting GitHub's 60 req/hr unauthenticated `api.github.com` limit). Manual clicks on **`Check Again`** or **`Check for Updates...`** bypass the TTL and fetch fresh data immediately.
  - No modal popup is shown on launch; instead, if `latestStable > installed`, the menu bar item title updates from `Check for Updates...` to **`Update Available (<tag>)...`**.

#### Markdown + Media Renderer (`MarkdownRenderer` + Media Prefetch)
- **`MarkdownRenderer`** (`+htmlFromMarkdown:title:tag:`): Pure Objective-C GFM-to-HTML converter supporting:
  1. **Block elements:** ATX headings (`#`–`######`), fenced code blocks (` ```lang `), GFM pipe tables (`| a | b |` with header separator `:---`, `:---:`, `---:`), blockquotes (`>`), unordered/ordered lists + task list checkboxes (`- [ ]`, `- [x]`), horizontal rules (`---`, `***`), raw HTML media blocks (`<img ...>`, `<video ...>`, `<p align="center">...</p>`, `<details><summary>...`), and paragraphs.
  2. **Inline elements:** Linked images/badges (`[![alt](img-url)](href-url)` — very common for shields.io badges!), standalone images/GIFs (`![alt](url)`), links (`[text](url)`), inline `` `code` ``, bold (`**...**`), italic (`*...*`), strikethrough (`~~...~~`), and bare URLs.
  3. **Embedded MP4 detection:**
     - Any Markdown image/link whose URL ends in `.mp4` / `.mov` / `.m4v`, raw `<video ... src="...">` tag, OR a standalone line containing a `https://github.com/user-attachments/assets/<uuid>` / `https://user-images.githubusercontent.com/...mp4` URL is emitted as a media token.
- **Media Prefetch & Content-Type Resolution (`UpdateManager`):**
  1. Render initial HTML immediately into `WebView` (text/tables/code appear right away with subtle "Loading media…" placeholders for remote `https://` media).
  2. Extract unique remote `http(s)://` media URLs from the release note (`img`, badge, `video`, and `github.com/user-attachments/assets/...` tokens; cap at 25 media items / 50 MB per asset so huge accidental files don't hang caching).
  3. On a background queue, download uncached media URLs via bundled `curl -fsSL --max-time 30 -D <headers-file>` into `~/Library/Caches/MavLlama/release-media/<sha256>.<ext>`:
     - Determine `<ext>` from HTTP `Content-Type` header + magic bytes (`video/mp4` -> `.mp4`, `image/gif` -> `.gif`, `image/svg+xml` -> `.svg`, `image/png` -> `.png`, `image/jpeg` -> `.jpg`, `video/quicktime` -> `.mov`). This handles GitHub's extensionless `https://github.com/user-attachments/assets/<uuid>` URLs for both screenshots/GIFs and dragged-in MP4 recordings!
  4. Re-render HTML replacing each resolved token with either:
     - `<video controls preload="metadata" style="max-width:100%; border-radius:6px;"><source src="file:///.../xxx.mp4" type="video/mp4"></video><div class="video-fallback"><a href="https://...">Open video in browser</a></div>` (for `.mp4`/`.m4v`/`.mov`), or
     - `<img src="file:///.../xxx.ext" alt="..." class="md-img">` (inline `vertical-align:middle` styling when inside badge rows / `<a href>` badges, block/max-width `100%` for screenshots/GIFs).
  5. Reload HTML in `WebView` with `baseURL: [NSURL fileURLWithPath:mediaCacheDir]`.
- **`WebView` Navigation Policy (`WebPolicyDelegate`):**
  - Intercept clicks on any `http://` or `https://` link (`WebNavigationTypeLinkClicked`) and open them in the user's chosen default browser via `[[NSWorkspace sharedWorkspace] openURL:]`, calling `[listener ignore]` so `WebView` stays on the release notes page.

#### In-Place `.app` Replacement Flow
When the user clicks the install/update button (enabled when the selected release has `appZipDownloadURL`, `selected != installed`, and `DownloadManager` isn't currently downloading):
1. Check `self.downloadManager.isDownloading` (don't collide with an active model/engine download; prompt user if busy).
2. Determine target bundle path: `NSString *targetAppPath = [[NSBundle mainBundle] bundlePath];` (e.g., `/Applications/MavLlama.app`) and its parent directory (`targetParentDir`).
3. Verify `[[NSFileManager defaultManager] isWritableFileAtPath:targetParentDir]` and `isWritableFileAtPath:targetAppPath`. If not writable (e.g., running from a read-only mounted volume or root-owned folder without write access), show a clear `NSAlert` explaining that `MavLlama.app` needs write access to its folder (or offer to reveal the downloaded `.zip` in Finder instead).
4. Optional SHA-256 lookup: if the release contains `checksums.txt`, fetch it via bundled `curl` and extract the SHA-256 matching `appZipAssetName`.
5. Download `appZipDownloadURL` using `DownloadManager` (showing live byte/% progress in the `Updates` tab) to `~/Library/Application Support/MavLlama/updates/<assetName>`.
6. Stage & verify in `~/Library/Application Support/MavLlama/updates/staging-<uuid>/`:
   - Extract with `/usr/bin/ditto -x -k <zipPath> <stagingDir>`.
   - Locate `MavLlama.app` inside `<stagingDir>` and verify `<stagingDir>/MavLlama.app/Contents/MacOS/MavLlama` is executable and `<stagingDir>/MavLlama.app/Contents/Info.plist` parses cleanly.
   - Strip quarantine extended attributes (`/usr/bin/xattr -dr com.apple.quarantine <stagingDir>/MavLlama.app` — ignore exit code if attr absent) so OS X 10.9 Gatekeeper does not block relaunch.
7. Stop `llama-server` cleanly (`[self.serverController stopSynchronouslyForTermination]`).
8. Write and launch a detached POSIX shell script (`~/Library/Application Support/MavLlama/updates/apply-update.sh`) via `NSTask` (`/bin/sh` detaching stdin/stdout/stderr to `~/Library/Logs/MavLlama-updater.log`):
   ```sh
   #!/bin/sh
   OLD_PID="$1"
   STAGED_APP="$2"
   TARGET_APP="$3"
   STAGING_DIR="$4"
   BACKUP_APP="${TARGET_APP}.old-$$"

   i=0
   while kill -0 "$OLD_PID" 2>/dev/null && [ $i -lt 50 ]; do
     sleep 0.2
     i=$((i + 1))
   done

   if mv "$TARGET_APP" "$BACKUP_APP"; then
     if mv "$STAGED_APP" "$TARGET_APP"; then
       rm -rf "$BACKUP_APP" "$STAGING_DIR"
       /usr/bin/open "$TARGET_APP"
       exit 0
     else
       mv "$BACKUP_APP" "$TARGET_APP"
     fi
   fi
   exit 1
   ```
9. Immediately call `[NSApp terminate:nil]`.

#### Updates Tab Layout (`MainWindowController`)
```
+-------------------------------------------------------------------------+
| Installed: v1.0.0   Latest: v1.1.0 (Update Available!)   [Check Again]  |
| Viewing Release: [ v1.1.0 — MavLlama 1.1 (Latest) v ] [View on GitHub]  |
+-------------------------------------------------------------------------+
| +---------------------------------------------------------------------+ |
| | # MavLlama v1.1.0                                                   | |
| | [MIT Badge] [Mavericks 10.9+ Badge]                                 | |
| |                                                                     | |
| | Full rendered GFM release notes inside WebView:                     | |
| | - Tables, code blocks, checklists                                   | |
| | - Cached screenshots, animated GIFs, & inline <video> MP4s          | |
| +---------------------------------------------------------------------+ |
| [===================>                  ] 54% (4.2 MB / 7.8 MB)          |
|                                       [ Update MavLlama & Relaunch ]    |
+-------------------------------------------------------------------------+
```

### 5.4 About Tab (`MainWindowController`)
Modeled directly on the user's `VRemind Settings -> About` reference screenshot:
```
+-------------------------------------------------------------------------+
|                                                                         |
|                              +----------+                               |
|                              |  llama   |  (72x72 rounded icon)         |
|                              |   icon   |                               |
|                              +----------+                               |
|                                MavLlama                                 |
|                         Current Version: 1.1.0                          |
|                                                                         |
|        +-------------------------------------------------------+        |
|        |   MavLlama — So I put local LLMs on Mavericks         |        |
|        |                 because nobody did it.                |        |
|        |                                                       |        |
|        |  Vibecoded by Caitlyn Momochi. Free & open source.    |        |
|        +-------------------------------------------------------+        |
|                                                                         |
|          [ YouTube ]  [ Twitter / X ]  [ GitHub ]  [ Instagram ]        |
|                                                                         |
|     Engine & config in ~/Library/Application Support/MavLlama           |
|                     Models in /Users/widi/Models                        |
+-------------------------------------------------------------------------+
```
- **Exact Social Button Targets (decided by user):**
  - `YouTube` -> `https://www.youtube.com/@bukancaitlyn`
  - `Twitter / X` -> `https://x.com/Y2Karyl`
  - `GitHub` -> `https://github.com/momochisoundpost`
  - `Instagram` -> `https://www.instagram.com/bukancaitlyn/`
- Clicking any button opens the URL in the user's chosen default browser via `[[NSWorkspace sharedWorkspace] openURL:]`.
- **Menu Bar Additions (`AppDelegate.m`):**
  - Add `Check for Updates...` (opens main window and selects tab `3` — `Updates`) and `About MavLlama` (opens main window and selects tab `4` — `About`) right below `Open MavLlama (Setup & Models)...`.

---

## 6. What Is Left to the Builder

- Exact Objective-C class/helper decomposition for `MarkdownRenderer` and custom `NSView` rounded card drawing (`NSBezierPath` rounded rect fill/stroke on OS X 10.9, since `NSBoxCustom` styling differs slightly on 10.9 vs 10.10+).
- CSS typography/colors inside the `WebView` stylesheet so tables, badges, blockquotes, code blocks, images, and `<video>` look crisp on Mavericks Aqua.
- Unit tests in `tests/` covering:
  - Version string comparison (`v1.0.0` vs `v1.1.0`, `v1.10.0`, `-beta.1`).
  - `MarkdownRenderer` output for GFM tables, linked badges (`[![alt](img)](url)`), images/GIFs, and MP4 `<video>` rewrite.
  - CPU-only / Mac Pro banner string generation for Haswell (`hasAVX2 = YES`), pre-Haswell (`hasAVX2 = NO`), and Mac Pro (`isMacPro = YES`).
- Bumping `CFBundleShortVersionString` in `resources/Info.plist` (e.g. `1.1.0`) when packaging the new release.
