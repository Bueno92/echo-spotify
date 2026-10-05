#!/usr/bin/env bash
set -euo pipefail

LIBRESPOT_REPO="https://github.com/librespot-org/librespot.git"
LIBRESPOT_COMMIT="d36f9f1907e8cc9d68a93f8ebc6b627b1bf7267d" # v0.8.0
TARGET="armv7-linux-androideabi"
ABI="armeabi-v7a"
API="24"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$ROOT/.build"
OUT="$ROOT/out"

need() { command -v "$1" >/dev/null 2>&1 || { echo "ERROR: missing command: $1" >&2; exit 1; }; }
need git
need rustup
need cargo
need python3

if ! cargo ndk --version >/dev/null 2>&1; then
  echo "ERROR: cargo-ndk missing; install cargo-ndk 4.1.2" >&2
  exit 1
fi
CARGO_NDK_VERSION="$(cargo ndk --version | awk '{print $2}')"
[[ "$CARGO_NDK_VERSION" == "4.1.2" ]] || {
  echo "ERROR: expected cargo-ndk 4.1.2, got $CARGO_NDK_VERSION" >&2
  exit 1
}

mkdir -p "$WORK" "$OUT"
rustup target add "$TARGET"

if [[ ! -d "$WORK/librespot/.git" ]]; then
  git clone "$LIBRESPOT_REPO" "$WORK/librespot"
fi

git -C "$WORK/librespot" fetch --tags --force origin
git -C "$WORK/librespot" checkout --detach "$LIBRESPOT_COMMIT"

# Verify the exact upstream assumptions our pipeline relies on.
grep -q 'pub const SAMPLE_RATE: u32 = 44100;' "$WORK/librespot/playback/src/lib.rs"
grep -q 'pub const NUM_CHANNELS: u8 = 2;' "$WORK/librespot/playback/src/lib.rs"
grep -q 'pub const NAME:.*"subprocess"' "$WORK/librespot/playback/src/audio_backend/subprocess.rs"
grep -q 'shell_words::split' "$WORK/librespot/playback/src/audio_backend/subprocess.rs"

echo "Building librespot v0.8.0 for $TARGET / Android API $API..."
(
  cd "$WORK/librespot"
  CARGO_NDK_PLATFORM="$API" cargo ndk \
    --target "$ABI" \
    build \
    --release \
    --no-default-features \
    --features "rustls-tls-webpki-roots,with-libmdns"
)

BIN="$WORK/librespot/target/$TARGET/release/librespot"
[[ -x "$BIN" ]] || { echo "ERROR: librespot not found at $BIN" >&2; exit 1; }
cp "$BIN" "$OUT/librespot"
chmod 755 "$OUT/librespot"

NDK="${ANDROID_NDK_HOME:-${ANDROID_NDK_ROOT:-}}"
if [[ -z "$NDK" ]]; then
  for base in "$HOME/Library/Android/sdk/ndk" "$HOME/Android/Sdk/ndk"; do
    if [[ -d "$base" ]]; then
      NDK="$(find "$base" -mindepth 1 -maxdepth 1 -type d | sort -V | tail -1)"
      break
    fi
  done
fi
[[ -n "$NDK" && -d "$NDK" ]] || { echo "ERROR: Android NDK not found; set ANDROID_NDK_HOME" >&2; exit 1; }

case "$(uname -s)-$(uname -m)" in
  Linux-x86_64) HOST_TAG=linux-x86_64 ;;
  Darwin-x86_64) HOST_TAG=darwin-x86_64 ;;
  Darwin-arm64|Darwin-aarch64) HOST_TAG=darwin-x86_64 ;;
  *) echo "ERROR: unsupported NDK host $(uname -s)-$(uname -m)" >&2; exit 1 ;;
esac

TOOLCHAIN="$NDK/toolchains/llvm/prebuilt/$HOST_TAG/bin"
CC="$TOOLCHAIN/armv7a-linux-androideabi${API}-clang"
READELF="$TOOLCHAIN/llvm-readelf"
[[ -x "$CC" ]] || { echo "ERROR: Android clang not found: $CC" >&2; exit 1; }
[[ -x "$READELF" ]] || { echo "ERROR: llvm-readelf not found: $READELF" >&2; exit 1; }

for src in spotify-netexec spotify-mixplay; do
  "$CC" -O2 -fPIE -pie -Wall -Wextra -Werror \
    "$ROOT/src/$src.c" -o "$OUT/$src"
  chmod 755 "$OUT/$src"
done

python3 "$ROOT/scripts/verify-elf.py" \
  "$OUT/librespot" "$OUT/spotify-netexec" "$OUT/spotify-mixplay"

# Fail if librespot accidentally gains host audio/OpenSSL dependencies.
DYNAMIC="$($READELF -d "$OUT/librespot")"
if printf '%s\n' "$DYNAMIC" | grep -Eqi 'libssl|libcrypto|libasound|libpulse|libjack|libportaudio'; then
  echo "ERROR: unexpected runtime dependency in librespot:" >&2
  printf '%s\n' "$DYNAMIC" >&2
  exit 1
fi

# Confirm the pinned source exposes the exact CLI options used by start-spotify.sh.
# Do not execute the ARM/Android binary on this x86_64 build host.
MAIN_RS="$WORK/librespot/src/main.rs"
for flag in backend device format zeroconf-backend zeroconf-port device-type disable-audio-cache system-cache; do
  grep -q '"'"$flag"'"' "$MAIN_RS" || {
    echo "ERROR: pinned librespot source missing CLI option --$flag" >&2
    exit 1
  }
done

{
  echo "librespot_commit=$LIBRESPOT_COMMIT"
  echo "target=$TARGET"
  echo "abi=$ABI"
  echo "android_api=$API"
  echo "features=rustls-tls-webpki-roots,with-libmdns"
  echo "ndk=$NDK"
  rustc --version | sed 's/^/rustc=/'
  cargo ndk --version | sed 's/^/cargo_ndk=/'
  echo "--- librespot ELF header ---"
  "$READELF" -h "$OUT/librespot"
  echo "--- librespot dynamic dependencies ---"
  "$READELF" -d "$OUT/librespot"
  echo "--- spotify-netexec dynamic dependencies ---"
  "$READELF" -d "$OUT/spotify-netexec"
  echo "--- spotify-mixplay dynamic dependencies ---"
  "$READELF" -d "$OUT/spotify-mixplay"
} > "$OUT/BUILD-INFO.txt"

echo "OK: build output in $OUT"
ls -lh "$OUT/librespot" "$OUT/spotify-netexec" "$OUT/spotify-mixplay" "$OUT/BUILD-INFO.txt"
