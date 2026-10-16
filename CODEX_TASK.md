# Codex task — publish and validate Echo Dot 3 Spotify Connect PoC

Repository target: `Bueno92/echo-spotify`

## Goal

Commit this V3 project to the repository, run the GitHub Actions workflow `Build Echo Dot 3 librespot`, diagnose/fix build issues if any, and leave a green workflow with a downloadable `echo-spotify-armv7-android24` artifact.

## Constraints / context

- Hardware target: Amazon Echo Dot 3rd gen 2018 (`donut`, model D9N29T), `echo-dot-assist` target `donut_puffin` / NS65741.
- Target ABI: ARMv7 Android/Bionic, API 24.
- Do not replace with generic armhf Linux.
- librespot must remain pinned to stable v0.8.0 commit `d36f9f1907e8cc9d68a93f8ebc6b627b1bf7267d` unless a verified build defect requires a change.
- Build with `--no-default-features --features rustls-tls-webpki-roots,with-libmdns` so no ALSA/OpenSSL dependency is introduced.
- librespot output: `pipe` backend, raw `S16`, 44.1 kHz stereo, into `mixplay -t Music -r 44100 -c 2` (foreground test) or hassmic.
- Spotify Connect Zeroconf TCP port is fixed to `24879`; `echo-dot-assist` lockdown only allows inbound 16384–32767.
- The original hack firewall must remain intact. Never globally reopen Amazon egress.
- librespot runs with 3990 as its real, effective and saved group (runas `3990,<groups>`, or hassmic), so its sockets match the existing `--gid-owner 3990` firewall exception. The former `spotify-netexec` (setfsgid then exec) did not: execve resets fsgid to egid (checked on a PC). `spotify-mixplay` went with it.
- No boot autostart yet. First device test must remain foreground-only.

## Validation required

1. Workflow parses and runs on GitHub-hosted Ubuntu.
2. Build succeeds for `armv7-linux-androideabi` / API 24.
3. `verify-elf.py` reports librespot as ELF32 little-endian ARM.
4. librespot dynamic deps do not contain libssl/libcrypto/libasound/libpulse/libjack/libportaudio.
5. `librespot --help` includes backend/device/format/zeroconf-backend/zeroconf-port/device-type/disable-audio-cache/system-cache.
6. Artifact contains `librespot`, `SHA256SUMS`, `start-spotify.sh`, `install-to-echo.sh`, `BUILD-INFO.txt`.
7. Report any change you make and why; do not silently alter network/firewall/audio assumptions.

## After green CI

Do not attempt Echo installation because the physical Echo has not arrived yet. The desired deliverable is the validated artifact plus a concise summary of anything that still needs real-device verification.
