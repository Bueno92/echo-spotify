#!/usr/bin/env bash
# Installs the Spotify Connect binaries on an Echo Dot 3 running echo-dot-assist, apart from it:
#   /data/local/hassmic/spotify/{librespot,spotify-netexec,start-spotify.sh,spotify.conf}
# hassmic updates (OTA bundles) never touch that folder, and hassmic (from the build that has spotify.c) lists its
# "Spotify Connect" switch only where librespot is there (spotify-netexec is the foreground test's).  Nothing starts by itself: first the
# foreground test (start-spotify.sh), then, once it works, the switch on hassmic's settings page.
#
# Works from a checkout (binaries in out/) and from the CI archive (binaries next to this script).  Checks the
# binaries against SHA256SUMS when there is one, and each copy on the Echo against the local file (md5: transfer).
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
D=/data/local/hassmic
S=$D/spotify
FILES="librespot spotify-netexec"        # spotify-mixplay: no longer used (start-spotify.sh)

if [[ -f "$HERE/librespot" ]]; then BIN="$HERE"; else BIN="$HERE/../out"; fi
START="$HERE/start-spotify.sh"; [[ -f "$START" ]] || START="$HERE/../scripts/start-spotify.sh"

command -v adb >/dev/null 2>&1 || { echo "ERROR: adb not found" >&2; exit 1; }
for f in $FILES; do
  [[ -f "$BIN/$f" ]] || { echo "ERROR: $BIN/$f missing: build it first (scripts/build-librespot-android.sh) or unpack the CI archive" >&2; exit 1; }
done
[[ -f "$START" ]] || { echo "ERROR: start-spotify.sh missing" >&2; exit 1; }
if [[ -f "$BIN/SHA256SUMS" ]]; then
  (cd "$BIN" && sha256sum -c --quiet SHA256SUMS) || { echo "ERROR: binaries differ from SHA256SUMS" >&2; exit 1; }
  echo "Binaries match SHA256SUMS."
fi

sh_echo() { adb shell "$1" | tr -d '\r'; }

PRODUCT="$(sh_echo 'getprop ro.product.device')"
BUILD="$(sh_echo 'getprop ro.build.display.id')"
[[ "$PRODUCT" == "donut_puffin" ]] || { echo "ERROR: expected donut_puffin, got $PRODUCT" >&2; exit 1; }
[[ "$BUILD" == *NS65741* ]] || { echo "ERROR: expected NS65741 firmware, got $BUILD" >&2; exit 1; }
[[ "$(sh_echo 'id -u')" == 0 ]] || { echo "ERROR: adb shell is not root" >&2; exit 1; }

# echo-dot-assist installed: its files are in the verified update (ota/current) or the factory copy (/system/hassmic);
# a trial copy may sit in /data/local/hassmic itself (scripts/deploy.sh)
HD="$(sh_echo "for d in $D/ota/current /system/hassmic $D; do [ -x \$d/runas ] && [ -x \$d/mixplay ] && [ -r \$d/device.conf ] && { echo \$d; break; }; done")"
[[ -n "$HD" ]] || { echo "ERROR: echo-dot-assist is not installed (no runas, mixplay and device.conf in $D/ota/current, /system/hassmic or $D)" >&2; exit 1; }
sh_echo "pidof hassmic" | grep -q . || echo "WARNING: hassmic is not running: check the satellite before testing Spotify"
echo "echo-dot-assist found in $HD."

adb shell "mkdir -p $S && chown root:root $S && chmod 755 $S"
for f in $FILES; do
  adb push "$BIN/$f" "$S/.$f.new" >/dev/null
  want="$(md5sum "$BIN/$f" | cut -d' ' -f1)"
  got="$(sh_echo "md5sum $S/.$f.new" | cut -d' ' -f1)"
  [[ "$want" == "$got" ]] || { adb shell "rm -f $S/.$f.new"; echo "ERROR: $f arrived damaged on the Echo" >&2; exit 1; }
  adb shell "chown root:root $S/.$f.new && chmod 755 $S/.$f.new && mv $S/.$f.new $S/$f"
done
adb push "$START" "$S/start-spotify.sh" >/dev/null
adb shell "chown root:root $S/start-spotify.sh && chmod 755 $S/start-spotify.sh"
adb shell "[ -f $S/spotify.conf ] || printf '%s\n' '# start-spotify.sh (foreground test) only; hassmic names it after the Echo' 'SPOTIFY_NAME=\"Echo Salon\"' 'BITRATE=\"320\"' > $S/spotify.conf; chmod 600 $S/spotify.conf"
adb shell "rm -f $D/librespot $D/spotify-netexec $D/spotify-mixplay $D/start-spotify.sh $S/spotify-mixplay"   # the first PoC's

if sh_echo "grep -c api/spotify/name $HD/hassmic" | grep -qv '^0$'; then
  echo "This hassmic has the Spotify Connect switch (settings page, Features); leave it off until the foreground test works."
else
  echo "This hassmic has no Spotify Connect switch yet (a build from before it): only the foreground test applies."
fi
echo
echo "Installed in $S. First the foreground test (Ctrl-C ends it):"
echo "  adb shell $S/start-spotify.sh"
echo "No autostart: hassmic's switch is that, once this test works every time."
