# MavLlama v1.1 (Global Inference Notice, GitHub Releases Updater + Markdown Viewer, & About Tab) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a universal CPU-only / Mac Pro Linux speed reminder, a built-in GitHub Releases updater with a GFM Markdown + cached media (`img`, `gif`, `mp4`, badges) viewer and in-place `.app` swapper, the official `llama.cpp` app icon, and a VRemind-style **About** tab to MavLlama.

**Architecture:** Pure Objective-C / Cocoa ARC (`-mmacosx-version-min=10.9 -march=core2`) building on MavLlama's existing bundled TLS 1.3 `curl`. `MarkdownRenderer` converts GitHub-flavored Markdown into semantic HTML5 + CSS while `UpdateManager` prefetches remote media (`Content-Type` + magic bytes) to `~/Library/Caches/MavLlama/release-media/` for OS X 10.9 `WebView` rendering and executes a detached POSIX `.app` swapper upon user-confirmed updates. `MainWindowController` gains two new `NSTabView` tabs (`Updates` and `About`) plus menu bar shortcuts in `AppDelegate`.

**Tech Stack:** Objective-C (ARC), Apple OS X 10.9 `Cocoa.framework` & `WebKit.framework` (`WebView`), bundled `curl` + OpenSSL 3, `sips` + `iconutil`, `/usr/bin/ditto`.

**Spec:** `docs/superpowers/specs/2026-11-25-updater-and-about-design.md`

## Global Constraints

- Strict compiler flags: `/usr/bin/clang -fobjc-arc -O2 -Wall -Wextra -Werror -mmacosx-version-min=10.9 -march=core2` linking only `-framework Cocoa -framework WebKit` (zero external `/opt/local` dylib leaks in `MavLlama` binary).
- All HTTPS traffic (`api.github.com`, release `.zip` bundles, `checksums.txt`, badges, images/GIFs, MP4s) must route through `DownloadManager`'s bundled `curl` + `ca-bundle.crt`, never `NSURLSession` or direct `WebView` remote loads.
- Non-Mac Pro inference notice copy: `Note: Mavericks inference is CPU-only (no OpenCL, no Metal).` when `hasAVX2 == YES`, else `Note: Mavericks inference is CPU-only (no AVX2, no OpenCL, no Metal).`
- Mac Pro inference notice copy: `Hey Mac Pro (<modelIdentifier>) — RAM restrictions lifted! Mavericks inference is CPU-only (<cpuCaps>). Honestly, on this machine you're better off running Linux, which yields 10–20x the speed depending on the model used.`
- Official icon source: `https://raw.githubusercontent.com/ggml-org/llama-brand/master/logo/png/app/apple/macos-1024x1024-dark.png` stored at `resources/llama-icon.png` and compiled into `AppIcon.icns`.
- About tab exact strings & social URLs:
  - Headline: `MavLlama — So I put local LLMs on Mavericks because nobody did it.`
  - Subtitle: `built in public by Caitlyn Momochi`
  - Buttons: `YouTube` (`https://www.youtube.com/@bukancaitlyn`), `Twitter / X` (`https://x.com/Y2Karyl`), `GitHub` (`https://github.com/momochisoundpost`), `Instagram` (`https://www.instagram.com/bukancaitlyn/`).

## Review Focus

- **Raw `<script>` or unsafe HTML in release notes:** `MarkdownRenderer` must escape `<script>` / arbitrary HTML while rendering safe Markdown and media tokens so release notes never execute scripts inside 10.9 `WebView` (pinned in Task 3).
- **Multi-digit & pre-release version ordering (`v1.10.0` vs `v1.2.0`, `v1.1.0-beta.1` vs `v1.1.0`):** Numeric component comparison must rank `1.10.0 > 1.2.0` and `1.1.0 > 1.1.0-beta.1` (pinned in Task 4).
- **Draft releases or source-only tags without `MavLlama*.zip`:** Drafts are excluded completely, and `latestStableRelease` skips pre-releases and releases lacking a `.zip` bundle (pinned in Task 4).
- **Spaces in macOS paths during `.app` replacement (`Application Support`):** `apply-update.sh` must receive paths strictly as positional `$1`..`$4` arguments and quote every variable so spaces never break `mv` or `open` (pinned in Task 4).
- **AVX1.0 vs AVX2 in global inference notice:** Non-Haswell (`hasAVX2 == NO`) must include `no AVX2`, Haswell (`hasAVX2 == YES`) must omit `no AVX2`, and `isMacPro == YES` must include the `10–20x` Linux note (pinned in Task 1).

