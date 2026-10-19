# docs/02b-gaps.md — two items `docs/02-deps.md` did not contain

Phase 3 was asked to confirm that `docs/02-deps.md` holds (a) a mapping of **all**
Settings pages to what each writes, and (b) the **full list of daemons/processes the
kept features need, with a process count**. Neither was present:

* (a) `docs/02-deps/04-settings.md` covered the keep-list pages and the must-remove
  pages, but **12 of the 32 page files were never named** (AddonsPage, ConnectionsPage,
  CreditsPage, DictationPage, FastfetchPage, HeroEditor, ImportPage, LightingTab,
  ProfilePage, ProfileToolbar, RecordingPage, UpdatesPage). It also did not map every
  page to its write target.
* (b) there was no consolidated process table and no process count anywhere.

This file supplies both, from file-level reads of the pinned upstream. Nothing here
re-traces what `docs/02-deps.md` already answers; it is strictly additive.

Scope note: the request said "31 Settings pages". The pinned tree actually contains
**32** `.qml` files under `ryoku/hub/quickshell/pages/`. Of these, **28 are navigable
pages** (the `pageFile` map in `Hub.qml:491` plus `global`, `import`, `windowmanager`)
and **4 are helper components** that are not nav destinations (HeroEditor,
LightingTab, ProfileToolbar, StoreWidgetCard). All 32 are classified below.

---

## Gap A — every Settings page file and what it writes

Method. For each page the write target was read from two on-disk sources:

1. the page's own code (`Settings.patch`, `FileView { path }`, `Process { command }`,
   `ryoku-hub <verb>`, `ryoku-plugins-place`, `ryostore`, `localectl`, `nmcli`, `pkexec`);
2. the shipped search schema `ryoku/hub/quickshell/schema/<Page>.js`, whose free-text
   `"src"` fields name exactly what the page persists (they are descriptive strings,
   not structured keys, but they are authoritative and in-tree).

`[READ]` throughout. "Compositor" means the write lands in Hyprland/Niri generated
config (the `settings.lua`/`rebinds.lua` chain severed for Mei, see `docs/02-deps.md`
Q4 and the `Hub.qml:696-723 → hub/backend/desktop.go → wm/hyprland/apply.go` chain).

