# IPTVXtremePlayer

A lightweight, native macOS IPTV player for **Intel Macs** (built and tested for a
2015 MacBook Pro on macOS Ventura). It connects to any **Xtream Codes** provider
and plays Live TV, Movies, and Series through **libVLC**, so it handles the
MPEG‑TS / MKV / HLS formats IPTV relies on.

Black + electric‑blue interface, macOS‑native AppKit UI, Keychain‑backed
credentials, and a self‑contained app bundle.

---

## What's new in 1.1

- **Responsive layout** — the window now sizes to your display's usable area and
  fits a 13″ MacBook; min size reduced; the sidebar no longer collides with the
  traffic-light buttons; the player window is full-bleed.
- **History management** — right-click any item in Recently Watched →
  "Remove from History" (also clears its resume point); "Clear History" with
  confirmation; right-click Favorites → "Remove from Favorites".
- **±10s seek buttons** in the player (disabled for live / non-seekable media).
- **Previous / Next episode** buttons during series playback only, in correct
  order across seasons; disabled at the first/last episode; auto-advance on end.
- **Loading-spinner fix** — the spinner now hides as soon as playback starts and
  reappears only on genuine buffering.
- **Seamless updates / no re-login** — see *Updating* below.

## Updating (install over an existing version)

1. **Quit IPTVXtremePlayer** if it's running (⌘Q) — macOS can't replace a running app.
2. Open `IPTVXtremePlayer.dmg` and drag the app onto **Applications**, choosing
   **Replace** when prompted.
3. Launch it. It reconnects to your last profile automatically.

This is a **manual drag-to-replace** installer (there is no built-in
auto-updater). Because the bundle identifier is unchanged, it replaces the old
app in place rather than creating a duplicate.

**Your data is preserved across updates** — profiles and passwords, favorites,
watch history and resume points, and settings all live **outside** the app
bundle (Keychain, UserDefaults, and `~/Library/Application Support/IPTVXtremePlayer/`),
so replacing the app never touches them. Credentials are additionally stored in
a machine-bound encrypted file, so an updated build **does not ask you to log in
again** (self-distributed builds are re-signed each release, which can otherwise
make the Keychain re-prompt). Nothing is reset unless you explicitly clear it.

## Architecture & stack

| Concern | Choice | Why |
|---|---|---|
| Language / UI | **Swift 5.8 + AppKit** (programmatic) | Lightest, fastest on old Intel hardware; no runtime overhead |
| Playback | **libVLC 3.0.x** via a thin C bridge | Broad codec support (TS, MKV, HLS, H.264/HEVC/AAC…) that AVFoundation lacks |
| Build | **`swiftc` / `clang`** (not SwiftPM/Xcode) | Only Command Line Tools are required; no full Xcode needed |
| Credentials | **Machine-bound AES-GCM file + macOS Keychain** | Passwords never touch disk in plaintext or logs; updates don't re-prompt |
| Caching | Memory + disk (images & API responses) | Fast reopen, works offline from stale cache, bounded memory |

Modules are cleanly separated:

```
Sources/
  VLCBridge/            # C shim exposing a small, stable wrapper over libVLC
    include/VLCBridge.h
    VLCBridge.c
  IPTVXtremePlayer/
    App/                # NSApplication bootstrap, menus, libVLC engine init
    Core/               # API client, models, Keychain, profiles, caches, user data
      XtreamClient.swift      # async Xtream Codes API, request de-duplication, timeouts
      XtreamModels.swift      # lenient Codable models (servers are inconsistent)
      KeychainService.swift   # secure credential storage
      Profile / ProfileStore  # saved connections (metadata in UserDefaults)
      Session / AppState      # connected session + cached content repository
      ImageCache / DataCache  # two-tier caching
      UserData.swift          # favorites, history, resume points, recent channels
    Player/             # VLCPlayer (Swift wrapper), player view + controls, window host
    UI/                 # Sidebar, top bar, connection screen, Home, Live TV,
                        # Movies, Series, detail screens, Favorites, Recent,
                        # Settings, Search, shared components
Scripts/build_app.sh   # compiles + packages the .app (and optional .dmg)
```

---

## Requirements

- **Intel Mac**, macOS 12+ (built for Ventura 13).
- **Xcode Command Line Tools**: `xcode-select --install`
- **VLC.app** installed (`/Applications/VLC.app`). It supplies libVLC headers,
  dylibs, and plugins **at build time**. These are copied into the app bundle, so
  the finished `.app` is self‑contained and does **not** require VLC afterward.
  Get VLC free at <https://www.videolan.org/vlc/>.

---

## Build & run

```bash
cd IPTVXtremePlayer
./Scripts/build_app.sh           # builds dist/IPTVXtremePlayer.app
./Scripts/build_app.sh --dmg     # also produces dist/IPTVXtremePlayer.dmg
```

Options: `--debug` (unoptimized build), `--vlc /path/to/VLC.app` (custom VLC location).

> Run the script in a normal terminal (the Swift/Clang toolchain writes to the
> system temp directory, which a restricted sandbox may block).

Launch:

```bash
open "dist/IPTVXtremePlayer.app"
```

First launch of an ad‑hoc‑signed app: if macOS Gatekeeper blocks it, **right‑click
the app → Open** once.

---

## Using the app

1. **Add a profile** on the connection screen: a name, your server URL
   (`http://host:port`), username, and password. Choose the live stream format
   (TS or M3U8 — most providers use TS). Optionally add an XMLTV EPG URL.
2. Click **Save & Connect**. Credentials are validated against the server; the
   app reports auth failures, expired/banned subscriptions, timeouts, and
   unreachable servers clearly.
3. Browse via the sidebar: **Home** (continue watching, recents, favorites, new
   content), **Live TV** (categories, search, embedded player, EPG now/next),
   **Movies** and **Series** (poster grids with category filter, sort, search,
   detail pages), **Favorites**, **Recently Watched**, **Settings**.
4. Player controls: play/pause, seek, volume, playback speed, aspect ratio,
   audio‑track and subtitle selection, fullscreen. Keyboard: space (play/pause),
   ←/→ (seek 10s), ↑/↓ (volume), `F` (fullscreen), `M` (mute), `Esc` (close).
5. Movies and series **resume** where you left off; series **auto‑advance** to
   the next episode.

Multiple profiles are supported — connect, disconnect, edit, delete, and refresh
from the connection screen / Settings.

---

## Security & performance notes

- Passwords are stored encrypted (machine-bound AES-GCM file, with a Keychain copy) — never in plaintext; logs redact credentials from URLs.
- Network I/O is async; identical in‑flight API requests are **de‑duplicated**.
- Large playlists are fetched per category; the player releases resources when
  switching channels; images and metadata are cached on disk.
- Connect only to IPTV services you are authorized to use.

## What depends on your provider

Some features only work if the provider supplies the data:

- **EPG** (needs provider short‑EPG or an XMLTV source).
- **Movie/series metadata** (plot, cast, posters, ratings, durations).
- **Catch‑up / archive** is not implemented.
- Subtitle/audio‑track options depend on what each stream contains.

---

## Verification status

- Compiles cleanly (0 warnings) and packages into a self‑contained `.app`.
- The bundled libVLC engine was confirmed to initialize and load its plugins
  from inside the bundle (no dependency on an installed VLC at runtime).
- Live Xtream authentication, catalog loading and stream delivery were verified
  against a real provider (see `PROJECT.md`); the on-screen UI behaviors still
  need a hands-on check on the Mac.
```
