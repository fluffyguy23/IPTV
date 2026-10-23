# IPTVXtremePlayer — Project Record

_Complete, living record of the app: what it is, how it's built, what works, what's
been fixed, and what's open. Last updated: 2026-10-10._

**Current release:** v1.2 (build 3) · bundle id `com.iptvxtreme.player` · Intel x86_64 · macOS 12+ (built for Ventura 13).
**Status:** Built, packaged, installed, and connected to a live provider. Compiles clean (0 warnings).

---

## 1. What it is

A lightweight, native **macOS IPTV player for Intel Macs** (target: 2015 MacBook Pro,
macOS Ventura). Connects to any **Xtream Codes** provider and plays **Live TV, Movies,
and Series** via **libVLC**. Black + electric‑blue UI, Keychain/encrypted‑file
credentials, self‑contained app bundle.

---

## 2. Architecture & key decisions

| Concern | Choice | Why |
|---|---|---|
| Language / UI | Swift 5.8 + AppKit (programmatic, no storyboards) | Lightest/fastest on old Intel hardware |
| Playback | libVLC 3.0.24 via a C bridge | Plays TS/MKV/HLS that AVFoundation can't |
| Build | `swiftc` / `clang` directly (not SwiftPM/Xcode) | Only Command Line Tools installed; SwiftPM needs Xcode's `PlatformPath` |
| Credentials | Machine‑bound AES‑GCM file (primary) + Keychain (secondary) | Survives updates with no re‑login prompt |
| Caching | Memory + disk (images & API responses) | Fast reopen, offline‑from‑cache, bounded memory |

**Why not SwiftPM:** no Xcode is installed (only CLT). `swift build` fails with
`unable to lookup item 'PlatformPath'`. The app is compiled directly with `swiftc` +
`clang` and bundled by `Scripts/build_app.sh`. `Package.swift` is kept for reference/full‑Xcode only.

**C↔Swift bridge:** uses a bridging header (`-import-objc-header VLCBridge.h`), so Swift
code does **not** `import VLCBridge`.

**libVLC bundling:** headers/dylibs/plugins come from the installed `/Applications/VLC.app`
at build time and are copied into `Contents/Frameworks` (flat layout; everything resolves
via `@rpath → @executable_path/../Frameworks`). The finished `.app` does **not** need VLC
installed afterward. Verified: the bundled engine initializes and loads 4 audio‑output
plugins from the bundle alone.

---

## 3. Project structure

```
IPTVXtremePlayer/
  Package.swift                 # reference only (CLT can't use SwiftPM here)
  Scripts/build_app.sh          # the real builder: compile + bundle + sign + .dmg
  README.md                     # user-facing readme
  PROJECT.md                    # this file
  Sources/
    VLCBridge/                  # C shim over libVLC
      include/VLCBridge.h
      VLCBridge.c
    IPTVXtremePlayer/
      main.swift                # NSApplication bootstrap
      App/AppDelegate.swift     # libVLC engine init, menus
      Core/
        Theme.swift Log.swift
        KeychainService.swift CredentialStore.swift   # credential storage
        Profile.swift ProfileStore.swift
        XtreamModels.swift LenientDecoding.swift XtreamError.swift
        XtreamClient.swift                            # async API + stream URLs
        Session.swift AppState.swift                  # connected session + repo
        ImageCache.swift DataCache.swift AppPaths.swift
        MediaRef.swift UserData.swift                 # favorites/history/resume
      Player/
        VLCPlayer.swift VideoContainerView.swift
        PlaybackItem.swift EpisodeNavigator.swift
        PlayerViewController.swift PlayerWindowController.swift
      UI/
        MainWindowController.swift  # window + RootViewController (coordinator)
        Coordinator.swift SidebarView.swift TopBarView.swift
        ConnectionViewController.swift
        HomeViewController.swift LiveTVViewController.swift
        MediaGridViewController.swift                 # Movies & Series grids
        VODDetailViewController.swift SeriesDetailViewController.swift
        FavoritesViewController.swift RecentViewController.swift
        SettingsViewController.swift SearchViewController.swift
        Common/ (AsyncImageView, PosterCard, PosterItem, StateViews, ScrollSupport, UIHelpers)
  build/                        # intermediate objects (regenerated)
  dist/                         # IPTVXtremePlayer.app + IPTVXtremePlayer.dmg
```

---

## 4. Features

**Connection / profiles:** multiple saved profiles; create/edit/delete/connect/refresh;
server URL + username + password + live format (TS/M3U8) + optional XMLTV; credential
validation with clear errors (auth failed, expired, banned, timeout, unreachable);
account status/expiry/connections shown.

**Live TV:** category + favorites filter, channel search, channel list with logos,
embedded player, fast switching, EPG now/next (when provider supplies it), per‑channel favorite.

**Movies / Series:** poster grids with category filter, sort (default/A–Z/recent/rating),
in‑section search; detail pages (artwork, plot, cast, genre, rating, duration); resume for
movies/episodes; season picker; **Prev/Next episode** + auto‑advance (cross‑season order).

