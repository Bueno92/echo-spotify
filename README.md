# Echo Dot 3 — Spotify Connect PoC (V3)

Goal: turn a rooted Echo Dot 3 (2018, `donut` / D9N29T) running `Gamer92000/echo-dot-assist` into an independent Spotify Connect receiver, with no Music Assistant requirement.

## Architecture

```text
Spotify app / Spotify cloud
        |
        v
librespot (ARMv7 Android 24)
        |
        | raw PCM S16 / 44.1 kHz / stereo
        v
spotify-mixplay -> mixplay -t Music
        |
        v
Amazon mixer -> Echo speaker
```

`spotify-netexec` gives librespot's sockets the network filesystem-group (`3990`) expected by the `echo-dot-assist` firewall. `spotify-mixplay` restores the effective mixer group before starting `mixplay`, so mixer access is not broken by the network fsgid.

## Double-checked assumptions

- Echo Dot 3 target in `echo-dot-assist`: `donut_puffin`, firmware NS65741, ARMv7, Android 7.1/API 24.
- Upstream build target used by `echo-dot-assist`: `armv7a-linux-androideabi24`.
- Rust Android target: `armv7-linux-androideabi`.
- librespot v0.8.0 playback constants: 44,100 Hz, stereo.
- librespot `subprocess` backend parses a command string and pipes raw PCM to its stdin.
- `echo-dot-assist` provides `mixplay` and a `Music` mixer stream.
- The lockdown permits inbound TCP/UDP only in 16384–32767. Spotify Connect is therefore pinned to TCP `24879`, which is inside that range and does not collide with the documented `echo-dot-assist` ports (16700, 26053, 28928, 28929, 28930).
- The lockdown's egress exception is `--gid-owner 3990`.
- `echo-dot-assist` itself uses temporary `setfsgid(real_gid)` when creating unrestricted sockets. V3 mirrors that design for librespot while restoring mixer fsgid for `mixplay`.

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
├── spotify-netexec
├── spotify-mixplay
└── BUILD-INFO.txt
```

## Local build

Prerequisites: Rust/rustup, Android NDK, Git, Python 3, cargo-ndk 4.1.2.

```bash
cargo install cargo-ndk --version 4.1.2 --locked
export ANDROID_NDK_HOME=/path/to/android-ndk
bash scripts/build-librespot-android.sh
```

## When the Echo arrives

First install upstream `echo-dot-assist` and confirm normal Assist/audio operation. Do not mix debugging Spotify with first-time Echo rooting.

Then:

```bash
bash scripts/install-to-echo.sh
adb shell '/data/local/hassmic/start-spotify.sh'
```

First test stays in the foreground. Do **not** autostart yet.

Expected behavior:

1. librespot starts without TLS/audio dependency errors.
2. `Echo Salon` appears in Spotify > Available devices on an iPhone on the same LAN.
3. Selecting it plays through the Dot speaker.
4. Amazon cloud services remain blocked by the original lockdown.
5. Assist still works after stopping Spotify.

## Phase 2 after PoC success

- boot autostart
- expose Spotify state to Home Assistant
- voice command routing (`joue X sur salon`)
- assistant duck/pause/resume integration
- hardware/Spotify volume synchronization
- clean upstream-able integration into `echo-dot-assist`
