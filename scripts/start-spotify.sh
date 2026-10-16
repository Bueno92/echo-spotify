#!/system/bin/sh
# Foreground test of Spotify Connect on an Echo Dot 3 with echo-dot-assist, as root over adb (Ctrl-C ends it):
#   adb shell /data/local/hassmic/spotify/start-spotify.sh
# librespot plays through mixplay on the mixer's Music stream, beside hassmic, which keeps running.  This is the test
# to pass, reproducibly, before hassmic's own "Spotify Connect" switch (which runs the same librespot, its sound through
# hassmic instead of mixplay).  Not both at once: they would share TCP 24879.
set -u

D=/data/local/hassmic
S=$D/spotify
CONF=$S/spotify.conf
CACHE=$D/state/spotify/cache       # the same login cache hassmic's switch uses afterwards

# echo-dot-assist's own files: the verified update, the factory copy, or a trial copy
HD=
for d in $D/ota/current /system/hassmic $D; do
    [ -x $d/runas ] && [ -x $d/mixplay ] && [ -r $d/device.conf ] && { HD=$d; break; }
done
[ -n "$HD" ] || { echo "echo-dot-assist not found (runas, mixplay, device.conf)"; exit 1; }
. $HD/device.conf || exit 1

SPOTIFY_NAME="Echo Salon"
BITRATE="320"
ZEROCONF_PORT="24879"              # fixed: lockdown.sh admits inbound TCP only on 16384-32767
[ -r "$CONF" ] && . "$CONF"

pid=$(cat $D/state/spotify/pid 2>/dev/null)
if [ -n "$pid" ] && grep -q librespot /proc/$pid/cmdline 2>/dev/null; then
    echo "hassmic's Spotify Connect runs (pid $pid): switch it off on the settings page first"
    exit 1
fi

mkdir -p "$CACHE"
chown "$DAEMON_USER" $D/state/spotify "$CACHE" 2>/dev/null || true
chmod 700 $D/state/spotify "$CACHE" 2>/dev/null || true

echo "Spotify Connect \"$SPOTIFY_NAME\", $BITRATE kbit/s, TCP $ZEROCONF_PORT; echo-dot-assist in $HD"
# runas -r 3990 keeps effective gid=aipc for Amazon mixer identity while
# setting real gid=3990. spotify-netexec then keeps fsgid=3990 for librespot's
# sockets. spotify-mixplay restores fsgid=aipc before executing mixplay.
exec "$HD/runas" -r 3990 "$DAEMON_USER" "$DAEMON_GROUPS" \
    "$S/spotify-netexec" \
    "$S/librespot" \
      --name "$SPOTIFY_NAME" \
      --device-type speaker \
      --bitrate "$BITRATE" \
      --backend subprocess \
      --zeroconf-backend libmdns \
      --zeroconf-port "$ZEROCONF_PORT" \
      --format S16 \
      --device "$S/spotify-mixplay $HD/mixplay -t Music -r 44100 -c 2" \
      --cache "$CACHE" \
      --system-cache "$CACHE" \
      --initial-volume 100 \
      --disable-audio-cache
