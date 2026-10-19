# docs/03-classification.md — Phase 3: component classification

Phase 3 turn: classify **every** component, file group, daemon, Settings page, font
and asset as **essential / optional-disabled / removable / uncertain**, each with
(a) the necessity-test reason, (b) a RAM/CPU estimate and whether it spawns a
process, and (c) what depends on it. Then: the resolved open items, a "bloat found"
list, an "opted out, can re-enable" list, licensing/credits, and the proposed Mei
Settings-page list.

**No code was changed, nothing was built or run, no installs.** This document is the
Phase 3 deliverable and ends in a STOP for owner approval.

## Labels

| Label | Meaning |
|---|---|
| `[READ]` | read directly from the pinned upstream source at the cited `path:line` |
| `[TESTED]` | observed by running something — **none in this phase** (read-only) |
| `[REPORTED]` | stated by an upstream source comment/doc; not independently measured |
| `[UNVERIFIED]` | inferred, or a runtime behaviour that cannot be proven without building |

Everything cost-related is an **estimate**, because nothing has been built or run:
upstream's read-only tree yields no RSS/CPU measurements. Estimates name their basis
and are `[UNVERIFIED]` unless they quote an upstream comment (`[REPORTED]`). The
formal measurement is Phase 8.

Measurement baseline for all Mei runs: XDG confinement into
`~/projects/mei/.run/{config,cache,state,data}` + Go dirs, per `AGENTS.md`.

---

## 0. Summary

* **Resident process count for the kept core: 3** — `ryoku-shell` (Go daemon),
  `qs -c shell` (Quickshell surface process, spawned by the daemon), `ryogami`
  (wallpaper daemon). See `docs/02b-gaps.md` §Gap B.
* **Kept daemons: 3.** Kept on-demand helpers: `matugen` (palette), `ryoku-hub`
  (Settings backend), `qs -c hub` (Settings window), assorted tiny shell-outs
  (brightness/audio).
* **Settings: 28 nav pages + 4 helper files → 5–6 kept.** Everything that writes
  Hyprland/Niri config, `/sys`, `/etc`, or a network API is cut (see §7).
* **Zero outbound internet calls** in the kept set; the only network traffic is the
  loopback palette bridge, which is itself optional-disabled (§3.4).
* **Five open items resolved** (§1). One is a real code defect (duplicate
  `NotificationServer`); one is a genuine confinement violation
  (`~/.cache/qs-rise-notifications.json`).
* **One material confinement risk** beyond the five: many QML `FileView` paths are
  built as `Quickshell.env("HOME") + "/.config"` and therefore **ignore
  `XDG_CONFIG_HOME`** — the XDG redirect alone does not confine them (§1.6).

---

## 1. Open items — resolved by reading code

### 1.1 Dual `NotificationServer` — **real, both instantiated; one must go** `[READ]`

Two `NotificationServer` objects exist in the shell process:

| # | Declaration | Instantiated at | Writes |
|---|---|---|---|
| A | `services/Notifs.qml:230` (singleton, id `server`) | loaded by `services/ServiceLoader.qml`; bound in `shell.qml:626` | `~/.local/state/ryoku/notifications.json` (via the shell state dir) |
| B | `barstyles/qsbar/panels/NotificationPanel.qml:26` (id `notifServer`) | `barstyles/qsbar/VariantRoot.qml:251` → live | `~/.cache/qs-rise-notifications.json` (`NotificationPanel.qml:90`) |

Only one process may own `org.freedesktop.Notifications`. Both are real code, both
are instantiated in the same Quickshell process; whichever registers first wins and
the other logs a D-Bus name-in-use error. **Which one wins is `[UNVERIFIED]`** without
building — it depends on load order, not on any static guard.

Which stays: **A (`services/Notifs.qml`)**. It is the integrated one — it drives
`NotificationPopups` (`shell.qml:382`), the DND `Binding` (`shell.qml:626`), the
`NotificationCard`, the framebar `MenuNotifications`, `QsTabRail`, `RailStatus`
unread badge, and the Kairos quick-settings page (`grep -rln Notifs` →
7 consumers). B is the qsbar style's own panel and additionally writes a **non-Ryoku
cache path** (`~/.cache/qs-rise-notifications.json`, the Quickshell-Rise heritage).

Action (Phase 4/6, not now): keep `services/Notifs.qml`; delete the `NotificationServer`
block from `NotificationPanel.qml` and bind the panel to `Notifs` history, **or** drop
the qsbar panel if the control-centre notifications view suffices. Either way B's
foreign cache write disappears.

Necessity: notification popups + history are on the keep-list → A is **essential**;
B is a duplicate → **removable**.

### 1.2 Polkit agent — **present, safely gated; the disable switch is "do not set the env var"** `[READ]`

The `ryoku-shell` daemon embeds a PolicyKit1 authentication agent
(`ipc/polkit.go`): it registers `org.freedesktop.PolicyKit1.Authority` on the **system
bus**, runs the PAM conversation through the setuid helper, and streams prompt state
over the `polkit` topic. Registration is gated:

> `polkit.go:35-40` — "SAFETY: registration is gated behind `RYOKU_POLKIT_AGENT=1`.
> Only one agent may [hold] the polkit slot. With the flag set it registers (and fails
> closed if another agent [is present]); [without it] whatever handles polkit today
> keeps working."

The upstream unit sets it: `ryoku-shell.service` →
`Environment=RYOKU_POLKIT_AGENT=1` (`[READ]`).

**Test-mode disable:** Mei runs the daemon directly (no unit), so simply **never set
`RYOKU_POLKIT_AGENT`**. With it unset the daemon does not register at all — it cannot
shadow the live session's agent (gnome-keyring PID 795 / whatever owns polkit today).
For belt-and-braces the Mei launcher will also `unset`/omit it explicitly, and the
nested test runs inside `dbus-run-session` so even the system-bus registration path is
isolated from the owner's session. The QML prompt surfaces
(`bar/PolkitSurface.qml`, `bar/popouts/PolkitPopout.qml`) only *render* a prompt when
the daemon forwards one; with no registration they never appear.

Related but separate: `daemon.go:442` starts a **keyring prompter**
(`org.gnome.keyring.SystemPrompter`, `ipc/prompter.go:31-39`) unconditionally. It does
not own `org.gnome.keyring` itself (gnome-keyring does); it offers a prompter service.
In the nested `dbus-run-session` it is isolated. For the kept set it is **not on the
keep-list** → candidate to drop from the trimmed daemon (§2.1).

Necessity: polkit prompting is on the keep-list only implicitly (control sidebar
privileged actions). Mei keeps the **code** but **disables registration**; the feature
stays available by opting in with the env var. Class: **optional-disabled**.

