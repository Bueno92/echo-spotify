#!/system/bin/sh
set -u

D=/data/local/hassmic
CONF="$D/spotify.conf"
CACHE="$D/spotify-cache"

. "$D/device.conf" || exit 1

SPOTIFY_NAME="Echo Salon"
BITRATE="320"
ZEROCONF_PORT="24879"

if [ -r "$CONF" ]; then
    . "$CONF"
fi

mkdir -p "$CACHE"
chown "$DAEMON_USER" "$CACHE" 2>/dev/null || true
chmod 700 "$CACHE" 2>/dev/null || true

# runas -r 3990 keeps effective gid=aipc for Amazon mixer identity while
# setting real gid=3990. spotify-netexec then keeps fsgid=3990 for librespot's
# sockets. spotify-mixplay restores fsgid=aipc before executing mixplay.
exec "$D/runas" -r 3990 "$DAEMON_USER" "$DAEMON_GROUPS" \
    "$D/spotify-netexec" \
    "$D/librespot" \
      --name "$SPOTIFY_NAME" \
      --device-type speaker \
      --bitrate "$BITRATE" \
      --backend subprocess \
      --zeroconf-backend libmdns \
      --zeroconf-port "$ZEROCONF_PORT" \
      --format S16 \
      --device "$D/spotify-mixplay $D/mixplay -t Music -r 44100 -c 2" \
      --cache "$CACHE" \
      --system-cache "$CACHE" \
      --initial-volume 100 \
      --disable-audio-cache