---

### Task 1: Global Inference Notice Helper & Official `llama.cpp` Icon Assets

**Files:**
- Create: `resources/llama-icon.png`
- Modify: `resources/Info.plist`
- Modify: `scripts/build-app.sh`
- Modify: `src/HardwareInspector.h`
- Modify: `src/HardwareInspector.m`
- Test: `tests/test_core.m`

**Interfaces:**
- Produces:
  - `+[HardwareInspector inferenceNoticeForIsMacPro:(BOOL)isMacPro modelIdentifier:(NSString *)modelIdentifier hasAVX2:(BOOL)hasAVX2]` -> `NSString *`
  - `Contents/Resources/AppIcon.icns` and `Contents/Resources/llama-icon.png` in built `.app` (`CFBundleShortVersionString` = `1.1.0`, `CFBundleIconFile` = `AppIcon`)

- [ ] **Step 1: Write failing unit tests for `inferenceNoticeForIsMacPro:modelIdentifier:hasAVX2:` in `tests/test_core.m`**

```objc
static void testInferenceNotices(void) {
    NSString *sandy = [HardwareInspector inferenceNoticeForIsMacPro:NO modelIdentifier:@"MacBookPro8,1" hasAVX2:NO];
    assert([sandy isEqualToString:@"Note: Mavericks inference is CPU-only (no AVX2, no OpenCL, no Metal)."]);

    NSString *haswell = [HardwareInspector inferenceNoticeForIsMacPro:NO modelIdentifier:@"MacBookPro11,1" hasAVX2:YES];
    assert([haswell isEqualToString:@"Note: Mavericks inference is CPU-only (no OpenCL, no Metal)."]);

    NSString *macPro = [HardwareInspector inferenceNoticeForIsMacPro:YES modelIdentifier:@"MacPro5,1" hasAVX2:NO];
    assert([macPro rangeOfString:@"MacPro5,1"].location != NSNotFound);
    assert([macPro rangeOfString:@"no AVX2, no OpenCL, no Metal"].location != NSNotFound);
    assert([macPro rangeOfString:@"Linux"].location != NSNotFound);
    assert([macPro rangeOfString:@"10–20x"].location != NSNotFound);

    NSLog(@"PASS: testInferenceNotices");
}
```
Call `testInferenceNotices();` in `main()`.

- [ ] **Step 2: Run test on Mavericks build host to verify it fails**

Sync `tests/test_core.m` to `widi@192.168.18.252:~/Projects/MavLlama/tests/` and run:
```bash
/usr/bin/clang -fobjc-arc -O2 -Wall -Wextra -Werror -mmacosx-version-min=10.9 -march=core2 \
  -framework Cocoa tests/test_core.m src/HardwareInspector.m src/ModelCatalog.m src/DownloadManager.m -o /tmp/test_core && /tmp/test_core catalog/models.json
```
Expected: FAIL to compile (`No known class method for selector 'inferenceNoticeForIsMacPro:modelIdentifier:hasAVX2:'`).

- [ ] **Step 3: Implement `+[HardwareInspector inferenceNoticeForIsMacPro:modelIdentifier:hasAVX2:]` and add `llama-icon.png` + `.icns` build step**

1. Declare and implement `+[HardwareInspector inferenceNoticeForIsMacPro:(BOOL)isMacPro modelIdentifier:(NSString *)modelIdentifier hasAVX2:(BOOL)hasAVX2]` in `src/HardwareInspector.h` / `src/HardwareInspector.m` returning the exact strings pinned in Global Constraints (defaulting empty `modelIdentifier` to `@"Mac Pro"`).
2. Download `https://raw.githubusercontent.com/ggml-org/llama-brand/master/logo/png/app/apple/macos-1024x1024-dark.png` to `resources/llama-icon.png`.
3. Update `resources/Info.plist`: set `CFBundleIconFile` to `AppIcon`, `CFBundleShortVersionString` to `1.1.0`, and `CFBundleVersion` to `2`.
4. Update `scripts/build-app.sh` (`RELEASE_TAG="${RELEASE_TAG:-v1.1.0}"`): copy `resources/llama-icon.png` to `$APP_DIR/Contents/Resources/llama-icon.png`, generate `$ROOT_DIR/build/AppIcon.iconset` (`icon_16x16.png`..`icon_512x512@2x.png`) via `/usr/bin/sips -z`, and run `/usr/bin/iconutil -c icns "$ROOT_DIR/build/AppIcon.iconset" -o "$APP_DIR/Contents/Resources/AppIcon.icns"`.