### 1.3 matugen — minimal Mei `config.toml` plan; every template and target `[READ]`

Pipeline (Q1, `docs/02-deps.md`): the daemon runs matugen twice —
`matugen image <img> … --json hex --dry-run` to read roles, then
`matugen -c <filtered config> json <carrier>` to render templates
(`matugen.go:1145,1253`). **`colors.json` and `tones.json` are written by the Go
daemon's own code, not by any template** (`matugen.go:~573`, `matugenColorsPath`
= `$XDG_CACHE_HOME/ryoku/colors.json`, `matugen.go:1783`). Every QML `Scheme`/`Theme`
/`Tokens` singleton watches those two files.

Consequence: **the kept shell palette needs zero matugen templates.** The templates
only fan the palette out to third-party apps and compositor surfaces, none of which is
on the keep-list.

`matugen.go:1750 matugenConfigHome()` = `$XDG_CONFIG_HOME` or `~/.config`; templates
are read from `<cfg>/matugen/` and matugen expands `~` to `$HOME`, so the shipped
`config.toml`'s literal `~/.config/...` paths are **not** confined by an XDG redirect.

**Every template in `ryoku/shell/matugen/config.toml`** (the always-render set):

| Template | input (shipped `~/.config/matugen/templates/`) | output (shipped) | Within `~/projects/mei`? |
|---|---|---|---|
| `[templates.kitty]` | `kitty-colors.conf` | `~/.config/kitty/current-theme.conf` | **no → REMOVE** (terminal) |
| `[templates.hypr]` | `hypr-colors.lua` | `~/.cache/ryoku/hypr-colors.lua` | no → **REMOVE** (no on-disk reader found in the kept tree; it is Ryoku's own Hyprland-Lua accent) |
| `[templates.btop]` | `btop.theme` | `~/.config/btop/themes/ryoku.theme` | **no → REMOVE** (btop) |
| `[templates.sharepicker]` | `share-picker.css` | `~/.cache/ryoku/share-picker.css` | no → **REMOVE** (xdg-desktop-portal chooser) |
| `[templates.qt6ct]` | `qt6ct-colors.conf` | `~/.config/qt6ct/colors/ryoku.conf` | no → **REMOVE** (Qt toolkit for *other* apps) |
| `[templates.kde]` | `kdeglobals` | `~/.cache/ryoku/kdeglobals-colors.conf` | no → **REMOVE** (KDE apps) |
| `post_hook` | — | runs `ryoku-cmd-folders` + `ryoku-cursor-material-recolor` | **REMOVE** (mutates the owner's file-manager icons + cursor) |

**Every template in `ryoku/shell/matugen/apps.toml`** (the gated fan-out — all
**REMOVE**, all point into the owner's home): gtk3 `~/.config/gtk-3.0/gtk.css`, gtk4
`~/.config/gtk-4.0/gtk.css`, vesktop, equibop, obs, zed, heroic, telegram, steam, cava,
ghostty, micro, papirus (`~/.cache/matugen/…`), fish, yazi, obsidian, zathura,
alacritty, tmux, sidra, ryotunes.

**Minimal Mei plan.** Generate `~/projects/mei/.run/config/matugen/config.toml`
containing `[config]` **only — no `[templates.*]`, no `post_hook`.** With no templates,
`matugenRenderTemplates` (`matugen.go:1145`) stages an empty filtered config and
matugen's render pass is a no-op; the `--dry-run` extraction still produces the roles
the daemon writes into `$HOME/.cache/mei/colors.json` + `tones.json`. Set
`XDG_CONFIG_HOME=.run/config` / `XDG_CACHE_HOME=$HOME/.cache` (= `.run/home/.cache`) so the daemon resolves
`matugenConfigHome()`/`matugenCacheHome()` inside the project. Ship **no** templates
initially. If the owner later wants themed kitty/btop, add a single template whose
`input_path`/`output_path` are **absolute `~/projects/mei/.run/...` paths** (never
`~/.config`), listed in the "opted out, can re-enable" section.

Verified by reading: no kept QML reads any of these six outputs `[READ]`
(`grep -rn hypr-colors` over the kept modules → no reader; the terminal/Qt/KDE outputs
are for apps Mei does not own).

### 1.4 The `127.0.0.1:47616` palette bridge — **loopback-only, HTTP (not file-based), optional-disabled** `[READ]`

* Implementation: `ryoku/palette-bridge/main.go`. Default bind is the flag
  `-listen 127.0.0.1:47616` (`main.go:241`); routes `/colors.json`, `/v1/palette`,
  `/v1/events`, `/healthz` (`main.go:255-258`). It is an **HTTP server, not a file** —
  there is no file-drop alternative.
* Loopback-only **by default** (`127.0.0.1`); the `-listen` flag could bind wider, but
  Mei would run it (if at all) with the loopback default.
* Consumers `[READ]`: browser extensions (`zen-extension/`), `spicetify/`, `vesktop/`,
  the Hub (`hub/backend/palettebridge.go:122`, hardcodes `http://127.0.0.1:47616`), and
  the ryogami wall-picker settings (`PaletteBridgeSettings.qml`). All are third-party
  app theming or off-list surfaces.
* Port configurability: only via the `-listen` launch flag; the Hub side is a
  **hard-coded** URL, so a different port would need a Hub edit too. No env override.

Necessity: nothing on the keep-list (bar/launcher/sidebar/notifications/wallpaper)
uses it — those read `colors.json` directly. Class: **optional-disabled** (browser /
app theming only). Its loopback traffic is the *only* network in the keep set (Q4).

### 1.5 ryogami reveal / live / depth — cost and how to disable while keeping stills `[READ]` + `[REPORTED]`

| Feature | Mechanism | Cost (estimate, `[UNVERIFIED]` unless noted) | Spawns a process? | Disable switch |
|---|---|---|---|---|
| Still-image wallpaper | daemon + `magick` for fit `[READ]` | small: Go daemon idle; one-shot `magick` per set | no (transient `magick`) | — (this is the baseline Mei keeps) |
| **Reveal transitions** | 22 presets, shared `transitionDurationMs = 2200` (`transitions.go:15-37`); rendered by the in-shell GPU shader in `modules/wallpaper/Backdrop.qml` | GPU shader pass for ~2.2 s per change; ~0 idle | no (runs in the Quickshell process) | per-change; the shader lives in the kept `Backdrop.qml`. Can be flattened to a plain crossfade by selecting a static/none preset — `[UNVERIFIED]` exact config key |
| **Live video** | `ryogami-live` in-repo C player, one process per live output, software-decodes a pre-transcoded clip into `wl_shm` (`livewall.go` header `[REPORTED]`) | `[REPORTED]` **~40–60 MB RSS per player**, "a fraction of a core"; plus a one-time `ffmpeg` transcode (`livewall.go`, `video.go`) | **yes**, one `ryogami-live` per video output | use a still, not a clip; no `video_enabled` (`wallTune`, `config.go:213-218`). `~/Pictures/livewalls` clips are optional |
| **Depth cut-out** | ported from NibrasShell ("depth effect engine", credits); `ryogami depth set|clear` + `surface.go:24-25` `depth`/`depthRev`; rendered by a shell shader | extra depth-map PNG + a shader pass; ~0 idle | no (shell shader) | `ryogami depth clear`; don't set a depth image |
| Resource tier | `resource_tier` (`config.go:21`, default `"medium"`, persisted) tunes live encode/render | lower tier = less CPU for live video | no | `ryogami wallpaper resource <tier>` (`verbs.go:78-86`) |

Conclusion: **still-image wallpaper without reveal/live/depth needs only the
`ryogami` Go daemon** (resident) + a transient `magick`; **no `ryogami-live`, no
`ffmpeg` decode loop, no depth map.** The reveal shader is inside the kept Quickshell
process (cheap, idle-zero, only fires on change) and is the visual-quality asset the
owner wants preserved — keep it. Live video and depth are the two RAM/CPU-heavy
options and are **optional-disabled** by default.

### 1.6 NEW — XDG confinement gap: QML `FileView` paths that ignore `XDG_CONFIG_HOME` `[READ]`

Beyond the five asked items, the read surfaced a concrete risk to `AGENTS.md` rule 1.
Many kept-module `FileView` paths are built as
`Quickshell.env("HOME") + "/.config" (+ "/ryoku/…")` rather than from
`XDG_CONFIG_HOME`. Redirection of `XDG_CONFIG_HOME` therefore does **not** contain
them. Counted with `grep -rnoE 'Quickshell\.env\("HOME"\) *\+ *"/…"'`:

* In the **kept** surfaces: `BarStudioPage` (`:215-217` uses XDG — OK),
  `barstyles/qsbar/Theme.qml:14,15,19,20,2157-2169` (shell.json, theme.json,
  notifications.json, stay-awake — **HOME-based**), `desktop/Singletons/Config.qml`
  (`widgets.json`, `brand.json`), `desktop/Singletons/Scheme.qml`, launcher
  `Config.qml`/`Scheme.qml`/`Frecency.qml`/`LauncherConfig.qml`, `overview`,
  `stage`, `bar/PluginPopouts.qml`.
* Foreign cache paths in **off-list** modules only, but note the one in the kept
  bar: `barstyles/qsbar/panels/NotificationPanel.qml:90`
  `~/.cache/qs-rise-notifications.json`, plus `qs-reactor-event`,
  `quickshell-scan-*`, `quickshell_widgets_v2`, `quickshell_barorder_v2`,
  `ryoku-capture-thumbs`, and `/tmp/ryoku-screenrecord-filename`.

Action (Phase 4/6): introduce a single XDG-aware path helper and replace the
`HOME + "/.config"` idioms in the kept modules, **or** run the kept shell with a
rewritten `HOME` inside `dbus-run-session` so `HOME + "/.config"` resolves inside
`.run/`. Both are `[UNVERIFIED]` until built. Class: **uncertain** (blocks the
"nothing outside the project" guarantee for Settings-driven writes; must be closed
before the acceptance test).

---

## 2. Component classification

Legend for the necessity column: **KL** = on the keep-list; **dep** = proven
dependency of a kept item (file-level); **off** = neither (→ removable / optional).

### 2.1 Daemons & processes

| Component | Class | Necessity (a) | Cost / spawns (b) | Depended on by (c) |
|---|---|---|---|---|
| `ryoku-shell` Go daemon (`ryoku/shell/ipc/`) | **essential** (trimmed) | KL ("trimmed ryoku-shell Go daemon"); owns the Unix socket, state topics, surface supervision | 1 resident process; Go, stdlib+`godbus`; est. **~15–30 MB RSS** `[UNVERIFIED]`; spawns `qs -c shell`, `wl-paste` (clipboard), `matugen`, and helper scripts | every QML singleton via `IpcRouter.qml`; network/tray topics; palette pipeline |
| `qs -c shell` Quickshell surface process | **essential** | KL (bar, launcher, sidebar, notifications all render here); spawned+respawned by the daemon (`daemon.go:761`, `components={"shell",true}`) | 1 resident process; est. **~120–250 MB RSS** for a Qt6/QML shell with blur+shaders `[UNVERIFIED]`; spawns nothing persistent | all surfaces |
| `ryogami` Go daemon (`ryoku/shell/ryogami/daemon/`) | **essential** | KL (wallpaper + matugen trigger); Q7 keeps it | 1 resident process; Go; est. **~10–25 MB RSS** `[UNVERIFIED]`; spawns `magick`/`ffmpeg` transiently | wallpaper topic → daemon palette; launcher/wallpaper surfaces |
| `ryogami-live` C player | **optional-disabled** | live video is not KL; stills need it not | 1 process **per live output**; `[REPORTED] ~40–60 MB RSS each** + a core fraction; one-time `ffmpeg` transcode | only live video wallpapers |
| `matugen` (binary) | **essential** | dep: the daemon's palette extraction; `matugen.go:775` | transient process per change; **binary 11,945,640 B `[TESTED]`**; brief CPU spike | `colors.json`/`tones.json` → all `Scheme` singletons |
| `ryoku-hub` (Go, `ryoku/hub/backend/`) | **essential** (trimmed) | KL (Settings backend: `settings.patch`, appearance/shell reads) | transient per Settings action; est. small; spawns on demand | Settings app |
| `qs -c hub` (Settings window) | **essential** | KL (Settings app) | transient while Settings is open; est. **~80–150 MB RSS** `[UNVERIFIED]` | Settings UI |
| `wl-paste --watch … __clip-ingest` | **removable** | clipboard history is **not** KL; started unconditionally by `daemon.go:432`→`clipboard.go:689` | 1 resident process; trim from the daemon | clipboard topic only (off-list) |
| `ryoku-eq` pipewire filter chain | **removable** | audio EQ is not KL (volume control is, and is in-process) | 0 unless kept; separate unit | EQ page only |
| `ryoku-idle` / `ryoku-clamshell` / `ryoku-ai-usage` / `ryoku-bootstrap` / `ryoku-palette-bridge` / `voxtype` / `ryoku-rashin` / `ryoku-qylock` / `ryoku-power`(cutover) | **removable** | each belongs to an off-list feature (idle-lock, lid, AI usage, one-shot materialize, browser theming, dictation, AI, lockscreen, power) | not started by Mei | their own pages/topics |
| keyring prompter (`org.gnome.keyring.SystemPrompter`, `prompter.go`) | **optional-disabled** | not KL; not needed without keyring-setting UI | in-process thread in the daemon; isolated in nested dbus | LockscreenPage only (cut) |
| polkit agent (`polkit.go`) | **optional-disabled** | keeps the *code*; **registration off** unless `MEI_POLKIT_AGENT=1` (§1.2) | in-process; registers only when opted in | privileged prompts |

### 2.2 Shell modules (`ryoku/shell/quickshell/shell/modules/`)

| Module | Class | Necessity (a) | Cost / spawns (b) | Depended on by (c) |
|---|---|---|---|---|
| `bar/` (frame + qsbar style) | **essential** | KL (top bar, workspaces, clock, audio, brightness, network, battery, tray, notifs indicator) | in-process (one Quickshell); GPU for blob/blur shaders | the shell root |
| `launcher/` | **essential** | KL (launcher) | in-process; `hands-adam.png` art | — |
| `notifications/` | **essential** | KL (notifications) | in-process | `services/Notifs.qml` |
| `osd/` | **essential** | KL (audio/brightness OSD feedback) | in-process | OSD feed |
| `wallpaper/` | **essential** | KL (wallpaper selector + reveal `Backdrop.qml`) | in-process GPU shader on change | wallpaper topic |
| `desktop/` (core: `Desktop.qml`, `Singletons/`) | **essential** (core) | KL (the desktop wallpaper host + shell config/scheme/theme singletons live here) | in-process | shell root, bar, launcher |
| `desktop/` extras (`aio/`, `calendar/`, `clock/`, `music/`, `notes/`, `stats/`, `weather/`, widget slots, `MusicVideoPicker`, `Plugin*`) | **optional-disabled / removable** | not KL (desktop widgets, notes, stats, music, weather) | in-process; hub art bloat | desktop only |
| `dock/` | **optional-disabled** | not KL | in-process | — |
| `overview/` | **optional-disabled** | not KL | in-process | — |
| `visualizer/` | **optional-disabled** | not KL (audio visualiser); `cava-bg` credit | in-process GPU spectrum shader | — |
| `clipboard/` | **removable** | not KL (clipboard history) | in-process + `wl-paste` watcher | — |
| `capture/` | **removable** | not KL (screenshot/record) | spawns `ffmpeg`/`slurp`-class tools | — |
| `stage/` | **removable** | not KL (web cut-out; needs `uv`) | in-process + Python | — |
| `confirm/` | **removable** | not KL (logout/power confirm dialogs) | in-process | — |
| bar styles `kairos/`, `sumi/` under `barstyles/` | **removable** | KL names only `qsbar` | in-process | — |

### 2.3 Shell services & singletons (`ryoku/shell/quickshell/shell/services/`)

| Service | Class | Necessity (a) | Cost / spawns (b) | Depended on by (c) |
|---|---|---|---|---|
| `ServiceLoader.qml`, `qmldir` | **essential** | dep: loads all singletons | in-process | shell root |
| `Config.qml`, `ShellState.qml`, `Flags.qml`, `Events.qml`, `Theme.qml`, `Scheme.qml`, `Icons.qml`, `Needle.qml` | **essential** | dep: config/scheme/theme/icon resolution the kept surfaces bind to | in-process (watches `colors.json`) | bar, launcher, sidebar |
| `Motion.qml` | **essential** | KL: the centralised motion language (`dur()` scaler; barReveal/menuSlide 250, sidebarEnter/Exit 400/200, push 420, crossfade/diagonal/rowReveal 200, notifIn/Out 420/340, fast/standard/morph/hover/spatial 140/300/420/100/500) | in-process | every animated surface |
| `Perf.qml` | **essential** | KL-adjacent: the single policy reader (`performance.json`); folds low-power/battery/Game-Mode into `reduceMotion`/`motionSpeed`/freeze flags; `Motion` reads it | in-process; one file watcher | `Motion`, all surfaces |
| `Audio.qml`, `Battery.qml`, `Network.qml`, `Tray.qml`, `Notifs.qml` | **essential** | KL: audio, battery, network, tray, notifications (in-process PipeWire/UPower/Quickshell) | in-process | bar widgets, sidebar |
| `BluetoothDiscovery.qml`, `BtLink.qml`, `Devices.qml` | **optional-disabled** | not KL (Bluetooth) | in-process | sidebar Bluetooth (optional) |
| `Music.qml`, `MusicPreview.qml`, `Media.qml`, `AudioBars.qml`, `VoiceBars.qml`, `Equalizer.qml` | **removable** | not KL (music/media/EQ/voice) | in-process; some poll network | menu/media surfaces |
| `Weather.qml`, `Holidays.qml`, `Updates.qml`, `Nightlight.qml`, `PowerProfiles.qml`, `ScreenTime.qml`, `Recorder.qml`, `Clipboard.qml`, `Stash.qml`, `Capture.qml`, `Camera.qml`, `Keypresses.qml`, `Keyring.qml`, `Polkit.qml` | **removable** | not KL (weather, holidays, updates, nightlight, power-profiles, screen-time, recorder, clipboard, stash, capture, camera, keypress, keyring, polkit-prompt) | in-process; `Weather`/`Holidays`/`Updates` make network calls | their own surfaces/pages |
| `SessionActions.qml`, `Session.qml` | **optional-disabled** | logout/reboot are stubbed in test mode; not KL | in-process | session menu |
| `Sysinfo.qml`, `StatsFeed.qml`, `Dock.qml`, `DockPreview.qml`, `BarProducts.qml`, `Toggles.qml`, `KeyboardLayout.qml`, `OsdFeed.qml`, `AppLaunch.qml` | mixed | `AppLaunch`, `Toggles`, `OsdFeed`, `KeyboardLayout` are dep for kept surfaces → **essential**; `Sysinfo`/`StatsFeed`/`Dock*`/`BarProducts` → **optional-disabled** | in-process | bar/sidebar |

### 2.4 Bar widgets (qsbar `modules/`) — keep-list subset

| Widget | Class | Necessity (a) |
|---|---|---|
| Workspaces | **essential** | KL (workspaces) |
| Clock / date | **essential** | KL (clock/date) |
| Audio indicator + `VolumePanel` | **essential** | KL (audio) |
| Brightness + `BrightnessPanel` | **essential** | KL (brightness) |
| Network + `NetworkPanel` + `NetworkManagerAdapter` | **essential** | KL (network) |
| Battery + `BatteryPanel` | **essential** | KL (battery) |
| Tray + `TrayPanel`/`TrayMenu` | **essential** | KL (system tray) |
| Notifications indicator | **essential** | KL (notifications) — but must point at `services/Notifs.qml`, not its own server (§1.1) |
| `MediaBrowser*`, `ImageCarousel*`, `MprisPanel`, `CpuPanel`, `GpuPanel`, `MemoryPanel`, `StoragePanel`, `ThermalsPanel`, `PowerProfilePanel`, `PluginPanel`, `MicrophonePeakMonitor`, `TooltipOverlay`, `VolumePanel`(kept), `BluetoothPanel` | **optional-disabled / removable** | not KL (media browser, image carousel, MPRIS, CPU/GPU/RAM/disk/thermals, power-profile, plugin, mic peak) |
| `DashboardPopup`, `NotificationPanel` | `DashboardPopup` **optional-disabled**; `NotificationPanel` **removable** (replaced by `services/Notifs.qml` per §1.1) | — |

`bar/framebars/**` (menu system: `FrameMenu*`, `menus/`) is **essential** — the bar's
dropdowns (quick settings, theme menu) depend on it. `bar/popouts/**` mixes kept
(sidebar-related) and off-list popouts (capture/music/bt/etc.) — split in Phase 4.

### 2.5 C++ / native plugin

| Component | Class | Necessity (a) | Cost / spawns (b) |
|---|---|---|---|
| `ryoku/shell/plugin/` `Ryoku.Blobs` QML/C++ plugin (`blobrect`, `blobgroup`, `blobmaterial`, shaders `blob.vert/.frag`) | **essential** | dep + KL: the frame-blob rendering the bar's look depends on (adapted from Caelestia, GPL-3) | in-process GPU; needs `cmake`+Qt shadertools to build (§Phase 4 deps) |
| `ryoku/ui` (`Ryoku.Ui`: Tokens, Ink, Spans, Ryodecors, Silhouette, etc.) QML module | **essential** | dep: Tokens/Scheme/Ink are imported by every kept surface; holds the design system + app-side motion tokens | in-process; ships `grain.png` + shaders |
| `ryoku/wm` (Hyprland/Niri provider Go lib) | **partial**: keep the **read-only** half (`Wm.qml` workspace/window state via `Settings.windows`); **do not vendor the writing half** | KL: Mei must not write Hyprland config; only read state | in-process/Go |

### 2.6 Fonts

| Font | Class | Necessity (a) | Cost (b) | Depends (c) |
|---|---|---|---|---|
| `Material Symbols Rounded` (`ttf-material-symbols-variable`, Apache-2.0) | **essential** | `MaterialIcon.qml:12` — every icon ligature; without it icons render as text | font raster in-process; package install needed | every bar/sidebar/settings icon |
| `Noto Sans CJK JP` (`noto-fonts-cjk`, OFL) | **essential** | the 力 seal + kanji marks (`Theme.fontJp`) | font raster | BrandMark, kanji labels |
| `JetBrainsMono Nerd Font` (`ttf-jetbrains-mono-nerd`, OFL) | **essential** | mono text + nerd glyphs (labels, code) | font raster | bar labels, launcher |
| `Space Grotesk` (`otf-space-grotesk`, OFL) | **essential** | default UI sans (`Tokens.ui`) | font raster | all UI text defaults |
| `Inter` / `Inter Display` (`inter-font`, OFL) | **essential-ish** | hub preview widget bodies (`ClockPreview`, `AioPreview`) | font raster | Settings previews (`[UNVERIFIED]` if any kept preview needs it) |
| `Fraunces` (`ttf-fraunces-variable`, OFL) | **optional-disabled** | display serif for titles; falls back to sans if absent | font raster | hub/overview titles |
| `Noto Sans` generic + `noto-fonts-emoji` | **optional-disabled** | fallback/emoji; no kept QML hardcodes them | font raster | emoji glyphs |
| `ttf-maple-mono-nf` | **removable** | "Not referenced by any kept QML" (`06` fragment) | — | terminal offer only |
| 11 bundled faces in `shell/assets/fonts/` (366,768 B) | **optional-disabled** (or **removable** if the widget-font picker is cut) | loaded by `modules/desktop/Singletons/Fonts.qml` purely to populate the Hub widget-font picker — not used by kept surfaces | 366 KB on disk; FontLoader registers at runtime | widget font picker only |
| `archivo-black.ttf` (`hub/quickshell/fonts/`, 40,544 B) | **removable** | RashinPage only (cut) | 40 KB | — |

### 2.7 Assets

| Asset | Class | Necessity (a) | Size / cost (b) |
|---|---|---|---|
| `qsbar/assets/` (11 files, 68,506 B) | **partial**: some essential | `gpu-card.svg`/`hdd-mark.svg`/`arch-*`/`oma*` are bar branding; `claude/codex/opencode` SVGs belong to AI widgets (removable) | 68.5 KB |
| `qsbar/shaders/` (`logo-tint`, `stream.frag`+`.qsb`, 68,197 B) | **optional-disabled** | audio-reactive stream shader (visualiser) — not KL; `logo-tint` may be used by the kept frame | 68 KB |
| `components/icons/` (152 symbolic SVGs, 65,090 B) | **essential** | icon fallback set (`SymbolIcon.qml:23`) used across the bar/sidebar | 65 KB; **licence unknown** — no LICENSE/README shipped (see §8) |
| launcher `shared/art/hands-adam.png` (681,800 B) | **optional-disabled** | launcher hero art; the launcher works without it (decorative) | 682 KB |
| `ryoku/ui/grain.png` (66,409 B) + shaders (`dither`, `spectrum`: 62,413 B) | `grain`+`dither` **essential** (design system); `spectrum` **optional-disabled** (visualiser) | — | 129 KB |
| `ryoku/ui/art/{graces,helm,justice}.svg` (115,794 B) | **optional-disabled** | ProfilePage/Rashin decorations (cut) | 116 KB |
| `reload-cover/assets/logo.png` (1,401 B) | **optional-disabled** | reload cover (kept only if the reload splash is kept) | 1.4 KB |
| `welcome/art/welcome-bg.png` (1,204,630 B) | **removable** | separate `welcome` surface (not KL) | 1.2 MB |
| Hub art (`dither-torii.png` 599 KB, `profile-hero.png` 49 KB, `roots.png` 765 KB, 3 tiling GIFs 332 KB) | **mostly removable** | Credits/Profile/SettingsSheet decorations; keep only if their kept pages use them | ~1.7 MB |
| `ryoku/assets/brand/logo.svg` + `logo-mark.svg` (1,146 B) | **essential (2 files)** | desktop-entry icons for the Mei launcher entry | 1.1 KB |
| `ryoku/assets/wallpapers/` (245,026,989 B) | **content, optional** | seeded wallpaper set; no code path requires a specific file | 233.7 MiB — **do not ship**; point the picker at the owner's folder |
| `ryoku/assets/ryodecors/` (4,165,851 B) | **removable** | ProfilePage/Rashin only (cut) | 3.97 MiB |
| `ryoku/assets/brand/{logo-mark.png,fastfetch-emblem.png,icon.png}` | **removable** | Fastfetch/installer branding (cut) | ~437 KB |

### 2.8 Binaries / external dependencies (kept set)

| Binary | Class | Necessity (a) | Present on host? |
|---|---|---|---|
| `quickshell` (`qs`) | **essential** | the shell + Settings render here | **yes** (0.3.2-1) |
| `matugen` | **essential** | palette extraction | yes (4.2.0) |
| `imagemagick` (`magick`) | **essential** | ryogami image fit/optimise | yes |
| `ffmpeg`/`ffprobe` | **optional-disabled** | live video transcode + luminance/thumb steps; stills do not need ffmpeg for decode but the daemon uses it for luminance | yes |
| `brightnessctl` | **essential** | brightness steps | yes |
| `wireplumber` + `pactl`/`wpctl` | **essential** | audio steps | yes |
| `inetutils`/`ip`/`iw`, NetworkManager | **essential** | network status | yes (NM present) |
| `jq` | **essential** | JSON patching helpers | yes |
| `go` (toolchain) | **essential to build** | compile `ryoku-shell`, `ryoku-hub`, `ryogami` | **no — Phase 4 install** |
| `cmake` (+ `ninja`), Qt shadertools | **essential to build** | build `Ryoku.Blobs` plugin + `Ryoku.Ui` | `cmake` **no** (Phase 4); `ninja` yes |
| `curl`, `inotify-tools` (`inotifywait`) | `curl` **removable** (only off-list network); `inotifywait` **essential if** ryogami watches clips/wallpaper dirs (`[UNVERIFIED]` usage) | — | `[UNVERIFIED]` |
| `uv` | **removable** | Stage/AI only (Q6) | no |
| `pkexec` | **removable** | only cut pages (Connections/Gpu/Lockscreen) | yes (but unused) |
| `openrgb` | **removable** | LightingTab only (cut) | `[UNVERIFIED]` |
| `vlc`/`mpv`-class | **not used** | ryogami uses its own C player | — |

### 2.9 Settings pages — all 32 files

Class key: **K** keep · **K\*** keep-trimmed (shell half only) · **O** optional-disabled ·
**R** removable. Full write mapping in `docs/02b-gaps.md` §Gap A.

| Page | Nav | Class | Writes / why |
|---|---|---|---|
| `GlobalPage.qml` | global | **K** | `shell.json` (language/locale/timezone/font/location) — but drop the `systemctl --user restart` and keep only shell keys |
| `DesktopPage.qml` | desktop | **K\*** | `brand.json` + `viz` + `shell.json`; **drop** any compositor rows |
| `BarStudioPage.qml` | bar-studio | **K** | `shell.json` (bar layout) — pure shell |
| `LauncherPage.qml` | launcher | **K** | `launcher.json` — pure shell |
| `AnimationsPage.qml` | animations | **K\*** | keep `theme.motion.scale`/`reduce` (shell); **sever** the `desktop.json` anim/hyprfocus editor |
| `WidgetsPage.qml` | widgets | **O** | `widgets.json`; desktop widgets are not KL → disabled by default |
| `PerformancePage.qml` | performance | **O** | `performance.json` (shell Perf); not KL, but harmless if the owner wants perf knobs → disabled |
| `CreditsPage.qml` | credits | **O** | reads nothing, writes nothing; fold text into an About/notice instead of a nav page |
| `WindowManagerPage.qml` | windowmanager | **R** | compositor editor (settings.lua) |
| `PluginsPage.qml` | plugins | **R** | compositor plugin list (`desktop.json`) |
| `LayerRulesPage.qml` | layerrules | **R** | compositor layer rules |
| `WindowRulesPage.qml` | windowrules | **R** | compositor window rules |
| `AppOverridesPage.qml` | appoverrides | **R** | compositor overrides |
| `InputPage.qml` | input | **R** | compositor input + `/etc/vconsole.conf` |
| `KeybindsPage.qml` | keybinds | **R** | Hyprland binds (rebinds.lua) |
| `DisplaysPage.qml` | displays | **R** | compositor outputs + `$RYOKU_MONITORS_DIR` |
| `SessionPage.qml` | session | **R** | compositor autostart/env |
| `GpuPage.qml` | gpu | **R** | `gpu.lua` + `/sys` via `ryoku-power` |
| `LockscreenPage.qml` | lockscreen | **R** | `/etc/pam.d/sddm`, sddm theme, qylock |
| `ConnectionsPage.qml` | connections | **R** | NM/BlueZ/hotspot; `pkexec` |
| `DictationPage.qml` | dictation | **R** | voxtype config + unit + models |
| `FastfetchPage.qml` | fastfetch | **R** | `config.jsonc` + shell rows (terminal) |
| `AddonsPage.qml` | addons | **R** | `plugins.json` + `ryostore` |
| `PluginsPage`/`StoreWidgetCard` | addons/widgets helper | **R** | `plugins.json` / store widget |
| `RecordingPage.qml` | recording | **R** | `keypresses.json`, `recording.json` |
| `UpdatesPage.qml` | updates | **R** | `hub.toml` update_interval |
| `ProfilePage.qml` | profile | **R** (or **O** if a profile switcher is wanted) | profile switching; not appearance/shell |
| `RashinPage.qml` | rashin | **R** | AI tool config |
| `ImportPage.qml` | import | **R** | rice import (`ryoku-hub import`) |
| `HeroEditor.qml` | — helper | **K\*** (only if DesktopPage keeps a hero editor) | edits `brand`/`viz` — pure shell |
| `LightingTab.qml` | — helper | **R** | OpenRGB |
| `ProfileToolbar.qml` | — helper | **O** | nav chrome; unused if ProfilePage cut |
| `StoreWidgetCard.qml` | — helper | **R** | store widget |

---

## 3. Bloat found

1. **Duplicate `NotificationServer`** (§1.1) — two servers, one foreign cache file.
2. **QML paths that ignore `XDG_CONFIG_HOME`** in kept modules (§1.6) — a confinement
   hole plus stale Quickshell-Rise cache files (`qs-rise-notifications.json`,
   `quickshell_widgets_v2`, `quickshell_barorder_v2`, `quickshell-scan-*`,
   `qs-reactor-event`).
3. **11 bundled display fonts (366 KB)** shipped only to populate a widget-font
   picker that the kept set does not use.
4. **Heavy decorative art** in kept-adjacent paths: `hands-adam.png` 682 KB, Hub art
   ~1.7 MB (`dither-torii` 599 KB, `roots.png` 765 KB, three tiling GIFs 332 KB),
   `welcome-bg.png` 1.2 MB.
5. **Three bar styles** (`kairos`, `qsbar`, `sumi`) where the keep-list names one.
6. **Off-list modules shipped whole**: overview, dock, visualiser, clipboard, capture,
   stage, and the desktop widget family (aio/notes/stats/music/weather/calendar/clock).
7. **Absolute scratch paths**: `/tmp/ryoku-hub.lock`, `/tmp/ryoku-screenrecord-filename`
   (and other `/tmp/ryoku-*.lock`s) — escape `$MEI_DIR`.
8. **Dead code/paths**: `ryoku-pill.sock` (dead), `uv` dependency, the AI usage /
   clamshell / eq / idle units.
9. **`curl` + outbound network** for weather/music/holidays/updates/rices — none KL.
10. **`pkexec` write paths** in Connections/Gpu/Lockscreen pages — system mutation.
11. **245 MB wallpaper set + 4 MB ryodecors** as seeded *content* in `ryoku/assets`.
12. **`ryoku-eq`** (pipewire filter chain) — a second pipewire instance for an EQ.

## 4. Opted out — can re-enable later

Each is off by default but reachable without re-architecting:

* **Live video wallpaper** (`ryogami-live`) — set a clip (or `video_enabled`).
* **Depth cut-out** — `ryogami depth set <map>`.
* **Palette bridge** (browser/app theming) — run the bridge + install the Zen/vesktop/
  spicetify integrations (loopback only).
* **Dock**, **Overview**, **audio visualiser**, **clipboard history**, **screenshot/
  capture**, **media/MPRIS widgets**, **desktop widgets** (widgets.json), **notes**,
  **stats/sysinfo panels**, **Bluetooth sidebar**.
* **Kairos / Sumi bar styles** (keep `qsbar` on).
* **Theme fan-out to apps** — add a Mei matugen template with an **absolute
  `~/projects/mei/.run/...` output** (never `~/.config`).
* **Performance page / `performance.json` knobs** (low-power, reduce-motion, ambient
  bar motion) — the shell already reads them; enabling the page is only UI.
* **Credits page** — re-add as a nav page, or keep the text as a notice.
* **Polkit agent** — set `MEI_POLKIT_AGENT=1` (nested/isolated only).
* **Keyring prompter**, **power-profiles**, **nightlight**, **weather**, **holidays**,
  **updates**, **music** — restore the topic + surface if wanted (weather/holidays/
  updates re-introduce the corresponding network calls, per Q4).

## 5. Uncertain / must be settled in Phase 4

| Item | Why uncertain | Action |
|---|---|---|
| Winner of the duplicate `NotificationServer` | needs a build to observe D-Bus arbitration | build once; assert `services/Notifs.qml` owns the name |
| Exact `ryogami` config key to force a static/no reveal | `transitionKinds`/presets read but the per-wallpaper key name not pinned | read `store.go`/`verbs.go` during integration |
| Whether any kept surface reads `hypr-colors.lua` | no reader found in the kept modules, but the frame may read it via a path not grepped | assert in Phase 6; default REMOVE |
| `inotifywait` requirement | ryogami watch code not fully traced | trace `watch.go`/`restore_watch.go` |
| RAM/CPU of every row above | nothing built/run | Phase 8 measurement |
| Icon-set licence | no LICENSE/README in `components/icons/` | resolve before redistribution |
| `Inter` usage by *kept* Settings pages | previews are for cut widget previews | keep only if a kept page renders it |
| `XDG` confinement of QML `HOME`-paths | needs runtime check | close in Phase 6, prove in the acceptance test |

---

## 6. Licensing & credits

### 6.1 Ryoku itself

* Root `LICENSE` = **GNU General Public License** (`LICENSE:1`); `NOTICE` states
  "distributed under the GNU General Public License version 3"; credit lines assert
  GPL-3 compatibility. Treat as **GPL-3.0-or-later** `[READ]`.
* `NOTICE` records derived work: **Caelestia** (frame-blob rendering + parts of the
  motion/animation curves) — **GPL-3**; **DankMaterialShell** (display-config UI
  portions) — **MIT**, © 2025 Avenge Media LLC; **OkShell** (frame-bar layout /
  rail-widget catalogue / Bar Studio workflow) — **GPL-3**. All adapted portions stay
  GPL-3-compatible.
* Ryoku's alpha series began as a fork of **Omarchy** (DHH) but the `NOTICE` states no
  Omarchy code/assets remain from the beta series on `[READ]`.

### 6.2 Third-party licences in the kept set

| Component | Licence | Source |
|---|---|---|
| `github.com/godbus/dbus/v5` (deb) | BSD-2-Clause (`vendor/.../LICENSE`) | vendored in `ryoku/shell/ipc` + `ryoku/hub/backend` |
| `golang.org/x/sys` (deb) | BSD-3-Clause | vendored |
| `github.com/BurntSushi/toml` (hub) | MIT | `hub/backend/go.mod` |
| `ryoku-wm`, `ryostore` (in-repo modules) | GPL-3 (Ryoku's own) | `replace` in go.mod |
| `palette-bridge/` | **MIT** (`palette-bridge/LICENSE:1`) | separate component |
| Fonts (`ttf-jetbrains-mono-nerd`, `inter-font`, `noto-fonts`, `noto-fonts-cjk`, `noto-fonts-emoji`, `otf-space-grotesk`, `ttf-fraunces-variable`) | **SIL OFL 1.1** (upstream packages; not vendored, installed system-wide) | Arch/AUR packages |
| `ttf-material-symbols-variable` (Material Symbols) | **Apache-2.0** | Arch package |
| `components/icons/` 152 SVGs | **unknown — no licence file in tree** | `[UNVERIFIED]` — **redistribution flag** |
| 11 bundled display fonts (366 KB) + `archivo-black.ttf` | **no licence file shipped in the repo** | **redistribution flag** — do not redistribute until resolved; personal use only |
| `qylock` lockscreen | GPL-3.0 (Darkkal44) — **NOT kept** | credit only |
| `caelestia` shell | GPL-3.0 — **adapted, credited** | credit |
| `dusky` | recolor templates + motion presets — credited | credit |
| `rishot`, `cava-bg`, `Brain_Shell`, `ActivSpot`, `hyprmod`, `inotify`, `noctalia`, `DankMaterial`, `Omarchy`, `CachyOS`, `Ricelin`, `nixos-configuration`, `dotfiles`, `NibrasShell`, `skwd-wall` | credited in `CreditsPage.qml:23-56` | credits |

### 6.3 Credits to preserve

The **20 projects + 7 testers** in `CreditsPage.qml:23-56` (qylock/Darkkal44,
caelestia/caelestia-dots, dusky/dusklinux, OkShell/John Oberhauser, rishot/Gakuseei,
cava-bg/leriart, Brain_Shell/Brainitech, ActivSpot/Devvvmn, hyprmod/BlueManCZ,
dotfiles/matteogini, inir/snowarch, noctalia/noctalia-dev, DankMaterial/AvengeMedia,
Omarchy/DHH, CachyOS, Ricelin/Gakuseei, nixos-configuration/ilyamiro,
dotfiles/Jules3182, NibrasShell/Ahmed Saadi, skwd-wall/liixini; testers bhimio1,
povargg, godspeed1709, VortexVirus, Lowingx, ΛVΛLON, JaviBOT96). Also the
`AGENTS.md`/`NOTICE` obligations: keep `NOTICE`, `CHANGES.md`, `UPSTREAM.md`, the GPL
header, and the Ryoku name/attribution. **The QS Bar / "Quickshell Rise" lineage**
(the `qs-rise-*` cache names, the "pill" comments in `shell.qml`) is a heritage to
credit — `[UNVERIFIED]` whether it is the Caelestia line or a separate source;
resolve against `CreditsPage`/NOTICE before publishing.

### 6.4 Redistribution obligations (flag)

* **GPL-3.0**: if Mei is distributed (binaries or source), it must ship the full
  corresponding source + the GPL text + notices. Personal/private use has no such
  obligation, but the licence still applies to any sharing.
* **Bundled fonts + icon set**: **no licence files in the tree** — treat as
  non-redistributable until resolved; if Mei is only used locally this is moot.
* **MIT/BSD vendored Go code**: keep their LICENSE files (already vendored).
* Keep `UPSTREAM.md` (pin `98a0368`, v0.75.5-beta.20) and `CHANGES.md` current with
  every modification from here on.

---

## 7. Proposed Mei settings-page list

Keep the Ryoku Hub look/UI framework; ship **only** Appearance + Shell, and **never
write compositor config**. Persist to Mei's config dir only (`$MEI_DIR/.run/config/mei`).

| Kept page | Nav label | What it writes (Mei's own config only) | Source |
|---|---|---|---|
| **Global** | General | `mei/shell.json`: `language`, `locale`, timezone display, `fontFamily`, weather location **fields** (no fetch) | `schema/GlobalPage.js` (shell rows) |
| **Desktop** | Appearance | `mei/brand.json` + `mei/visualizer.json` (`viz` keys) + `mei/shell.json` appearance keys; wallpaper pick via the wallpaper surface | `schema/DesktopPage.js` |
| **Bar Studio** | Bar | `mei/shell.json` (bar style/layout, widget placement) | `BarStudioPage.qml:215-217` |
| **Launcher** | Launcher | `mei/launcher.json` | `schema/LauncherPage.js` |
| **Animations** | Motion | `mei/shell.json` → `theme.motion.scale`, `theme.motion.reduce` only | `AnimationsPage.qml:154-159` |

Optional (disabled by default, discussed): **Widgets** (`mei/widgets.json`),
**Performance** (`mei/performance.json`), **Credits** (read-only informational).

**Cut (24 + 4 helpers)** — every compositor editor
(`windowmanager`, `plugins`, `layerrules`, `windowrules`, `appoverrides`, `input`,
`keybinds`, `displays`, `session`, `gpu`, `lockscreen`), plus the off-list
non-compositor pages (`connections`, `dictation`, `fastfetch`, `addons`, `recording`,
`updates`, `profile`, `rashin`, `import`) and the four helper components
(`HeroEditor` only if the hero editor is kept, else cut; `LightingTab`,
`ProfileToolbar`, `StoreWidgetCard` cut).

**Severed machinery (do not vendor the writing half):** the Hub `save()/preview()/
restore()` compositor-draft chain (`Hub.qml:696-723,889-996`), the
`desktop save|preview|restore|scheme|anim-preset` verbs, `wm/hyprland` +
`wm/niri` write paths (`settings.lua`/`rebinds.lua`/`settings.kdl`/`rebinds.kdl`),
`hyprctl reload`, cursor/plugins/shellpref writes (`docs/02-deps/04-settings.md`
§"The Hyprland write path to sever"). Mei keeps the **read-only** compositor state
(`Settings.windows`, `Settings.configFiles`).

The vendored Settings UI framework is the Hub's QML shell + `Ryoku.Ui` (both kept);
only its page registry, schema files, and backend verbs are trimmed.

---

## 8. Carried into Phase 4 (plan) / Phase 6 (build)

1. **Daemon trim** (Q2 + §2.1): keep `wm`, `network`, `tray`, `settings`, `wallpaper`,
   `audio`, `brightness`, `menu`/`bar`/`barstyle`, surface ids; drop weather/calendar/
   music/updates/stage/plugin(s)/browser-host/clipboard/Voxtype + their spawns and
   network calls.
2. **Sever the Hyprland write chain** (§7) and drop the `desktop save|preview|restore`
   verbs + niri twins.
3. **Rename/redirect** per Q5; generate the minimal Mei `matugen/config.toml` (§1.3).
4. **Fix the duplicate `NotificationServer`** → keep `services/Notifs.qml`, reduce the
   qsbar panel (§1.1).
5. **Close the XDG confinement gap** for QML `HOME`-paths (§1.6) before the acceptance
   test.
6. **Keep `ryogami`**; live video + depth off by default (§1.5, Q7).
7. **Dependencies to approve in Phase 4** (exact commands, per `AGENTS.md` rule 2):
   `go`, `cmake` (+ existing `ninja`), the font packages
   (`ttf-material-symbols-variable`, `noto-fonts-cjk`, `ttf-jetbrains-mono-nerd`,
   `otf-space-grotesk`, `inter-font`, `ttf-fraunces-variable`), and the Qt shadertools
   path if built from source. **Not** `uv`.
8. **Settings page registry**: 5 kept pages + optional Widgets/Performance/Credits;
   sever all compositor writes; persist only under Mei's config dir.

No code has changed. Awaiting approval before Phase 4.
