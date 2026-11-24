#!/usr/bin/env bash
set -euo pipefail

export PATH="/opt/local/bin:/opt/local/sbin:/usr/bin:/bin:/usr/sbin:/sbin"

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/MavLlama.app"
MANIFEST="$ROOT_DIR/catalog/engine-manifest.json"

assert_no_leaks() {
  local bin="$1"
  local leaks
  leaks="$(/opt/local/bin/otool -L "$bin" | tail -n +2 | awk '{print $1}' | grep -E '^/(opt|usr)/local/' || true)"
  if [ -n "$leaks" ]; then
    echo "FAIL: external library leak in $bin:" >&2
    echo "$leaks" >&2
    exit 1
  fi
  echo "OK (no external dylib leaks): $bin"
}

echo "=== 1. Verify MavLlama.app bundle & bundled curl ==="
assert_no_leaks "$APP_DIR/Contents/MacOS/MavLlama"
assert_no_leaks "$APP_DIR/Contents/Resources/bin/curl"
for lib in "$APP_DIR/Contents/Frameworks"/*.dylib; do
  assert_no_leaks "$lib"
done

# Verify bundled curl works cleanly without DYLD_LIBRARY_PATH
HTTP_CODE="$(env -i PATH=/usr/bin:/bin "$APP_DIR/Contents/Resources/bin/curl" \
  --cacert "$APP_DIR/Contents/Resources/ca-bundle.crt" \
  -s -o /dev/null -w "%{http_code}" --max-time 10 "https://api.github.com/")"
if [ "$HTTP_CODE" != "200" ]; then
  echo "FAIL: bundled curl returned HTTP $HTTP_CODE on https://api.github.com/" >&2
  exit 1
fi
echo "OK: bundled curl TLS 1.3 / OpenSSL 3 returned HTTP 200"

echo "=== 2. Verify all 5 engine tarballs ==="
HOST_TIER="$(/usr/bin/python -c '
import subprocess
feat = subprocess.check_output(["sysctl", "-n", "machdep.cpu.features"]).decode()
if "AVX" in feat.split() or "AVX1.0" in feat.split():
    print("sandybridge")
elif "SSE4.2" in feat.split():
    print("nehalem")
else:
    print("core2")
')"

for tier in core2 nehalem sandybridge ivybridge haswell; do
  TAR="$(ls "$DIST_DIR"/mavllama-engine-*-darwin13-"${tier}".tar.gz | head -n 1)"
  [ -f "$TAR" ]
  ACTUAL_SHA="$(shasum -a 256 "$TAR" | awk '{print $1}')"
  EXPECTED_SHA="$(/usr/bin/python -c "import json; d=json.load(open('$MANIFEST')); print(d['tiers']['$tier']['sha256'])")"
  if [ "$ACTUAL_SHA" != "$EXPECTED_SHA" ]; then
    echo "FAIL: SHA-256 mismatch for $TAR ($ACTUAL_SHA != $EXPECTED_SHA)" >&2
    exit 1
  fi
  echo "OK (SHA-256 matches manifest): $(basename "$TAR")"

  UNPACK="/tmp/mavllama-verify-${tier}"
  rm -rf "$UNPACK"
  mkdir -p "$UNPACK"
  tar -xzf "$TAR" -C "$UNPACK"
  assert_no_leaks "$UNPACK/llama-server"
  for lib in "$UNPACK"/*.dylib; do
    assert_no_leaks "$lib"
  done

  if [ "$tier" = "core2" ] || [ "$tier" = "nehalem" ] || [ "$tier" = "$HOST_TIER" ]; then
    VER="$(env -i PATH=/usr/bin:/bin "$UNPACK/llama-server" --version | head -n 1)"
    echo "OK (executed $tier): $VER"
  fi
  rm -rf "$UNPACK"
done

echo "ALL MAVLLAMA BUNDLE & ENGINE VERIFICATION CHECKS PASSED"
