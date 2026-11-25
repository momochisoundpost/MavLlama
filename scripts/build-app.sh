#!/usr/bin/env bash
set -euo pipefail

export PATH="/opt/local/bin:/opt/local/sbin:/usr/bin:/bin:/usr/sbin:/sbin"

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
RELEASE_TAG="${RELEASE_TAG:-v1.1.0}"
CURL_VERSION="${CURL_VERSION:-8.23.0}"
CURL_URL="https://curl.se/download/curl-${CURL_VERSION}.tar.gz"
CURL_BUILD="$ROOT_DIR/build/curl-${CURL_VERSION}"
CURL_PREFIX="$ROOT_DIR/build/curl-prefix"
DIST_DIR="$ROOT_DIR/dist"
APP_DIR="$DIST_DIR/MavLlama.app"
NCPU="$(sysctl -n hw.ncpu || echo 4)"

mkdir -p "$ROOT_DIR/build" "$DIST_DIR"

# 1. Build minimal Core-2-safe curl linked only to OpenSSL 3 + zlib + Apple frameworks
if [ ! -x "$CURL_PREFIX/bin/curl" ]; then
  CURL_TAR="$ROOT_DIR/build/curl-${CURL_VERSION}.tar.gz"
  if [ ! -f "$CURL_TAR" ]; then
    /opt/local/bin/curl -fL --retry 3 -o "$CURL_TAR" "$CURL_URL"
  fi
  rm -rf "$CURL_BUILD" "$CURL_PREFIX"
  mkdir -p "$CURL_BUILD"
  tar -xzf "$CURL_TAR" -C "$CURL_BUILD" --strip-components=1

  pushd "$CURL_BUILD" >/dev/null
  export MACOSX_DEPLOYMENT_TARGET=10.9
  CC="/usr/bin/clang" \
  CFLAGS="-march=core2 -O2 -mmacosx-version-min=10.9" \
  CPPFLAGS="-I/opt/local/libexec/openssl3/include -I/opt/local/include" \
  LDFLAGS="-L/opt/local/libexec/openssl3/lib -L/opt/local/lib" \
  ./configure \
    --prefix="$CURL_PREFIX" \
    --disable-shared \
    --enable-static \
    --with-openssl=/opt/local/libexec/openssl3 \
    --with-zlib=/opt/local \
    --without-libidn2 \
    --without-libpsl \
    --without-brotli \
    --without-zstd \
    --without-nghttp2 \
    --without-nghttp3 \
    --without-ngtcp2 \
    --without-librtmp \
    --without-libssh2 \
    --disable-ldap \
    --disable-ldaps \
    --disable-dict \
    --disable-telnet \
    --disable-tftp \
    --disable-pop3 \
    --disable-imap \
    --disable-smb \
    --disable-smtp \
    --disable-gopher \
    --disable-mqtt \
    --disable-manual \
    --disable-docs
  make -j "$NCPU"
  make install
  popd >/dev/null
fi

# 2. Assemble MavLlama.app bundle
rm -rf "$APP_DIR"
mkdir -p \
  "$APP_DIR/Contents/MacOS" \
  "$APP_DIR/Contents/Frameworks" \
  "$APP_DIR/Contents/Resources/bin"

cp "$ROOT_DIR/resources/Info.plist" "$APP_DIR/Contents/Info.plist"
cp "$ROOT_DIR/resources/llama-icon.png" "$APP_DIR/Contents/Resources/llama-icon.png"
cp "$ROOT_DIR/catalog/models.json" "$APP_DIR/Contents/Resources/models.json"
cp "$ROOT_DIR/catalog/engine-manifest.json" "$APP_DIR/Contents/Resources/engine-manifest.json"
cp "/opt/local/share/curl/curl-ca-bundle.crt" "$APP_DIR/Contents/Resources/ca-bundle.crt"