- [ ] **Step 4: Run `test_core` and `scripts/build-app.sh` on Mavericks to verify**

Run `/tmp/test_core catalog/models.json` and `test -f dist/MavLlama.app/Contents/Resources/AppIcon.icns` after `bash scripts/build-app.sh`.
Expected: `PASS: testInferenceNotices` and `AppIcon.icns` + `llama-icon.png` present in `dist/MavLlama.app/Contents/Resources/`.

- [ ] **Step 5: Commit**

```bash
git add resources/llama-icon.png resources/Info.plist scripts/build-app.sh src/HardwareInspector.h src/HardwareInspector.m tests/test_core.m
git commit -m "feat: add global inference notice helper and llama.cpp app icon"
```

---

### Task 2: HTTP Headers & Media Cache Helper in `DownloadManager`

**Files:**
- Modify: `src/DownloadManager.h`
- Modify: `src/DownloadManager.m`
- Test: `tests/test_core.m`

**Interfaces:**
- Produces:
  - `+[DownloadManager fetchDataFromURL:(NSString *)urlString headers:(NSDictionary *)headers error:(NSError **)outError]` -> `NSData *` (existing `fetchDataFromURL:error:` delegates to this with `nil` headers; always sends `-A "MavLlama/1.1"`).
  - `+[DownloadManager classifyMediaData:(NSData *)headerBytes contentType:(NSString *)contentType urlString:(NSString *)urlString extension:(NSString **)outExt isVideo:(BOOL *)outIsVideo]` -> `BOOL` (pure classifier for unit testing).
  - `+[DownloadManager cacheMediaURL:(NSString *)urlString inDirectory:(NSString *)cacheDir maxBytes:(uint64_t)maxBytes fileURL:(NSURL **)outFileURL isVideo:(BOOL *)outIsVideo error:(NSError **)outError]` -> `BOOL`

- [ ] **Step 1: Write failing unit tests for media classification (`Content-Type` + magic bytes for extensionless GitHub URLs) in `tests/test_core.m`**

```objc
static void testMediaClassifier(void) {
    NSString *ext = nil;
    BOOL isVideo = NO;
    // Extensionless github user-attachments MP4 (ftyp box at offset 4)
    const uint8_t mp4Magic[] = {0x00, 0x00, 0x00, 0x18, 'f', 't', 'y', 'p', 'i', 's', 'o', 'm'};
    NSData *mp4Data = [NSData dataWithBytes:mp4Magic length:sizeof(mp4Magic)];
    assert([DownloadManager classifyMediaData:mp4Data contentType:@"video/mp4" urlString:@"https://github.com/user-attachments/assets/1234-uuid" extension:&ext isVideo:&isVideo]);
    assert([ext isEqualToString:@"mp4"] && isVideo == YES);

    // Shields.io SVG badge with no .svg suffix
    NSData *svgData = [@"<svg xmlns=\"http://www.w3.org/2000/svg\"></svg>" dataUsingEncoding:NSUTF8StringEncoding];
    assert([DownloadManager classifyMediaData:svgData contentType:@"image/svg+xml;charset=utf-8" urlString:@"https://img.shields.io/badge/Mavericks-10.9-blue" extension:&ext isVideo:&isVideo]);
    assert([ext isEqualToString:@"svg"] && isVideo == NO);

    // Animated GIF magic bytes even with generic octet-stream content-type
    NSData *gifData = [@"GIF89a\x01\x00\x01\x00" dataUsingEncoding:NSISOLatin1StringEncoding];
    assert([DownloadManager classifyMediaData:gifData contentType:@"application/octet-stream" urlString:@"https://github.com/user-attachments/assets/abcd" extension:&ext isVideo:&isVideo]);
    assert([ext isEqualToString:@"gif"] && isVideo == NO);

    NSLog(@"PASS: testMediaClassifier");
}
```

