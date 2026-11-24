#!/usr/bin/env bash
set -euo pipefail

export PATH="/opt/local/bin:/opt/local/sbin:/usr/bin:/bin:/usr/sbin:/sbin"

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RELEASE_TAG="${RELEASE_TAG:-v1.0.0}"
LLAMA_CPP_REF="${LLAMA_CPP_REF:-66a3b01}"
LLAMA_CPP_SRC="${LLAMA_CPP_SRC:-$ROOT_DIR/build/llama.cpp}"
REPO_URL="${REPO_URL:-https://github.com/momochisoundpost/MavLlama}"
BUILD_DIR="$ROOT_DIR/build/llama-engines"
DIST_DIR="$ROOT_DIR/dist"
MANIFEST_PATH="$ROOT_DIR/catalog/engine-manifest.json"

mkdir -p "$ROOT_DIR/build" "$DIST_DIR" "$ROOT_DIR/catalog"

# Reuse existing clone if present at the pinned commit, otherwise clone fresh
if [ ! -d "$LLAMA_CPP_SRC/.git" ]; then
  if [ -d "/Users/widi/Projects/llama.cpp/.git" ]; then
    LLAMA_CPP_SRC="/Users/widi/Projects/llama.cpp"
  else
    git clone https://github.com/ggml-org/llama.cpp.git "$LLAMA_CPP_SRC"
  fi
fi

ACTUAL_COMMIT="$(git -C "$LLAMA_CPP_SRC" rev-parse --short HEAD)"
echo "Using llama.cpp at $LLAMA_CPP_SRC (commit $ACTUAL_COMMIT, requested $LLAMA_CPP_REF)"

if [ "${ALLOW_ANY_COMMIT:-0}" != "1" ] && [ "$ACTUAL_COMMIT" != "$LLAMA_CPP_REF" ]; then
  git -C "$LLAMA_CPP_SRC" fetch --depth 1 origin "$LLAMA_CPP_REF" || true
  git -C "$LLAMA_CPP_SRC" checkout "$LLAMA_CPP_REF"
  ACTUAL_COMMIT="$(git -C "$LLAMA_CPP_SRC" rev-parse --short HEAD)"
fi

TIERS=("core2" "nehalem" "sandybridge" "ivybridge" "haswell")

tier_flags() {
  case "$1" in
    core2)
      echo "-DGGML_SSE42=OFF -DGGML_AVX=OFF -DGGML_F16C=OFF -DGGML_AVX2=OFF -DGGML_FMA=OFF -DGGML_BMI2=OFF"
      ;;
    nehalem)
      echo "-DGGML_SSE42=ON -DGGML_AVX=OFF -DGGML_F16C=OFF -DGGML_AVX2=OFF -DGGML_FMA=OFF -DGGML_BMI2=OFF"
      ;;
    sandybridge)
      echo "-DGGML_SSE42=ON -DGGML_AVX=ON -DGGML_F16C=OFF -DGGML_AVX2=OFF -DGGML_FMA=OFF -DGGML_BMI2=OFF"
      ;;
    ivybridge)
      echo "-DGGML_SSE42=ON -DGGML_AVX=ON -DGGML_F16C=ON -DGGML_AVX2=OFF -DGGML_FMA=OFF -DGGML_BMI2=OFF"
      ;;
    haswell)
      echo "-DGGML_SSE42=ON -DGGML_AVX=ON -DGGML_F16C=ON -DGGML_AVX2=ON -DGGML_FMA=ON -DGGML_BMI2=ON"
      ;;
    *)
      echo "Unknown tier: $1" >&2
      exit 1
      ;;
  esac
}

normalize_dylib_name() {
  case "$1" in
    libc++.1.0.dylib|libc++.1.dylib) echo "libc++.1.dylib" ;;
    libc++abi.1.0.dylib|libc++abi.1.dylib) echo "libc++abi.1.dylib" ;;
    libunwind.1.0.dylib|libunwind.1.dylib) echo "libunwind.1.dylib" ;;
    *) echo "$1" ;;
  esac
}

relink_binary() {
  local target="$1"
  local prefix="$2"
  local deps
  deps="$(/opt/local/bin/otool -L "$target" | tail -n +2 | awk '{print $1}' | grep '^/opt/local/' || true)"
  for dep in $deps; do
    local base
    base="$(normalize_dylib_name "$(basename "$dep")")"
    /opt/local/bin/install_name_tool -change "$dep" "${prefix}/${base}" "$target"
  done
}

NCPU="$(sysctl -n hw.ncpu || echo 4)"
rm -rf "$BUILD_DIR"