# 2b. Build macOS AppIcon.icns from resources/llama-icon.png
ICONSET_DIR="$ROOT_DIR/build/AppIcon.iconset"
rm -rf "$ICONSET_DIR"
mkdir -p "$ICONSET_DIR"
/usr/bin/sips -z 16 16     "$ROOT_DIR/resources/llama-icon.png" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
/usr/bin/sips -z 32 32     "$ROOT_DIR/resources/llama-icon.png" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
/usr/bin/sips -z 32 32     "$ROOT_DIR/resources/llama-icon.png" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
/usr/bin/sips -z 64 64     "$ROOT_DIR/resources/llama-icon.png" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
/usr/bin/sips -z 128 128   "$ROOT_DIR/resources/llama-icon.png" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
/usr/bin/sips -z 256 256   "$ROOT_DIR/resources/llama-icon.png" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
/usr/bin/sips -z 256 256   "$ROOT_DIR/resources/llama-icon.png" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
/usr/bin/sips -z 512 512   "$ROOT_DIR/resources/llama-icon.png" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
/usr/bin/sips -z 512 512   "$ROOT_DIR/resources/llama-icon.png" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
/usr/bin/sips -z 1024 1024 "$ROOT_DIR/resources/llama-icon.png" --out "$ICONSET_DIR/icon_512x512@2x.png" >/dev/null
/usr/bin/iconutil -c icns "$ICONSET_DIR" -o "$APP_DIR/Contents/Resources/AppIcon.icns"

# 3. Bundle minimal curl + OpenSSL 3 + zlib dylibs and rewrite install names
cp "$CURL_PREFIX/bin/curl" "$APP_DIR/Contents/Resources/bin/curl"
cp -L "/opt/local/libexec/openssl3/lib/libssl.3.dylib" "$APP_DIR/Contents/Frameworks/libssl.3.dylib"
cp -L "/opt/local/libexec/openssl3/lib/libcrypto.3.dylib" "$APP_DIR/Contents/Frameworks/libcrypto.3.dylib"
cp -L "/opt/local/lib/libz.1.dylib" "$APP_DIR/Contents/Frameworks/libz.1.dylib"

chmod 755 "$APP_DIR/Contents/Resources/bin/curl" "$APP_DIR/Contents/Frameworks"/*.dylib

relink_to_dir() {
  local target="$1"
  local rel_prefix="$2"
  local deps
  deps="$(/opt/local/bin/otool -L "$target" | tail -n +2 | awk '{print $1}' | grep '^/opt/local/' || true)"
  for dep in $deps; do
    local base
    base="$(basename "$dep")"
    /opt/local/bin/install_name_tool -change "$dep" "${rel_prefix}/${base}" "$target"
  done
}

relink_to_dir "$APP_DIR/Contents/Resources/bin/curl" "@executable_path/../../Frameworks"
for lib in libssl.3.dylib libcrypto.3.dylib libz.1.dylib; do
  /opt/local/bin/install_name_tool -id "@loader_path/$lib" "$APP_DIR/Contents/Frameworks/$lib"
  relink_to_dir "$APP_DIR/Contents/Frameworks/$lib" "@loader_path"
done

# 4. Compile MavLlama Objective-C binary (strict OS X 10.9 Core 2 baseline)
/usr/bin/clang -fobjc-arc -O2 -Wall -Wextra -Werror \
  -mmacosx-version-min=10.9 -march=core2 \
  -framework Cocoa -framework WebKit \
  "$ROOT_DIR/src/main.m" \
  "$ROOT_DIR/src/AppDelegate.m" \
  "$ROOT_DIR/src/HardwareInspector.m" \
  "$ROOT_DIR/src/DownloadManager.m" \
  "$ROOT_DIR/src/ModelCatalog.m" \
  "$ROOT_DIR/src/EngineManager.m" \
  "$ROOT_DIR/src/ServerController.m" \
  "$ROOT_DIR/src/MarkdownRenderer.m" \
  "$ROOT_DIR/src/UpdateManager.m" \
  "$ROOT_DIR/src/MainWindowController.m" \
  -o "$APP_DIR/Contents/MacOS/MavLlama"

chmod 755 "$APP_DIR/Contents/MacOS/MavLlama"

# 5. Package release zip
ZIP_NAME="MavLlama-${RELEASE_TAG}-Mavericks.zip"
ZIP_PATH="$DIST_DIR/$ZIP_NAME"
rm -f "$ZIP_PATH"
/usr/bin/ditto -c -k --sequesterRsrc --keepParent "$APP_DIR" "$ZIP_PATH"

ZIP_SHA="$(shasum -a 256 "$ZIP_PATH" | awk '{print $1}')"
if [ -f "$DIST_DIR/checksums.txt" ]; then
  grep -v "$ZIP_NAME" "$DIST_DIR/checksums.txt" > "$DIST_DIR/checksums.txt.tmp" || true
  mv "$DIST_DIR/checksums.txt.tmp" "$DIST_DIR/checksums.txt"
fi
echo "$ZIP_SHA  $ZIP_NAME" >> "$DIST_DIR/checksums.txt"

echo "Built $APP_DIR and $ZIP_PATH (sha256=$ZIP_SHA)"
