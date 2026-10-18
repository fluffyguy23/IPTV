# IPTV

An IPTV app for Mac, Windows, iOS and Android. It is a native Xtream Codes player with Live TV, Movies and Series, a shared black and electric-blue design, and libVLC playback.

| Platform | Folder | Status |
|---|---|---|
| macOS (Intel, 12+) | [`IPTVXtremePlayer/`](IPTVXtremePlayer/README.md) | Swift + AppKit, v1.1 |
| Android 8.0 – 16 | [`IPTVXtremeAndroid/`](IPTVXtremeAndroid/README.md) | Kotlin + Jetpack Compose, v1.1 |
| Windows, iOS | — | Not started |

## Setup

1. Copy `.env.example` to `.env` and fill in the values. The file holds **build-time settings only**: Android release-signing passwords and the VLC.app path for the macOS build. `.env` is git-ignored.
2. Build:
   - macOS: `cd IPTVXtremePlayer && ./Scripts/build_app.sh --dmg`
   - Android: `cd IPTVXtremeAndroid && ./gradlew assembleRelease`

## Credentials & security

- **No IPTV credentials are in this repository or in any build.** Each user enters their own server, username and password in the app.
- Android stores passwords encrypted with AES-256-GCM under an Android Keystore key. macOS uses a machine-bound encrypted file plus the Keychain.
- Logs redact usernames and passwords from URLs.
- `.env`, keystores and signing files are git-ignored. Values in `.env` are used only by the build tools and are never packaged into an app, because anything bundled in an APK can be extracted.
- Android release builds use R8 shrinking and obfuscation, strip debug logging, and exclude app data from backups.