**Player:** play/pause, timeline seek, **±10s** buttons, volume/mute, playback speed,
aspect ratio, audio‑track & subtitle selection, fullscreen; auto‑hiding controls;
keyboard shortcuts (space, ←/→ = ±10s, ↑/↓ volume, F fullscreen, M mute, Esc).

**Home / Favorites / Recently Watched:** Continue Watching, Recent Channels, Favorites,
new Movies/Series rails; favorites grouped by type; history with **right‑click remove** and
**Clear History**.

**Global search** across channels/movies/series. Image + metadata disk caching.

**Offline downloads (v1.2):** "Download This Video Offline" pill in the player top bar
and on movie detail; Downloads sidebar section (also opens from the connection screen
without signing in); downloaded titles play from disk automatically.

---

## 5. Xtream integration & live test results

Tested against the owner's private provider (host and account details intentionally omitted). Results:

- **Auth:** success — status `Active`, expires **2026‑12‑12**, 1 connection, formats `ts`+`m3u8`.
- **Catalog:** 466 live categories / **15,951 channels**; 156 VOD cats / **69,590 movies**;
  83 series cats / **7,460 series**. Detail calls parse.
- **Streams:** live plays on `:8080` (HTTP 200, `video/mp2t`, TS + m3u8); movies play on
  `:8080` (HTTP 200, `video/x-matroska` MKV, redirect to VOD origin followed).
- **EPG:** server returns an **empty** short‑EPG body → app shows "no guide" gracefully.

**Important provider behavior baked into the app:**
- **Stream port differs from API port.** The API answers on `:80` but streams require the
  `server_info` port (`:8080`). `XtreamClient.resolveStreamBase(from:)` (called in
  `AppState.finishConnect`) derives the stream base from `server_info`, so the user can
  enter `http://<provider-host>` without a port.
- **VOD redirects** to a different origin host — libVLC follows it automatically.
- **1 concurrent connection** on this account → switching streams may briefly 403 until
  the previous one is released.

---

## 6. Build & install

**Build** (normal terminal, not a restricted sandbox — the toolchain needs system temp):
```bash
cd "IPTVXtremePlayer"
./Scripts/build_app.sh            # -> dist/IPTVXtremePlayer.app
./Scripts/build_app.sh --dmg      # also -> dist/IPTVXtremePlayer.dmg
# options: --debug, --vlc /path/to/VLC.app
```
Requires: Xcode Command Line Tools + VLC.app installed (build‑time only).

**Install / update:**
1. **Quit** IPTVXtremePlayer (⌘Q) — macOS can't replace a running app.
2. Open the DMG → drag to **Applications** → **Replace**.
3. Launch. First launch of an ad‑hoc build: **right‑click → Open** if Gatekeeper blocks it.

Same bundle id across versions → replaces in place, no duplicate. App auto‑reconnects to
the last profile on launch.

---

## 7. Data preservation & "no re‑login"

All user data lives **outside** the app bundle, so updates never touch it:
- **Profiles + passwords** — UserDefaults (metadata) + encrypted file + Keychain.
- **Favorites, history, resume points** — `~/Library/Application Support/IPTVXtremePlayer/UserData/`.
- **Caches** — `~/Library/Application Support/IPTVXtremePlayer/` (ImageCache, DataCache).

**No re‑login mechanism:** credentials are stored in a **machine‑bound AES‑GCM encrypted
file** (`CredentialStore`/`FileCredentials`), read **before** the Keychain, so a re‑signed
update doesn't trigger a Keychain prompt. Verified on this Mac: seal→write→read→open
round‑trips, on‑disk data is encrypted (password not readable), and a wrong‑machine key is
rejected. Auto‑connect to the last profile means you land in the library with no login step.

---

## 8. v1.1 changelog (this release)

Six requested changes implemented:
1. **Responsive layout** — window sizes to the display's usable area, fits a 13″ MacBook,
   smaller min size, sidebar no longer collides with traffic lights, full‑bleed player.
2. **History management** — right‑click "Remove from History" (clears resume too);
   "Clear History" with confirm; right‑click "Remove from Favorites".
3. **±10s** rewind/forward buttons (disabled for live / non‑seekable).
4. **Prev/Next episode** controls (series only, correct cross‑season order, disabled at
   bounds, auto‑advance on end).
5. **Loading‑spinner fix** — spinner hides when playback starts, reappears only on genuine buffering.
6. **Seamless update** — encrypted‑file credentials + auto‑connect; version → 1.1/build 2.

**Adversarial code review** (4 reviewers → each finding verified by a skeptic): 17 findings,
14 confirmed → **8 distinct bugs, all fixed** before shipping:

