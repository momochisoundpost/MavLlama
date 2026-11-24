# MavLlama

**Zero-terminal local LLM runner and hardware-aware model marketplace for OS X 10.9 Mavericks.**

Built by [Caitlyn Momochi (`@momochisoundpost`)](https://github.com/momochisoundpost) at Momochi Soundpost — in the same zero-dependency native Mac utility spirit as [VRemind](https://github.com/momochisoundpost/VRemind).

---

## Why MavLlama?

Getting modern local AI (`llama.cpp`) running on OS X 10.9 Mavericks normally means installing MacPorts, Clang 18, `macports-libcxx`, `libMacportsLegacySupport`, tuning CMake flags so your CPU doesn't hit `SIGILL`, and hunting down GGUF URLs.

**MavLlama** wraps all of that into a single double-click native Cocoa app:

- **Works on any OS X `10.9.x` build** — no App Store update, `13F1911`, AquaProxy, Xcode, or MacPorts required.
- **Self-contained HTTPS downloads** — bundles a minimal `-march=core2` `curl` + OpenSSL 3 + modern CA bundle inside `MavLlama.app` so GitHub Releases and HuggingFace work even on bone-stock OS X `10.9.0`.
- **5 CPU-tier engine builds** — inspects your CPU flags (`sysctl`) and downloads the exact `llama-server` build for your hardware (**Core 2 Duo** through **Haswell**), with SHA-256 verification.
- **Hardware-aware Model Marketplace** — 16 curated public GGUFs spanning **Gemma 3**, **DeepSeek**, **Qwen**, **Llama 3.2**, **Phi-4**, and **SmolLM2**, filtered by physical RAM (with an override checkbox, custom `.gguf` import, and custom URL downloader).
- **Mac Pro Unrestricted Mode** — automatically detects `MacPro*` models (`MacPro3,1`–`MacPro6,1`), unlocks the full catalog regardless of RAM filter, and reminds you that Mavericks inference is CPU-only (no AVX2, no OpenCL, no Metal).
- **Native Mavericks Menu Bar Controller** — monitors server PID, active model, RAM free / AI memory, and download progress; includes **Start / Stop / Restart** and **`Launch the chatbot`** (opens Momiji, Chromium Legacy, Firefox Dynasty, or InterWeb, or shows your LAN URL for phones, tablets, and modern PCs if you haven't installed a modern browser yet).

---

## Supported Hardware Tiers (OS X 10.9.x)

| Tier | Representative Macs | ISA Flags |
|---|---|---|
| `core2` | Merom / Penryn Core 2 Duo, `MacPro3,1` | `SSSE3` baseline (no SSE4.2 / AVX) |
| `nehalem` | Nehalem / Westmere Core i-series, `MacPro4,1` / `MacPro5,1` | `SSE4.2` |
| `sandybridge` | 2011 Sandy Bridge MacBook Pro / Air / iMac / Mac mini | `SSE4.2` + `AVX` |
| `ivybridge` | 2012–early 2013 Ivy Bridge Macs, `MacPro6,1` | `SSE4.2` + `AVX` + `F16C` |
| `haswell` | Mid 2013–2014 Haswell Macs | `SSE4.2` + `AVX` + `F16C` + `AVX2` + `FMA` + `BMI2` |

---

## Quick Start

1. Download **`MavLlama-v1.0.0-Mavericks.zip`** from [GitHub Releases](https://github.com/momochisoundpost/MavLlama/releases/latest), unzip it, and move `MavLlama.app` to `/Applications`.
2. Double-click **`MavLlama.app`** — the **System Check & Engine** tab inspects your OS, CPU tier, RAM, disk space, and browser.
3. Click **Download Tailored Engine** to pull the prebuilt `llama-server` archive matching your CPU.
4. Open the **Model Marketplace** tab, pick a model sized for your RAM (start with `SmolLM2 360M` or `Qwen2.5 0.5B` for snappy ~15–20 tok/s replies, `Gemma 3 4B` / `DeepSeek-R1 1.5B` on 8 GB Macs, or **`Qwen3 30B-A3B` MoE** / **`DeepSeek-V2-Lite` MoE** on 16 GB+ Macs), and click **Download**.
5. Click **`Launch the chatbot`** in the menu bar — or open **`http://<your-mac-ip>:8080`** from any phone, tablet, or modern PC on your Wi-Fi!

---

## Building from Source (on OS X 10.9 Mavericks)

Requires MacPorts on OS X 10.9 with `clang-18`, `cmake`, `ninja`, `macports-libcxx`, `legacy-support`, `openssl3`, `zlib`, and `curl-ca-bundle`:

```bash
# 1. Run core unit tests
/usr/bin/clang -fobjc-arc -O2 -Wall -Wextra -Werror -mmacosx-version-min=10.9 \
  -framework Foundation src/HardwareInspector.m src/ModelCatalog.m \
  src/DownloadManager.m tests/test_core.m -o /tmp/mavllama_tests
/tmp/mavllama_tests catalog/models.json

# 2. Build all 5 CPU-tier llama-server tarballs and generate catalog/engine-manifest.json
./scripts/build-engines.sh

# 3. Build minimal Core-2-safe curl + MavLlama.app + release zip
./scripts/build-app.sh

# 4. Verify zero external dylib leaks, bundled TLS, and engine SHA-256s
./scripts/verify-bundle.sh
```

---

## FAQ

**Why are you doing this?**  
Because it's technically possible — especially in the age of AI, where you can literally run GTA 5 right in your browser. If a browser tab can run Los Santos, a 2013 skeuomorphic cat OS deserves its own local chatbot.

**Wait… how fast does it actually run?**  
On a small model like `Qwen2.5 0.5B` on a Sandy Bridge i7, you get a genuinely snappy **~18–22 tokens/sec**. On a **30B MoE** running across 15-year-old dual-core DDR3 RAM? Expect a deeply meditative **2–4 tokens/sec** — slow enough to read along comfortably, fast enough to make your friends stare at Activity Monitor in disbelief.

**I have a cheese-grater Mac Pro with 64 GB of cheap ECC DDR3 and a beastly GPU. Can I use OpenCL or Metal?**  
Nope! OS X Mavericks predates Metal by two years, and `llama.cpp` dropped old OpenCL here — plus your Xeons probably don't have AVX2 either. MavLlama lifts all RAM restrictions for Mac Pros so you *can* cram `Gemma 3 27B` or `Qwen3 30B-A3B Q4_K_M` straight into RAM, and politely reminds you that your CPU will be doing 100% of the heavy lifting while your GPU watches from the sidelines.

**Why won't the chat UI load in Mavericks' built-in Safari?**  
Because Safari 9 hasn't seen a JavaScript standard since 2015 and immediately faints when it meets a modern web app. MavLlama looks for **Momiji**, **Chromium Legacy**, **Firefox Dynasty**, or **InterWeb** first — and if you haven't installed one yet, it hands you your Mac's LAN URL so your phone, tablet, or main PC can talk to the Mavericks brain instead.

**My Mac App Store is dead and I'm stuck on an older `10.9.x` build (not `13F1911`). Am I screwed?**  
Not at all. MavLlama doesn't care about the Mac App Store, `13F1911`, AquaProxy, or MacPorts. It ships its own minimal `-march=core2` `curl` + OpenSSL 3 + modern CA certificates inside the `.app` bundle, so even a completely untouched OS X `10.9.0` install from 2013 can talk to HuggingFace over TLS 1.3.

**Will this turn my Core 2 Duo MacBook into a tiny aluminum jet engine?**  
Oh, 100%. Stick to `SmolLM2 360M` or `Qwen2.5 0.5B` if you'd like your MacBook to stay on the desk instead of achieving low-Earth orbit, and keep Macs Fan Control handy.

**Is this practical for real daily work?**  
Define "practical." Is it replacing an RTX 5090 rig? No. Does it turn "e-waste" into a whisper-quiet offline LAN AI appliance — and give you the ultimate flex at a coffee shop or on stream? Absolutely.

---

## Credits

- [ggml-org/llama.cpp](https://github.com/ggml-org/llama.cpp) — inference engine and embedded chat Web UI
- [MacPorts](https://www.macports.org/) — `clang-18`, `macports-libcxx`, `macports-legacy-support`, and OpenSSL 3 on OS X 10.9
- [Mavericks Forever](https://mavericksforever.com/) — Momiji and modern Mavericks ecosystem patches

Licensed under the [MIT License](LICENSE).