| # | Page file | Nav id | What it writes (target — mechanism) | Evidence |
|---|---|---|---|---|
| 1 | `AddonsPage.qml` | `addons` | `~/.config/ryoku/plugins.json` — `ryoku-plugins-place <id> enabled\|host\|settings`; also `ryostore install\|remove`, `ryostore internal install-guest\|remove-guest`, `ryostore open plugins\|bundles` | `schema/AddonsPage.js` |
| 2 | `AnimationsPage.qml` | `animations` | **Compositor** `desktop.json` (Hyprland animation curves) via `ryoku-hub desktop defaults` / `Settings.patch` | `schema/AnimationsPage.js` |
| 3 | `AppOverridesPage.qml` | `appoverrides` | **Compositor** `desktop.json` (per-app override rules) | `schema/AppOverridesPage.js` |
| 4 | `BarStudioPage.qml` | `bar-studio` | `~/.config/ryoku/shell.json` (bar style/layout) — `FileView` write; the gallery reads `ryostore catalog --category barstyles` | `BarStudioPage.qml:215-217`; `schema/BarStudioPage.js` |
| 5 | `ConnectionsPage.qml` | `connections` | **No Ryoku config.** Hosts `WifiTab`/`BluetoothTab`/`HotspotTab`: NetworkManager profiles (`nmcli connection add\|modify`), BlueZ adapter `enabled` over D-Bus, `rfkill unblock bluetooth`; uses `pkexec /usr/bin/ryoku-network-kill` and `ryoku-wifi-backend` | `ConnectionsPage.qml:69,95,687,809,1496`; `schema/{WifiTab,BluetoothTab,HotspotTab}.js` |
| 6 | `CreditsPage.qml` | `credits` | **Nothing** (static credit list only) | `CreditsPage.qml:23-56` |
| 7 | `DesktopPage.qml` | `desktop` | `brand.json`, `shell.json`, `viz` keys — `Settings.patch` (and hero image via `HeroEditor`) | `schema/DesktopPage.js` |
| 8 | `DictationPage.qml` | `dictation` | voxtype `config.toml` (`[whisper]`, mode 0600), whisper model files, `systemctl --user enable\|disable --now voxtype.service`; verb `ryoku-hub voxtype` | `schema/DictationPage.js` |
| 9 | `DisplaysPage.qml` | `displays` | **Compositor** `desktop.json` + `monitors-applied.json` + `<name>.json` under `$RYOKU_MONITORS_DIR` + `shell.json`; `ryoku-hub outputs profiles` | `schema/DisplaysPage.js` |
| 10 | `FastfetchPage.qml` | `fastfetch` | `config.jsonc` — `ryoku-hub fastfetch save\|preview\|get`; also `shell.json` | `schema/FastfetchPage.js` |
| 11 | `GlobalPage.qml` | `global` | `shell.json` (language/locale/timezone/font/weather location); shells out to `timedatectl`, `fc-list`, `systemctl --user restart ryoku-shell.service` | `schema/GlobalPage.js`; `GlobalPage.qml:78,83` |
| 12 | `GpuPage.qml` | `gpu` | `~/.config/ryoku/gpu-presets.json`, **Compositor** `gpu.lua`, `power.json`; `ryoku-power aspm\|charge-limit\|profiles` (writes `/sys`), `ryoku-hub gpu\|cpu set` | `schema/GpuPage.js` |
| 13 | `HeroEditor.qml` | — helper | No write of its own; edits the `brand`/`viz` hero fields surface of `DesktopPage` | `pages/HeroEditor.qml` |
| 14 | `ImportPage.qml` | `import` | `ryoku-hub import` (rice materialize/import), `Settings.configFiles`, `Settings.provider` | `schema/ImportPage.js`; `ImportPage.qml` |
| 15 | `InputPage.qml` | `input` | **Compositor** `desktop.json` + `shell.json`; `/etc/vconsole.conf` via `localectl set-x11-keymap` | `schema/InputPage.js` |
| 16 | `KeybindsPage.qml` | `keybinds` | **Compositor** Hyprland binds — `ryoku-hub keybinds`, `ryoku-hub apps`, `ryoku-hub shell get`; submap verbs `wmAct("submap.*")` | `KeybindsPage.qml:63,82,98,330` |
| 17 | `LauncherPage.qml` | `launcher` | `launcher.json` | `schema/LauncherPage.js` |
| 18 | `LayerRulesPage.qml` | `layerrules` | **Compositor** layer rules via `Settings.modelsKey("wm.hyprland.layerRules")` (compositor draft) | `LayerRulesPage.qml:37,406` |
| 19 | `LightingTab.qml` | — helper | OpenRGB lighting via `ryoku-hub lighting` (OpenRGB SDK); not a nav page | `pages/LightingTab.qml`; `hub/backend/lighting.go` |
| 20 | `LockscreenPage.qml` | `lockscreen` | `~/.config/ryoku/keyring.json`, `/etc/pam.d/sddm` (pam_gnome_keyring), sddm theme `99-ryoku.conf`; `ryostore open lockscreens` | `schema/LockscreenPage.js` |
| 21 | `PerformancePage.qml` | `performance` | `performance.json` (shell `Perf.qml` policy: motion + `disabledComponents`) | `schema/PerformancePage.js` |
| 22 | `PluginsPage.qml` | `plugins` | **Compositor** Hyprland plugin list — `ryoku-hub desktop plugins list` (patches `desktop.json`) | `PluginsPage.qml:232` |
| 23 | `ProfilePage.qml` | `profile` | No file write found. Probes machine-id/pacman log; profile switching flows through `ryoku-hub profile` | `ProfilePage.qml:47`; `hub/backend/profile.go` |
| 24 | `ProfileToolbar.qml` | — helper | **Nothing** (nav toolbar chrome) | `pages/ProfileToolbar.qml` |
| 25 | `RashinPage.qml` | `rashin` | AI tool config; reads `$XDG_RUNTIME_DIR/ryoku-rashin/setup.json`; `ryoku-rashin status\|paths` | `RashinPage.qml:98,150,195` |
| 26 | `RecordingPage.qml` | `recording` | `keypresses.json`, `recording.json` | `schema/RecordingPage.js` |
| 27 | `SessionPage.qml` | `session` | **Compositor** `desktop.json` (autostart/env) | `schema/SessionPage.js` |
| 28 | `StoreWidgetCard.qml` | — helper | `plugins.json` via `ryoku-plugins-place` (store widget preview card) | `schema/StoreWidgetCard.js` |
| 29 | `UpdatesPage.qml` | `updates` | `hub.toml` `[ui] update_interval` | `schema/UpdatesPage.js` |
| 30 | `WidgetsPage.qml` | `widgets` | `widgets.json` via `ryoku-plugins-place` | `schema/WidgetsPage.js` |
| 31 | `WindowManagerPage.qml` | `windowmanager` | **Compositor** provider settings (`Settings.provider`) — the Hypr/Niri apply chain | `WindowManagerPage.qml:25` |
| 32 | `WindowRulesPage.qml` | `windowrules` | **Compositor** `desktop.json` window rules | `schema/WindowRulesPage.js` |

Schema-only helpers that are **not** page files but live in the same folder and feed
pages (listed so the folder is fully accounted for): `BluetoothTab.js`, `HotspotTab.js`,
`WifiTab.js` (used by `ConnectionsPage`), `ThemeCatalog.js`, `WindowSettings.js`
(compositor window settings), `PluginPlacementEditor.js` (used by `WidgetsPage`/plugins).

