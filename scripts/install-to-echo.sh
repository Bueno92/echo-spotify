#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
D=/data/local/hassmic

command -v adb >/dev/null 2>&1 || { echo "ERROR: adb not found" >&2; exit 1; }
for f in librespot spotify-netexec spotify-mixplay; do
  [[ -f "$ROOT/out/$f" ]] || { echo "ERROR: build out/$f first" >&2; exit 1; }
done

PRODUCT="$(adb shell getprop ro.product.device | tr -d '\r')"
BUILD="$(adb shell getprop ro.build.display.id | tr -d '\r')"
[[ "$PRODUCT" == "donut_puffin" ]] || { echo "ERROR: expected donut_puffin, got $PRODUCT" >&2; exit 1; }
[[ "$BUILD" == *NS65741* ]] || { echo "ERROR: expected NS65741 firmware, got $BUILD" >&2; exit 1; }

adb shell "test -x $D/hassmic && test -x $D/mixplay && test -x $D/runas && test -r $D/device.conf" \
  || { echo "ERROR: echo-dot-assist is not installed/validated yet" >&2; exit 1; }

for f in librespot spotify-netexec spotify-mixplay; do
  adb push "$ROOT/out/$f" "$D/$f" >/dev/null
done
adb push "$ROOT/scripts/start-spotify.sh" "$D/start-spotify.sh" >/dev/null
adb shell "chmod 755 $D/librespot $D/spotify-netexec $D/spotify-mixplay $D/start-spotify.sh"

adb shell "test -f $D/spotify.conf || printf '%s\n' 'SPOTIFY_NAME=\"Echo Salon\"' 'BITRATE=\"320\"' 'ZEROCONF_PORT=\"24879\"' > $D/spotify.conf"
adb shell "chmod 600 $D/spotify.conf"

echo "Installed. First foreground test:"
echo "  adb shell '$D/start-spotify.sh'"
echo "Do NOT configure boot autostart yet."