# Initial clean configure with strict -march=core2 base flags so ggml-base/llama/common are Core 2 safe
cmake -G Ninja -S "$LLAMA_CPP_SRC" -B "$BUILD_DIR" \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_OSX_DEPLOYMENT_TARGET=10.9 \
  -DCMAKE_C_COMPILER=/opt/local/bin/clang \
  -DCMAKE_CXX_COMPILER=/opt/local/bin/clang++ \
  -DCMAKE_C_FLAGS="-march=core2 -isystem /opt/local/include/LegacySupport -O3" \
  -DCMAKE_CXX_FLAGS="-march=core2 -nostdinc++ -isystem /opt/local/include/libcxx/v1 -isystem /opt/local/include/LegacySupport -D_LIBCPP_DISABLE_AVAILABILITY -O3" \
  -DCMAKE_EXE_LINKER_FLAGS="-L/opt/local/lib/libcxx -L/opt/local/lib/libcxx/libunwind -L/opt/local/lib -Wl,-rpath,/opt/local/lib/libcxx -Wl,-rpath,/opt/local/lib -lc++ -lc++abi -lunwind -lMacportsLegacySupport" \
  -DBUILD_SHARED_LIBS=OFF \
  -DGGML_NATIVE=OFF \
  -DGGML_METAL=OFF \
  -DGGML_ACCELERATE=OFF \
  -DGGML_BLAS=OFF \
  -DGGML_OPENMP=OFF \
  -DLLAMA_CURL=OFF \
  -DLLAMA_OPENSSL=OFF \
  -DLLAMA_BUILD_TESTS=OFF \
  -DLLAMA_BUILD_EXAMPLES=OFF \
  -DLLAMA_BUILD_TOOLS=ON \
  -DLLAMA_BUILD_SERVER=ON \
  $(tier_flags "core2")

JSON_ITEMS=()
: > "$DIST_DIR/checksums.txt"

for tier in "${TIERS[@]}"; do
  echo "=== Building tier: $tier ==="
  cmake -S "$LLAMA_CPP_SRC" -B "$BUILD_DIR" $(tier_flags "$tier")
  cmake --build "$BUILD_DIR" -j "$NCPU" --target llama-server

  STAGE="$ROOT_DIR/build/stage-$tier"
  rm -rf "$STAGE"
  mkdir -p "$STAGE"

  cp "$BUILD_DIR/bin/llama-server" "$STAGE/llama-server"
  cp -L "/opt/local/lib/libcxx/libc++.1.dylib" "$STAGE/libc++.1.dylib"
  cp -L "/opt/local/lib/libcxx/libc++abi.1.dylib" "$STAGE/libc++abi.1.dylib"
  cp -L "/opt/local/lib/libcxx/libunwind/libunwind.1.dylib" "$STAGE/libunwind.1.dylib"
  cp -L "/opt/local/lib/libMacportsLegacySupport.dylib" "$STAGE/libMacportsLegacySupport.dylib"

  chmod 755 "$STAGE/llama-server" "$STAGE"/*.dylib
  relink_binary "$STAGE/llama-server" "@executable_path"

  for lib in libc++.1.dylib libc++abi.1.dylib libunwind.1.dylib libMacportsLegacySupport.dylib; do
    /opt/local/bin/install_name_tool -id "@executable_path/$lib" "$STAGE/$lib"
    relink_binary "$STAGE/$lib" "@loader_path"
  done

  TAR_NAME="mavllama-engine-${RELEASE_TAG}-darwin13-${tier}.tar.gz"
  TAR_PATH="$DIST_DIR/$TAR_NAME"
  tar -czf "$TAR_PATH" -C "$STAGE" .

  SHA="$(shasum -a 256 "$TAR_PATH" | awk '{print $1}')"
  BYTES="$(stat -f%z "$TAR_PATH")"
  URL="${REPO_URL}/releases/download/${RELEASE_TAG}/${TAR_NAME}"

  echo "$SHA  $TAR_NAME" >> "$DIST_DIR/checksums.txt"
  JSON_ITEMS+=("    \"$tier\": { \"url\": \"$URL\", \"sha256\": \"$SHA\", \"sizeBytes\": $BYTES }")
  echo "Built $TAR_NAME ($BYTES bytes, sha256=$SHA)"
done

{
  echo "{"
  echo "  \"schemaVersion\": 1,"
  echo "  \"releaseTag\": \"$RELEASE_TAG\","
  echo "  \"llamaCppCommit\": \"$ACTUAL_COMMIT\","
  echo "  \"tiers\": {"
  for i in "${!JSON_ITEMS[@]}"; do
    if [ "$i" -lt "$((${#JSON_ITEMS[@]} - 1))" ]; then
      echo "${JSON_ITEMS[$i]},"
    else
      echo "${JSON_ITEMS[$i]}"
    fi
  done
  echo "  }"
  echo "}"
} > "$MANIFEST_PATH"

echo "Wrote $MANIFEST_PATH"