- [ ] **Step 2: Run test on Mavericks to verify it fails**

Expected: FAIL to compile (`classifyMediaData:contentType:urlString:extension:isVideo:` undeclared).

- [ ] **Step 3: Implement header-aware `fetchDataFromURL:headers:error:`, `classifyMediaData:...`, and `cacheMediaURL:...` in `DownloadManager`**

- Always pass `-A "MavLlama/1.1"` to `curl`; append `-H "Key: Value"` for each entry in `headers`.
- `classifyMediaData:...` checks HTTP `Content-Type` (`video/mp4`, `video/x-m4v`, `video/quicktime`, `image/gif`, `image/svg+xml`, `image/png`, `image/jpeg`, `image/webp`) and falls back to magic bytes (`ftyp` at bytes 4..7 -> `mp4`, `GIF87a`/`GIF89a` -> `gif`, `\x89PNG` -> `png`, `\xFF\xD8\xFF` -> `jpg`, `<svg` -> `svg`) and URL path extension. Returns `NO` for HTML/non-media payloads (`text/html`).
- `cacheMediaURL:...` hashes `urlString` via SHA-256 (reusing `CommonDigest`), returns any existing `<sha256>.*` hit in `cacheDir` immediately, otherwise runs bundled `curl -fsSL --max-time 30 --max-filesize <maxBytes> -D <tmpHeaders> -o <tmpBody> <url>`, classifies via `classifyMediaData:...`, atomically renames `<tmpBody>` to `<cacheDir>/<sha256>.<ext>`, and populates `*outFileURL` + `*outIsVideo`.

- [ ] **Step 4: Run `test_core` on Mavericks to verify**

Expected: `PASS: testMediaClassifier`.

- [ ] **Step 5: Commit**

```bash
git add src/DownloadManager.h src/DownloadManager.m tests/test_core.m
git commit -m "feat: add custom HTTP headers and curl media cache helper to DownloadManager"
```

---

### Task 3: GFM-to-HTML `MarkdownRenderer` with Tables, Badges, GIFs, & MP4 `<video>`

**Files:**
- Create: `src/MarkdownRenderer.h`
- Create: `src/MarkdownRenderer.m`
- Modify: `scripts/build-app.sh`
- Test: `tests/test_core.m`

**Interfaces:**
- Produces:
  - `@interface MavResolvedMedia : NSObject` with `@property (nonatomic, copy) NSString *fileURLString; @property (nonatomic, assign) BOOL isVideo;`
  - `+[MarkdownRenderer extractRemoteMediaURLsFromMarkdown:(NSString *)markdown]` -> `NSArray *` (ordered unique `http(s)://` URLs from `![...](url)`, `[![...](img)](href)`, `<img src="...">`, `<video src="...">`, `[...](...mp4)`, and standalone `https://github.com/user-attachments/assets/...` lines, capped at 25).
  - `+[MarkdownRenderer renderHTMLFromMarkdown:(NSString *)markdown releaseTitle:(NSString *)title releaseTag:(NSString *)tag resolvedMedia:(NSDictionary *)resolvedMedia]` -> `NSString *` (`resolvedMedia` maps original URL `NSString *` -> `MavResolvedMedia *`).

- [ ] **Step 1: Write failing unit tests for `MarkdownRenderer` in `tests/test_core.m`**

