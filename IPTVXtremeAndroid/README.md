# IPTVXtreme for Android

The Android version of **IPTVXtremePlayer**. It has the same black and electric-blue design and the same features as the macOS app, rebuilt as a native Android app (Kotlin + Jetpack Compose). It connects to any **Xtream Codes** provider and plays Live TV, Movies and Series through **libVLC**, so it handles the MPEG-TS, MKV and HLS formats IPTV relies on.

- **Supports:** Android 8.0 (API 26) through Android 16 (API 36). It is built against the latest SDK (API 36).
- **Devices:** phones, tablets, foldables and Android TV boxes (it has a TV launcher banner and D-pad support).
- **Version:** 1.1 (versionCode 2), package `com.iptvxtreme.player`.

---

## Which APK to install

Builds are placed in `dist/`:

| File | For |
|---|---|
| `IPTVXtreme-1.1-arm64-v8a.apk` | **Most phones from 2017 onward** (recommended) |
| `IPTVXtreme-1.1-armeabi-v7a.apk` | Older or budget 32-bit phones and many Android TV sticks |
| `IPTVXtreme-1.1-universal.apk` | Any device. Larger, because it contains every CPU type. Use it if you're unsure |
| `IPTVXtreme-1.1-x86_64.apk` / `-x86.apk` | Emulators and Intel-based devices |

If you don't know which one your device needs, install the **universal** APK.

## Installing on a phone

1. Copy the APK to the phone (USB, Google Drive, a messaging app to yourself, etc.).
2. Tap the APK. When Android asks, allow **Install unknown apps** for the app you opened it from (Files, Chrome, Drive…).
3. Tap **Install**, then **Open**.
4. Play Protect may warn about an app from an unknown developer. Choose **More details → Install anyway**. This happens because the app isn't on the Play Store.

Or install over USB with debugging enabled:

```bash
adb install -r dist/IPTVXtreme-1.1-arm64-v8a.apk
```

**Updating:** install the new APK over the old one. It is signed with the same key (`release.keystore`), so profiles, favorites and history are kept and you don't have to log in again.

## Testing checklist

1. **Login:** add a profile with *your* server URL, username and password, then tap **Save & Connect**. A wrong password should show "Incorrect username or password."
2. **Relaunch:** close the app completely and reopen it. It should reconnect automatically.
3. **Live TV:** pick a category, search, and tap a channel. It plays in the embedded player. Then try the star (favorite), the full-screen button, and switching channels.
4. **Movies / Series:** check the grid, the category and sort controls, the filter box, and the detail page. Play a movie, leave halfway, and check that Continue Watching resumes it.
5. **Series:** play an episode, then test the Prev/Next buttons and auto-advance to the next episode.
6. **Player:** tap to show or hide the controls, use ±10s (or double-tap left/right), drag the timeline, and open settings (aspect ratio, fit/fill, speed, audio, subtitles). Rotate the device.
7. **History / Favorites:** long-press an item to remove it, and try **Clear History**.
8. **Background:** press Home during playback, then return. Playback should resume where it was.

## Building from source

Requirements: JDK 17 and the Android SDK (platform 36 and build-tools 36).

```bash
cd IPTVXtremeAndroid
./gradlew assembleRelease      # signed APKs -> app/build/outputs/apk/release/
./gradlew assembleDebug        # debug APKs
```

Release signing reads `keystore.properties` (store file, alias and passwords). That file and `release.keystore` are excluded from version control. **Back both up.** Without that exact key, future updates can't install over the current app.

## Security & privacy

- **No credentials are bundled.** The app ships with no default server, username or password. Every user enters their own on first launch.
- Passwords are encrypted with **AES-256-GCM** using a key held in the **Android Keystore**, which is hardware-backed where the device supports it. The key can't be exported, so the stored password can't be decrypted off the device.
- Profiles, credentials and history are **excluded from cloud backup and device transfer**.
- Logs redact usernames and passwords from every URL. Stream URLs, which contain credentials, are passed between screens in memory only and never through Intents.
- Cleartext HTTP is allowed, because nearly all Xtream providers serve over plain HTTP on user-entered hosts.

## What depends on your provider

- **EPG** needs the provider's short-EPG.
- **Movie and series metadata** (plot, cast, posters, ratings) comes from the provider.
- Subtitle and audio-track options depend on what each stream contains.
- **Catch-up / archive** isn't implemented (same as the macOS app).
- If your account allows **1 connection**, switching streams quickly can briefly fail with a 403 until the previous stream is released.