Net: of the 28 nav pages, **24 write only** — or compose through — **Hyprland/Niri
config, hardware, or off-keep-list subsystems**. Only the following touch files that
are (or could be) Mei's own shell config: `GlobalPage`, `DesktopPage`, `BarStudioPage`,
`LauncherPage`, `WidgetsPage`, `PerformancePage` (all under `~/.config/ryoku/*.json`).
This matches the Phase 2 finding and is carried into `docs/03-classification.md`.

---

## Gap B — daemons/processes the kept features need, with a process count

Derived from `exec.Command` inventories and the supervision code:
`grep exec.Command ryoku/shell/ipc/*.go`, `ryoku/shell/ryogami/daemon/*.go`,
`ryoku/shell/ipc/daemon.go:23-45` (persistent components), `daemon.go:430-461`
(what starts at boot), `daemon.go:761` (the `qs` spawn). `[READ]`

### Resident (steady-state) processes for the keep-list

| # | Process | Count | Role | Started by | Keep? |
|---|---|---|---|---|---|
| 1 | `ryoku-shell daemon` (Go) | **1** | single control plane: owns the Unix socket, all state topics, supervises the Quickshell surface(s) | Mei launcher (or a `mei-*` unit) | **essential** |
| 2 | `qs -c shell` (Quickshell) | **1** | the one consolidated surface process — renders bar, launcher, sidebar/control-centre, notifications, OSD, tray host | spawned and respawned by #1 (`daemon.go:761`, `components` = `{"shell", true}`) | **essential** |
| 3 | `ryogami` (Go) | **1** | wallpaper daemon (still image, palette hand-off to #1) | Mei launcher / own unit (`ryoku/shell/systemd/user/ryogami.service`) | **essential** |
| | **Subtotal, kept core** | **3** | | | |

### Conditionally resident (depends on keep decisions)

| # | Process | Count | Role | Notes |
|---|---|---|---|---|
| 4 | `wl-paste --watch <self> __clip-ingest` | 1 if clipboard kept | clipboard-history ingestion | started unconditionally by `daemon.go:432` → `clipboard.go:689`, **not on the keep-list**; Mei's trimmed daemon must skip it or accept the extra process |
| 5 | `ryogami-live` (in-repo C player) | **0 for still images**, one per live output for video walls | decodes a pre-transcoded clip into `wl_shm` | `livewall.go` header reports ~40–60 MB RSS per player `[REPORTED upstream comment]`; not resident when the wallpaper is a still |
| 6 | `pipewire` EQ filter chain (`ryoku-eq`) | 0 | audio equaliser | off-keep-list; separate unit `ryoku-eq.service` |

### Transient / on-demand (0 resident)

`matugen` (palette extraction `--json hex --dry-run` + optional template pass),
`ryoku-hub` (one-shot per Settings action), `qs -c hub` (Settings window while open),
`ffmpeg` (ryogami clip transcode; daemon luminance/thumbnail steps),
`ryoku-hw-backlight` / `ryoku-cmd-brightness` / `brightnessctl` (brightness — small
steps + restore), `pactl` / `wpctl` (audio — small steps + restore), `nmcli` / `iw` /
`ip` (network status reads), `wl-copy` (clipboard write, only if clipboard kept),
`pkexec` (only reached from **cut** pages: Connections, Gpu, Lockscreen).

### Explicitly NOT needed for the keep-list

`ryoku-idle` (idle/auto-lock), `ryoku-clamshell` (lid), `ryoku-ai-usage`,
`ryoku-bootstrap` (one-shot materialize), `ryoku-palette-bridge` (browser/app theming),
`voxtype` (dictation), `ryoku-rashin` (AI), `ryoku-qylock` (lockscreen),
`ryoku-power`/`ryoku-power-cutover` (power profiles), `ryoku-network-kill`.

### systemd units in the tree (`ryoku/shell/systemd/user/`)

`ryoku-shell.service`, `ryogami.service`, `ryoku-idle.service`,
`ryoku-clamshell.service`, `ryoku-eq.service`, `ryoku-ai-usage.service`,
`ryoku-bootstrap.service`, `ryoku-session.target`, plus
`ryoku/palette-bridge/packaging/systemd/ryoku-palette-bridge.service`.
**Mei needs none of them**: its launcher starts `ryoku-shell` (→ which spawns
`qs -c shell`) and `ryogami`, and nothing else. For the record, the upstream unit
sets two env vars the daemon cares about — `RYOKU_POLKIT_AGENT=1` (polkit agent
registration) and `QT_MEDIA_BACKEND=ffmpeg` — and Mei deliberately sets **neither**
(see `docs/03-classification.md`, open item 2).

### Count for the kept core

**3 resident processes** (`ryoku-shell`, `qs -c shell`, `ryogami`) + 1 transient
`matugen` on each palette change + 1 transient `ryoku-hub`/`qs -c hub` when Settings
is open. Everything else is either off the keep-list or spawned only by an action.