```objc
static void testMarkdownRenderer(void) {
    NSString *md =
        @"# MavLlama 1.1\n"
        @"[![MIT](https://img.shields.io/badge/license-MIT-blue.svg)](https://opensource.org/licenses/MIT)\n\n"
        @"| Tier | SIMD |\n"
        @"| :--- | :---: |\n"
        @"| Core 2 | SSSE3 |\n\n"
        @"![Demo](https://example.com/demo.gif)\n\n"
        @"https://github.com/user-attachments/assets/9999-video\n\n"
        @"<script>alert('xss')</script>\n";

    NSArray *urls = [MarkdownRenderer extractRemoteMediaURLsFromMarkdown:md];
    assert(urls.count == 3);
    assert([urls containsObject:@"https://img.shields.io/badge/license-MIT-blue.svg"]);
    assert([urls containsObject:@"https://example.com/demo.gif"]);
    assert([urls containsObject:@"https://github.com/user-attachments/assets/9999-video"]);

    MavResolvedMedia *badge = [[MavResolvedMedia alloc] init];
    badge.fileURLString = @"file:///tmp/cache/badge.svg";
    badge.isVideo = NO;

    MavResolvedMedia *vid = [[MavResolvedMedia alloc] init];
    vid.fileURLString = @"file:///tmp/cache/clip.mp4";
    vid.isVideo = YES;

    NSDictionary *map = @{
        @"https://img.shields.io/badge/license-MIT-blue.svg": badge,
        @"https://github.com/user-attachments/assets/9999-video": vid
    };

    NSString *html = [MarkdownRenderer renderHTMLFromMarkdown:md releaseTitle:@"v1.1.0" releaseTag:@"v1.1.0" resolvedMedia:map];
    assert([html rangeOfString:@"<table>"].location != NSNotFound);
    assert([html rangeOfString:@"<td>Core 2</td>"].location != NSNotFound);
    assert([html rangeOfString:@"file:///tmp/cache/badge.svg"].location != NSNotFound);
    assert([html rangeOfString:@"<video controls"].location != NSNotFound);
    assert([html rangeOfString:@"file:///tmp/cache/clip.mp4"].location != NSNotFound);
    assert([html rangeOfString:@"<script>"].location == NSNotFound); // escaped!

    NSLog(@"PASS: testMarkdownRenderer");
}
```

- [ ] **Step 2: Run test on Mavericks to verify it fails**

Expected: FAIL (`MarkdownRenderer.h` file not found).

- [ ] **Step 3: Implement `MarkdownRenderer.h` / `MarkdownRenderer.m` and add `src/MarkdownRenderer.m` + `-framework WebKit` to `scripts/build-app.sh`**

