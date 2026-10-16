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

# Build the same pinned sources and feature set for the CI host so we can run
# --help there. The Android binary itself cannot execute on the x86_64 runner.
HELP="$WORK/librespot-help.txt"
echo "Verifying librespot CLI options with a native host build..."
(
  cd "$WORK/librespot"
  cargo run \
    --release \
    --no-default-features \
    --features "rustls-tls-webpki-roots,with-libmdns" \
    -- \
    --help > "$HELP"
)
for flag in backend device format zeroconf-backend zeroconf-port device-type disable-audio-cache system-cache; do
  grep -q -- "--$flag" "$HELP" || {
    echo "ERROR: librespot --help missing CLI option --$flag" >&2
    exit 1
  }
done

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
READELF="$TOOLCHAIN/llvm-readelf"
[[ -x "$READELF" ]] || { echo "ERROR: llvm-readelf not found: $READELF" >&2; exit 1; }

# librespot is the only binary: echo-dot-assist's runas gives it group 3990 (start-spotify.sh), or hassmic does
python3 "$ROOT/scripts/verify-elf.py" "$OUT/librespot"

# Fail if librespot accidentally gains host audio/OpenSSL dependencies.
DYNAMIC="$($READELF -d "$OUT/librespot")"
if printf '%s\n' "$DYNAMIC" | grep -Eqi 'libssl|libcrypto|libasound|libpulse|libjack|libportaudio'; then
  echo "ERROR: unexpected runtime dependency in librespot:" >&2
  printf '%s\n' "$DYNAMIC" >&2
  exit 1
fi

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
  echo "--- librespot --help ---"
  cat "$HELP"
} > "$OUT/BUILD-INFO.txt"

echo "OK: build output in $OUT"
ls -lh "$OUT/librespot" "$OUT/BUILD-INFO.txt"