| # | Sev | Bug | Fix |
|---|-----|-----|-----|
| 1 | High | Prev/Next buttons never rendered (navigator set after view loaded) | Pass navigator into player `init` |
| 2 | Med | Resume restarted at 0:00 when VLC reported length late | Wait for real length before latching resume |
| 3 | Med | Keychain‑only creds not migrated → repeat prompts | Backfill encrypted file on Keychain hit |
| 4 | Low | +10s seeked backward in final second | Clamp forward ≥ current position |
| 5 | Low | ±10s active on non‑seekable streams | Dim based on `isSeekable` each tick |
| 6 | Low | Episode index desynced on URL‑build failure | Commit index only after item builds |
| 7 | Med | Player window not full‑bleed; title inset useless | Add `.fullSizeContentView` to player window |
| 8 | Low | Launch did a synchronous main‑thread Keychain read ×2 | Read once, off main; password‑carrying connect |

---

## 8b. v1.2 — Offline downloads (macOS only)

Design (`Core/DownloadManager.swift`, `UI/DownloadsViewController.swift`, `UI/Common/DownloadPill.swift`):
- `URLSession` download tasks, delegate on the main queue, **one at a time** (queue) because
  IPTV plans often allow a single connection. No new dependencies.
- Storage: `Application Support/IPTVXtremePlayer/Downloads/Files/` (0600, excluded from
  Time Machine) + `Downloads/index.json` (records: MediaRef, profile id, status, sizes, error).
- **Credentials never hit disk**: stream URLs and URLSession resume data (both embed the
  username/password) are kept in memory only. After a restart, Retry rebuilds the URL
  from the connected session of the same profile.
- A file is moved into `Files/` only after validation (2xx, not text/html/json, ≥64 KB,
  size == Content-Length); until then it is never listed as playable.
- Launch reconciliation: queued/downloading → failed "Interrupted"; completed-but-missing
  → failed; unowned files deleted.
- Disk guard: refuses to start with < 1 GB free; cancels if the remaining bytes would leave
  < 512 MB free. Quit warns while a download is active.
- `PlaybackItem.preferringOfflineCopy()` makes movie/episode items play the local file when
  one exists; live items never change. `PlayerViewController` now takes `UserData?`
  (not a full `Session`) so offline titles play while disconnected.
- Provider limits: Xtream VOD/episodes are plain HTTP files without DRM, downloaded with the
  user's own subscription; live channels (endless streams) and `.m3u8` titles are rejected.
  A download occupies one provider connection.

Testing (harness built from the app sources, isolated `CFFIXED_USER_HOME`, public sample
videos + a local throttled server — no subscription credentials used): **41/41 checks pass**
— full download with progress, size match, duplicate prevention (done / in progress),
404, HTML error page, 403, unreachable host, live/HLS rejection, network drop → retry
resumes from offset, cancel → retry resumes, queueing, force-quit mid-download →
"Interrupted" after restart, persistence across two restarts, delete removes file+record,
index contains no URLs. The downloaded file decoded fully in libVLC with networking denied
by `sandbox-exec`. Not yet done: on-screen GUI click-through and a real-provider download.

## 9. Verification status

- ✅ Compiles clean (0 warnings), release build, x86_64.
- ✅ Self‑contained bundle; libVLC engine initializes from the bundle.
- ✅ Live Xtream auth + catalog + real stream bytes (live TS/m3u8, VOD MKV) confirmed.
- ✅ Credential encryption round‑trip + machine binding verified.
- ✅ DMG checksum valid.
- ⚠️ **GUI not launched in the build environment** (sandbox can't open a windowed app).
  The six on‑screen behaviors are verified by code review + compile, not an on‑screen run —
  exercise them on the Mac.

---

## 10. Known limitations

- **Provider‑dependent:** EPG (empty on this provider), metadata/posters, subtitle/audio
  tracks — only present when the provider supplies them. Catch‑up/archive not implemented.
- **1 concurrent connection** on this account → brief 403 when switching streams quickly.
- **Ad‑hoc signed:** first launch may need right‑click → Open; a re‑signed build can make the
  **Keychain** (secondary copy) prompt once for the Mac login password — clicking **Deny** is
  safe (the app uses its encrypted file). See open items.
- No built‑in auto‑updater — updates are manual drag‑to‑replace (data is preserved).

---

## 11. Open items / next steps

- [ ] **Optional:** remove the Keychain secondary store entirely (file‑only) so the macOS
      Keychain prompt never appears again. Pending user go‑ahead; needs a rebuild + reinstall.
- [ ] Verify all v1.1 UI behaviors on‑device (layout/resize/fullscreen, history remove,
      ±10s, Prev/Next episode, spinner) — environment couldn't launch the GUI.
- [ ] (Future enhancement) a real in‑app update mechanism.

---

## 12. Build environment notes (for future sessions)

- Mac: Intel x86_64, macOS 13.7.8 Ventura. Swift 5.8.1, **CLT only (no Xcode)**.
- Building needs `dangerouslyDisableSandbox` / a normal terminal — the sandbox blocks
  `xcrun`'s temp cache, and `open`/`osascript` are blocked (so GUI launch/tests can't run here).
- VLC.app 3.0.24 installed at `/Applications/VLC.app` (libVLC source for the build).