- Parse line-by-line state machine for fenced code blocks (` ``` `), GFM pipe tables (header row + `| :--- |` alignment separator + body rows), headings (`#`..`######`), blockquotes (`>`), lists (`- `, `* `, `1. `, plus `- [ ]` / `- [x]` checkboxes), horizontal rules, standalone attachment/video URLs, safe raw `<img>`/`<video src="...">` extraction (converting attributes cleanly while HTML-escaping all other raw `<...>` tags so `<script>` is rendered inert as `&lt;script&gt;`), and inline formatting (`[![alt](img)](href)` badge links, `![alt](src)` images, `[label](href)` links, `` `code` ``, `**bold**`, `*italic*`, `~~strike~~`).
- When an extracted media URL exists in `resolvedMedia`:
  - `isVideo == YES`: emit `<div class="media-video"><video controls preload="metadata"><source src="<fileURL>" type="video/mp4"></video><div class="video-fallback"><a href="<origURL>">Open video in browser</a></div></div>`.
  - `isVideo == NO`: emit `<img src="<fileURL>" alt="<escapedAlt>" class="<badge-or-img>">`.
  - Unresolved media URL: emit a clean placeholder box (`Loading media…` or clickable fallback link) without making direct `https://` `<img>`/`<video>` requests inside 10.9 `WebView`.
- Include clean Mavericks-friendly embedded CSS (clean Helvetica Neue / Lucida Grande typography, bordered zebra GFM tables, inline badge spacing, rounded code blocks, `max-width: 100%` images & videos).

- [ ] **Step 4: Run `test_core` on Mavericks to verify**

Compile with `src/MarkdownRenderer.m` included and run `/tmp/test_core catalog/models.json`.
Expected: `PASS: testMarkdownRenderer`.

- [ ] **Step 5: Commit**

```bash
git add src/MarkdownRenderer.h src/MarkdownRenderer.m scripts/build-app.sh tests/test_core.m
git commit -m "feat: add GFM MarkdownRenderer with tables, badges, GIFs, MP4 video, and XSS escaping"
```

---

### Task 4: `UpdateManager` (GitHub Releases Parser, Version Comparator, 6h Cache, Media Prefetch, & Safe `.app` Swapper)

**Files:**
- Create: `src/UpdateManager.h`
- Create: `src/UpdateManager.m`
- Modify: `scripts/build-app.sh`
- Test: `tests/test_core.m`

**Interfaces:**
- Consumes: `DownloadManager`, `MarkdownRenderer`, `ServerController`
- Produces:
  - `@interface MavReleaseInfo : NSObject` (`tagName`, `name`, `body`, `htmlURL`, `publishedAt`, `prerelease`, `draft`, `appZipAssetName`, `appZipDownloadURL`, `appZipSizeBytes`, `checksumsDownloadURL`)
  - `+[UpdateManager compareVersion:(NSString *)v1 toVersion:(NSString *)v2]` -> `NSComparisonResult`
  - `+[UpdateManager parseReleasesFromData:(NSData *)jsonData error:(NSError **)outError]` -> `NSArray *` (excludes `draft == YES`)
  - `+[UpdateManager latestStableReleaseFromReleases:(NSArray *)releases]` -> `MavReleaseInfo *` (highest version with `!prerelease && appZipDownloadURL.length > 0`)
  - `+[UpdateManager updaterShellScriptContents]` -> `NSString *`
  - `-[UpdateManager currentAppVersion]` -> `NSString *`
  - `-[UpdateManager checkForUpdatesForceRefresh:(BOOL)force completion:(void (^)(NSArray *releases, MavReleaseInfo *latestStable, BOOL updateAvailable, NSError *error))completion]`
  - `-[UpdateManager renderRelease:(MavReleaseInfo *)release initialHTML:(void (^)(NSString *html, NSURL *baseURL))initialBlock updatedHTML:(void (^)(NSString *html, NSURL *baseURL))updatedBlock]`
  - `-[UpdateManager installRelease:(MavReleaseInfo *)release downloadManager:(DownloadManager *)downloadManager serverController:(ServerController *)serverController progress:(MavDownloadProgressBlock)progressBlock completion:(void (^)(BOOL launchedUpdater, NSString *errorMessage))completion]`

- [ ] **Step 1: Write failing unit tests for version comparison, draft/prerelease filtering, and shell script quoting in `tests/test_core.m`**

```objc
static void testUpdateManagerParsingAndVersions(void) {
    assert([UpdateManager compareVersion:@"v1.0.0" toVersion:@"1.0.0"] == NSOrderedSame);
    assert([UpdateManager compareVersion:@"v1.1.0" toVersion:@"v1.0.0"] == NSOrderedDescending);
    assert([UpdateManager compareVersion:@"v1.10.0" toVersion:@"v1.2.0"] == NSOrderedDescending);
    assert([UpdateManager compareVersion:@"v1.1.0-beta.1" toVersion:@"v1.1.0"] == NSOrderedAscending);

    NSString *sampleJSON =
        @"["
        @"  {\"tag_name\":\"v1.2.0-draft\",\"name\":\"Draft\",\"draft\":true,\"prerelease\":false,\"body\":\"x\",\"assets\":[{\"name\":\"MavLlama-v1.2.0-Mavericks.zip\",\"browser_download_url\":\"https://example.com/d.zip\",\"size\":100}]},"
        @"  {\"tag_name\":\"v1.2.0-beta.1\",\"name\":\"Beta\",\"draft\":false,\"prerelease\":true,\"body\":\"beta\",\"assets\":[{\"name\":\"MavLlama-v1.2.0-beta.1-Mavericks.zip\",\"browser_download_url\":\"https://example.com/b.zip\",\"size\":100}]},"
        @"  {\"tag_name\":\"v1.1.1-notes\",\"name\":\"Source Only\",\"draft\":false,\"prerelease\":false,\"body\":\"no zip\",\"assets\":[]},"
        @"  {\"tag_name\":\"v1.1.0\",\"name\":\"MavLlama 1.1\",\"draft\":false,\"prerelease\":false,\"body\":\"# Notes\",\"assets\":["
        @"    {\"name\":\"MavLlama-v1.1.0-Mavericks.zip\",\"browser_download_url\":\"https://example.com/app.zip\",\"size\":8123456},"
        @"    {\"name\":\"checksums.txt\",\"browser_download_url\":\"https://example.com/checksums.txt\",\"size\":128}"
        @"  ]}"
        @"]";
    NSError *err = nil;
    NSArray *releases = [UpdateManager parseReleasesFromData:[sampleJSON dataUsingEncoding:NSUTF8StringEncoding] error:&err];
    assert(err == nil);
    assert(releases.count == 3); // draft excluded

    MavReleaseInfo *latest = [UpdateManager latestStableReleaseFromReleases:releases];
    assert(latest != nil);
    assert([latest.tagName isEqualToString:@"v1.1.0"]);
    assert([latest.appZipAssetName isEqualToString:@"MavLlama-v1.1.0-Mavericks.zip"]);
    assert([latest.checksumsDownloadURL isEqualToString:@"https://example.com/checksums.txt"]);

    NSString *script = [UpdateManager updaterShellScriptContents];
    assert([script rangeOfString:@"\"$TARGET_APP\""].location != NSNotFound);
    assert([script rangeOfString:@"\"$STAGED_APP\""].location != NSNotFound);

    NSLog(@"PASS: testUpdateManagerParsingAndVersions");
}
```

- [ ] **Step 2: Run test on Mavericks to verify it fails**

Expected: FAIL (`UpdateManager.h` file not found).

- [ ] **Step 3: Implement `UpdateManager.h` / `UpdateManager.m` and add `src/UpdateManager.m` to `scripts/build-app.sh`**

- Implement `compareVersion:toVersion:` by stripping leading `v`/`V`, splitting on `-` (`base` vs optional `prerelease`), comparing integer dot components of `base`, and ranking `no-prerelease > has-prerelease` when `base` components match.
- Implement `checkForUpdatesForceRefresh:completion:` reading/writing `~/Library/Caches/MavLlama/releases-cache.json` (`fetchedAt` epoch + raw array) with a 21600-second (6-hour) TTL when `force == NO`, calling `[DownloadManager fetchDataFromURL:@"https://api.github.com/repos/momochisoundpost/MavLlama/releases" headers:@{@"Accept": @"application/vnd.github+json"} error:&err]` on a background queue and dispatching completion on the main queue.
- Implement `renderRelease:initialHTML:updatedHTML:` emitting immediate HTML from `MarkdownRenderer`, then prefetching remote URLs via `[DownloadManager cacheMediaURL:... inDirectory:mediaCacheDir maxBytes:50ULL*1024*1024 ...]` on a background queue and invoking `updatedBlock` on the main queue if any new media resolved.
- Implement `installRelease:...` following Spec Section 5.3 steps 1–9: check bundle & parent write permissions, optionally fetch `checksums.txt` to resolve SHA-256 for `release.appZipAssetName`, download `.zip` via `DownloadManager`, extract with `/usr/bin/ditto -x -k` into `~/Library/Application Support/MavLlama/updates/staging-<uuid>`, verify `MavLlama.app/Contents/MacOS/MavLlama` is executable and `Info.plist` parses, strip quarantine via `/usr/bin/xattr -dr com.apple.quarantine`, stop `serverController` synchronously, launch detached `/bin/sh apply-update.sh <pid> <stagedApp> <targetApp> <stagingDir>`, and call `[NSApp terminate:nil]`.

- [ ] **Step 4: Run `test_core` on Mavericks to verify**

Compile with `src/UpdateManager.m` included and run `/tmp/test_core catalog/models.json`.
Expected: `PASS: testUpdateManagerParsingAndVersions`.

- [ ] **Step 5: Commit**

```bash
git add src/UpdateManager.h src/UpdateManager.m scripts/build-app.sh tests/test_core.m
git commit -m "feat: implement UpdateManager for GitHub Releases, media prefetch, and .app swap"
```

---

### Task 5: `Updates` & `About` Tabs, Global Banner Wiring, Menu Bar Items, & Full Bundle Verification

**Files:**
- Modify: `src/MainWindowController.h`
- Modify: `src/MainWindowController.m`
- Modify: `src/AppDelegate.m`

**Interfaces:**
- Consumes: `HardwareInspector`, `UpdateManager`, `MarkdownRenderer`, `DownloadManager`, `ServerController`
- Produces:
  - Updated `-[MainWindowController initWithHardwareInfo:downloadManager:engineManager:serverController:updateManager:]`
  - 5-tab `MainWindowController`: `0` = `System Check & Engine` (with global `inferenceNoticeLabel`), `1` = `Model Marketplace`, `2` = `Settings`, `3` = `Updates`, `4` = `About`
  - Menu bar items in `AppDelegate`: `Check for Updates...` (dynamically titled `Update Available (<tag>)...` when a newer stable release is detected) and `About MavLlama`

- [ ] **Step 1: Update `MainWindowController.h/.m` with global `inferenceNoticeLabel`, `Updates` tab (`WebView` + `WebPolicyDelegate`), and `About` tab**

1. **System Check & Engine tab:** Replace Mac-Pro-only `macProBannerLabel` visibility toggle with always-visible `inferenceNoticeLabel` populated by `[HardwareInspector inferenceNoticeForIsMacPro:self.hardware.isMacPro modelIdentifier:self.hardware.modelIdentifier hasAVX2:self.hardware.hasAVX2]`.
2. **Updates tab (`buildUpdatesTab`):**
   - Header bar: installed version vs latest version status label, `Check Again` button, `NSPopUpButton` release selector, and `View on GitHub` button.
   - Body: `WebView` (`<WebKit/WebKit.h>`) with `policyDelegate = self` intercepting `WebNavigationTypeLinkClicked` `http(s)://` clicks and routing them to `[[NSWorkspace sharedWorkspace] openURL:]` + `[listener ignore]`.
   - Footer: `NSProgressIndicator` + status text + action button implementing Spec Section 5.3 button rules (`Update to <tag> & Relaunch`, `Up to Date (<tag>)`, or confirmation `NSAlert` for pre-release / downgrade). Triggers `[self refreshUpdatesIfNeeded]` when tab `3` is selected for the first time.
3. **About tab (`buildAboutTab`):**
   - Centered `72×72` custom `NSView` drawing `[NSImage imageNamed:@"llama-icon"]` clipped to a `16pt` rounded rect.
   - Centered `MavLlama` (`20pt` bold) and `Current Version: <version>` (`12.5pt` gray).
   - Centered rounded card (`520×84`, subtle dark/slate tinted fill + border via `NSBezierPath`) displaying bold `MavLlama — So I put local LLMs on Mavericks because nobody did it.` and italic `built in public by Caitlyn Momochi`.
   - Centered row of 4 buttons (`YouTube`, `Twitter / X`, `GitHub`, `Instagram`) opening the exact URLs from Global Constraints via `[[NSWorkspace sharedWorkspace] openURL:]`.
   - Centered storage footer showing `Engine & settings stored in ~/Library/Application Support/MavLlama` and `Models stored in <modelsDirectory>`.

- [ ] **Step 2: Wire `UpdateManager`, menu bar shortcuts, and 6-hour launch check in `AppDelegate.m`**

- Instantiate `self.updateManager = [[UpdateManager alloc] init]`, pass to `MainWindowController`, add `Check for Updates...` (`selectTab:3`) and `About MavLlama` (`selectTab:4`) menu items below `Open MavLlama (Setup & Models)...`, and invoke `[self.updateManager checkForUpdatesForceRefresh:NO completion:...]` at the end of `applicationDidFinishLaunching:` to update the menu item title to `Update Available (<tag>)...` if `updateAvailable == YES`.

- [ ] **Step 3: Sync full repo to Mavericks, run `test_core`, `scripts/build-app.sh`, and `scripts/verify-bundle.sh`**

Run on `widi@192.168.18.252`:
```bash
cd ~/Projects/MavLlama
/usr/bin/clang -fobjc-arc -O2 -Wall -Wextra -Werror -mmacosx-version-min=10.9 -march=core2 \
  -framework Cocoa -framework WebKit \
  tests/test_core.m src/HardwareInspector.m src/ModelCatalog.m src/DownloadManager.m src/MarkdownRenderer.m src/UpdateManager.m \
  -o build/test_core && ./build/test_core catalog/models.json
bash scripts/build-app.sh
bash scripts/verify-bundle.sh
```
Expected:
- `ALL MAVLLAMA CORE TESTS PASSED`
- `Built .../dist/MavLlama.app and .../dist/MavLlama-v1.1.0-Mavericks.zip` with zero warnings under `-Werror`
- `ALL MAVLLAMA BUNDLE & ENGINE VERIFICATION CHECKS PASSED` (confirming zero external `/opt/local` dylib leaks in `MavLlama`)

- [ ] **Step 4: Commit**

```bash
git add src/MainWindowController.h src/MainWindowController.m src/AppDelegate.m
git commit -m "feat: add Updates and About tabs, global CPU-only notice, and menu bar update check"
```
