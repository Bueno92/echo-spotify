# Echo Dot 3 — Spotify Connect PoC (V3)

Goal: turn a rooted Echo Dot 3 (2018, `donut` / D9N29T) running `Gamer92000/echo-dot-assist` into an independent Spotify Connect receiver, with no Music Assistant requirement.

## Architecture

```text
Spotify app / Spotify cloud
        |
        v
librespot (ARMv7 Android 24), group 3990: may reach the Internet
        |
        | raw PCM S16 / 44.1 kHz / stereo on a pipe (--backend pipe)
        v
mixplay -t Music (foreground test), group aipc: may use the mixer
   or hassmic (its Spotify Connect switch)
        |
        v
Amazon mixer -> Echo speaker
```

The `echo-dot-assist` firewall lets out to the Internet only sockets created with the file system group 3990
(`--gid-owner 3990`). librespot is started with 3990 as its real, effective and saved group (echo-dot-assist's `runas
<user> 3990,<groups>` in `start-spotify.sh`, or hassmic itself); exec then sets its file system group to 3990 as well.
librespot needs no mixer: its sound leaves through a pipe, to a `mixplay` started separately with the mixer's group
aipc, or to hassmic. The first version had two wrappers, `spotify-netexec` (`setfsgid(3990)` then exec, which the exec
undoes: checked on a PC, `Gid: 3990 1000 1000 1000` after it, so librespot would have been held to the LAN) and
`spotify-mixplay`; both are gone, librespot is the only binary.

## Double-checked assumptions

- Echo Dot 3 target in `echo-dot-assist`: `donut_puffin`, firmware NS65741, ARMv7, Android 7.1/API 24.
- Upstream build target used by `echo-dot-assist`: `armv7a-linux-androideabi24`.
- Rust Android target: `armv7-linux-androideabi`.
- librespot v0.8.0 playback constants: 44,100 Hz, stereo.
- librespot `pipe` backend writes raw PCM to its stdout.
- `echo-dot-assist` provides `mixplay` and a `Music` mixer stream.
- The lockdown permits inbound TCP/UDP only in 16384–32767. Spotify Connect is therefore pinned to TCP `24879`, which is inside that range and does not collide with the documented `echo-dot-assist` ports (16700, 26053, 28928, 28929, 28930).
- The lockdown's egress exception is `--gid-owner 3990`.
- `echo-dot-assist` itself uses temporary `setfsgid(real_gid)` when creating unrestricted sockets. That does not carry over an exec (execve resets fsgid to egid), so librespot gets 3990 as its effective group instead (runas `3990,<groups>`, or hassmic).

## Source pins

- librespot: stable `v0.8.0`, commit `d36f9f1907e8cc9d68a93f8ebc6b627b1bf7267d`
- Rust: `1.86.0` (librespot needs >=1.85, cargo-ndk 4.1.2 needs >=1.86)
- cargo-ndk: `4.1.2`
- Android NDK: `r27d`
- Android API: `24`

We deliberately use `rustls-tls-webpki-roots` and `with-libmdns` to avoid OpenSSL/ALSA dependencies on Fire OS.

## Build with GitHub Actions

The included workflow builds and verifies the ARMv7 Android binaries and uploads a ready-to-install artifact.

Expected files:

```text
out/
├── librespot
├── SHA256SUMS      (CI)
└── BUILD-INFO.txt
```

## Local build

Prerequisites: Rust/rustup, Android NDK, Git, Python 3, cargo-ndk 4.1.2.

```bash
cargo install cargo-ndk --version 4.1.2 --locked
export ANDROID_NDK_HOME=/path/to/android-ndk
bash scripts/build-librespot-android.sh
```

## Installing on the Echo

First install echo-dot-assist and confirm normal Assist/audio operation. Do not mix debugging Spotify with first-time
Echo rooting.

From a checkout (after a local build, binaries in `out/`) or from the unpacked CI archive (binaries next to the script,
checked against its `SHA256SUMS`):

```bash
bash scripts/install-to-echo.sh          # or: bash install-to-echo.sh in the unpacked archive
adb shell /data/local/hassmic/spotify/start-spotify.sh
```

Everything goes into `/data/local/hassmic/spotify/` (root-owned, 755), apart from echo-dot-assist: its updates never
touch that folder. The script finds echo-dot-assist's `runas`, `mixplay` and `device.conf` where an installed Echo has
them (`/data/local/hassmic/ota/current`, else `/system/hassmic`), checks each copy on the Echo, and removes the files of
the first PoC from `/data/local/hassmic/`.

### 1. Foreground test

`start-spotify.sh` runs librespot in the foreground (Ctrl-C ends it), its sound through `mixplay -t Music`, hassmic
running beside it. Name and bitrate from `spotify.conf` next to it. Expected behavior:

1. librespot starts without TLS/audio dependency errors.
2. `Echo Salon` appears in Spotify > Available devices on a phone on the same LAN.
3. Selecting it plays through the Dot speaker.
4. Amazon cloud services remain blocked by the original lockdown.
5. Assist still works after stopping Spotify.

Repeat it (several sessions, a restart of the Echo in between) before step 2.

### 2. hassmic's switch (the autostart)

echo-dot-assist builds with `spotify.c` list a **Spotify Connect** card on the settings page (Features) once the files
above are installed. Off by default; switch it on only after the foreground test passes every time. hassmic then runs
the same librespot itself, under the Echo's name, and plays its PCM (`--backend pipe`) through its own mixer stream:
ducked while you talk to the Echo, at the Echo's volume (the app's slider sets it, `--volume-ctrl fixed`), stopped by a
newer source (Music Assistant, Bluetooth). Its login cache is the one the foreground test used
(`/data/local/hassmic/state/spotify/cache`, 0700). Not both at once: the foreground test refuses to start while
hassmic's runs (TCP 24879).

What differs from the foreground test, and is checked only on the Echo: hassmic reads the pipe instead of mixplay, and
`--onevent` (a shell script hassmic writes into `state/spotify`). The name in the Spotify app is the Echo's unless one
is set in the card ("Name in Spotify").
