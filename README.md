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

## Credits

- [ggml-org/llama.cpp](https://github.com/ggml-org/llama.cpp) — inference engine and embedded chat Web UI
- [MacPorts](https://www.macports.org/) — `clang-18`, `macports-libcxx`, `macports-legacy-support`, and OpenSSL 3 on OS X 10.9
- [Mavericks Forever](https://mavericksforever.com/) — Momiji and modern Mavericks ecosystem patches

Licensed under the [MIT License](LICENSE).
