# 02 — Phase 2: dependency map

Read-only dependency mapping of the pinned upstream (`Ryoku` `98a0368`, v0.75.5-beta.20)
for the Mei keep-list. **No code was changed, nothing was built, nothing was installed.**
Nothing outside `~/projects/mei` was touched.

Raw per-area traces live in `docs/02-deps/*.md` (written by read-only trace agents);
this document is the consolidated report: the seven required resolutions first, then the
per-feature maps in full.

Labels: `[TESTED]` = a command I ran in this session; `[READ]` = read from upstream source;
`[UNVERIFIED]` = inferred/uncertain. Nothing here is `[TESTED]` for *runtime* behaviour —
the shell has not been built or run (that is Phase 4+).

## Keep-list under test

Top bar (`qsbar`) + workspaces · launcher · Super+Escape control sidebar / quick settings ·
clock/date · audio · brightness · network · battery · system tray · notifications ·
wallpaper + matugen · trimmed `ryoku-shell` daemon · Settings (appearance + shell pages only).

---

## Resolutions

### Q1 — Who invokes matugen on wallpaper change, and what it writes

**The `ryoku-shell` Go daemon runs matugen — not `ryogami`, and not the QML.** `[TESTED]`

- Exec site: `ryoku/shell/ipc/matugen.go:775` → `exec.Command("matugen", args...)`.
- Arg builder: `matugen.go:157 matugenArgs(img, knobs, mode)`.
- Trigger chain `[READ]`:
  1. `ryogami` publishes the `wallpaper` topic on `$XDG_RUNTIME_DIR/ryogami.sock`.
  2. The daemon mirrors it (`ryoku/shell/ipc/ryogami.go`).
  3. `theming.go:157 scheduleTheme()` → `theming.go:171 paintWorker()`.
  4. `matugen.go:556 matugenApply(img)` (wallpaper-driven) or
     `matugen.go:681 matugenApplyStatic(name)` (fixed scheme).
  - Manual paths: `daemon.go:1336 matugenReload(args[1])` and CLI `matugen-preview`
    (`main.go:57`).
- Two passes `[READ]`: `matugen image … --json hex --dry-run` to read roles, then
  `matugen -c <filtered config> json <carrier>` to render templates
  (`matugenRenderTemplates`, `matugen.go:1145`).

**What it writes** `[READ]`:

| Path | Author | Purpose |
|---|---|---|
| `~/.cache/ryoku/colors.json` | **the daemon's Go code** (`matugen.go:~573`; comment `matugen.go:48-51` "the plane owns `colors.json` and matugen fans it out") | the one file every QML `Scheme`/`Theme`/`Tokens` singleton watches |
| `~/.cache/ryoku/tones.json` | daemon | tonal ramp |
| `~/.cache/ryoku/hypr-colors.lua` | matugen template `[templates.hypr]` | **cache only** — the Hyprland colour accents, read by the frame; NOT written into the Hyprland config dir |
| `~/.config/kitty/current-theme.conf`, `~/.config/btop/themes/ryoku.theme`, `~/.config/qt6ct/colors/ryoku.conf` | matugen templates | terminal/btop/qt6ct theming |
| `~/.cache/ryoku/{share-picker.css,kdeglobals-colors.conf}` | matugen templates | misc |

> **Phase 6 finding:** `ryoku/shell/matugen/config.toml` uses **literal `~/.config/...`
> paths** (`config.toml:12,16,20,31`), not `$XDG_CONFIG_HOME`. Redirecting
> `XDG_CONFIG_HOME` alone will **not** confine matugen's outputs; Mei must generate its own
> `matugen/config.toml` (templates + outputs point into `~/projects/mei/.run/...`).
> Good news: the Hyprland-colour template targets `~/.cache/...`, so matugen does **not**
> write Hyprland config.

### Q2 — The `ryoku-shell` IPC verb list, and which verbs each kept feature calls

Transport `[READ]` (`statestream.go:20-34`): one AF_UNIX socket carries
`subscribe <topic>` (state, daemon→QML) and `call <topic>.<method> <json>` (intent,
QML→daemon). The socket path is `$XDG_RUNTIME_DIR/ryoku-shell.sock` (`main.go:18-20`).
The shell talks to it via `modules/bar/barstyles/qsbar/core/IpcRouter.qml`, and spawns
`ryoku-shell <surface-id>` to open surfaces (`shell.qml:451,507,780`).

**Dispatch verbs** (`daemon.go`, `grep 'case "'`): `menu`, `bar`, `dock`, `voice`,
`barstyle`, `lock-quiesce`, `lock`, `unlock-prepare`, `sleep-ready`, `suspend`,
`suspend-cancel`, `audio`, `brightness`, `hub`, `stage` (+ `set-effect`, `refresh`,
`cancel`, `status`, `models`, `cut-layer`, `set-layer`, `add-layer`, `remove-layer`,
`clear`), `theme`, `gtk`, `reload`, `status`, `ping`, `signature`, `quit`, `plugin`,
`plugins`, `state`, `sound`, plus a `qs` passthrough. `[TESTED]`

**Surface-id map** (`daemon.go:986-1003`): `launcher`, `wallpaper-menu`→`wallpaper`,
`clipboard`, `stash`, `visualizer`, `menu app-launcher`→`launcher`, … `[READ]`

**State topics** registered with `registerTopic()` `[TESTED]`: `calendar`, `clipboard`,
`music`, `network`, `nightlight`, `osd`, `polkit`, `powerprofiles`, `settings`, `stage`,
`tray`, `updates`, `weather`, `wm`.

**CLI surface** (`main.go`) `[READ]`: `daemon`, `__clip-ingest`, `theme catalog`,
`matugen-preview`, `icons`, `browser-host`, plus any dispatched verb forwarded to the daemon.

**Mapping — kept feature → verb/topic:**

| Kept feature | Daemon verb | Daemon topic | Notes |
|---|---|---|---|
| top bar / frame | `bar`, `barstyle`, `menu`, `state`, `sound` | `wm` | frame model + menus |
| workspaces | — | `wm` | via the compositor provider |
| launcher | surface-id `launcher`; `menu` | — | |
| control sidebar | surface-id; `theme` | `settings`, `network`, `tray` | quick settings |
| clock/date | — | — (calendar = holidays, off-list) | local `Clock` |
| audio | `audio` | — | in-process: PipeWire/`AudioData.qml` |
| brightness | `brightness` | — | shell-out: `ryoku-cmd-brightness` → `brightnessctl` (needs backlight write access: udev rule or `video` group) |
| network | — | **`network`** | status is a daemon topic |
| battery | — | — | in-process: UPower |
| system tray | — | **`tray`** | |
| notifications | — | — | in-process: Quickshell NotificationServer |
| wallpaper | surface-id `wallpaper` | **`wallpaper`** (from `ryogami`) | |
| matugen theming | `theme` (+ CLI `matugen-preview`) | `settings` | palette out = `colors.json` |
| Settings (appearance/shell) | `hub`, `settings.patch`, `reload`, `reload-cover` | `settings` | must not reach `desktop save` (§Q5/§04) |

**Important:** audio, battery and notifications have **no** daemon topic/verb — they are
Quickshell in-process services (PipeWire, UPower, the NotificationServer). Network and tray
**are** daemon topics. That determines what a trimmed daemon must still own.

### Q3 — Assets needed from the excluded dirs (`ryoku/assets` etc.)

**Essentially none for code.** `[READ]` (fragment `06`)

- No runtime QML under `ryoku/shell/quickshell/**`, `ryoku/hub/quickshell/**` or `ryoku/ui/**`
  reads a file under the off-disk `ryoku/assets/`.
- The only off-disk brand files that matter are the **desktop-entry logos**:
  `ryoku/assets/logo.svg` + `logo-mark.svg` = **1,146 B total**.
- The referenced brand set totals **440,167 B**; that is the real ceiling if every branded
  image were copied.
- `ryoku/assets/wallpapers/` (**245,026,989 B**) and `ryodecors/` (4,165,851 B) are **seeded
  content**, referenced by the wallpaper browser (a live source), not by code paths Mei keeps.

So: ship nothing from `ryoku/assets` except the two logos (or Mei's own). All kept UI art
(`qsbar` assets/shaders, `launcher`'s `hands-adam.png`, `ui/grain.png` + shaders, icons,
the 11 bundled fonts, `hub/quickshell/fonts/archivo-black.ttf`) is already **on disk** in the
sparse checkout.

### Q4 — Network call inventory

Every endpoint found in the daemon, shell, hub and palette-bridge, tied to its feature.
**None of the outbound calls below is on the keep-list** (the only keep-list "network" is the
loopback palette bridge). `[TESTED]` for the greps; feature mapping `[READ]`.

| Endpoint | Where | Feature | On keep-list? |
|---|---|---|---|
| `api.open-meteo.com`, `geocoding-api.open-meteo.com`, `air-quality-api.open-meteo.com`, `ipwho.is` | `ipc/weather.go:38-41` | weather topic | ❌ disable |
| `lrclib.net` (×2), `api.deezer.com`, `itunes.apple.com`, `i.ytimg.com`, `i.scdn.co` | `ipc/music.go:37-40,634,677-679` | music lyrics/art | ❌ disable |
| `nagerholidays.com` | `ipc/calendar.go:19` | calendar/holidays | ❌ disable |
| `api.open-meteo.com` + `ip-api.com` (direct curl) | `modules/launcher/shared/Singletons/Weather.qml:57,150` | launcher weather | ❌ disable |
| `api.duckduckgo.com` + `duckduckgo.com` web engines | `modules/launcher/shared/providers/web/*` | launcher web search | ❌ disable |
| `speed.cloudflare.com` | shell QML (speed test) | network page speed test | ❌ disable |
| `litterbox.catbox.moe` | `quickshell/ryoshot/shell.qml:854` | screenshot upload | ❌ excluded surface |
| `api.openai.com` | `hub/backend/voxtype.go:243`, `hub/quickshell/schema/DictationPage.js:52` | dictation | ❌ disable |
| `github.com` (rices/plugin fetch) | `hub/backend/ricepublish.go:92`, `PluginsPage.qml:527` | rices/plugins | ❌ disable |
| `aur.archlinux.org`, `wiki.archlinux.org`, `www.npmjs.com`, `www.shadertoy.com` | shell/hub QML | updates / visualizer shaders | ❌ disable |
| `127.0.0.1:47616` palette bridge | `palette-bridge/*`, `hub/backend/palettebridge.go:122` | wallpaper matugen → browser | ✅ **keep (loopback)** |
| `ryoku-shell (https://github.com/…)` | `ipc/music.go:46` | HTTP User-Agent only | harmless (dies with music) |

`ryogami` itself makes no outbound calls at runtime `[READ]`; its choose-a-wallpaper sources
(wallhaven/Steam/moewalls) are part of the picker and are off-list.

**Result:** with the keep-list as specified, the shell should make **zero outbound internet
calls**; the only network traffic is loopback to the palette bridge.

### Q5 — Hard-coded `ryoku`/`ryoku-hub`/`ryogami` names, and the Mei rename

Full table in `docs/02-deps/05-names-network-uv.md`. Summary + what to KEEP:

| Artifact | Kind | Where | Mei action |
|---|---|---|---|
| `ryoku-shell.sock` | socket | `ipc/main.go:18` + QML clients | → `mei-shell.sock` |
| `ryoku-shell.sock.lock` | lock | `ipc/daemon.go:277` | derive from new name |
| `ryogami.sock` | socket | `ryogami/daemon/proto.go:92`, `ipc/ryogami.go:42` | → `mei-wall.sock` |
| `ryoku-pill.sock` | dead socket | `ipc/actions.go:113` | **delete** |
| **`/tmp/ryoku-hub.lock`** | lock (absolute) | `ipc/control.go:179` | → `/tmp/mei-hub.lock` |
| `/tmp/ryoshot.lock`, `/tmp/ryopin.lock`, `/tmp/ryoku-keys.lock` | locks | Frame/catalog/ryoshot | rename or drop with their surfaces |
| `ryoku-qsbar-brightness.lock` | lock | `barstyles/qsbar/RyokuPower.js:26` | → `mei-…` |
| `qylock.<sess>.<suffix>` | lock markers | `ipc/actions.go:185-195` | → `mei-lock.*` |
| `~/.config/ryoku/`, `~/.cache/ryoku/`, `~/.local/state/ryoku/` | config/cache/state | `ipc/config.go:53-60`, `matugen.go`, `bar.go` | → `…/mei/` (XDG-derived → redirect via `XDG_*`) |
| `~/.config/ryogami-wall/config.json`, `~/.cache/ryogami/` | config/cache | `ryogami/daemon/config.go:117-284` | → `…/mei-wall/` |
| `ryoku-shell.service`, `ryogami.service`, `ryoku-*.service`, `ryoku-session.target` | units | `ryoku/shell/systemd/user/*` | → `mei-*` / `mei-wall.service` |
| `RYOKU_*` env | env | `polkit.go:35`, `actions.go:20`, `clipboard.go:45`, `bar.go:402`, units | → `MEI_*` |
| `ryoku-shell`/`ryoku-hub`/`ryogami` binaries, `qs -c hub` config ids | bins/configs | PKGBUILDs, `control.go:142` | → `mei-*` |
| **`/run/polkit/agent-helper.socket`**, `/usr/lib/polkit-1/polkit-agent-helper-1` | sockets/paths | `ipc/polkit.go:61,69` | **KEEP** (polkit-owned) |
| **`org.gnome.keyring.SystemPrompter`** + `/org/gnome/keyring/Prompter` | D-Bus | `ipc/prompter.go:31-39` | **KEEP** (third-party contract) |
| **`org.kde.StatusNotifierWatcher`**, `org.freedesktop.*`, `org.mpris.*` | D-Bus | `ipc/tray.go:32-34` etc. | **KEEP** (freedesktop/KDE contracts) |

### Q6 — `uv`

**Nothing on the keep-list needs it.** `uv` is used only by `ryoku/shell/scripts/ryostage`
(`ryostage:348-371`, to provision a Python for the Stage web cut-out) and by the excluded
Rashin/AI path. `[TESTED]` grep. → **Drop `uv` from Mei's dependency set.**

### Q7 — Two wallpaper options, costed

Full costing in `docs/02-deps/03-wallpaper-theming.md`. Summary `[READ]` (+ measured sizes):

- **matugen is common to both** and is the only large measured binary: **11,945,640 B** `[TESTED]`.
- **Option A — keep `ryogami`** (as shipped): adds the `ryogami` Go daemon (stdlib-only; size
  `[UNVERIFIED]`, not built) + optional `ryogami-live` C helper for live video; runtime deps
  imagemagick, ffmpeg, quickshell, curl, inotify-tools (`ryogami/PKGBUILD:29`). Gives the
  `wallpaper` topic bridge, GPU reveal transitions, depth cut-out, playlists, day/night,
  live video — **with no shell edits**.
- **Option B — `hyprpaper`/`swww`/`swaybg` + matugen**: none is installed, so bytes are
  `[UNVERIFIED]`; it would require reworking ~9 files that speak the ryogami contract
  (`modules/wallpaper/Wallpaper.qml`, `WallpaperFrame.qml`, `Backdrop.qml`,
  `desktop/Desktop.qml:431`, `shell.qml:177-193`, `ipc/ryogami.go`, `bar/Frame.qml:72,406`,
  `barstyles/qsbar/panels/ImageCarousel*.qml`, `hyprland/modules/binds.lua:62-63`) and it
  **loses** the reveal shader, live video, the depth channel and the picker.
- **Verdict:** no measured byte win (matugen dominates; substitutes unmeasured) and a large
  blast radius. **Keep `ryogami`** unless live video + reveal motion are explicitly dropped
  — that is a Phase 4/5 decision, not a size win.

---

## Per-feature dependency maps

The six maps below give, per surface: files, QML imports, singletons, IPC verbs, binaries,
services/daemons, Qt modules, fonts, assets, and network calls.

- `01` — top bar (`qsbar`) and its widgets
- `02` — launcher and control sidebar
- `03` — wallpaper and theming (matugen)
- `04` — Settings (appearance + shell pages)
- `05` — names, network calls, uv
- `06` — fonts, assets, QML modules, Qt modules

### Carried into Phase 3

1. **Settings must not write Hyprland config** — sever the chain
   `Hub.qml:696-723 → hub/backend/desktop.go:100,229,243,381,383,388 →
   wm/hyprland/apply.go:56,59 → config_store.go:605-609 → act.go:169-177 (hyprctl reload)`,
   and drop the `desktop save|preview|restore` verbs + `niri` twins (`wm/niri/apply.go:52,55`).
2. **Daemon trim:** keep `wm`, `network`, `tray`, `settings`, `wallpaper`, `audio`,
   `brightness`, `menu`/`bar`/`barstyle`, surface ids; drop weather/calendar/music/updates/
   stage/plugin(s)/browser-host and their network calls (Q4).
3. **Rename/redirect** per Q5, and generate a Mei `matugen/config.toml` with project paths (Q1).
4. **Wallpaper:** keep `ryogami` (Q7).
5. **Dependencies to approve in Phase 4:** `go`, `cmake` (+ existing `ninja`), the font
   packages, and — only if built from source — the Qt shadertools path. **Not** `uv`.
6. Unresolved item to settle in Phase 3: the bar's notifications indicator was reported to
   bind its own `NotificationServer` (`panels/NotificationPanel.qml:87`) alongside
   `services/Notifs.qml` — dual ownership `[UNVERIFIED]` (fragment `01`).

---

---

## 01 — Top bar (qsbar) and its widgets

Phase-2 dependency map of the Ryoku top bar in bar style `qsbar` and the bar
widgets on the Mei keep list: workspaces, clock/date, audio indicator,
brightness, network, battery, system tray, notifications indicator.

Scope of evidence: read-only trace of the pinned upstream checkout at
`$HOME/projects/mei/upstream` (Ryoku v0.75.5-beta.20, commit 98a0368).
Every path below is repo-root-relative; the shell lives under
`ryoku/shell/quickshell/shell/`. All labels are `[READ]` (I opened the file at
the cited line) or `[UNVERIFIED]` (an inference not directly proven by a read).
There are **no `[TESTED]` claims**: the upstream tree was never built or run
(read-only phase), so nothing here is runtime-verified.

The single load-bearing fact for trimming: **qsbar is a self-contained folder
style**. It does not use `shell/barkit`, and its widgets bind their own data
(native PipeWire/UPower/Quickshell notification server, or local `bash`
shell-outs), not the shared `shell.services` widgets. `[READ]`

---

### Files

#### Style selection / configuration
- `ryoku/shell/quickshell/shell/services/Config.qml` — the shell.json reader.
  `property alias barStyle` at `:40`; the `JsonAdapter` default
  `property string barStyle: "qsbar"` at `:193`; `property alias qsbar` at `:48`
  and `property var qsbar: ({})` at `:197`. The file watched is
  `$XDG_CONFIG_HOME/ryoku/shell.json` (`:169`). `[READ]`
- `ryoku/shell/quickshell/shell/services/BarProducts.qml` — resolves a style id to
  its scene. `builtins` maps `"qsbar": "barstyles/qsbar/Scene.qml"` at `:53-56`;
  `sceneUrl()` at `:58-68` returns `""` for `"sumi"` (the built-in painted frame),
  a relative Scene for a builtin, or a `file://` store view. `[READ]`
- `docs/barstyles.md:30-104` documents the `barStyle` key, defaults and the
  selection flow (matches the code above). `[READ]`
- Selection code path: `Config.barStyle` → `BarProducts.sceneUrl(id)` →
  `Frame.qml` Loader. `[READ]`

#### Bar/frame core — `ryoku/shell/quickshell/shell/modules/bar/`
- `Frame.qml` (496 lines) — one monitor's frame bar. `qsbarPrimaryHost` at `:43`;
  `sumiActive` (built-in frame active) at `:50`; the four reservation `FrameEdge`s
  at `:115-118`; the overlay `PanelWindow` at `:120-451` (input `mask`, blob group,
  `FrameChrome`, `Bar` rails, `FrameMenuManager`); the per-monitor style `Loader`
  at `:457-479` with `active: !root.sumiActive && (root.barEnabled || root.qsbarPrimaryHost)`
  and `source: BarProducts.sceneUrl(Config.barStyle)`; builtin-load retry timer at
  `:480-488`. `runBarAction()` at `:65-77`. `[READ]`
- `FrameEdge.qml` (59 lines) — the exclusive-zone reservation surface per edge. `[READ]`
- `Bar.qml` (57 lines) — the **sumi** rail host: a Repeater over four edges
  instantiating `FrameRail` with `BarWidgetHost` delegates (`:30-56`). Not used by
  qsbar (`visible: … root.sumiActive`). `[READ]`
- `FrameRail.qml` (118 lines) — one rail edge (band + three `RailZone`s). sumi path. `[READ]`
- `BarWidgetHost.qml` (106 lines) — maps a sumi catalogue id to its `Rail*`
  component; `componentFor()` at `:33-57`. sumi path, not qsbar. `[READ]`
- `FrameMenuManager.qml` — the per-monitor menu/surface manager used by *both*
  paths; qsbar gets top-bar folding via `topBar`/`barEdge` (`:42-60`) fed from
  `Frame.qml:380-391`. `[READ]`
- `FrameMenu.qml`, `FrameSurface*.qml`, `MenuWidgetHost.qml`, `RailZone.qml`,
  `FrameChrome.qml`, `popouts/*`, `framebars/*` — frame chrome / menu bodies /
  sumi widgets. Present and loaded by `Frame.qml`, but only their qsbar-relevant
  pieces matter here. `[READ]` (directory listing)
- `ryoku/shell/framebars/FrameBars.qml` + `FrameBars.js` + `BarCatalog.qml` +
  `MenuCatalog.qml|.js` + `qmldir` (`module Ryoku.FrameBars`) — the config schema
  singleton `Config.normalizedFrameBars` normalizes through
  (`Config.qml:34`). Used by the frame and by the sumi rails; qsbar reads only a
  little of it (e.g. `Frame.qml:85-110`). `[READ]`

#### qsbar style — `…/modules/bar/barstyles/qsbar/`
- `Scene.qml` (52 lines) — per-monitor entry the `Frame` Loader mounts. Hosts the
  single bar system once, on the primary output (`isPrimary` at `:32-36`), via a
  `Loader` that builds `VariantRoot { id: barRoot }` + `IpcRouter { barRoot }`
  (`:38-50`). `[READ]`
- `VariantRoot.qml` (289 lines) — binds one `BarSlot` per real output
  (`:208-225`), a popup dismiss layer (`:227-238`), and instantiates every panel:
  `TooltipOverlay, DashboardPopup, PowerProfilePanel, MemoryPanel, CpuPanel,
  GpuPanel, ThermalsPanel, StoragePanel, AiUsagePanel, VolumePanel, TrayPanel,
  NotificationPanel, NetworkPanel, BluetoothPanel, BatteryPanel, PluginPanel,
  BrightnessPanel, MprisPanel, WorkspacePanel, ControlCenter, TrayMenu`
  (`:240-260`). Owns the `qsbar` IPC handler (`:274-281`). `[READ]`
- `BarSlot.qml` (2325 lines) — the **widget host**: one `PanelWindow` per output
  carrying the shell surface and all widgets. This is the file the task calls
  ~1700 lines (it is 2325 at this commit). Component/registry section `:909-1255`.
  `[READ]`
- `Theme.qml` (3701 lines) — the qsbar root object passed to every widget as
  `root`. Palette, per-widget visibility flags, palette/token helpers, status
  pollers, tray/notification state, the config persist socket. `[READ]`
- `core/BarCatalog.qml` + `core/widgets.json` — id↔gid catalogue (loads
  `widgets.json` synchronously, `:49-58`). `[READ]`
- `core/IpcRouter.qml` (125 lines) — external IPC surface: handlers `lifecycle`,
  `layout`, `ryoku.system-update`, `reactor`, `theme`, `picker` (`:81-117`). `[READ]`
- `BarPlugins.qml` — discovers store plugins via `…/plugins/discover.sh --all`
  (`:84-95`). Only relevant if store plugins are kept. `[READ]`
- `Palette.js`, `IconMap.js`, `RyokuPower.js`, `Theme.qml`, `qmldir`, `LICENSE`,
  `quotes.txt`, `assets/`, `shaders/` — support files. `[READ]` (listing)
- `barstyles/sumi/manifest.json` — Sumi is scene-less (`"scene":""`); the built-in
  frame paints it. `[READ]`
- `barstyles/kairos/` — the other built-in style; out of scope. `[READ]` (listing)

#### Keep-list widget components — `…/qsbar/modules/`
- `WorkspaceWidget.qml` (608), `ClockWidget.qml` (63), `AudioWidget.qml` (92),
  `AudioData.qml` (31), `BrightnessWidget.qml` (174), `NetworkWidget.qml` (277),
  `BatteryWidget.qml` (202), `TrayWidget.qml` (130), `NotificationWidget.qml` (61),
  `NotificationSilenceWidget.qml` (45). `[READ]`
- Shared primitives the keep-list uses: `UiText.qml` (12), `IconText.qml` (14),
  `TooltipMixin.qml` (31), `PacmanMarker.qml` (workspace "pacman" style), plus
  `ReactorLayer.qml`/`ParticleStream.qml`/`StreamShader.qml` for the gap animation
  (part of the bar surface, motion keep-list). `[READ]`

#### Services the keep-list binds to — `…/shell/services/`
- `Tray.qml`, `Network.qml`, `Notifs.qml`, `Icons.qml`, `Config.qml`; plus the
  notification server inside `…/qsbar/panels/NotificationPanel.qml`. `Audio.qml`
  and `Battery.qml` exist but are **not** used by the bar widgets (see below). `[READ]`
- `ryoku/ui/Singletons/Wm.qml` — the `Wm` singleton the workspace widget reads
  (module `Ryoku.Ui.Singletons`, `qmldir` `singleton Wm Wm.qml`). `[READ]`

Note: everything above is on disk in the sparse checkout. No off-disk
`git show` was required; the few assets with no in-tree reference are noted under
**Assets**.

---

### QML imports

Per file (exact `import` lines read):

- `BarSlot.qml:6-14` — `QtQuick`, `QtQuick.Effects`, `QtQuick.Shapes`,
  `Quickshell`, `Quickshell.Wayland`, `Quickshell.Io`, `"modules"`,
  `shell.services as Svc`, `Ryoku.PluginKit`. `[READ]`
- `VariantRoot.qml:8-15` — `Quickshell`, `Quickshell.Io`, `Quickshell.Wayland`,
  `QtQuick`, `Ryoku.Ui.Singletons`, `"panels"`, `"controlcenter"`,
  `services/lib/screens.js`. `[READ]`
- `Scene.qml:12-16` — `Quickshell`, `QtQuick`, `services/lib/screens.js`, `"."`, `"core"`. `[READ]`
- `Theme.qml:1-8` — `QtQuick`, `Quickshell`, `Quickshell.Io`,
  `Quickshell.Services.UPower`, `shell.services`, `Ryoku.Ui.Singletons`,
  `"core"`, `"Palette.js"`. `[READ]`
- `Frame.qml:3-9` — `QtQuick`, `Quickshell`, `Quickshell.Wayland`,
  `Ryoku.Blobs`, `Ryoku.Ui.Singletons`, `shell.services`, `framebars/RailGeometry.js`. `[READ]`
- Widgets:
  - `WorkspaceWidget.qml:1-4` — `Ryoku.Ui.Singletons`, `QtQuick`, `QtQuick.Shapes`, `shell.services`. `[READ]`
  - `ClockWidget.qml:1-4` — `QtQuick`, `Quickshell`, `Quickshell.Io`, `shell.services as Svc`. `[READ]`
  - `AudioWidget.qml:1-5` — `QtQuick`, `Quickshell`, `Quickshell.Io`, `shell.services`, `Ryoku.Ui.Singletons`. `[READ]`
  - `AudioData.qml:1-2` — `QtQuick`, `Quickshell.Services.Pipewire`. `[READ]`
  - `BrightnessWidget.qml:1-5` — `QtQuick`, `Quickshell`, `Quickshell.Io`, `../RyokuPower.js`, `Ryoku.Ui.Singletons`. `[READ]`
  - `NetworkWidget.qml:1-5` — `QtQuick`, `Quickshell`, `Quickshell.Io`, `../IconMap.js`, `Ryoku.Ui.Singletons`. `[READ]`
  - `BatteryWidget.qml:1-5` — `QtQuick`, `Quickshell`, `Quickshell.Services.UPower`, `shell.services`, `Ryoku.Ui.Singletons`. `[READ]`
  - `TrayWidget.qml:1-4` — `Quickshell`, `shell.services`, `QtQuick`, `Ryoku.Ui.Singletons`. `[READ]`
  - `NotificationWidget.qml:1-3` — `QtQuick`, `Quickshell`, `Ryoku.Ui.Singletons`. `[READ]`
  - `NotificationSilenceWidget.qml:1-4` — `QtQuick`, `Quickshell`, `Quickshell.Io`, `Ryoku.Ui.Singletons`. `[READ]`
- Services: `Tray.qml:3-5`, `Network.qml:2-5`, `Notifs.qml:2-5`, `Icons.qml:3-5`
  (all `Quickshell*` + `Ryoku.Ui.Singletons` where shown); `Wm.qml:3-7`
  (`Quickshell.WindowManager`, `Quickshell.Wayland`). `[READ]`

---

### Singletons

The qsbar widgets reach the shell through named-module singletons and through the
qsbar-local `Theme` object (`BarSlot` passes `root: theme`, `VariantRoot.qml:216`).
`[READ]`

- `Ryoku.Ui.Singletons.Wm` (`ryoku/ui/Singletons/Wm.qml`) — workspaces and window
  state. Read by `WorkspaceWidget.qml:23,27,37,43,45,58,202-207`; acts through
  `Wm.focusWorkspace` (`Theme.qml:3406`). `[READ]`
- `shell.services.Tray` (`services/Tray.qml`) — the SNI row. `TrayWidget.qml:25`
  (`Tray.items`), `:56` (`Tray.activate`). `[READ]`
- `shell.services.Config` (`services/Config.qml`) — `barStyle`, `qsbar`, and
  `formatLoc` for date/time locale (`BarSlot.qml:1138`, `ClockWidget.qml:26`). `[READ]`
- `shell.services.Icons` (`services/Icons.qml`) — resolved tray icon paths
  (`TrayWidget.qml:39`). `[READ]`
- `shell.services.Notifs` (`services/Notifs.qml`) — the shell's shared
  `NotificationServer`. Referenced by `shell.qml:381,626` and the framebars/kairos
  paths. **The qsbar notification widget does not read it** — see Services. `[READ]`
- `shell.services.Audio` (`services/Audio.qml`) and `shell.services.Battery`
  (`services/Battery.qml`) — exist, but the qsbar bar widgets do **not** use them
  (audio uses `AudioData`/PipeWire; battery uses UPower directly). `[READ]`
- qsbar-local: `Theme` (`…/qsbar/Theme.qml`) is the `root` object providing
  `widgetContentColor`, `widgetHasFill`, `iconOnly`, `mono`, `seal`, per-widget
  `mod*` flags and popup-state booleans. `[READ]`
- `Ryoku.FrameBars` (`ryoku/shell/framebars/FrameBars.qml`) — config schema used
  by `Config.normalizedFrameBars`, `Frame.qml`, `FrameMenuManager.qml`. `[READ]`

---

### IPC verbs used

Two transports: (a) the Quickshell `IpcHandler` targets on the running shell
(`qs -c shell`), and (b) the `ryoku-shell` daemon's unix socket
`$XDG_RUNTIME_DIR/ryoku-shell.sock` (line protocol `subscribe <topic>` /
`call <method> <json>`). `[READ]`

Quickshell `IpcHandler` targets (shell-internal):
- `qsbar` — `settings(route)`, `layout()` (`VariantRoot.qml:274-281`). `[READ]`
- `lifecycle.ready`, `layout.lock/unlock`, `ryoku.system-update.refresh`,
  `reactor.test/monsweep/clear`, `theme.apply/applyLauncher/reload`,
  `picker.theme/wallpaper/screenshots/videos` (`core/IpcRouter.qml:81-117`). `[READ]`

Daemon socket verbs actually reached by the keep-list path:
- `subscribe wm` and `call wm.act {...}` — `ryoku/ui/Singletons/Wm.qml:317` and
  `:199`/`:222`; used for workspace focus (`workspace.focus`) and window/output
  actions. `[READ]`
- `subscribe tray` + `call tray.activate | tray.contextMenu | tray.scroll |
  tray.aboutToShow | tray.menuEvent` — `services/Tray.qml:38-42,61`. `[READ]`
- `call settings.patch {"path":"qsbar"|"qsbar.<key>"|"barStyle",...}` — the only
  writer of shell.json; qsbar persists widget/visibility/layout state over
  `Theme.qml:3207-3270` (`_cfgPath`, `_cfgCtl`, `:3257`). The daemon registers
  `settings.patch` at `ryoku/shell/ipc/settings.go:1116`. `[READ]`
- `ryoku-shell icons` — not socket IPC; the daemon CLI subcommand Icons runs
  (`services/Icons.qml:87`). `[READ]`
- `ryoku-shell hub open connections` — the network widget's right-click launcher
  (`Theme.qml:2541-2542`). `[READ]`
- `ryoku-shell lock` — frame rail "lock" action (`Frame.qml:67`). `[READ]`
- `settings.patch` for `screenShader`/`launcherTarget` from `Config.qml:97-98,113-114`. `[READ]`

The `network.*` daemon topic verbs (`subscribe network`, `call network.wifiScan |
network.wifiSetEnabled | network.wifiConnect | network.wifiDisconnect |
network.wifiForget | network.wgActivate | …`) exist in
`services/Network.qml:51-64,107` and `ryoku/shell/ipc/network.go:110`, but the
**bar NetworkWidget itself does not call them** — it has no reference to the
`Network` singleton (its import list omits `shell.services` as a used singleton;
it shells out instead). `[READ]`

---

### Binaries shelled out

Keep-list widgets (`bash -c` / `Process.command`, exact sources):
- Brightness (`BrightnessWidget.qml:111-160` via `RyokuPower.js:1-40`):
  `bash`, `ryoku-hw-backlight`, `ls`, `brightnessctl`, `cut`, `tr`, `awk`,
  `flock` (lock file `$XDG_RUNTIME_DIR/ryoku-qsbar-brightness.lock`), and on
  failure `notify-send` (`:41-42`). `[READ]`
- Network (`NetworkWidget.qml:201-218`): `bash`, `ip route get 1.1.1.1`, `awk`,
  `iw dev … link`, `sed`, `printf`, reading `/proc/net/dev` and
  `/sys/class/net/<if>/wireless`; right-click runs
  `ryoku-shell hub open connections` (`:263`). `[READ]`
- Notifications silence indicator (`NotificationSilenceWidget.qml:27-31`):
  `bash -c` with `command -v true` then `omarchy toggle notification silencing`
  (dead branch on Ryoku; `true` short-circuits). This widget is in the G8 group. `[READ]`

Bar-root / theme shell-outs (run whenever qsbar is the active style, independent
of which widgets are shown):
- `Theme.qml:3563-3569` — `bash` probe for the theme root (`$HOME/.local/state/ryoku/current`, `/usr/share/ryoku`). `[READ]`
- `Theme.qml:2298-2420` — backend probes: `bash`, `true idle status`,
  `true notifications ping`, `pgrep -x hypridle`, `sh -c command -v makoctl`,
  `makoctl mode` (mako not shipped; guarded by `_makoAvailable`). `[READ]`
- `Theme.qml:2422-2468` — recording indicator: `pgrep -o -f ^gpu-screen-recorder`, `ps -o etimes= -p`. `[READ]`
- `Theme.qml:2494-2523` — voxtype indicator: `bash`, `voxtype status`, `jq`. `[READ]`
- `Theme.qml:2530-2534` — `bash -c "systemctl is-active --quiet NetworkManager"`. `[READ]`
- `Frame.qml:71` — screenshot (`sh -c "flock … qs -c ryoshot"`); `:72`
  `ryogami wallpaper ui`; `:73` `ryoku-cmd-color-picker`; `:67` `ryoku-shell lock`. `[READ]`
- Plugin placement (only if store plugins kept): `ryoku-plugins-place`
  (`Theme.qml:607-612`). `[READ]`

Services: `Icons.qml:27-30,87` resolves `ryoku-shell` (dev: `$RYOKU_SHELL_DIR/ipc/ryoku-shell`)
and runs `… icons`. `[READ]`

---

### Services / daemons

- `ryoku-shell` Go daemon — owns the unix socket and the topics the bar reads
  (`wm`, `tray`, `settings`) and writes (`settings.patch`). It also owns network
  state (`ryoku/shell/ipc/network.go`), tray/SNI (`tray.go`), icons (`icons.go`),
  and the shell lifecycle. qsbar depends on it for workspaces, tray, config
  persistence, and (via `Wm`) window/output actions. `[READ]`
- PipeWire (via Quickshell) — default sink volume/mute for the audio widget;
  event-driven, no subprocess (`AudioData.qml:19-30`). `[READ]`
- UPower (via Quickshell) — battery `displayDevice` for the battery widget
  (`BatteryWidget.qml:12-27`). `[READ]`
- Quickshell `NotificationServer` — **two instances exist**: `services/Notifs.qml:230`
  (shell-wide, used by `shell.qml:381,626`) and
  `qsbar/panels/NotificationPanel.qml:26` (qsbar's own, `keepOnReload: true`).
  The qsbar bell reads `root.notifCount` (`NotificationWidget.qml:10`), bound from
  `NotificationPanel.qml:87` to that panel's `unreadCount` (`:83`). So the qsbar
  notifications indicator is driven by `NotificationPanel.qml`'s server, not by
  the `Notifs` singleton. Which server actually owns
  `org.freedesktop.Notifications` at runtime is `[UNVERIFIED]` (not run);
  two `keepOnReload` servers are a known upstream wrinkle to resolve in Phase 3. `[READ]`
- NetworkManager — read only indirectly: the bar widget parses the routing table
  and `iw`, not NM; NM presence only toggles a panel hint (`Theme.qml:2529-2534`). `[READ]`
- brightnessctl / the `ryoku-hw-backlight` helper — brightness backend. `[READ]`

---

### Qt modules

- `QtQuick` (all), `QtQuick.Shapes` (`BarSlot.qml:8`, `WorkspaceWidget.qml:3`),
  `QtQuick.Effects` (`BarSlot.qml:7`). `[READ]`
- `Quickshell`, `Quickshell.Io`, `Quickshell.Wayland` (`BarSlot.qml:9-11`,
  `Frame.qml:4-5`, `VariantRoot.qml:8-10`). `[READ]`
- `Quickshell.Services.Pipewire` (`AudioData.qml:2`). `[READ]`
- `Quickshell.Services.UPower` (`BatteryWidget.qml:3`, `Theme.qml:4`). `[READ]`
- `Quickshell.Services.Notifications` (`Notifs.qml:4`, `NotificationPanel.qml:6`). `[READ]`
- `Quickshell.WindowManager`, `Quickshell.Wayland` (`Wm.qml:6-7`). `[READ]`
- `Ryoku.Ui.Singletons`, `Ryoku.PluginKit`, `Ryoku.FrameBars`, `Ryoku.Blobs` —
  project modules (`BarSlot.qml:14`, `Frame.qml:6`, `Config.qml:5-6`). `[READ]`

`BarSlot.qml` needs the QApplication/threads pragmas from `shell.qml` only for the
tray's Qt Widgets; `shell.qml:1-9` declares them. `[READ]`

---

### Fonts

- `JetBrainsMono Nerd Font` — `Theme.qml:121` (`root.mono`), used by the clock,
  audio %, brightness %, network SSID/RX-TX, battery %, tray badge, date label,
  workspace numbers/frame, pacman glyph (`WorkspaceWidget.qml:280,337,521`). `[READ]`
- `Material Symbols Rounded` — `IconText.qml:10`; all glyph icons (volume
  `graphic_eq`, network wifi/lan, tray `more_horiz` U+E5D3, bell U+E7F4,
  notifications_off U+E7F6). `[READ]`
- `Adwaita Mono` — workspace "magic" sparkles (`WorkspaceWidget.qml:299`). `[READ]`
- `Noto Sans CJK JP` — workspace "kanji" numerals (`WorkspaceWidget.qml:317`). `[READ]`
- `Space Grotesk` — the shell-wide `Config.fontFamily` default (`Config.qml:186`);
  not used by the keep-list bar widgets directly (they use `root.mono`). `[READ]`
- The bundled `…/shell/assets/fonts/*` (`Fonts.qml:20-30`) are for desktop-widget
  display faces, **not** the bar. `[READ]`

---

### Assets

- Keep-list bar widgets use **no image files**: glyphs are icon-font ligatures
  (`IconText`/`UiText`) and the drawn sun/battery/pacman are `Rectangle`/`Canvas`
  geometry. Tray icons come from the daemon as `iconPath`/`iconName`
  (`TrayWidget.qml:39`) and resolve through `Icons.path`. `[READ]`
- qsbar `assets/*` are consumed only by **excluded** widgets:
  `gpu-card.svg` (`GpuWidget.qml:37`), `logo-tint.frag.qsb` shader
  (`GpuWidget.qml:47`, `ClaudeWidget.qml:196`, `AiUsagePanel.qml:144`),
  `claude.svg`/`codex-cli.svg`/`opencode-mark.svg`
  (`ClaudeWidget.qml:237,247,257`, `AiUsagePanel.qml:449,461,474`). `[READ]`
- `assets/arch-header-arch.png`, `arch-header-linux.png`, `bob2.png`, `bob3.png`,
  `omacom-text.png`, `hdd-mark.svg`, `codex.svg` have **no in-tree reference**
  (grep over `ryoku/**/*.qml|js|json` returned none) — orphaned/dead assets.
  `[UNVERIFIED]` (may be referenced by a path built dynamically or by a store
  style).
- Shaders the gap animation uses live in `barstyles/qsbar/shaders/`
  (`stream.frag`, `stream.frag.qsb`, `logo-tint.frag.qsb`); `StreamShader.qml:88`
  loads `stream.frag.qsb` (part of the motion keep-list surface). `[READ]`

---

### Network calls

- Keep-list bar widgets make **no HTTP/S requests** — grep for `http|curl|wget|
  fetch(` across the eight widget files returned nothing. `[READ]`
- The network widget's `ip route get 1.1.1.1` (`NetworkWidget.qml:204`) is a
  routing-table lookup (no packet to the address). `[READ]`
- Weather (`WeatherWidget.qml:1-3,16-22`) reads the daemon-fed `Weather`
  singleton and makes no HTTP itself; the daemon (`ryoku/shell/ipc/weather.go`)
  does. Weather is a G8 sub-widget and is **excluded**. `[READ]`
- `CloudflareSpeedTest.qml:21-22` hard-codes `https://speed.cloudflare.com/__down`
  and `__up`; it is invoked only by excluded panels. `[READ]`
- The daemon's network/weather/tray topics are the only real network surfaces,
  and they live in `ryoku-shell`, not the bar QML. `[READ]`

---

### Necessity / exclusions

Widget registry (`BarSlot.qml:1248-1255`) maps gid→component; `core/widgets.json`
is the catalogue. Default lanes (`BarSlot.qml:2124-2139`): left
`G1 G2 G3 · G5 G6 G4 G7 · ·`, center `G8`, right
`G9 G10 G11 G14 G12 G13 G16 G18 G17 G15 G19`. `[READ]`

**Keep-list (traced above):**
| Widget | gid | Component file | Data source |
|---|---|---|---|
| Workspaces | G2 | `modules/WorkspaceWidget.qml` | `Wm` (daemon `wm` topic + ext-workspace) |
| Clock + date | G8 | `modules/ClockWidget.qml` + inline date (`BarSlot.qml:1123-1145`) | `SystemClock`, `Config.formatLoc` |
| Audio | G6 | `modules/AudioWidget.qml` + `AudioData.qml` | PipeWire (Quickshell) |
| Brightness | G13 | `modules/BrightnessWidget.qml` | `brightnessctl` / `ryoku-hw-backlight` via bash |
| Network | G11 | `modules/NetworkWidget.qml` | bash (`ip`/`iw`); panel via daemon |
| Battery | G12 | `modules/BatteryWidget.qml` | UPower (Quickshell) |
| System tray | G3 | `modules/TrayWidget.qml` | `Tray` service (daemon `tray` topic) |
| Notifications indicator | G3 | `modules/NotificationWidget.qml` | `NotificationPanel.qml` `NotificationServer` |

Related keep-list (not in the eight asked for, keep OFF by default): launcher
`G1` (`modules/LauncherWidget.qml`), and the DND indicator
`NotificationSilenceWidget.qml` inside G8 (borderline "notifications").

**Everything else in the bar is NOT on the Mei keep list** (excluded; each is one
component file, easy to opt back in by re-enabling its gid):
- `G4` Memory — `modules/MemoryWidget.qml` (panel `MemoryPanel.qml`)
- `G5` CPU — `modules/CpuWidget.qml` (panel `CpuPanel.qml`)
- `G7` AI usage — `modules/ClaudeWidget.qml` (panel `AiUsagePanel.qml`; assets above)
- `G8` Weather — `modules/WeatherWidget.qml` (+ `WeatherFX.qml`)
- `G8` Stay-awake indicator — `modules/IdleWidget.qml` (`Theme.qml:2149-2191`)
- `G8` Screen-record indicator — `modules/ScreenRecordWidget.qml`
- `G8` Voxtype indicator — `modules/VoxtypeWidget.qml` (`Theme.qml:2494-2523`)
- `G8` Update indicator — `modules/UpdateWidget.qml` (`omarchy`-flavoured)
- `G9` Now-playing/MPRIS — `modules/MprisWidget.qml` (+ `MprisArtwork/MprisSelect`)
- `G10` Quick (idle-inhibitor · media-browser · theme display) —
  `IdleInhibitorWidget.qml`, `MediaBrowserWidget.qml`, `ThemeDisplayWidget.qml`
- `G14` Power profile — `modules/PowerProfileWidget.qml`
- `G15` Bluetooth — `modules/BluetoothWidget.qml`
- `G16` CPU temperature — `modules/CpuTemperatureWidget.qml`
- `G17` GPU — `modules/GpuWidget.qml`
- `G18` Storage — `modules/StorageWidget.qml`
- `G19` Keyboard layout — `modules/LayoutWidget.qml`

Panels/popouts that would be pulled in only by excluded widgets (all in
`…/qsbar/panels/`): `DashboardPopup, MemoryPanel, CpuPanel, GpuPanel,
ThermalsPanel, StoragePanel, AiUsagePanel, BluetoothPanel, PowerProfilePanel,
MprisPanel, PluginPanel`, plus the pickers `ImageCarousel*`, `MediaBrowser*`,
`PluginPanel`, and `CloudflareSpeedTest` (the only direct-HTTP file). Panels
needed by the keep list: `VolumePanel, NetworkPanel, BatteryPanel,
BrightnessPanel, TrayPanel, TrayMenu, NotificationPanel, WorkspacePanel,
TooltipOverlay`, and (for the launcher) `ControlCenter`. `[READ]`

Also excluded / optional for Mei and relevant to bar startup cost:
- The gap "reactor" stream (`ReactorLayer.qml`, `ParticleStream.qml`,
  `StreamShader.qml`, `barAnim != 0`) spawns per-frame shader work; `Theme.qml:2578`
  default `barAnim = 1`. Motion is on the keep list — keep the mechanism, consider
  `barAnim = 0` default if it does not read. `[UNVERIFIED]` (perf not measured).
- The many `Theme.qml` status pollers (`pgrep hypridle`, `gpu-screen-recorder`,
  `voxtype`, `systemctl NetworkManager`) run regardless of widget visibility.
  Trimming the excluded indicators lets those pollers (`:2386-2534`) be deleted
  too. `[READ]`

Opt-back-in for each excluded row: it is one `Component` in
`BarSlot.qml`'s registry and one row in `core/widgets.json`; restoring the entry
plus its lane slot re-enables it, so trimming should be done as "widget off /
pollers off", not file deletion, wherever the widget still compiles. `[READ]`

---

## 02 — Launcher and control sidebar

Source: Ryoku v0.75.5-beta.20 @ `98a0368`, read-only sparse checkout
`$HOME/projects/mei/upstream`. Everything below is cited to `file:line`.
Because this phase only *read* the tree (no build, no run), every claim is
`[READ]` unless noted `[UNVERIFIED]` (an off-disk helper's internals, or a
runtime behaviour a static read cannot prove). There are no `[TESTED]` claims in
this phase.

Two surfaces are traced: **A) the Launcher** (`modules/launcher/`) and **B) the
Super+Escape control sidebar / quick settings** (`modules/bar`). Note the naming
trap in the brief: the qsbar **ControlCenter** (`barstyles/qsbar/controlcenter/`)
is the *bar settings* panel the logo opens (`studio` target), **not** the
Super+Escape quick-settings surface. Both live under section B and are separated
explicitly.

### Launcher

Entry: `modules/launcher/Launcher.qml` — a `Scope` (`Launcher.qml:10`) that the
shell builds lazily per monitor (`shell.qml:281-300`). It loads
`catalog.json` (`Launcher.qml:94-103`), picks the variant from
`LauncherConfig.variant` (`Launcher.qml:35`), and loads that variant's
`entrypoint` through a `Loader` (`Launcher.qml:107-120`). Open/close is owned by
`ShellState.launcherOpen` (`Launcher.qml:137-140`); the legacy
`IpcHandler`/`ryoku-launcher.sock` control channel is removed
(`Launcher.qml:136-140`). The shell's `CustomShortcut` `"launcher"`
(`shell.qml:538-542`) and the `"launcher"` bus case (`shell.qml:460-462`)
flip that flag.

**Variants (item 2).** `catalog.json` declares four variants with
`default: "hero"` and `fallback: "okshell"` (`catalog.json:3-4`): `main`
(`catalog.json:6-13`), `hero` (`catalog.json:14-21`), `okshell`
(`catalog.json:22-29`), `kairos` (`catalog.json:30-37`). The active variant is
selected by the JSON key **`variant`** in `~/.config/ryoku/launcher.json`
(`shared/Singletons/LauncherConfig.qml:25`, default `"hero"` at
`LauncherConfig.qml:34`). This is **not** a `shell.json` subtree; the launcher's
only `shell.json` reads are appearance keys via
`shared/Singletons/Config.qml:71` (frame/island/font/grain) and the
`themePalette` fallback in the okshell variant
(`variants/okshell/Main.qml:52-60`).

#### Files

On-disk inventory (`.qml`, `.js`, `.json`, `.png`; the `*.test.mjs` and `qa/`
harness are listed too but are dev-only, see exclusions):

- Root: `Launcher.qml`, `catalog.json`.
- `shared/`: `AnswerPanel.qml`, `AskPanel.qml`, `CategoryTabs.qml`,
  `HelpPanel.qml`, `Spinner.qml`, `WeatherGlyph.qml`,
  `art/hands-adam.png`.
- `shared/lib/`: `catalog.js`, `contrast.js`, `dispatch.js`,
  `launcherstate.js`, `lifecycle.js`, `providerids.js`, `radio.js`,
  `results.js`, `rofiscript.js`, `weather.js` (+ `*.test.mjs`).
- `shared/providers/`: `Provider.qml`, `Providers.qml`, `requeststate.js`;
  sub-dirs `actions/` (`Actions.qml`, `catalog.js`), `apps/` (`Apps.qml`,
  `appactions.js`), `calc/` (`Calc.qml`, `calc.js`), `find/` (`Find.qml`),
  `media/mpris/` (`Mpris.qml`), `packages/` (`Packages.qml`, `gpk.js`),
  `radio/` (`RadioTuner.qml`), `recent/` (`Recent.qml`, `recent.js`),
  `script/` (`Script.qml`), `snippets/` (`Snippets.qml`, `placeholders.js`),
  `web/` (`Web.qml`, `ddg.js`, `engines.js`), `windows/` (`Windows.qml`).
- `shared/Singletons/`: `qmldir`, `Config.qml`, `LauncherConfig.qml`,
  `Scheme.qml`, `Motion.qml`, `Metrics.qml`, `Frecency.qml`, `Dispatcher.qml`,
  `Weather.qml`, `Players.qml`, `Radio.qml`, `Performance.qml`, `Theme.qml`.
- `variants/hero/`: `Main.qml`, `Launcher.qml`, `LauncherSurface.qml`,
  `ActionShelf.qml`, `DismissScrim.qml`, `FrostLayer.qml`, `HeroShutter.qml`,
  `LeadResult.qml`, `LocalFrost.qml`, `ModeKey.qml`, `Preview.qml`,
  `ResultDrawer.qml`, `ResultLedger.qml`, `WindowRail.qml`,
  `WindowRailSurface.qml`.
- `variants/main/`: `Main.qml`, `Launcher.qml`, `ActionPanel.qml`,
  `BrandMark.qml`, `BtConnections.qml`, `MediaSources.qml`, `NowPlaying.qml`,
  `Preview.qml`, `RadioAside.qml`, `RestDashboard.qml`, `ResultGrid.qml`,
  `ResultList.qml`, `SearchRow.qml`, `Squircle.qml`, `TransportButton.qml`,
  `metrics.js`.
- `variants/okshell/`: `Main.qml`, `Preview.qml`.
- `variants/kairos/`: `Main.qml`, `Preview.qml`.
- `qa/`: `fixtures.sh`, `run.sh`, `scenarios.json`, `README.md` (dev harness).

Direct-load list: `Launcher.qml` → `catalog.json`, `shared/Singletons`
(`Launcher.qml:6`), `shared/providers` (`Launcher.qml:7`),
`shared/lib/catalog.js` (`Launcher.qml:8`) → a variant `Main.qml`. Each variant
`Main.qml` instantiates `Providers` (`Providers.qml:18-31`) which pulls in every
provider file above, and the variant's own surface files.

#### QML imports

Union across `modules/launcher/**/*.qml` (counts from the tree; the same module
set applies to all variants):

- `import QtQuick` (base), `import QtQuick.Layouts`, `import QtQuick.Controls`,
  `import QtQuick.Shapes`, `import QtQuick.Effects`, `import QtQml.Models`.
- `import Quickshell`, `import Quickshell.Io`, `import Quickshell.Wayland`,
  `import Quickshell.Widgets`, `import Quickshell.Services.Mpris`,
  `import Quickshell.Bluetooth`.
- `import Ryoku.Ui` and `import Ryoku.Ui.Singletons` (aliases `Ui`, `Svc`;
  provided by `ryoku/ui/qmldir:1` and `ryoku/ui/Singletons/qmldir`).
- `import shell.services` (the `shell.services` singleton module,
  `services/qmldir:1`), aliased `Svc` in providers.
- Local: `"shared/Singletons"`, `"shared/providers"`, `"shared/lib/*.js"`,
  variant-local `"."` / `metrics.js`.

(`Ryoku.Blobs` / `Ryoku.FrameBars` / `Ryoku.PluginKit` are **not** imported by
the launcher.)

#### Singletons

Declared locally in `shared/Singletons/qmldir:1-12`:

- `Theme` (`Theme.qml`), `Config` (`Config.qml`), `LauncherConfig`
  (`LauncherConfig.qml:6`), `Scheme` (`Scheme.qml`), `Motion`, `Metrics`,
  `Frecency`, `Dispatcher`, `Weather`, `Players`, `Radio`, `Performance`.

Bound from the shell: `shell.services` singletons used by the launcher include
`Icons`, `Bluetooth`, `Perf`, `Media`, `Audio`, `Network`, and `ShellState`
(`services/qmldir:1-56`; referenced in providers and variant files). From
`Ryoku.Ui.Singletons`: `Tokens`, `Wm`, `I18n`, `Spawn`
(`ryoku/ui/Singletons/qmldir`).

#### IPC verbs used

The launcher itself opens **no** socket. It reaches the daemon and helpers
indirectly:

- `shell.qml` owns `ShellState.launcherOpen`; the launcher signals
  `requestClose` (`Launcher.qml:19`, `shell.qml:296-297`).
- The `Wm` singleton talks to `$XDG_RUNTIME_DIR/ryoku-shell.sock` with the line
  protocol `call <method> <json>` / `subscribe wm`
  (`ryoku/ui/Singletons/Wm.qml:290-291`, `:310-317`). The hero variant uses it
  for `input.focusFollowsMouse` on open/close
  (`Wm.qml:239`; call sites `variants/hero/Main.qml:296-323`).
- Action/provider entries `exec` a `ryoku-shell` client (below), which then hits
  the daemon's IPC: `ryoku-shell lock`, `ryoku-shell menu
  quick-settings[#clipboard]`, `ryoku-shell visualizer-overlay`,
  `ryoku-shell reload` (`shared/providers/actions/catalog.js:10-13,33,37`).

#### Binaries shelled out

Direct `Process`/`Spawn.run`/`execDetached` in the launcher tree:

- `curl` — `shared/Singletons/Weather.qml:56`, `:150`;
  `shared/providers/web/Web.qml:93`.
- `mkdir -p` — `shared/Singletons/Weather.qml:127`.
- `ryoku-cmd-calc` — `shared/providers/calc/Calc.qml:143`.
- `ryoku-cmd-radio` — `shared/providers/radio/RadioTuner.qml:103`; `"status"` at
  `shared/Singletons/Radio.qml:92`, other verbs at `Radio.qml:75`.
- `gpk` (+ a terminal) — `shared/providers/packages/Packages.qml:166,217,260,271`.
- `fd` — `shared/providers/find/Find.qml:130-135`; `sh -c command -v fd` at
  `Find.qml:215`; `xdg-open` at `Find.qml:176-177`.
- `find --version` — `shared/providers/recent/Recent.qml:192`.
- `ryoku-rashin` (Ask/AI) — `shared/AskPanel.qml:109,117,159`.
- `wl-copy` (via `sh -c`) — `shared/AskPanel.qml:167`.
- `kitty -e nvim` — `shared/AskPanel.qml:176`; `xdg-open` at
  `AskPanel.qml:180,184,419`.
- `ryoku-app terminal` (for `Terminal=true` entries) —
  `services/AppLaunch.qml:24,30`, invoked from `Apps.qml:49,63`.
- Action catalog argv (`shared/providers/actions/catalog.js`): `ryoku-shell`
  (`:10-13,33,37`), `ryoku-cmd-caffeine` (`:14`), `ryoku-cmd-game-mode` (`:15`),
  `ryoku-monitor` (`:16`), `ryogami wallpaper` (`:18-19`),
  `ryoku-cmd-nightlight` (`:20`), `sh -c flock … qs -c ryoshot` (`:22`),
  `ryoku-cmd-screenrecord` (`:23`), `ryoku-cmd-color-picker` (`:24`),
  `ryoku-cmd-ocr` (`:25`), `ryoku-cmd-qr-scan` (`:26`),
  `ryoku-cmd-google-lens` (`:27`), `playerctl` (`:29-31`),
  `ryoku-cmd-songrec` (`:32`), `sh -c … qs -c hub` (`:35`),
  `sh -c … qs -c keys` (`:36`).

The launcher's `Windows`/`Mpris` providers use Quickshell services
(`Quickshell.Services.Mpris`, `shared/providers/media/mpris/Mpris.qml:4`) rather
than binaries.

#### Services / daemons

- `ryoku-shell` daemon (`ryoku/shell/ipc/`, Go `main`; socket
  `$XDG_RUNTIME_DIR/ryoku-shell.sock`) — reached only through the `Wm` singleton
  and through spawned `ryoku-shell <verb>` clients `[UNVERIFIED]` for daemon-side
  internals (off-disk beyond `ryoku/shell/ipc/`).
- `ryoku-app` (terminal launcher) and `ryoku-rashin` (AI ask) — helpers, off-disk
  `[UNVERIFIED]`; their PKGBUILDs exist at
  `release/packages/ryoku-rashin/PKGBUILD`.
- `AppLaunch`/`Icons`/`Perf`/`Media`/`Bluetooth`/`Audio`/`Network` singletons
  (shell.services).

#### Qt modules

QtQuick, QtQuick.Layouts, QtQuick.Controls, QtQuick.Shapes, QtQuick.Effects,
QtQml.Models; Quickshell core + `.Io`, `.Wayland`, `.Widgets`,
`.Services.Mpris`, `.Bluetooth`.

#### Fonts

Launcher text resolves through `shared/Singletons/Theme.qml:76-77`
(`Ui.Tokens.ui` = **Space Grotesk**, `Ui.Tokens.mono` = **SpaceMono Nerd Font**,
`ryoku/ui/Singletons/Tokens.qml:106-107`). The launcher's own config exposes a
`fontFamily` defaulting to **JetBrainsMono Nerd Font**
(`shared/Singletons/Config.qml:56,97`) — read from `shell.json`. Material
Symbols Rounded is used directly by the icon-font variants
(`variants/kairos/Main.qml:245,294`, `variants/okshell/Main.qml:258,305`).

#### Assets

- `shared/art/hands-adam.png` — hero/main placeholder art
  (`variants/hero/HeroShutter.qml:89`, `variants/hero/Preview.qml:64`,
  `variants/main/RestDashboard.qml:96`, `variants/main/Preview.qml:136`).
- Colors: `~/.cache/ryoku/colors.json` (`shared/Singletons/Scheme.qml:90`).
- Config/state files read: `~/.config/ryoku/launcher.json`
  (`LauncherConfig.qml:25`), `~/.config/ryoku/shell.json` (`Config.qml:71`),
  `~/.config/ryoku/theme.json` (`Config.qml:107`),
  `~/.config/ryoku/launcher-scripts.json` (`Script.qml:23`),
  `~/.config/ryoku/launcher-snippets.json` / `launcher-quicklinks.json`
  (`Snippets.qml:28,38`), `~/.local/state/ryoku/launcher-usage.json`
  (`Frecency.qml:12`).

#### Network calls

- **Direct HTTP in the launcher's own Weather singleton**:
  `curl -s --max-time 10 https://api.open-meteo.com/v1/forecast…`
  (`shared/Singletons/Weather.qml:56-62`) and the keyless geolocate
  `curl -s --max-time 8 http://ip-api.com/json/?fields=status,city,lat,lon`
  (`Weather.qml:150`).
- **DuckDuckGo instant answers**: `curl -s --max-time 8 <ddg api>`
  (`shared/providers/web/Web.qml:93`; URL built in
  `shared/providers/web/ddg.js:8`).
- Search-engine fallbacks open external URLs (no fetch):
  `shared/providers/web/engines.js:6-12`.
- `AskPanel` may open `http://127.0.0.1:3600/#/chat` (local Rashin server)
  (`shared/AskPanel.qml:184`).

### Control sidebar (Super+Escape) / quick settings

**What Super+Escape actually opens.** `ryoku/hyprland/modules/binds.lua:61`
binds `SUPER + Escape` to the global `ryoku:quicksettings` (declared
`ryoku/wm/binds.go:160`, chord `SUPER + Escape`). The shell registers the
matching in-process `CustomShortcut` `"quicksettings"`
(`shell.qml:781-785`) whose handler is `toggleSurface("quicksettings")` →
`ShellState.requestSurfaceActive("quick-settings", undefined)`
(`shell.qml:481-483`). `requestSurfaceActive` emits on the surface bus with the
focused monitor (`services/ShellState.qml:84-86`); each monitor's
`FrameMenuManager` listens and calls `openSurface(id, …)`
(`modules/bar/Frame.qml:398-413`; `FrameMenuManager.qml:453`). The surface
record for `"quick-settings"` lives in `ryoku/shell/framebars/MenuCatalog.js:32`
(`widgets: ["quick-settings"]`, `minWidth: 410`, `anchor: "left"`) and is hosted
by `MenuWidgetHost` → `MenuQuickSettings`
(`modules/bar/MenuWidgetHost.qml:40,85`). Super+Escape therefore opens
**`MenuQuickSettings`** (the frame-menu sidebar), **not** the qsbar
`ControlCenter`.

**The qsbar ControlCenter is the logo's *other* target.** The qsbar `launcher`
widget (the 力 logo) opens the ControlCenter when `Config.launcherTarget ===
"studio"` (the default) and the Super+Escape quick-settings surface when it is
`"quick"` (`barstyles/qsbar/modules/LauncherWidget.qml:122-128`; toggle in the
rail at `controlcenter/CcRail.qml:253-265` and in
`framebars/menus/quicksettings/QuickSettingsHome.qml:166-174`). The key is
`launcherTarget` in `~/.config/ryoku/shell.json` (default `"studio"`,
`services/Config.qml:106-119,194`).

**Bar style selector (item 2).** Which bar design renders is `Config.barStyle`
in `shell.json`, default `"qsbar"` (`services/Config.qml:36-40,193`). Built-in
styles resolve via `BarProducts.builtins` — `qsbar → barstyles/qsbar/Scene.qml`,
`kairos → barstyles/kairos/Scene.qml` — with `sumi` the painted frame
(`services/BarProducts.qml:48-56,63`). `Frame` loads the scene
(`modules/bar/Frame.qml:457-479`). This section documents the **qsbar** path
(the default) plus the **frame-menu / popout** path (which renders regardless of
style, `FrameMenuManager` with `topBar` mode, `Frame.qml:380`).

**Keep-list scope.** Audio, brightness, network, battery tiles/sliders plus the
sidebar shell itself are the quick-settings items to keep
(`QuickSettingsHome.qml:199-347`). Everything else in the ControlCenter routes
(bar layout, identity, community plugins) and the non-core tabs (weather,
capture, notifications, media, stage, clipboard, AI) are exclusions — see the
last section.

#### Files

**B1 — qsbar ControlCenter (bar settings; logo `studio` target).** All under
`modules/bar/barstyles/qsbar/`:

- `controlcenter/`: `ControlCenter.qml`, `CcRail.qml`, `CcHead.qml`,
  `CcSearch.qml`, `PageMotionStage.qml`, `SearchEngine.js`, `qmldir`.
- `controlcenter/kit/`: `CcTokens.qml`, `CcWidgetList.qml`,
  `CcWidgetColorPopover.qml`, `CcWorkspacePreview.qml`, `CcSwatchGrid.qml`,
  `CcScrollRail.qml`, `BarSilhouette.qml`, `Routes.js`, `Widgets.js`, `qmldir`.
- `controlcenter/routes/`: `BarsRoute.qml`, `IdentityRoute.qml`,
  `LayoutRoute.qml`, `WidgetsRoute.qml`, `DockRoute.qml`, `CommunityRoute.qml`,
  `qmldir`.
- Host: `barstyles/qsbar/VariantRoot.qml:14,259` (`import "controlcenter"`;
  `ControlCenter { id: controlCenter }`), fed by `barstyles/qsbar/Scene.qml:38-51`.

**B2 — Super+Escape quick-settings sidebar (frame menu).**

- Dispatcher: `modules/bar/FrameMenuManager.qml`,
  `modules/bar/FrameMenu.qml`, `modules/bar/MenuWidgetHost.qml`.
- Body: `modules/bar/framebars/menus/MenuQuickSettings.qml` (+ shared
  menu/quick-settings kit in `framebars/menus/`: `QsTile.qml` `QsSlider.qml`
  `QsSection.qml` `QsSeg.qml` `QsIconButton.qml` `QsHoldButton.qml`
  `QsNavRow.qml` `QsTabRail.qml` `QsTip.qml` `MenuButton.qml` `MenuColumn.qml`
  `MenuContainer.qml` `MenuDivider.qml` `MenuSpacer.qml` `MenuHostLoader.qml`
  `MenuWeather.qml` `MenuNetwork.qml` `MenuBluetooth.qml` `MenuAudioInput.qml`
  `MenuAudioOutput.qml` `MenuNotifications.qml` `MenuMedia.qml`
  `MenuClipboard.qml` `MenuTheme.qml` `MenuPowerProfile.qml`
  `MenuQuickActions.qml` `MenuLayoutSwitcher.qml` `MenuClock.qml`
  `MenuClockCard.qml` `QsCalendarEmbed.qml` `AudioDevicePicker.qml`
  `MediaHero.qml` `VolumeFader`/`MenuVolumeFader.qml` `WeatherCard.qml`
  `WeatherMoon.qml` `WallTile.qml` `WallVideo.qml` `Revealer*.qml`).
- Tabs: `framebars/menus/quicksettings/`: `QuickSettingsHome.qml`,
  `QuickSettingsNotifications.qml`, `QuickSettingsWeather.qml`,
  `QuickSettingsCapture.qml`, `QuickSettingsMedia.qml`,
  `QuickSettingsStage.qml`. Tab catalogue:
  `ryoku/shell/framebars/MenuCatalog.js:22-33` (`home, notifications, weather,
  capture, stage`; `MenuQuickSettings.qml:24-33` reads the enabled set).

**B3 — popouts.** Two distinct sets:

- **Frame popouts** (`modules/bar/popouts/`, hosted by the frame menu system):
  `Popout.qml` (base), `AudioPopout.qml`, `BatteryPopout.qml`,
  `NetworkPopout.qml`, `BluetoothPopout.qml`, `BtHero.qml`, `MusicPopout.qml`,
  `MusicHoverPopout.qml`, `SysMonitorPopout.qml`, `CapturePopout.qml`,
  `KeyringPopout.qml`, `PolkitPopout.qml`, `VoicePopout.qml`,
  `DockPreviewPopout.qml`, `PopoutCard.qml`, `PopoutChip.qml`,
  `PopoutAction.qml`, `PopoutBatteryGauge.qml`, `PopoutDetailRow.qml`,
  `PopoutHeadButton.qml`. Wired in `modules/bar/FrameSurface.qml:4,82-178`
  and `modules/bar/PluginPopouts.qml:7`.
- **qsbar barstyle popups** (`modules/bar/barstyles/qsbar/panels/`, real
  `PanelWindow`s instantiated in `VariantRoot.qml:240-260`): `VolumePanel.qml`
  (audio), `BrightnessPanel.qml`, `NetworkPanel.qml`, `BluetoothPanel.qml`,
  `BatteryPanel.qml`, `PowerProfilePanel.qml`, `NotificationPanel.qml`,
  `TrayPanel.qml`, `TrayMenu.qml`, `MprisPanel.qml`,
  `DashboardPopup.qml`, `CpuPanel.qml`, `GpuPanel.qml`, `MemoryPanel.qml`,
  `StoragePanel.qml`, `ThermalsPanel.qml`, `WorkspacePanel.qml`,
  `AiUsagePanel.qml`, `PluginPanel.qml`, `TooltipOverlay.qml`,
  `MicrophonePeakMonitor.qml`, `NetworkManagerAdapter.qml`,
  `ImageCarouselPanel.qml`/`ImageCarouselCarousel.qml`/
  `ImageCarouselHearthstone.qml`, `MediaBrowserPanel.qml`/
  `MediaBrowserCarousel.qml`/`MediaBrowserHearthstone.qml`,
  `ImagePickerModel.js`, `qmldir`.

#### QML imports

**B1 (controlcenter):** `QtQuick`, `QtQuick.Shapes`, `Quickshell`,
`Quickshell.Io`, `Quickshell.Wayland`, `Ryoku.Ui`, `Ryoku.Ui.Singletons`,
`shell.services` (aliased `Services` in `DockRoute.qml:8`), local
`"../modules"`, `"../kit"`, `kit/Routes.js`, `kit/Widgets.js`,
`SearchEngine.js`. (`ControlCenter.qml:1-9`.)

**B2 (quick settings / frame menus):** `QtQuick`, `Quickshell`,
`Quickshell.Io`, `Quickshell.Bluetooth`, `Quickshell.Services.Mpris`,
`Quickshell.Dialogs`(QtQuick.Dialogs), `QtMultimedia`, `Ryoku.FrameBars`,
`Ryoku.Ui.Singletons`, `shell.services`, local `".." as Pill` /
`".." as Menus`, `"../../../../components"`, `stage/Singletons`,
`services/lib/weather.js`, `framebars/widgets`. (`MenuQuickSettings.qml:1-6`;
union over `framebars/menus/`.)

**B3 (popouts):** `QtQuick`, `Quickshell`, `Quickshell.Io`,
`Quickshell.Wayland`, `Quickshell.Bluetooth`, `Quickshell.Widgets`,
`Quickshell.Services.Mpris`, `QtQuick.Effects`, `Qt.labs.folderlistmodel`,
`Ryoku.Blobs`, `Ryoku.Ui.Singletons`, `shell.services`,
`"../../../components"`, `utils/artcolor.js`, `framebars/menus`.
(`Popout.qml:1-9`; union over `popouts/`.)

**B3 (qsbar panels):** `QtQuick`, `QtQuick.Shapes`, `QtQuick.Effects`,
`Quickshell`, `Quickshell.Io`, `Quickshell.Wayland`, `Quickshell.Widgets`,
`Quickshell.Services.Pipewire`, `Quickshell.Services.Notifications`,
`Quickshell.Services.Mpris`, `Quickshell.Bluetooth`, `Quickshell.Networking`,
`Ryoku.Ui.Singletons`, `Ryoku.PluginKit`, `shell.services`, local
`"../modules"`, `"../RyokuPower.js"`, `"../IconMap.js"`.

#### Singletons

- **shell.services** bound by the sidebar: `ShellState` (bus, `shell.qml:513-528`,
  `Frame.qml:398-413`), `Config` (`MenuQuickSettings.qml:5`,
  `CcRail.qml:6`), `Audio` (Pipewire; `QuickSettingsHome.qml:299-321`),
  `Battery` (UPower; `QuickSettingsHome.qml:121,133,151-156`),
  `Network` (`QuickSettingsHome.qml:210-212`), `Bluetooth`/`Toggles`
  (`QuickSettingsHome.qml:213,223-227`), `Toggles` (`Toggles.qml:20-53`),
  `PowerProfiles` (`QuickSettingsHome.qml:367-379`), `Nightlight`, `Flags`,
  `SessionActions` (`QuickSettingsHome.qml:86`), `Dock` (`CcRail`/`DockRoute`),
  `Perf`, `Icons`, `Weather`, `Media`, `Music`, `Updates`,
  `KeyboardLayout`, `Tray`, `Notifs` (`MenuWidgetHost.qml:78-90`),
  `Devices` (backlight/DDC brightness, `services/Devices.qml`).
- **Ryoku.FrameBars** (`ryoku/shell/framebars/qmldir:1`): `MenuCatalog`,
  `BarCatalog`, `FrameBars` (`MenuQuickSettings.qml:4`).
- **Ryoku.Ui.Singletons**: `Tokens`, `I18n`, `Spawn`, `Wm`, `Ink`, etc.
  (`ControlCenter.qml:8`, `MenuQuickSettings.qml:6`).
- **qsbar local**: `Theme` (the qsbar root, `qsbar/qmldir:3`;
  `VariantRoot.qml:25-27`), `BarCatalog`/`BarPlugins` (`core/BarCatalog.qml`,
  `Theme.qml:264-265`), `CcTokens` (`controlcenter/kit/CcTokens.qml`).

#### IPC verbs used

- **qsbar IpcHandler** (`target: "qsbar"`, `VariantRoot.qml:274-281`):
  `settings(route)` (opens/`close` the ControlCenter) and
  `layout()` (returns `theme.barLayout` JSON).
- **IpcRouter verbs** (`core/IpcRouter.qml:81-117`): target `lifecycle`
  `ready`; `layout` `lock`/`unlock`; `ryoku.system-update` `refresh`;
  `reactor` `test`/`monsweep`/`clear`; `theme` `apply`/`applyLauncher`/
  `reload`; `picker` `theme`/`wallpaper`/`screenshots`/`videos`.
- **Shell IpcHandler** (`target: "shell"`, `shell.qml:715-743`):
  `openSurface`, `closeSurface`, `keyringPrompt`, `keyringHide`, `voiceShow`,
  `voiceOff`, `voiceHide`, `pluginPopout`, `bar`, `closeAllMenus`,
  `sessionConfirm`; plus `visualizer` (`shell.qml:748-760`) and `keypresses`
  (`shell.qml:762-777`).
- **Daemon socket verbs** (`$XDG_RUNTIME_DIR/ryoku-shell.sock`, line protocol
  `subscribe <topic>` / `call <method> <json>`): `settings.patch`
  (`Theme.qml:3257`, `services/Config.qml:97,113`, `services/Dock.qml:149`),
  `weather.configure`/`weather.retry` (`services/Weather.qml:70-78`),
  `network.*` (`services/Network.qml:90`), `session.*`
  (`services/SessionActions.qml:19`), plus `subscribe weather|network|tray|
  updates|powerprofiles|nightlight|music|calendar|clipboard|osd` on the
  respective services, and `wm` via `Wm` (`Wm.qml:317`).
- **Help/action spawns that re-enter the daemon**: `ryoku-shell hub open
  connections` (`Theme.qml:2541-2542`), `ryoku-shell hub open`
  (`MenuQuickActions.qml:54`), `ryoku-shell lock` (`QuickSettingsHome.qml:93`,
  `MenuQuickActions.qml:55`), `ryoku-shell hub open input`
  (`qsbar/modules/LayoutWidget.qml:105`).

#### Binaries shelled out

- ControlCenter shell-out: `sh -c "flock -n -o /tmp/ryoku-hub.lock qs -c hub"`
  (`controlcenter/ControlCenter.qml:215`); Hub rail button `rj` when link
  clicked; `CommunityRoute.qml` runs `ryoku plugin add|export|share|remove`
  (`:85,88,89,91`), `xdg-open` (`:265,270`), `ryostore open plugins` (`:325`);
  `LayoutRoute.qml:561` opens `ryostore open plugins`; `xdg-open` in the Hub
  button (`ControlCenter.qml:215`).
- qsbar Theme processes (`Theme.qml`): `cat` (`:412`, `:3084`, `:3634`),
  `bash -c` collect/detect (`:1356,1390,1409,1966,1981,1995,2013,2038,2300,
  2327,2496,2531,3565`), `systemctl --user start ryoku-ai-usage.service`
  (`:1460`), `ps -eo` (`:1989`), `lsblk -J` (`:2045`), `pgrep -x hypridle`
  (`:2388`), `sh -c command -v makoctl` (`:2400`), `makoctl mode` (`:2410`),
  `pgrep -o -f ^gpu-screen-recorder` (`:2424`), `true` (`:2456`),
  `systemctl is-active NetworkManager` (`:2531`), plus `bash -c` AI-usage
  readers (`:1356,1390,1409`).
- **Shared brightness fader** (used by the quick-settings Home slider,
  `QuickSettingsHome.qml:323-327` → `modules/bar/BrightnessControl.qml`):
  `ddcutil` (`BrightnessControl.qml:127`; `services/Devices.qml:96,160`),
  `ryoku-hw-backlight` + `brightnessctl` (`services/Devices.qml:131-132`),
  `nvibrant` (screen vibrance, `services/Devices.qml` header `:7`).
- Media/sound popups: `pavucontrol` (fallback `notify-send`) in
  `panels/VolumePanel.qml:681`; `upower` + `brightnessctl` via `RyokuPower.js`
  (`RyokuPower.js:16,32,35-50`; call sites `panels/BrightnessPanel.qml:216,238,
  246`, `panels/BatteryPanel.qml:202`; widgets
  `modules/BrightnessWidget.qml:113,129,147,155`); `kitty btop`
  (`panels/BatteryPanel.qml:230`, `panels/CpuPanel.qml:358`);
  `rfkill unblock|block wifi` (`panels/NetworkPanel.qml:152`, `:1542`);
  `ryoku-shell hub open connections` for Wi-Fi/BT settings
  (`panels/NetworkPanel.qml:1433`, `panels/BluetoothPanel.qml:510`,
  `modules/NetworkWidget.qml:263`, `modules/BluetoothWidget.qml:74`).
- Frame popouts: `bluetoothctl info` (`popouts/BtHero.qml:73`), `rfkill unblock
  bluetooth` (`popouts/BluetoothPopout.qml:101`), `bash -c` capture
  (`popouts/CapturePopout.qml:112`), `nautilus` (`CapturePopout.qml:468`),
  `playerctl` (`qsbar/modules/MprisArtwork.qml:56`).
- Quick-settings home/session: `systemctl reboot|poweroff`
  (`QuickSettingsHome.qml:103,110`), `ryoku-shell lock` (`:93`),
  `ryoku-cmd-color-picker|ocr|qr-scan|google-lens`
  (`MenuQuickActions.qml:53`; `QsTabRail.qml:62,66,70,78`),
  `ryoku-shell hub open` (`QsTabRail.qml:74`).

#### Services / daemons

- `ryoku-shell` daemon (Go, `ryoku/shell/ipc/`; socket
  `$XDG_RUNTIME_DIR/ryoku-shell.sock`) — the sidebar's audio/network/weather/
  power/battery/updates state all arrive as daemon topic frames
  (`services/*.qml` `subscribe` calls). `[UNVERIFIED]` daemon internals.
- PipeWire/WirePlumber via `Quickshell.Services.Pipewire`
  (`services/Audio.qml:1-10`; `qsbar/modules/AudioData.qml`).
- NetworkManager via the daemon `network` topic (`services/Network.qml:9-12`)
  and `panels/NetworkManagerAdapter.qml`.
- UPower via `Quickshell.Services.UPower` (`services/Battery.qml:1-5`,
  `qsbar/Theme.qml:4`) and the `upower` CLI (`RyokuPower.js:35`).
- `ryoku-ai-usage.service` (user systemd; `qsbar/Theme.qml:1460`).
- `ryostore`/`ryoku plugin` (community widgets; `CommunityRoute.qml:85`).
- The Hub (`qs -c hub`) and `ryostore` are off-disk helpers `[UNVERIFIED]`.

#### Qt modules

QtQuick, QtQuick.Shapes, QtQuick.Effects, QtQuick.Dialogs, QtMultimedia,
Qt.labs.folderlistmodel; Quickshell core + `.Io`, `.Wayland`, `.Widgets`,
`.Bluetooth`, `.Networking`, `.Services.Mpris`, `.Services.Pipewire`,
`.Services.Notifications`, `.Services.UPower`; C++ QML module **Ryoku.Blobs**
(`popouts/Popout.qml:4`, `Frame.qml:6`) `[UNVERIFIED]` (built from
`ryoku/shell/plugin`, not in the sparse checkout).

#### Fonts

- qsbar Theme: `mono` = **JetBrainsMono Nerd Font** (`qsbar/Theme.qml:121`);
  CJK seal/glyphs use **Noto Sans CJK JP** (`Theme.qml:3042`,
  `controlcenter/routes/IdentityRoute.qml:133`).
- ControlCenter kit: **Adwaita Mono** (`kit/CcWorkspacePreview.qml:128`) and
  **Noto Sans CJK JP** (`kit/CcWorkspacePreview.qml:142`).
- qsbar widget icons: **Material Symbols Rounded**
  (`qsbar/modules/IconText.qml:10`); Nerd Font glyphs
  (`qsbar/modules/PacmanMarker.qml:47`, `WorkspaceWidget.qml:521`).
- Quick-settings/menu chrome: `Ryoku.Ui.Singletons.Tokens` — `ui` = Space
  Grotesk, `mono` = SpaceMono Nerd Font (`ryoku/ui/Singletons/Tokens.qml:106-107`),
  read as `Theme.fontPrimary` in `QuickSettingsHome.qml:70,126,158`.

#### Assets

- qsbar logos/art: `barstyles/qsbar/assets/` — `arch-header-arch.png`,
  `arch-header-linux.png`, `bob2.png`, `bob3.png`, `claude.svg`,
  `codex.svg`, `codex-cli.svg`, `gpu-card.svg`, `hdd-mark.svg`,
  `omacom-text.png`, `opencode-mark.svg`.
- qsbar shaders: `barstyles/qsbar/shaders/logo-tint.frag.qsb`,
  `stream.frag`, `stream.frag.qsb`; also `barstyles/qsbar/quotes.txt`,
  `LICENSE`.
- Palette/state files: `~/.cache/ryoku/colors.json` (`Theme.qml:18`),
  `~/.cache/quickshell_widgets_v2` (`Theme.qml:2904`),
  `~/.cache/quickshell_barorder_v2` (`Theme.qml:404`),
  `~/.local/state/ryoku/current` (`Theme.qml:3565`),
  `~/.local/state/ryoku/store/barstyles.json`
  (`services/BarProducts.qml:11,20`).

#### Network calls

- **No direct HTTP** from the ControlCenter or `MenuQuickSettings` chrome. The
  quick-settings **Weather** tab (`QuickSettingsWeather.qml:1-40` →
  `MenuWeather.qml`) binds `shell.services.Weather`, which makes **no HTTP**: it
  `subscribe`s the daemon's `weather` topic (`services/Weather.qml:9,104`) and
  the fetch happens daemon-side.
- Thumbnail image fetches when media art is shown:
  `https://i.ytimg.com/vi/<id>/mqdefault.jpg`
  (`qsbar/modules/MprisArtwork.qml:32`).
- Speed-test module: `https://speed.cloudflare.com/__down` / `__up`
  (`qsbar/modules/CloudflareSpeedTest.qml:21-22`).
- GitHub URLs are only string-parsed/opened externally
  (`panels/ImageCarouselHearthstone.qml:350`,
  `panels/ImageCarouselPanel.qml:347`).

### Necessity / exclusions

Labels: `[READ]` verified by reading on-disk source; `[UNVERIFIED]` depends on a
helper/daemon not in the sparse checkout. Nothing here was executed, so nothing
is `[TESTED]`.

**Launcher — keep (core).** `Launcher.qml`, `catalog.json`, the `hero` variant
(default) `variants/hero/*`, `shared/lib/*`, `shared/Singletons/*`,
`shared/providers/Provider.qml`, `Providers.qml`, `apps/*` (app launching),
`actions/*`, `requeststate.js`, `shared/Spinner.qml`,
`shared/CategoryTabs.qml`. These satisfy "launcher" on the keep-list. `[READ]`

**Launcher — exclusion candidates (opt back in by config/file):**

- **Calculator** `shared/providers/calc/*` (`Calc.qml:143` → `ryoku-cmd-calc`).
  Disable by removing `Calc {}` from `Providers.qml:25` (or the `calc` prefix
  route). `[READ]`
- **Clipboard action** (`actions/catalog.js:11`, `ryoku-shell menu
  quick-settings#clipboard`). Remove the catalog entry. `[READ]`
- **Web search / DuckDuckGo** `shared/providers/web/*` (`Web.qml:93`).
  Remove `Web {}` (`Providers.qml:30`) to stop the only launcher search HTTP
  call. `[READ]`
- **AI / Ask & Answer panels** `shared/AskPanel.qml`, `shared/AnswerPanel.qml`
  (`ryoku-rashin`, off-disk `[UNVERIFIED]`). Dispatch entries are behind
  prefixes (`providerids.js`); remove the panels and their dispatcher hooks to
  fully drop AI. `[READ]`
- **Find / file search** `shared/providers/find/*` (`fd`, `xdg-open`).
  Remove `Find {}` (`Providers.qml:23`). `[READ]`
- **Packages / gpk** `shared/providers/packages/*` (`gpk`).
  Remove `Packages {}` (`Providers.qml:25`); also drops the `gpk` dependency.
  `[READ]`
- **Radio** `shared/providers/radio/*`, `shared/Singletons/Radio.qml`
  (`ryoku-cmd-radio`). Remove `RadioTuner {}` (`Providers.qml:26`). `[READ]`
- **Snippets / quicklinks** `shared/providers/snippets/*`.
  Remove `Snippets {}` (`Providers.qml:29`). `[READ]`
- **Scripts / rofi shim** `shared/providers/script/*`, `lib/rofiscript.js`.
  Remove `Script {}` (`Providers.qml:28`). `[READ]`
- **Recent** `shared/providers/recent/*`, `shared/Singletons/Frecency.qml`.
  Remove `Recent {}` (`Providers.qml:27`); note Frecency also ranks Apps, so
  dropping it changes app ordering. `[READ]`
- **Windows switcher provider** `shared/providers/windows/*`.
  Remove `Windows {}` (`Providers.qml:31`). `[READ]`
- **Weather in the launcher** `shared/Singletons/Weather.qml` + the mosaic art:
  set `showWeather=false` in `launcher.json` (`LauncherConfig.qml:17,42`) to
  hide it; delete the singleton to drop the two `curl` calls
  (`Weather.qml:56,150`). `[READ]`
- **Wallpaper-switch actions** (`actions/catalog.js:18-19`, `ryogami`).
  Remove those catalog rows. `[READ]`
- **Extra launcher variants** `variants/main`, `variants/okshell`,
  `variants/kairos`: keep only `variants/hero` and trim `catalog.json:6-37`
  to one entry (keep `default`/`fallback` pointing at `hero`). `[READ]`
- **Dev-only**: all `*.test.mjs`, `shared/contrast.js` tests, and the whole
  `qa/` folder (`qa/run.sh`, `qa/fixtures.sh`, `qa/scenarios.json`) are not
  needed at runtime. `[READ]`

**Control sidebar — keep (core).** The sidebar shell + audio/brightness/network/
battery: `FrameMenuManager`/`FrameMenu`/`MenuWidgetHost`, `MenuQuickSettings`,
the `Qs*` kit, `QuickSettingsHome.qml` (tiles + volume/mic sliders +
`BrightnessControl` at `:323-327`), the audio/network/bluetooth sub-pages
(`MenuNetwork`, `MenuBluetooth`, `MenuAudioInput`, `MenuAudioOutput`,
`AudioDevicePicker`), `FrameSurface` + `AudioPopout`/`BatteryPopout`/
`NetworkPopout`/`BluetoothPopout`, and the qsbar `panels/VolumePanel`,
`BrightnessPanel`, `NetworkPanel`, `BatteryPanel`, `NetworkManagerAdapter`.
On Hyprland the compositor `SUPER + Escape` bind
(`ryoku/hyprland/modules/binds.lua:61`) is the trigger; keep the shell
`CustomShortcut "quicksettings"` (`shell.qml:781-785`). `[READ]`

**Control sidebar — exclusion candidates:**

- **Weather tab** (`QuickSettingsWeather.qml`, `MenuWeather.qml`): drop
  `"weather"` from `MenuCatalog.js:30` `quickSettingsDefaults` (or the
  `quick-settings` menu `modules` list in `shell.json`). This also drops the
  daemon weather fetch trigger. `[READ]`
- **Capture tab** (`QuickSettingsCapture.qml`, `CapturePopout.qml`,
  `ryoshot`/screenshot): drop `"capture"` from `MenuCatalog.js:30`. `[READ]`
- **Notifications tab** (`QuickSettingsNotifications.qml`, `MenuNotifications`):
  drop `"notifications"`. (Note: notifications as a top-level surface is on the
  keep-list; only this *tab* is optional.) `[READ]`
- **Media/Stage tabs** (`QuickSettingsMedia.qml`, `QuickSettingsStage.qml`,
  `MenuMedia`, `MediaHero`, `WallTile`, `WallVideo`): drop `"media"`/`"stage"`.
  `[READ]`
- **Clipboard** (`MenuClipboard.qml`, `MenuQuickActions` clipboard action):
  remove; the launcher catalog clipboard row too (`catalog.js:11`). `[READ]`
- **OCR / QR / Google Lens / colour-picker quick actions**
  (`MenuQuickActions.qml:53`, `QsTabRail.qml:62,66,70,78`; launcher
  `catalog.js:24-27`): remove the tile/rail entries. `[READ]`
- **AI usage widget/panel** (`qsbar/modules/ClaudeWidget.qml`,
  `panels/AiUsagePanel.qml`, `ryoku-ai-usage.service`; `Theme.qml:1460`):
  hidden by default (`modClaude: false`, `Theme.qml` mod flags) — set/keep
  `aiTools`/`claude` off in `shell.json .qsbar` or drop the widget. `[READ]`
- **Community / plugin runtime** (`controlcenter/routes/CommunityRoute.qml`
  → `ryoku plugin`, `ryostore`; `qsbar/panels/PluginPanel.qml`,
  `qsbar/BarPlugins.qml`): remove the Community route
  (`controlcenter/kit/Routes.js:32-34`) and the plugin host. This is the single
  biggest off-keep-list off-disk dependency (`ryostore`, `[UNVERIFIED]`).
  `[READ]`
- **ControlCenter bar-settings routes** (`BarsRoute`, `IdentityRoute`,
  `LayoutRoute`, `WidgetsRoute`, `DockRoute`): not on the keep-list. They are
  the logo's `studio` target; set `launcherTarget: "quick"` in `shell.json`
  (`Config.qml:106-119`) so the logo opens quick settings instead, then the whole
  `controlcenter/` tree (≈4.3k LOC) plus its `IpcHandler target "qsbar"` can be
  dropped. `[READ]`
- **Wallpaper picker / carousel / media-browser panels**
  (`panels/ImageCarousel*`, `panels/MediaBrowser*`,
  `ryogami/wall-ui`): gate off; the Wallpaper selector itself is on the
  keep-list (via ryogami), so keep only what it needs. `[READ]`
- **System-monitor panels/widgets** (`CpuPanel`, `GpuPanel`, `MemoryPanel`,
  `StoragePanel`, `ThermalsPanel`, `panels/DashboardPopup.qml`, the
  sysmon/cpu/mem/gpu/storage widgets + their `bash -c` collectors in
  `Theme.qml:1964-2047`): optional; each is guard-gated by
  `modCpu/modMemory/...` in `shell.json .qsbar`. `[READ]`
- **Cloudflare speed test** (`qsbar/modules/CloudflareSpeedTest.qml`): the only
  direct control-side network caller besides thumbnail fetches; remove it.
  `[READ]`
- **Tray/MPRIS panels** (`TrayPanel`, `TrayMenu`, `MprisPanel`, `MprisWidget`,
  `MprisArtwork`): tray + now-playing; tray is on the keep-list, the MPRIS
  artwork thumbnail fetch (`i.ytimg.com`) is not. `[READ]`
- **Dev-only**: `Theme.qml` debug processes, test harnesses, `*.test.mjs`,
  `qa/`. `[READ]`

**Risks / caveats for the owner.** `[UNVERIFIED]` — Ryoku.Blobs (C++
QML module) must still be built/installed for `Frame` and `Popout`, and the
qsbar panels import `Ryoku.PluginKit`; dropping the plugin runtime may not be
possible without patching those imports. `[UNVERIFIED]` — `ryoku-shell` daemon
must keep the `weather`/`network`/`audio`/`settings.patch` topics or the
sidebar's audio/network/weather/battery bindings go dead. `[READ]` — the
`launcherTarget` and `barStyle` keys live in `shell.json`; both must survive in
Mei's own config dir with the same names or the logo/sidebar wiring breaks.

---

## 03 — Wallpaper and theming (matugen)

Dependency map for the wallpaper → palette path in upstream **Ryoku**
(`0.75.5-beta.20` @ `98a0368253d9628be72b853985878a5db90e1547`), read from the
sparse checkout at `~/projects/mei/upstream/` (read-only) plus off-disk trees via
`git show HEAD:<path>`. Scope: the `ryogami` wallpaper daemon (`ryoku/shell/ryogami/`),
the shell palette pipeline (`ryoku/shell/ipc/`), the shell QML that paints it
(`ryoku/shell/quickshell/shell/modules/wallpaper/`), the matugen config/templates
(`ryoku/shell/matugen/`), the palette consumers (`ryoku/ui`, qsbar `Theme.qml`), and
the optional `palette-bridge`.

Labels: **[TESTED]** I ran the command in this session; **[READ]** read from
committed source / blob sizes; **[UNVERIFIED]** inferred or not confirmed by
execution. Nothing here was built or run against the Ryoku tree. Citations are
`path:line` for content and `path` + bytes for sizes.

**Headline correction (the brief's premise is wrong):** matugen is **not** run by
`ryoku/shell/ryogami/daemon/`. It is run by the **`ryoku-shell` Go IPC daemon** in
`ryoku/shell/ipc/matugen.go`. The `ryogami` PKGBUILD comment still says "matugen
(palette on apply)" (`release/packages/ryogami/PKGBUILD`), and `ryogami.go`'s header
still calls ryogami "the Rust wallpaper daemon"; both are stale — the daemon is Go
(`ryoku/shell/ryogami/daemon/go.mod`) and it never invokes matugen.

---

### Pipeline overview

One image change drives two independent consumers: the pixels (ryogami → QML
backdrop) and the palette (`ryoku-shell` daemon → matugen → `colors.json` →
singletons). [READ]

1. **Trigger.** The bar image carousel shells out
   `["ryogami","wallpaper","set",path]`
   (`ryoku/shell/quickshell/shell/modules/bar/barstyles/qsbar/panels/ImageCarouselCarousel.qml:225`,
   `…/ImageCarouselPanel.qml:216`, `…/ImageCarouselHearthstone.qml:223`); the picker
   runs `ryogami wallpaper ui` (`…/qsbar/panels/…`, `bar/Frame.qml:72,406`) and the
   keybinds run `ryogami wallpaper ui` / `ryogami wallpaper random`
   (`ryoku/hyprland/modules/binds.lua:62-63`). The picker itself calls the JSON-RPC
   `wall.apply` (`ryoku/shell/ryogami/wall-ui/qml/services/DaemonClient.qml:188-203`).
2. **ryogami applies + publishes.** `wallpaperVerb` (`ryoku/shell/ryogami/daemon/verbs.go:25-102`)
   → `applyWallpaper` → surface republish. It persists `~/.cache/ryogami/outputs.json`
   (`apply.go:184,277`) and `~/.local/state/ryoku-wallpaper` (`apply.go:200-208,236-239`),
   then publishes one coalesced `{default, outputs}` frame on the **`wallpaper`
   topic** of `$XDG_RUNTIME_DIR/ryogami.sock` (`proto.go:9-12,87-93`).
3. **Shell QML renders the pixels.** `Wallpaper.qml` subscribes
   (`write("subscribe wallpaper\n")`, `…/wallpaper/Wallpaper.qml:56,65-89`), parses
   the frame (`WallpaperFrame.qml:19-40`), and `modules/desktop/Desktop.qml:431`
   instantiates `WallpaperMod.Backdrop`, which reveals the image through a GPU
   shader (`Backdrop.qml:414-445`) or plays a live clip with QtMultimedia
   (`Backdrop.qml:447-461`). The shell root wires the bridge in `shell.qml:177-193`.
4. **`ryoku-shell` daemon mirrors the topic.** `watchRyogami`
   (`ryoku/shell/ipc/ryogami.go:188-227`) connects to the same socket and
   `consumeRyogamiFrames` (`:163-182`) computes `srcChanged`; on a change it calls
   `d.scheduleTheme()` (`:178-180`).
5. **Theme pass.** `scheduleTheme` (`ryoku/shell/ipc/theming.go:157-162`) pokes a
   buffered channel; `paintWorker` (`theming.go:171-225`) picks the current still and
   calls `d.matugenApply(pic)` (`theming.go:208`, `matugen.go:556-607`).
6. **matugen, two passes** (see Q1). The Go daemon authors `~/.cache/ryoku/colors.json`
   itself (`matugen.go:573`) and fans the same palette into the app templates
   (`matugenRenderTemplates`, `matugen.go:1145-1183`).
7. **Reload / push.** `matugenReload` (`matugen.go:1284-1301`) sets gsettings, pokes
   kitty, and `nudgePalette()` pushes `qs -c shell ipc call theme reload`
   (`matugen.go:1310-1312` → `ipc/actions.go:58-77` → `IpcRouter.qml:104-109`).
8. **Consumers read the palette.** Every `Scheme.qml`, `Theme.qml` and `Tokens.qml`
   watches `~/.cache/ryoku/colors.json` with a `FileView` (see *Singletons*).

A fixed named theme short-circuits step 5-6: `paintWorker` runs
`matugenApplyStatic` from the theme catalog instead (`theming.go:178-195`,
`matugen.go:681-700`), so the two sources never write `colors.json` on one trigger.

---

### Q1 — Who runs matugen, and what it writes

**Answer: the `ryoku-shell` Go daemon, in `ryoku/shell/ipc/matugen.go`.** ryogami
never touches matugen. The trigger is a `wallpaper`-topic frame change mirrored by
`ipc/ryogami.go`, not a matugen call inside the wallpaper daemon.

matugen is installed `[TESTED]` (`matugen 4.2.0-1`, `/usr/bin/matugen`). The daemon
runs it in **two passes** [READ]:

**Pass 1 — scheme generation (stdout only, `--dry-run`):**

```
matugen image <img> -t <schemeType> -m <dark|light>
        --contrast <c> --lightness-dark <ld> --lightness-light <ll>
        --source-color-index <i> --prefer <pref> --json hex --dry-run
```

argv built in `matugenArgs` (`matugen.go:157-190`); executed by `runMatugenCapture`
(`matugen.go:774-783`). `schemeType` defaults to `scheme-tonal-spot` (`:79`); `mode`
is resolved by `resolveMode` from the knobs (`light|dark|sun|smart`, `:209-228`);
`prefer` is required (the installed matugen refuses non-interactive source pick
without it). A video wallpaper is first sampled to a PNG still by `liveFrame`
(`theming.go:74-104`, via `ffmpeg`) because "matugen decodes images only"
(`matugen.go:552-563`). Stdout is parsed by `parseMatugenPalette` (`:788-823`) and
`parseMatugenTones` (`:830-859`).

**Pass 2 — templating (writes files):**

```
matugen -c <filtered-config.toml> json <carrier.json>
```

`matugenRender` (`matugen.go:1249-1256`). The filtered config is the shipped
`config.toml` (+ `apps.toml` when app-theming is on) with only the roster-enabled
`[templates.*]` blocks (`filterMatugenConfig`, `:1121-1138`;
`matugenRenderFiltered`, `:1235-1245`). The carrier is `matugenShellPalette` wrapped
in matugen's nested shape (`matugenCarrier`, `:1024-1061`), written to
`~/.cache/ryoku/matugen-carrier.json` (`:1148-1149`).

**Everything the pipeline writes** [READ]:

| Path | Written by | Citation |
|---|---|---|
| `~/.cache/ryoku/colors.json` | **the Go daemon**, not matugen (base16 + camelCase M3 roles) | `matugen.go:573` (write), `:1011-1019` (shape), `:1782-1784` (path) |
| `~/.cache/ryoku/tones.json` | Go daemon (six tonal ramps) | `matugen.go:594`, `:1788-1790` |
| `~/.cache/ryoku/matugen-carrier.json` | Go daemon (pass-2 carrier) | `matugen.go:1148-1149` |
| `~/.cache/ryoku/active-config.toml`, `active-apps.toml` | Go daemon (filtered configs) | `matugen.go:1240-1244` |
| `~/.cache/ryoku/hypr-colors.lua` | matugen (template `hypr`) | `matugen/config.toml:15-17` |
| `~/.cache/ryoku/share-picker.css` | matugen (template `sharepicker`) | `matugen/config.toml:26-28` |
| `~/.cache/ryoku/kdeglobals-colors.conf` | matugen (template `kde`); Go merges into `~/.config/kdeglobals` | `matugen/config.toml:44-46`; merge `matugen.go:1421-1453` |
| `~/.config/kitty/current-theme.conf` | matugen (template `kitty`) | `matugen/config.toml:11-13` |
| `~/.config/btop/themes/ryoku.theme` | matugen (template `btop`) | `matugen/config.toml:19-21` |
| `~/.config/qt6ct/colors/ryoku.conf` | matugen (template `qt6ct`) | `matugen/config.toml:30-32` |
| GTK / Discord / Obsidian / Zed / … (21 blocks) | matugen, only when app-theming on | `matugen/apps.toml` (whole file) |
| `~/.config/ryoku/matugen.json` | **read/watch**, written by Hub/wall-ui, not matugen | `matugen.go:1773-1777`; watch `:1730-1746` |

Template output roots are pre-created by `matugenEnsureDirs` (`matugen.go:1794-1829`).
`~/.cache/ryoku/colors.json` is authored by the Go control plane on **both** the
wallpaper path (`:573`) and the static-theme path (`:690`) — matugen itself never
writes it. This is the single file every Quickshell singleton watches.

Side effects of a pass (not files): `matugenReload` runs
`gsettings set org.gnome.desktop.interface color-scheme/gtk-theme/accent-color`,
`pkill -USR1 -x kitty` (`matugen.go:1284-1301,1356-1363,1372-1391`), and the
`qt6ct` template's `post_hook` runs `ryoku-cmd-folders` and
`ryoku-cursor-material-recolor` (`matugen/config.toml:33-39`). `applyFont`
(`matugen.go:1623-1632`) is the same shape for fonts.

---

### Files

| Path (relative to `upstream/`) | Role |
|---|---|
| `ryoku/shell/ipc/matugen.go` | the matugen pipeline: scheme gen, `colors.json`/`tones.json`, carrier, template fan-out, reload, knobs, all path helpers |
| `ryoku/shell/ipc/theming.go` | `scheduleTheme`, `paintWorker`, `liveFrame`, `frameOffset`, `wallState` |
| `ryoku/shell/ipc/ryogami.go` | shell→ryogami socket bridge, `watchRyogami`, `consumeRyogamiFrames`, `depthPublish` |
| `ryoku/shell/ipc/actions.go` | `ipcCall` / `qsSelect` (`qs -c <cfg> ipc call …`) |
| `ryoku/shell/matugen/config.toml` | core template map (kitty, hypr, btop, sharepicker, qt6ct, kde) |
| `ryoku/shell/matugen/apps.toml` | app-suite template map (gtk3/4, discord, obs, zed, heroic, telegram, steam, cava, ghostty, micro, papirus, fish, yazi, obsidian, zathura, alacritty, tmux, sidra, ryotunes) |
| `ryoku/shell/matugen/templates/` | the matugen input templates |
| `ryoku/shell/ryogami/daemon/{main,daemon,verbs,rpc,proto,config,apply,surface,store,topics,scan,livewall,effects,grade,optimize,upscale,playlist,daynight,transitions}.go` | the wallpaper daemon (own Go module, stdlib-only) |
| `ryoku/shell/ryogami/wall-ui/` | the vendored skwd-wall picker (QML + matugen templates for previews + services) |
| `ryoku/shell/livewall/livewall.c` + `build.sh` | the C `ryogami-live` video-wallpaper layer-shell player |
| `ryoku/shell/quickshell/shell/modules/wallpaper/{Wallpaper,WallpaperFrame,Backdrop,OverviewBackdrop}.qml` + `reveal.frag(.qsb)` + `skwd/` | the shell-side topic bridge and reveal renderer |
| `ryoku/ui/Singletons/Tokens.qml`, `…/Singletons/Scheme.qml`, `…/qsbar/Theme.qml` | palette consumers |
| `ryoku/shell/systemd/user/{ryogami,ryoku-shell}.service` | the two session units |
| `ryoku/palette-bridge/main.go` | optional localhost HTTP palette bridge (SPA integrations) |
| `docs/theming.md` | upstream's own description of the pipeline |

---

### QML imports

Wallpaper + palette path only [READ]:

| File | Imports |
|---|---|
| `shell/modules/wallpaper/Wallpaper.qml:3-5` | `QtQuick`, `Quickshell`, `Quickshell.Io` |
| `shell/modules/wallpaper/WallpaperFrame.qml:1` | `QtQuick` |
| `shell/modules/wallpaper/Backdrop.qml:3-5` | `QtQuick`, `QtMultimedia`, `"Singletons"` |
| `shell/modules/desktop/Desktop.qml:20` | `import "../wallpaper" as WallpaperMod` |
| `shell/shell.qml:17-18` | `modules/wallpaper`, `modules/wallpaper/Singletons` |
| `ui/Singletons/Tokens.qml` | `QtQuick`, `Quickshell`, `Quickshell.Io` (+ `Ryoku.Ui` types) |
| `shell/modules/bar/barstyles/qsbar/Theme.qml:1-8` | `QtQuick`, `Quickshell`, `Quickshell.Io`, `Ryoku.Ui.Singletons`, `shell.services` |
| `shell/ryogami/wall-ui/qml/Colors.qml:1-4` | `QtQuick`, `Quickshell`, `Quickshell.Io`, `"services"` |

`Quickshell.Io` is what provides the `FileView`/`Socket`/`Process` primitives the
whole path rests on. `Backdrop.qml` is the only file on the path that needs
`QtMultimedia` (live-wallpaper playback).

---

### Singletons

The palette reaches the UI through per-surface `Scheme`/`Theme`/`Tokens`
singletons, all watching `$XDG_CACHE_HOME/ryoku/colors.json` (`~/.cache/ryoku/colors.json`)
with a `FileView { watchChanges: true }` [READ]:

| Singleton | `colors.json` read | Surface |
|---|---|---|
| `ryoku/ui/Singletons/Tokens.qml` | `:348-356` | shared design system (`Ryoku.Ui.Singletons`) |
| `shell/services/Scheme.qml` | `:99` | shell-global |
| `shell/modules/desktop/Singletons/Scheme.qml` | `:153` | desktop backdrop chrome |
| `shell/modules/launcher/shared/Singletons/Scheme.qml` | `:90` | launcher |
| `shell/modules/overview/Singletons/Scheme.qml` | `:74` | overview |
| `shell/modules/visualizer/Singletons/Scheme.qml` | `:124` | visualizer |
| `shell/quickshell/plugins/kit/Singletons/Scheme.qml` | `:100` | plugin kit |
| `shell/modules/bar/barstyles/qsbar/Theme.qml` | `:18` (`colorsPath`) | the bar (qsbar) |
| `hub/quickshell/Singletons/Scheme.qml` | `:51` | Settings app |
| `shell/ryogami/wall-ui/qml/Colors.qml` | `:15` | wallpaper picker |

These singletons also read `~/.config/ryoku/theme.json` (`followWallpaper`) and
`~/.config/ryoku/shell.json` (named theme), so a theme pass and a fixed palette
resolve through one chain (`Tokens.qml:330-356`). The `nudgePalette` IPC push
exists because the atomic-rename write can be missed by the file watch
(`matugen.go:1303-1309`).

---

### IPC verbs used

**Over `$XDG_RUNTIME_DIR/ryogami.sock`** (one socket, four grammars — `proto.go:9-12`)
[READ]:

- plain verbs: `subscribe wallpaper` (QML `Wallpaper.qml:74`; daemon
  `ipc/ryogami.go:209`); `wallpaper set|random|next|repaint|restore|ui|resource|live-reload`
  and `depth set|clear` (`ryogami/daemon/verbs.go:14-127`).
- JSON-RPC methods (`ryogami/daemon/rpc.go`): `wall.apply` (`:61`),
  `wall.list` (`:57`), `wall.random_start/stop/status` (`:220-241`),
  `wall.daynight_*` (`:242-265`), `wall.palette_frame` (`:284-297`),
  `wall.import/delete/metadata/favourite` (`:131-166`), `playlist.*` (`:298-365`),
  `upscale.*` (`:381-390`), `optimize.*` (`:99-124`), `effects.*` (`:75-93`),
  `state.get/set` (`:39-45`), `wm.focusedOutput` (`:29`).

**Over the shell's Quickshell IPC** — `qs -c <cfg> ipc call <target> <fn> [arg]`
(`ipc/actions.go:58-77`) [READ]:

- `shell theme reload` — fired by `nudgePalette` (`matugen.go:1311`); handler at
  `shell/modules/bar/barstyles/qsbar/core/IpcRouter.qml:104-109` (`theme.reload`).
- `shell theme apply|applyLauncher` — same handler (`IpcRouter.qml:106-107`).
- `shell picker wallpaper` — opens the picker (`IpcRouter.qml:111-117`).

**Over the Hub's localhost palette bridge** (optional): `ryoku-hub palette-bridge
status|enable|disable|restart` (`ryoku/hub/backend/palettebridge.go:176-185`; wall-ui
`settings/PaletteBridgeSettings.qml:30-40`).

The `depth` verbs are the shell daemon handing stage cutouts back to ryogami
(`ipc/ryogami.go:98-120`).

---

### Binaries shelled out

Measured with `stat`/`readlink -f` on `PATH` this session **[TESTED]**; versions from
`pacman -Q` **[TESTED]**:

| Binary | Bytes | Version | Called by |
|---|---|---|---|
| `matugen` | 11,945,640 | 4.2.0-1 | `ryoku-shell` daemon (`matugen.go:775,1253`) |
| `ffmpeg` | 428,296 | 2:9.0.2-2 | shell `liveFrame`/luma (`theming.go:92`; `matugen.go:307,377`); ryogami `livewall`/`scan`/`optimize`/`upscale` |
| `ffprobe` | 202,944 | (ffmpeg pkg) | ryogami `livewall.go:73`, `scan.go:443`, `upscale.go` |
| `quickshell` / `qs` | 6,002,104 | 0.3.2-1 | the QML runtime; `qs ipc call` (`ipc/actions.go:66`); ryogami spawns wall-ui (`process.go:74`) |
| `magick` / `convert` | 14,824 | imagemagick 7.1.2.34-1 | ryogami thumbnails/colour/grading (`effects.go:300`, `scan.go:245`, `grade.go:127`) |
| `curl` | 223,536 | — | wall-ui remote downloads (`WallhavenService.qml:149`); palette-bridge install paths |
| `inotifywait` | 435,640 | — | wall-ui folder watcher (`wall-ui/qml/services/WatcherService.qml:117`) |
| `kitty` | 100,600 | — | SIGUSR1 reload target (`matugen.go:1299,1631`) |
| `gsettings` | (glib) | — | GTK nudges (`matugen.go:1289,1361,1626-1628`) |
| `pkill` | (procps) | — | `pkill -USR1 -x kitty` (`matugen.go:1299,1631`) |
| `ryoku-cursor-material-recolor` | [UNVERIFIED] | — | cursor recolor (`matugen.go:583`; `config.toml:39`) |
| `ryoku-cmd-folders` | [UNVERIFIED] | — | folder-icon recolor (`config.toml:39`) |
| `papirus-folders` | [UNVERIFIED] | — | papirus post_hook (`apps.toml:63`) |
| `nice` | (coreutils) | — | ryogami `livewall.go:199,310` |

Not installed here: `ryogami`, `ryogami-live`, `ryoku-shell`, `ryoku-palette-bridge`
(all built from source in this repo) **[TESTED]**.

---

### Services / daemons

| Unit | ExecStart | Notes |
|---|---|---|
| `ryoku-shell.service` | `/usr/bin/ryoku-shell daemon` | `ryoku/shell/systemd/user/ryoku-shell.service`; owns the matugen pipeline; `Environment=QT_MEDIA_BACKEND=ffmpeg`, `RYOKU_POLKIT_AGENT=1` |
| `ryogami.service` | `/usr/bin/ryogami` | `ryoku/shell/systemd/user/ryogami.service`; `MALLOC_CONF=…` tuning for the Quickshell-based picker; `KillMode=process` |
| *(optional)* `ryoku-palette-bridge` | localhost HTTP | shipped as its own package; enabled via the Hub; **not** part of the wallpaper→matugen path |

Both are `PartOf=ryoku-session.target`, `After=ryoku-session.target`,
`ConditionEnvironment=WAYLAND_DISPLAY`, `Restart=always`, `Slice=session.slice`.
matugen is not a daemon: it is a short-lived child of `ryoku-shell` per palette pass.

`ryogami` runs two long-lived things: the daemon (catalog/thumbnails/apply/depth) and,
for live wallpapers, one `ryogami-live` process per output (`livewall.go:17-23`) built
from `ryoku/shell/livewall/livewall.c`.

---

### Qt modules

From the PKGBUILDs [READ] and the imports:

| Qt package | Why the path needs it |
|---|---|
| `qt6-base` | QtCore/QtGui under Quickshell |
| `qt6-declarative` | `QtQuick` in every bridge/`Scheme`/`Theme` |
| `qt6-multimedia` | `Backdrop.qml:4,447-461` (`MediaPlayer`/`VideoOutput`/`AudioOutput`) — live wallpapers; also `ryoku-desktop` hard-depends it |
| `qt6-svg` | SVG assets in the bar/picker |
| `qt6-imageformats` | WebP/AVIF/JPEG wallpaper decoding |
| `qt6-wayland` | Quickshell's Wayland QPA plugin |
| `qt6-shadertools` | **build-time only** — bakes `reveal.frag.qsb` and `skwd/*.qsb`; the `.qsb` files ship, so no runtime compile |
| `quickshell` | the QML runtime the daemon, picker and shell all run on |

`ryoku-shell/PKGBUILD` runtime `depends`: `quickshell ffmpeg wayland jq uv`
(`release/packages/ryoku-shell/PKGBUILD:18`). `ryogami/PKGBUILD`:
`imagemagick ffmpeg quickshell curl inotify-tools` (`:29`), `makedepends go wayland
wayland-protocols`. `ryoku-desktop` hard-depends `matugen`, `qt6-multimedia`,
`qt6-declarative`, `adw-gtk-theme`, `gnome-themes-extra`, and the toolkits the
templates target.

---

### Fonts

The pipeline writes fonts but does not ship the display faces [READ]:

- 11 bundled faces load at runtime via `FontLoader` in
  `ryoku/shell/quickshell/shell/modules/desktop/Singletons/Fonts.qml:20-30`
  (`reckoner`, `jf-flat`, `abberancy`, `daydream`, `sabana`, `unrealised`, `vip-rawy`,
  `xenophobia`, `vexa-light`, `overhead`, …) — 366,768 B total, on disk under
  `ryoku/shell/quickshell/shell/assets/fonts/`.
- `applyFont` (`matugen.go:1623-1632`) pushes the chosen system fonts to gsettings
  (`font-name`, `document-font-name`, `monospace-font-name`), rewrites
  `~/.config/qt6ct/qt6ct.conf` (`writeQt6ctFont`, `:1658-1678`) and
  `~/.config/kitty/current-font.conf` (`writeKittyFont`, `:1683-1690`), then SIGUSR1s
  kitty. This runs off the settings topic (`fontSig`, `:1608-1617`), not the matugen
  pass.
- Compiled defaults: family `Space Grotesk` / mono `SpaceMono Nerd Font`, size 11
  (`matugen.go:1643-1651`); `Tokens.qml` defaults to `Fraunces` / `Space Grotesk` /
  `SpaceMono Nerd Font` / `Noto Sans CJK JP`.

The families themselves are Phase-4 installs (see `06-fonts-qt-assets.md`); matugen
shells to `gsettings`/`qt6ct`/`kitty` regardless of whether the family exists.

---

### Assets (incl. off-disk ryoku/assets, with sizes)

**On-disk (inside the checkout, referenced by the path)** [READ]:

| Path | Bytes | Referenced by |
|---|---|---|
| `ryoku/shell/quickshell/shell/assets/fonts/` (11 files) | 366,768 | `modules/desktop/Singletons/Fonts.qml:20-30` |
| `ryoku/shell/quickshell/reload-cover/assets/logo.png` | 1,401 | `reload-cover/ReloadMedia.qml:64` |
| `ryoku/shell/quickshell/shell/modules/bar/barstyles/qsbar/assets/` (11 files) | 68,506 | `qsbar/modules/ClaudeWidget.qml:237-257`, `GpuWidget.qml:37`, `panels/AiUsagePanel.qml:449-474` |
| `ryoku/shell/ipc/assets/*.oga` (5 sounds, `go:embed`) | — | `ryoku/shell/ipc/sounds.go:21` |
| `ryoku/shell/quickshell/shell/modules/wallpaper/reveal.frag` + `.qsb`, `skwd/*.qsb` | — | `Backdrop.qml:302,316,431` |

**Off-disk `ryoku/assets` (not in the sparse checkout)** — sizes from
`git ls-tree -r -l HEAD ryoku/assets` [READ], 94 entries / **250,784,221 B** total:

| Path | Bytes | Referenced by | Needed here? |
|---|---|---|---|
| `ryoku/assets/brand/logo.svg` | 594 | `ryoku/shell/deploy.sh:617`; `ryoku-desktop/PKGBUILD` | launcher entry icon |
| `ryoku/assets/brand/logo-mark.svg` | 552 | `ryoku/shell/deploy.sh:609` | fallback app icon |
| `ryoku/assets/brand/logo-mark.png` | 43,143 | `hub/quickshell/pages/FastfetchPage.qml:282` | no (Fastfetch) |
| `ryoku/assets/brand/fastfetch-emblem.png` | 377,909 | `FastfetchPage.qml:281`; `ryoku-desktop/PKGBUILD` | no (Fastfetch) |
| `ryoku/assets/ryodecors/*` (23 files) | 4,165,851 | `ryoku/shell/deploy.sh:541` | no (Decor/Profile/Rashin) |
| `ryoku/assets/wallpapers/*` (59 files) | 245,026,989 | seeded into `~/Pictures/Wallpapers`; not path-hardcoded | seeded content, not a runtime dep |

`ryoku/assets/brand/` = 1,591,381 B. **No runtime QML on the wallpaper/theming path
reads an off-disk `ryoku/assets` file** — the palette path reads the *user's*
`~/Pictures/Wallpapers`, and the wallpapers under `ryoku/assets/wallpapers/` are
seeded content only. The scripts that copy assets (`deploy.sh:541,609,617`) run at
deploy/install time, not per palette pass.

---

### Network calls

[READ] The wallpaper→palette path makes **no** outbound calls of its own:

- `matugen` runs entirely offline on a local file. No template performs a fetch.
- `resolveMode("sun")` depends on the **weather poll** (`sun.go` / `weather.go`) only
  when the mode knob is `sun` (`matugen.go:236-245`); the default `smart` mode uses
  only the local image (`:209-228`).
- The `palette-bridge` is **localhost-only**: it binds `127.0.0.1:47616`
  (`palette-bridge/main.go:241`) and serves `/colors.json`, `/v1/palette`,
  `/v1/events`, `/healthz` (`:255-258`) for local SPA integrations; no network egress.
- Outbound traffic belongs to the **picker only**, not the palette path: the
  wall-ui's `WallhavenService` (`wallpaper/WallhavenService.qml:149,190` — `curl`
  against `https://wallhaven.cc/api/v1/`), Steam Workshop downloads
  (`services/SteamDownloadService.qml`), and MoeWalls/MotionBGs, all host-allowlisted.
  The bar/palette never call these.

---

### Q7 — Two wallpaper options, costed

Two ways to reach the same end state (image on screen, palette regenerated by
matugen). Sizes measured this session **[TESTED]**; the substitute daemons are **not
installed**, so their sizes are **[UNVERIFIED]**.

#### Option A — keep `ryogami` (as shipped)

What you build/ship beyond matugen:

| Item | Bytes | Source |
|---|---|---|
| `ryogami` Go binary | [UNVERIFIED] (not built; stdlib-only module, 1.9 MB source) | built from `ryoku/shell/ryogami/daemon` (`ryogami/PKGBUILD` `go build -mod=vendor`) |
| `ryogami-live` C binary | [UNVERIFIED] (built from `ryoku/shell/livewall/livewall.c`, 18,909 B source) | `livewall/build.sh`, only needed for live video |
| runtime tools | `imagemagick` + `ffmpeg` + `quickshell` + `curl` + `inotify-tools` | `ryogami/PKGBUILD:29` |
| the picker (wall-ui) | QML tree, shipped to `/usr/share/ryogami` | `ryogami/PKGBUILD` `package()` |

Gives: the `wallpaper` topic → `Wallpaper.qml` bridge, the GPU reveal transitions
(`Backdrop.qml`, 16 kinds + `skwd/` shaders), depth cutout, playlists, day/night
rotation, and live video — **with zero edits** to the shell QML or the Go bridge.

#### Option B — substitute `hyprpaper` / `swww` / `swaybg` + matugen only

| Candidate | Bytes | Installed? |
|---|---|---|
| `hyprpaper` | NOT FOUND | no |
| `swww` / `swww-daemon` | NOT FOUND | no |
| `swaybg` | NOT FOUND | no |
| `mpvpaper` | NOT FOUND | no |

Sizes cannot be measured here; all are **[UNVERIFIED]** (they would have to be
installed first, which is out of scope). matugen (11,945,640 B) stays in **both**
options and dominates every measured number.

#### Cost comparison

| | Option A (ryogami) | Option B (swww/swaybg + matugen) |
|---|---|---|
| Extra binaries to build/ship | `ryogami` + `ryogami-live` (sizes [UNVERIFIED]) | `hyprpaper`/`swww`/`swaybg` (sizes [UNVERIFIED]) |
| Extra runtime deps | imagemagick, ffmpeg, quickshell, curl, inotify-tools | none beyond the compositor tool + matugen |
| Shell edits needed | **none** | **must cut the topic bridge** (below) |
| Transitions / reveal shader | yes (`Backdrop.qml:414-445`) | no (plain set) |
| Live video wallpapers | yes (QtMultimedia + `ryogami-live`) | no (swaybg/hyprpaper are still-only; mpvpaper is a separate, heavier player) |
| Depth cutout, playlists, day/night | yes | no |
| Palette (matugen) | unchanged | unchanged |

**What Option B actually costs in code** (files that reference the ryogami
contract and would need rework) [READ]: `shell/modules/wallpaper/Wallpaper.qml`
(the topic socket), `WallpaperFrame.qml` (frame parse), `Backdrop.qml` (reveal +
`live`/`videoUrl`), `shell/modules/desktop/Desktop.qml:431` (the backdrop host),
`shell/shell.qml:177-193` (wiring), `ryoku/shell/ipc/ryogami.go` (daemon bridge) with
its consumers in the `ryoku-shell` daemon, `bar/Frame.qml:72,406` and
`barstyles/qsbar/panels/ImageCarousel*.qml` (`applyBgProc` → `ryogami wallpaper set`),
and `ryoku/hyprland/modules/binds.lua:62-63`.

**Verdict (bytes + blast radius):** matugen is the only large measured binary
(11.9 MB) and is common to both. Option B saves no measured bytes on this box (none
of the substitutes are installed, so the comparison is code, not size) while
deleting the reveal shader, live video, the depth channel and the picker, and
requiring edits across ~9 shell/daemon files. **Keep `ryogami` unless live video and
the reveal motion are explicitly dropped from the keep list** — that decision is
Phase 4/5, not a size win.

---

### Necessity / exclusions

**Mandatory for "wallpaper + matugen theming" to work** [READ]/[UNVERIFIED]:

- `ryoku-shell` daemon (owns the entire matugen pipeline — `ryoku/shell/ipc/`).
- `ryogami` daemon **or** a replacement that supplies the applied-wallpaper signal.
  The `ryoku-shell` pipeline keys on the ryogami `wallpaper` topic
  (`ipc/ryogami.go`); dropping ryogami without a substitute leaves the palette with
  no trigger.
- `matugen` (the renderer).
- `quickshell` (the runtime the shell + picker run on).
- `ffmpeg` (video-still sampling `theming.go:92`; luma/chroma `matugen.go:307,377`).
- The QML wallpaper module (`Wallpaper/Frame/Backdrop`) and the palette singletons.

**Conditional** [READ]:

- `qt6-multimedia` — only for live video wallpapers (`Backdrop.qml:4`). A still-only
  Mei could drop it and the `Backdrop.qml` video blocks.
- `ryogami-live` (C) — only for video wallpapers; built by `ryogami/PKGBUILD`.
- `imagemagick` / `curl` / `inotify-tools` — picker-side (thumbnails, remote
  downloads, folder watch), not palette-side.
- `qt6-imageformats` — WebP/AVIF wallpapers only.
- `kde` / GTK / app-suite templates — optional; the shell palette does not need them
  (`apps.toml` is gated by `themeRyokuApps` + `themeAppsEnabled`, `matugen.go:1172`).

**Excluded / not on the path**:

- `palette-bridge` (`ryoku/palette-bridge/`) — optional SPA integration; not needed
  by wallpaper + matugen on an existing Hyprland box.
- `ryoku/assets/wallpapers/` (245 MB) + `ryodecors/` (4.17 MB) — seeded content, not a
  runtime dependency of the pipeline.
- ryogami's `upscale`/`optimize`/`effects`/`playlist`/`daynight` RPC surfaces — extras
  beyond "apply + palette"; safe to disable behind their config flags but they ship in
  the same binary.
- The `hub` matugen backend (`ryoku/hub/backend/matugen.go`) — it only *writes knobs*
  to `~/.config/ryoku/matugen.json` (`:170`), the file the daemon watches
  (`matugen.go:1730-1746`); it renders nothing. A Mei settings page may write that
  file without importing the Hub.

**Opt-back-in notes:** if `ryogami` is dropped for Option B, the palette trigger must
be re-sourced (e.g. a tiny watcher that calls the shell's `theme reload` handler
`IpcRouter.qml:104-109` after an `swww`/`swaybg` set), and `Backdrop.qml` reduced to a
plain `Image` — the reveal transition and live video are lost either way.

---

## 04 — Settings (ryoku-hub): appearance + shell pages only

Dependency map for the Ryoku Settings app (`ryoku/hub`, the "Hub") as Mei reduces
it. Mei keeps the Hub **look and UI framework** but only the pages that edit
**Appearance** and **Shell** state; every page that authors or edits compositor
config is removed, and the Hyprland write path is severed so Settings never
writes or generates Hyprland config.

- Upstream root (read-only): `$HOME/projects/mei/upstream`. All paths below
  are relative to `upstream/ryoku/` unless a fuller path is given.
- Labels: **[READ]** = read from source, not executed. **[UNVERIFIED]** =
  inferred, not proven by a run. **[TESTED]** = proven by an executed test; the
  Hub was **not** built or run while writing this doc, so no claim here is
  **[TESTED]**.
- The Hub frontend is Quickshell/QML; the backend is the Go binary `ryoku-hub`
  (`hub/backend/`). The frontend shells the backend out once per verb.

### App structure and nav groups

**[READ]** The Hub is a Quickshell configuration:

| Role | File |
|---|---|
| Config entry (instantiates `Hub.qml`) | `hub/quickshell/shell.qml` |
| Window, rail, router, config store, hypr seam | `hub/quickshell/Hub.qml` (1820 lines) |
| Generic schema renderer | `hub/quickshell/SchemaPage.qml` |
| Row/card controls + write dispatch | `hub/quickshell/SettingsSheet.qml`, `ui/SettingRow.qml`, `ui/SettingCard.qml` |
| Desktop launcher entry | `hub/ryoku-hub.desktop` (`Exec=ryoku-shell hub open`) |
| Go backend | `hub/backend/*.go` (module `ryoku-hub`) |
| Hub-local singletons | `hub/quickshell/Singletons/` (no `module` line; imported relatively as `"../Singletons"`) |
| Shared UI kit | `ui/` (`module Ryoku.Ui`) and `ui/Singletons/` (`Ryoku.Ui.Singletons`) |

**[READ]** Rail sections are declared as task groups in `Hub.qml:102-125`:

- `OVERVIEW`: `profile`, `global` (General), `updates`
- `DEVICES`: `displays`, `connections`, `input`, `gpu`
- `LOOK`: `animations`, `lockscreen`
- `COMPOSITOR`: `windowmanager`, `plugins`, `layerrules`
- `DESKTOP`: `bar-studio` (Bar Studio), `desktop`, `widgets`, `launcher`
- `KEYS & APPS`: `keybinds`, `appoverrides`, `windowrules`
- `SYSTEM`: `performance`, `session`, `recording`, `dictation`, `fastfetch`, `import`
- `EXTEND`: `addons`, `rashin`
- footer: `credits`

**[READ]** Section key → page file map at `Hub.qml:490-496` (`pageFile()`); the
generic renderer is used by pages whose schema is data-driven.

**[READ]** Two derived sets decide chrome and provenance, not the page file:

- `framedSet` (`Hub.qml:403-407`) — pages that keep the rail + bottom action bar:
  `bar-studio, desktop, plugins, input, animations, global, windowmanager,
  windowrules, appoverrides, layerrules, session`.
- `compositorSections` (`Hub.qml:412-420`) — **any section owning a row whose
  `src === "desktop.json"`**. This is the machine-checkable line between
  compositor-editor pages and shell pages; `isShellSection(key)` (`Hub.qml:421`)
  is its complement. A page is "shell" iff none of its rows target
  `desktop.json`.

**Owner's "Appearance" and "Shell" groups.** There is **no page named
Appearance or Shell**; the rail is task-grouped. Mapping the owner's two keep
groups onto real files (justification = the row `src` and what the page edits):

- **Appearance** ≈ `LOOK` + `DESKTOP` + the cross-cutting `global` rows:
  `animations` (its shell-motion half), `lockscreen` (out of scope — see
  Must-remove), `bar-studio`, `desktop`, `widgets`, `launcher`, `global`. Their
  rows carry `src` of `shell` / `viz` / `brand` / `launcher.json` /
  `widgets.json` — i.e. shell-owned stores, **not** `desktop.json`.
- **Shell** ≈ `DESKTOP` (shell-backed frame/bar/launcher/widgets rows) plus the
  shell keys inside `SYSTEM` (`fastfetch`'s two `src:"shell"` rows,
  `schema/FastfetchPage.js:93,109`). Pure shell pages write only `shell.json`,
  `visualizer.json`, `brand.json`, `launcher.json`, `widgets.json`, `plugins.json`
  and the daemon-managed `shell.json` — never a compositor config.

The compositor halves of hybrid pages (notably `animations`) fall on the other
side of `compositorSections` and are removed.

### Keep-list pages (appearance + shell) mapped to real files

Every page below has **no row with `src:"desktop.json"`** (so it is a shell
section), and its writes land in Mei's own config dir. Global motion keys live in
`shell.json` under `theme.motion.*` and are written through the daemon seam, not
the hypr draft (`pages/AnimationsPage.qml:154-159`).

#### Global (`global` → `GlobalPage.qml`)
- **Files**: `hub/quickshell/pages/GlobalPage.qml`,
  `hub/quickshell/schema/GlobalPage.js` (6 rows, all `src:"shell"` — language,
  regional formats, location, timezone, temperature units, system font);
  page helpers `hub/quickshell/TimezoneMap.qml`, `hub/quickshell/tzmap.js`,
  `hub/quickshell/world-land.js`.
- **Singletons/services**: `Settings` (`hub/.../Singletons/Settings.qml`) —
  every edit is `Settings.patch(k,v)` → daemon → `shell.json`; `I18n`
  (`Ryoku.Ui.Singletons.singleton I18n`) for the language/locale tables; the
  shell daemon owns `shell.json`.
- **QML imports** (`GlobalPage.qml:1-6`): `QtQuick`, `Quickshell.Io`,
  `Ryoku.Ui`, `Ryoku.Ui.Singletons`, `".."`, `"../schema/GlobalPage.js"`.
- **ryoku-hub verbs**: none (state flows through `settings.patch`).
- **External binaries** (`GlobalPage.qml`): `fc-list` (line 48, installed font
  families), `timedatectl set-timezone` (line 61) and `timedatectl show -p
  Timezone` (line 78), `systemctl --user restart ryoku-shell.service` (line 83).
- **Fonts**: none bundled; enumerates installed families via `fc-list`.
- **Assets**: none.
- **Network**: none in this page; setting `weatherLocation` reaches the geocode
  call in `SettingsSheet.qml:998-999` (see Network calls).

#### Desktop (`desktop` → `DesktopPage.qml`)
- **Files**: `hub/quickshell/pages/DesktopPage.qml`,
  `hub/quickshell/schema/DesktopPage.js` (27 `src:"viz"`, 5 `src:"brand"`, 9
  `src:"shell"`), `hub/quickshell/ReloadCoverControl.qml`,
  `hub/quickshell/ReloadCoverModel.js`.
- **Singletons/services**: `Settings` for `src:"shell"` rows; `vizFV` / `brandFV`
  `FileView`+`JsonAdapter` in `Hub.qml:828-887` write `visualizer.json` /
  `brand.json`; `Scheme` (`Singletons/Scheme.qml`, reads `~/.cache/ryoku/colors.json`);
  `Silhouette` / `VizStyles` (`Ryoku.Ui.Singletons`) for galleries. The Go
  `desktop` verbs used here are only `reload-cover` (below); the hypr verbs
  (`desktop save/preview/restore`) are severed.
- **QML imports** (`DesktopPage.qml:1-7`): `QtQuick`, `Quickshell.Io`,
  `Ryoku.Ui`, `Ryoku.Ui.Singletons`, `".."`, `"../schema/DesktopPage.js"`.
- **ryoku-hub verbs**: `ryoku-hub clipboard stats` / `clipboard prune`
  (`DesktopPage.qml:115,138`); `ryoku-hub reload-cover import|prune`
  (`Hub.qml:753,951`).
- **External binaries**: `xdg-open` via `Hub.qml:596` (`openSettingsFile`).
- **Fonts**: `fontFamily` row (shell key).
- **Assets**: `hub/quickshell/art/{dither-torii,profile-hero,roots}.png`,
  reload-cover managed assets under `$XDG_DATA_HOME/ryoku/reload-cover/`
  (`hub/backend/reloadcover.go:59-65`).
- **Network**: none.

#### Bar Studio (`bar-studio` → `BarStudioPage.qml`)
- **Files**: `hub/quickshell/pages/BarStudioPage.qml`,
  `hub/quickshell/schema/BarStudioPage.js` (**`rows = []`** — feeds search only),
  `hub/quickshell/barstudio/*.qml` + `BarStudioModel.js` + `qmldir`
  (`module barstudio`).
- **Singletons/services**: `Settings` — frame/bar keys are live-applied through
  `stageLive`→`settings.patch` (`Hub.qml:630-666`, `liveKeys` at `:639`);
  `Ryoku.FrameBars` (`shell/framebars`, `module Ryoku.FrameBars`) for the frame
  model.
- **QML imports** (`BarStudioPage.qml:6-11`): `Quickshell.Io`, `Ryoku.Ui`,
  `Ryoku.Ui.Singletons`, `Ryoku.FrameBars`, `"../barstudio"`,
  `"../barstudio/BarStudioModel.js"`.
- **ryoku-hub verbs**: none; edits ride `Settings.patch`.
- **External binaries** (`BarStudioPage.qml`): `ryostore open barstyles` (58),
  `ryostore catalog --category barstyles` (82), `ryostore install barstyles <id>`
  (71), `ryoku-shell bar settings` (231), `xdg-open`.
- **Fonts**: shell font keys only.
- **Assets**: bar-style skins fetched into the shell; `ui/grain.png`.
- **Network**: indirectly through `ryostore` catalog/install **[UNVERIFIED]**.

#### Launcher (`launcher` → `LauncherPage.qml`)
- **Files**: `hub/quickshell/pages/LauncherPage.qml`,
  `hub/quickshell/schema/LauncherPage.js` (13 rows, all `src:"launcher.json"`).
- **Singletons/services**: `FileView` on
  `$XDG_CONFIG_HOME/ryoku/launcher.json` (`LauncherPage.qml:155`); reads the
  shell's launcher module dir via `RYOKU_SHELL_DIR` (`LauncherPage.qml:30-36`).
- **QML imports** (`LauncherPage.qml:1-9`): `QtQuick`, `Quickshell.Io`,
  `Ryoku.Ui`, `Ryoku.Ui.Singletons`, `"..."`-relative page imports.
- **ryoku-hub verbs**: none.
- **External binaries**: none (reads the launcher module dir).
- **Fonts/assets/network**: none of note.

#### Widgets (`widgets` → `WidgetsPage.qml`)
- **Files**: `hub/quickshell/pages/WidgetsPage.qml`,
  `hub/quickshell/schema/WidgetsPage.js` (70 rows, all `src:"widgets.json"`),
  `hub/quickshell/pages/StoreWidgetCard.qml`, previews
  (`ClockPreview/AioPreview/StatsPreview/CalendarPreview/MusicPreview/
  WeatherPreview/NotesPreview.qml`), and the embedded `SettingsSheet.qml` /
  `AppPicker.qml`.
- **Singletons/services**: `Settings` (`src:"shell"` rows embedded), `FileView`
  on `ryoku/widgets.json` (`WidgetsPage.qml:298`) and `ryoku/plugins.json`
  (`:548`).
- **QML imports** (`WidgetsPage.qml:1-9`): `QtQuick`, `Quickshell.Io`,
  `Ryoku.Ui`, `Ryoku.Ui.Singletons`, `"../schema/WidgetsPage.js"`.
- **ryoku-hub verbs**: none; installs go through the store scripts.
- **External binaries** (`WidgetsPage.qml`): `bash -c "fc-list …"` (94),
  `quickshell/plugins/discover.sh` (476), `ryostore` (store installs),
  `ryoku-plugins-place` (widget placement).
- **Fonts**: enumerates installed families (`fc-list`).
- **Assets**: store widget thumbnails; previews.
- **Network**: `ryostore` store calls **[UNVERIFIED]**.

#### Animations — **shell-motion half only** (`animations` → `AnimationsPage.qml`)
- **Files**: `hub/quickshell/pages/AnimationsPage.qml`;
  `hub/quickshell/schema/AnimationsPage.js` (single row
  `desktop.appearance.animations`, `src:"desktop.json"` — this one row is the
  compositor half and is dropped).
- **Keep (shell motion)**: `theme.motion.scale` and `theme.motion.reduce`,
  read via `Settings.get("theme.motion.*")` and written with
  `Settings.patch("theme.motion."+key, v)` (`AnimationsPage.qml:154-159`,
  controls at `:715,:722`). These live in `shell.json` and retune the shell
  live — they are the full motion language Mei keeps centralised.
- **Sever (Hyprland window editor)**: `anim-preset` file
  (`ryoku-hub desktop anim-preset`, `AnimationsPage.qml:182,186`) and the
  `wm.hyprland.anim.*` / `wm.hyprland.plugins.hyprfocus.*` draft keys
  (`AnimationsPage.qml:193-297,936-1039,1176`) — all `source:"desktop.json"`.
  Split this page: keep the shell-motion block, delete the GLOBAL/MOTION/curve
  workshop and hyprfocus sections.
- **Singletons/services/imports**: `Settings`; imports `Quickshell.Io`,
  `Ryoku.Ui`, `Ryoku.Ui.Singletons`.
- **External binaries**: `ryoku-hub desktop anim-preset` (severed with the
  editor).
- **Fonts/assets/network**: none.

### Must-remove pages (compositor config editors)

**[READ]** Every page below owns at least one row with `src:"desktop.json"`
(so `compositorSections[key]` is true) or writes a compositor config by another
route. Remove the page file, its schema, and its routing entry.

| Section | Page file | Writes / why removed |
|---|---|---|
| `windowmanager` | `pages/WindowManagerPage.qml` (+ `schema/WindowSettings.js`) | `desktop.json` appearance/input/cursor; provider schema rows; drives `settings.lua` |
| `plugins` | `pages/PluginsPage.qml` (+ `schema/PluginsPage.js`, `schema/PluginPlacementEditor.js`) | `desktop.json` `plugins.*`; `hyprctl eval`/plugin load |
| `layerrules` | `pages/LayerRulesPage.qml` (+ `schema/LayerRulesPage.js`) | `desktop.json` layer rules → settings.lua |
| `input` | `pages/InputPage.qml` (+ `schema/InputPage.js`) | `desktop.json` `input.*` (kb layout, touchpad) |
| `keybinds` | `pages/KeybindsPage.qml` (+ `schema/KeybindsPage.js`, `KeybindsPage.test.mjs`) | `desktop.json` `keybinds`/`keybindRebinds`/`unbinds` → settings.lua + rebinds.lua |
| `windowrules` | `pages/WindowRulesPage.qml` (+ `schema/WindowRulesPage.js`) | `desktop.json` `windowRules` |
| `appoverrides` | `pages/AppOverridesPage.qml` (+ `schema/AppOverridesPage.js`) | `desktop.json` `appOverrides` |
| `displays` | `pages/DisplaysPage.qml` (+ `schema/DisplaysPage.js`) | monitors `<name>.json` + `desktop.json`; compositor output config |
| `session` | `pages/SessionPage.qml` (+ `schema/SessionPage.js`) | `desktop.json` autostart/env |
| `gpu` | `pages/GpuPage.qml` (+ `schema/GpuPage.js`) | `gpu.lua` (a Hyprland config file), `~/.config/ryoku/gpu-presets.json`, compositor env |
| `animations` (hypr half) | `pages/AnimationsPage.qml` GLOBAL/MOTION + hyprfocus blocks | `anim-preset` file + `wm.hyprland.*` |
| `lockscreen` | `pages/LockscreenPage.qml` (+ `schema/LockscreenPage.js`) | qylock themes (`ryoku-hub lock`), `/etc/pam.d/*` via `pkexec`, `~/.config/qylock/*`, `ryoku keyring`/`security-key`, fprintd — not Appearance/Shell and touches the system |
| `performance` | `pages/PerformancePage.qml` (+ `schema/PerformancePage.js`) | `ryoku-power` CPU/power profiles (no compositor config, but out of scope) |

Out of scope (not compositor editors, not Appearance/Shell; list as exclusions):
`profile`, `updates`, `connections`, `recording`, `dictation`, `fastfetch`
(non-`shell` rows), `addons`, `rashin`, `import`, `credits`.

**Pure compositor-editor vs pure shell/appearance.** `windowmanager`, `plugins`,
`layerrules`, `input`, `keybinds`, `windowrules`, `appoverrides`, `displays`,
`session` are pure compositor editors. `global`, `desktop`, `bar-studio`,
`widgets`, `launcher` and the shell half of `animations` are pure shell/appearance.
`animations` is the one genuine hybrid and must be split; `gpu`, `lockscreen`,
`performance` are non-compositor but out of scope.

### What Settings writes

**[READ]** Two write families. "Mei keeps" land under Mei's own config dir and
never touch a compositor; "sever" are the compositor/global writes.

**Mei may keep (shell + appearance, in Mei's config dir):**

| File | Writer | Cited at |
|---|---|---|
| `ryoku/shell.json` | shell daemon only, via `settings.patch`/`settings.reset` | `Hub.qml:820-826`, `Singletons/Settings.qml:64-65`, `shell/ipc/settings.go:18-20,1076,1116,1126` |
| `ryoku/visualizer.json` | `vizFV` JsonAdapter | `Hub.qml:706,828-868` |
| `ryoku/brand.json` | `brandFV` JsonAdapter; also reload-cover asset | `Hub.qml:708,869-887`; `reloadcover.go:63-65` |
| `ryoku/launcher.json` | `FileView` | `pages/LauncherPage.qml:155` |
| `ryoku/widgets.json` | `FileView` | `pages/WidgetsPage.qml:298` |
| `ryoku/plugins.json` | `ryoku-plugins-place` | `schema/AddonsPage.js:15` |
| `ryoku/hub.toml` ([ui] section/advanced/update_interval) | `ryoku-hub config set` | `hub/backend/config.go:15-34,93-105` |
| `$XDG_DATA_HOME/ryoku/reload-cover/*` | `ryoku-hub reload-cover import` | `reloadcover.go:59-65,233-319` |
| `ryoku/anim-preset` | **shell motion preset** (kept only if Mei keeps presets; see exclusions) | `hub/backend/desktop.go:626-649` |

Note: `shell.json` is **never opened by the Hub** — it is read through the
`settings` subscription and written only through the daemon
(`Singletons/Settings.qml:7-15`, `shell/ipc/settings.go:18-20`). Mei's daemon is
the sole writer there too.

**Must be severed (compositor or system):**

| File / action | Writer | Cited at |
|---|---|---|
| `ryoku/desktop.json` | `desktop save` (single writer) | `hub/backend/desktop.go:100,229-257,239` |
| `hypr/settings.lua` | provider `apply` | `wm/hyprland/apply.go:56,65`; `wm/hyprland/config_store.go:605-609` |
| `hypr/rebinds.lua` | provider `apply` | `wm/hyprland/apply.go:59,66`; `config_store.go:605-609` |
| `ryoku/user_edits/hypr/settings.lua` + `rebinds.lua` | overlay copy | `config_store.go:508-510,605-609` |
| `hyprctl reload` / `reload config-only` | provider `act` | `wm/hyprland/act.go:169-177` |
| `niri/settings.kdl`, `niri/rebinds.kdl`, `ryoku/user_edits/niri/{settings,rebinds}.kdl` | niri provider | `wm/niri/apply.go:52,55,59-60`; `wm/niri/config_store.go:572-577`; `wm/detect.go:181` |
| `ryoku/matugen.json`, `~/.cache/ryoku/colors.json`, `/etc/pam.d/*`, `~/.config/qylock/*`, `SHELL` into `desktop.env` | various | `matugen.go:165-197`; `schemes.go:29-33`; `pages/LockscreenPage.qml:143-160`; `hub/backend/shellpref.go` |

The Hub also writes user files it treats as hand-editable: `kitty/current-theme.conf`
etc. via matugen (`schemes.go:289-295`, `matugen.go:247-270`) — out of scope.

### The Hyprland write path to sever

**[READ]** The full chain, frontend → `hyprctl`, with both sides named:

1. **Hub QML triggers** — `Hub.qml:696-723` `save()`; on any hypr change it runs
   `ryoku-hub desktop save <JSON>` (`Hub.qml:716-718`). Live preview tick runs
   `desktop preview` (`Hub.qml:942`); revert/quit run `desktop restore`
   (`Hub.qml:729,963`). The draft is read from `desktop get` / `desktop defaults`
   (`Hub.qml:910,925`).
2. **Hub hub backend** — `runDesktop` dispatch (`hub/backend/desktop.go:83-161`):
   `save`→`saveDesktop` (`:100,229`), `preview`→`previewDesktop` (`:101,261`),
   `restore`→`restoreDesktop` (`:106,305`). `saveDesktop` writes
   `desktop.json` (`:239`) then `applyLive()` (`:243`).
3. **Provider facade** — `applyLive`→`applyDesktop` (`:396-405,381`) →
   `desktopClient().Apply(desktopStorePath())` (`:383`) → `Act(ActionConfigReload)`
   (`:388`).
4. **Hyprland provider apply** — `wm/hyprland/apply.go:56` writes `settings.lua`
   and `:59` writes `rebinds.lua` via `writeOverlayLua`.
5. **Overlay writer** — `wm/hyprland/config_store.go:605-609`: `atomicWrite` to
   `userEditsHyprDir()` (`:508-510`) **and** to `hyprConfigDir()` (`:503`).
6. **Reload → hyprctl** — `wm/hyprland/act.go:169-177` `ActionConfigReload` runs
   `ctl("reload")` / `ctl("reload","config-only")`. `ctl` is the hyprctl wrapper
   in `wm/hyprland/session.go` (the file that also defines `dispatch`/`evalLua`
   at `:123,:130`).
7. **Generated-file list** — `wm/detect.go:179-182`:
   `hypr/settings.lua`, `hypr/rebinds.lua`,
   `ryoku/user_edits/hypr/settings.lua`, `ryoku/user_edits/hypr/rebinds.lua`
   (and the niri twins at `:181`).

**niri (KDL) twin**: `wm/niri/apply.go:52,55` write `settings.kdl`/`rebinds.kdl`
via `writeOverlayKdl` (`wm/niri/config_store.go:572-577`, overlay dir `:536`),
and `wm/niri/act.go:287,357` regenerate `settings.kdl` for input/border acts.

**Other compositor writes from the Hub** to sever: cursor
(`desktop.go:407-417` `Act(ActionCursorSet)` → `hyprctl setcursor`), plugins
(`desktop.go:348-375`), and `shellpref.go` (SHELL env persisted into
`desktop.env` then `applyDesktop()`).

To sever cleanly: keep the Hub QML's read-only compositor state
(`Settings.windows`, `Settings.configFiles`, `Hub.qml:501-503`), but drop the
`hypr*` draft/save/preview machinery (`Hub.qml:889-996`) and the `desktop
save|preview|restore|scheme|anim-preset` verbs and their callers, and do not
vendor the writing half of `ryoku-wm` (see Backend inventory).

### Backend inventory

**[READ]** `hub/backend/` is Go module **`ryoku-hub`** (`go 1.26.4`).
`main.go:23-136` dispatches verbs; **all** of these must be audited, and only
the shell/appearance subset kept.

Files (non-test), one line of purpose:

| File | Concern |
|---|---|
| `main.go` | verb dispatch (`:23-136`) |
| `config.go` | `hub.toml` get/set (`:15-105`) |
| `desktop.go` | neutral wm backend: `desktop.json` + provider apply/act (write path) |
| `desktop_enum.go` | cursor/kb-layout enumeration |
| `wm.go` | compositor **switch** backend (`wm list|preview`) |
| `outputs.go` | display page backend (monitors) |
| `keybinds.go` | keybind legend JSON |
| `apps.go` | default-apps roles |
| `shellpref.go` | login-shell persistence (`~/.bashrc`/`.zshrc`, `desktop.env`) |
| `lock.go` | qylock skin management |
| `schemes.go` | palette schemes; writes `colors.json`/`theme.json`/`matugen.json` |
| `matugen.go` | matugen config + app template rendering |
| `palettebridge.go` | palette-bridge integration (systemd unit) |
| `profile.go` | Profile page share backend (`profile.json`) |
| `rice.go`, `ricepublish.go`, `sharestatus.go` | rices + screen-share status |
| `reloadcover.go` | reload-cover asset import/prune |
| `fastfetch.go` | fastfetch `config.jsonc` editor |
| `import*.go` (`import`, `import_apply`, `import_parse`, `import_types`, `import_undo`) | config import/undo |
| `gpu*.go` (`gpu`, `gpuapply`, `gpudomain`, `gpuhook`, `gpumode`, `gpumux`, `gpupreset`, `gputune`, `gpuvm`, `hwcaps`) | GPU/power + passthrough |
| `cputune.go` | CPU power profiles |
| `lighting.go`, `lightingfx.go`, `openrgb.go`, `qmk.go`, `aura.go` | RGB/lighting devices |
| `clipboard.go` | clipboard stats/prune (via daemon) |
| `daemonclient.go` | one client onto the shell daemon socket (`:25-52`) |
| `voxtype.go` | dictation backend |
| `vendor/ryoku-wm/*.go` | vendored wm seam (client/action/binds/caps/cursor/detect/reclaim/state) |
| `vendor/ryostore/compat/version.go` | vendored ryostore compat |

**go.mod** (`hub/backend/go.mod`):
- `require`: `github.com/BurntSushi/toml v1.6.0`,
  `github.com/godbus/dbus/v5 v5.2.2`, `golang.org/x/sys v0.27.0`,
  `ryoku-wm v0.0.0`, `ryostore v0.0.0`.
- `replace ryoku-wm => ../../wm` (line 18) — the wm seam, present.
- `replace ryostore => ../../apps/ryostore/backend` (line 16) — **OFF-disk**: only
  `hub/backend/vendor/ryostore/compat/version.go` exists; the real
  `apps/ryostore/backend` tree is not in the checkout. Builds that pull in
  `ryostore` therefore cannot compile from this tree as-is **[UNVERIFIED]**.
  Mei should pin the vendored stub or drop the `ryostore` dependency with the
  pages that used it (Add-ons/Lockscreen/Bar Studio store calls).

The Hub shells the provider binary as `ryoku-wm-<name>`
(`hub/backend/vendor/ryoku-wm/client.go:49,59,384` `exec.CommandContext`).

### QML imports

**[READ]** Across the keep pages and shared kit:

- `QtQuick`, `QtQuick.Controls`, `QtQuick.Shapes` (`pages/LockscreenPage.qml:3-5`)
- `Qt.labs.folderlistmodel` (`GlobalPage.qml:5`)
- `Quickshell`, `Quickshell.Io`
- `Ryoku.Ui` (`ui/qmldir:1 module Ryoku.Ui`)
- `Ryoku.Ui.Singletons` (`ui/Singletons/qmldir`)
- `Ryoku.FrameBars` (`shell/framebars/qmldir:1`)
- relative: `".."`, `"../Singletons"`, `"../barstudio"`, `"../schema/*.js"`

These require Quickshell **and** the `Ryoku.Ui` QML plugin plus the shell's
`framebars` module to be on the import path. Mei keeps `ui/` and the framebars
module; it can drop `Ryoku.Wm.Hyprland` (`wm/hyprland/qml/qmldir`) with the
compositor pages.

### Singletons

Hub-local (`hub/quickshell/Singletons/qmldir`):

| Singleton | Concern | Keep? |
|---|---|---|
| `Theme` | Hub palette/type/motion tokens (`Singletons/Theme.qml`) | keep |
| `Settings` | daemon `settings` topic; `settings.patch`/`reset` | keep |
| `Scheme` | live palette from `~/.cache/ryoku/colors.json` | keep |
| `ProviderSchema` | provider rows/`unhonored` for wm pages | drop with wm pages |
| `Updates` | daemon `updates` topic | drop (out of scope) |
| `SysInfo`, `LiveStats` | profile/sysinfo from helpers | drop (Profile) |
| `UserSchemes` | RyoStore theme catalog | drop (out of scope) |

Shared (`ui/Singletons/qmldir`): `Tokens`, `Ink`, `Paths`, `I18n`, `Spans`,
`Silhouette`, `VizStyles`, `Ryodecors`, `ProfileStore`, `Spawn`, `Version`,
`Wm`. Keep `Tokens`/`I18n`/`Spawn`/`Silhouette`/`VizStyles`/`Ryodecors`; `Wm`
and `ProfileStore` travel with their pages.

### IPC verbs used / binaries shelled out

**[READ]** `ryoku-hub` verbs referenced from QML (keep pages in **bold**):
`config get|set`, **`desktop get|defaults|schema|unhonored|save|preview|restore|anim-preset`**,
**`clipboard stats|prune`**, **`reload-cover import|prune`**, `lock list|set`,
`keybinds`, `apps`, `shell get|set|prompt`, `wm list|preview`, `outputs`,
`gpu|cpu|lighting|voxtype|rice|fastfetch|profile|matugen|import|share`,
`palette-bridge`. Engine: `Hub.qml:717,729,753,910,925,942,951,963`;
`ProviderSchema.qml:56,72`; `AnimationsPage.qml:182,186`.

External binaries shelled out by Hub QML: `ryostore`, `ryoku-shell`, `ryoku`,
`ryoku-plugins-place`, `ryoku-network-kill`, `nmcli`, `rfkill`, `systemctl`,
`timedatectl`, `fc-list`, `usermod`, `xdg-open`, `sh`/`bash`, `pkexec`,
`fprintd-list`, `fprintd-enroll`, `fprintd-verify`, `fprintd-delete`, `busctl`,
`curl`, `kitty`, `qs` (`SettingsSheet.qml:480-485`), `gsettings` (backend
`schemes.go:336`), `matugen` (`schemes.go:49`), `pkill` (`schemes.go:166`).

### Services / daemons

**[READ]**

- `ryoku-shell` daemon — control socket `$XDG_RUNTIME_DIR/ryoku-shell.sock`
  (`Singletons/Settings.qml:47`; `hub/backend/daemonclient.go:30`). Topics
  `settings`, `wm`, `updates`, clipboard; verbs `settings.patch|reset`
  (`shell/ipc/settings.go:40-41,1116,1126`). Sole writer of `shell.json`.
- `ryoku-shell.service` — restarted by GlobalPage on timezone change
  (`GlobalPage.qml:83`).
- `ryoku-wm-<provider>` — the compositor provider binary the Hub execs
  (`vendor/ryoku-wm/client.go`). Not needed once the write path is severed.
- `ryoku-palette-bridge.service` (`palettebridge.go:13,91`), `fprintd`
  (`LockscreenPage.qml:775,860`), `systemd-timedated` (GlobalPage timezone),
  `power-profiles-daemon`/`ryoku-power`, `voxtype.service`.

### Qt modules

**[READ]** `QtQuick`, `QtQuick.Controls`, `QtQuick.Shapes`,
`Qt.labs.folderlistmodel`, plus the Quickshell modules `Quickshell`,
`Quickshell.Io`. No QtNetwork/QtWebEngine usage in the Hub frontend.

### Fonts

**[READ]** `Singletons/Theme.qml:53-56` names Fraunces (display), Space Grotesk
(UI), Noto Sans CJK JP (kanji marks), JetBrainsMono Nerd Font (mono). One font
is bundled: `hub/quickshell/fonts/archivo-black.ttf`. Font lists for the
`fontFamily` pickers are read live via `fc-list` (`GlobalPage.qml:48`,
`WidgetsPage.qml:94`). I18n text uses `Ryoku.Ui.Singletons.I18n`.

### Assets

**[READ]**

- `hub/quickshell/art/`: `dither-torii.png`, `profile-hero.png`, `roots.png`,
  `tiling-dwindle.gif`, `tiling-master.gif`, `tiling-scrolling.gif` (the tiling
  gifs are referenced by the Appearance layout demo in `SettingsSheet.qml:534`).
- `hub/quickshell/fonts/archivo-black.ttf`.
- `ui/grain.png`; `ui/art/{graces,helm,justice}.svg`;
  `ui/shaders/{dither,spectrum}.frag` + `.qsb`.
- Reload-cover managed assets at runtime: `$XDG_DATA_HOME/ryoku/reload-cover/`
  (`reloadcover.go:59-65`).
- Bar skins and store widgets come from `ryostore` at runtime.

### Network calls

**[READ]** In the Hub frontend the only direct outbound call is the geocode
lookup used by the location control:

- `SettingsSheet.qml:998-999`: `curl -s --max-time 6
  https://geocoding-api.open-meteo.com/v1/search…` (feeds `weatherLocation` on
  GlobalPage).

Indirect/other **[UNVERIFIED]**:

- `ryostore catalog|install|open` (Bar Studio, Widgets, Lockscreen) — store
  network.
- `ryoku-hub share status` / `rice publish` (`palettebridge.go:119-123` probes
  `127.0.0.1:47616/healthz`; `ricepublish.go`) — local/`[UNVERIFIED]` remote.
- `RashinPage.qml:177` talks to `http://127.0.0.1:<port>` (local; page dropped).
- `Updates` singleton consumes the daemon `updates` topic (daemon does the fetch).

Mei's Appearance/Shell pages therefore need network only for the optional
weather-place search; drop the `location`/`timezone` controls or keep the single
geocode call if offline behaviour is acceptable.

### Necessity / exclusions

Each kept item below passes the necessity test (on the keep list, or required by
one that is). Costs are static estimates from source, not measured.

| Item | Why kept | Cost / spawned | Opt-back-in |
|---|---|---|---|
| `Hub.qml`, `SchemaPage.qml`, `SettingsSheet.qml`, `ui/` kit | the Settings look + framework the owner asked to reuse | QML only | — |
| `Singletons/{Theme,Settings,Scheme}.qml` | palette, daemon seam, live colours | 1 socket to daemon | — |
| `GlobalPage`, `DesktopPage`, `BarStudioPage`, `LauncherPage`, `WidgetsPage` | Appearance + Shell editors | per-page `FileView`/`Process` | add page back to `groups` + `pageFile` |
| `AnimationsPage` (shell-motion block only) | centralised motion language; `theme.motion.*` | 1 patch | restore hypr block to re-add window anims (not advised) |
| `ryoku-shell` daemon `settings` topic | sole writer of `shell.json` | 1 daemon | already trimmed |
| `ryoku-hub` `config`, `reload-cover`, `clipboard` verbs | hub.toml + reload-cover asset + clipboard page | 1 short-lived process per call | drop with their pages |
| `ui` QML plugin + `Ryoku.FrameBars` module | imported by kept pages | QML plugin load | — |

**Excluded (reported, disabled):**

- **All compositor writers**: `desktop save|preview|restore|scheme|anim-preset`,
  the `ryoku-wm` provider applying `settings.lua`/`rebinds.lua` +
  `hyprctl reload`, the niri KDL writers, and the `hypr*` QML machinery
  (`Hub.qml:889-996`). **This is the required severance**: Settings never
  writes/generates Hyprland config. *Opt back in*: re-vendor the writing half of
  `ryoku-wm` and re-add the `desktop` write verbs and the compositor pages.
- **Compositor-editor pages**: `windowmanager`, `plugins`, `layerrules`,
  `input`, `keybinds`, `windowrules`, `appoverrides`, `displays`, `session`,
  `gpu`, and the hypr half of `animations`. *Opt back in*: re-add the page
  files, their `schema/*.js`, and the `groups`/`pageFile` entries.
- **Out-of-scope pages**: `profile`, `updates`, `connections`, `recording`,
  `dictation`, `fastfetch` (non-shell rows), `addons`, `rashin`, `import`,
  `credits`. *Opt back in*: one rail line + page file each.
- **`lockscreen`**: writes `/etc/pam.d/*` (via `pkexec`), `~/.config/qylock/*`,
  `ryoku keyring`/`security-key`, fprintd, qylock skins — neither Appearance nor
  Shell and touches the system. *Opt back in*: re-add `LockscreenPage.qml` and
  `hub/backend/lock.go`.
- **`performance`** (`ryoku-power` CPU/power profiles) and **`gpu`**
  (`gpu.lua`/passthrough): hardware/system power, not Appearance/Shell.
- **`matugen` app-template fan-out** (`schemes.go`, `matugen.go`): writes
  `colors.json`, `theme.json`, `matugen.json` and every external app config
  (kitty, GTK, Qt, …). Keep Mei's palette generation only if it writes into
  Mei's own dir; sever the app-config fan-out.
- **`ryostore` dependency**: `go.mod` replace points at an **OFF-disk**
  `apps/ryostore/backend` (only the vendored `compat/version.go` exists). Drop
  the store-backed pages (Add-ons, Lockscreen, Bar Studio store fetch) or pin
  the vendored stub; do not fetch the missing tree.
- **Hub vices that write outside Mei's dir**: `shellpref.go` (login-shell
  initiation files, `desktop.env`), `palettebridge.go` (enables a systemd unit),
  `lighting*`/`openrgb`/`qmk`/`aura` (RGB devices), `voxtype` (dictation),
  `import*` (rewrites dotfiles), `ricepublish`/`share` (network). All excluded
  with their pages.

No file under `upstream/` was modified; this document is the only file written.

---

## 05 — Names, network calls, and uv

Phase 2 dependency mapping for the Mei fork of Ryoku v0.75.5-beta.20 (commit `98a0368253d9628be72b853985878a5db90e1547`).
Source is read-only. Every citation below was produced by `git grep -n`/`git show`/`sed` against
`$HOME/projects/mei/upstream` (on-disk `ryoku/{shell,hub,wm,ui,palette-bridge}` and off-disk
blobs at `HEAD`). Labels: **[READ]** = line verified in file contents; **[UNVERIFIED]** = quoted from
docs/CHANGELOG or inferred, not re-read in source; **[TESTED]** = none (no build/run permitted).

Convention assumed for the "Mei action" columns: product prefix `ryoku` → `mei`, daemon/config
`ryogami` → `mei-wall` (it is an in-repo Rust daemon, not third-party). Third-party D-Bus names
(`org.freedesktop.*`, `org.kde.*`, `org.gnome.*`, `org.mpris.*`) are **interfaces to other
software** and must **never** be renamed.

---

### Q5 — Hard-coded names (sockets, locks, D-Bus, paths)

#### Q5.1 Unix sockets

| Name | What it is | Where (file:line) | Env-derived / absolute |
|---|---|---|---|
| `ryoku-shell.sock` | The single control socket the Go shell daemon owns; command clients + the Hub dial it | `ryoku/shell/ipc/main.go:18` (const), `:20-26` (`sockPath()`), `:89` (dial) **[READ]** | Env-derived: `$XDG_RUNTIME_DIR/ryoku-shell.sock`, falls back to `/tmp` |
| `ryoku-shell.sock` (clients) | Hub backend dials the daemon socket | `ryoku/hub/backend/daemonclient.go:26-30` **[READ]** | Env-derived `$XDG_RUNTIME_DIR` |
| `ryoku-shell.sock` (QML) | Hub + shell QML `Socket`/services targets | `ryoku/hub/quickshell/Singletons/Settings.qml:47`, `Updates.qml:11`, `pages/RecordingPage.qml:68`, `pages/DisplaysPage.qml:192,211`; `ryoku/shell/quickshell/shell/services/{Config.qml:257,Clipboard.qml:20,Dock.qml:160,Holidays.qml:9,Keypresses.qml:15,Keyring.qml:37}`, `modules/bar/barstyles/kairos/settings/IslandSettings.qml:82`, `modules/bar/barstyles/qsbar/Theme.qml:3207`, `modules/bar/framebars/menus/MenuTheme.qml:36`, `modules/stage/Singletons/StageBackend.qml:92`; `ryoku/shell/ryogami/wall-ui/qml/wallpaper/settings/ComfortSettings.qml:24` **[READ]** | Env-derived `(Quickshell.env("XDG_RUNTIME_DIR") \|\| "/tmp")` |
| `ryoku-shell.sock.lock` | Flock guarding a double daemon start (socket file alone is not proof of liveness) | `ryoku/shell/ipc/daemon.go:277` (`holdDaemonLock(path + ".lock")`) **[READ]** | Derived from the socket path (env-derived) |
| `ryoku-shell.sock` (doctor) | `ryoku` CLI probes it | `ryoku/cli/internal/doctor/doctor.go:3192` (off-disk) **[READ]** | Env-derived |
| `ryogami.sock` | Rust/Go wallpaper daemon surface + depth IPC socket | `ryoku/shell/ryogami/daemon/proto.go:87-92` (`socketPath()`); `ryoku/shell/ipc/ryogami.go:37-42` (`ryogamiSock()`); `:49` dial, `:199` subscribe; wall-ui client `ryoku/shell/ryogami/wall-ui/qml/services/DaemonClient.qml:396` **[READ]** | Env-derived `$XDG_RUNTIME_DIR/ryogami.sock`, falls back to `/tmp` |
| `ryoku-pill.sock` | Consolidated-pill command socket — **dead in production** (single shell omits `SocketServer`), retained for the retire phase | `ryoku/shell/ipc/actions.go:105-116` (`pillSockPath()` at `:109-113`) **[READ]** | Env-derived `$XDG_RUNTIME_DIR/ryoku-pill.sock` |
| `/run/polkit/agent-helper.socket` | systemd-socket-activated polkit helper; daemon dials it (polkit ≥126 dropped setuid helper) | `ryoku/shell/ipc/polkit.go:63-69` (`polkitHelperSocket` at `:69`), dialed at `:78` **[READ]** | **Absolute** package var (test-overridable) |
| `/usr/lib/polkit-1/polkit-agent-helper-1` | Fallback setuid polkit helper path (pre-126 installs) | `ryoku/shell/ipc/polkit.go:59-61` (`polkitHelperPath` at `:61`) **[READ]** | **Absolute** |
| `Quickshell ipc.sock` | Per-instance Quickshell socket under the instance runtime dir (pruned by the daemon) | `ryoku/shell/ipc/qsruntime.go:12,24,60,80,111` **[READ]** | Env-derived `$XDG_RUNTIME_DIR` |

#### Q5.2 Lock / marker files

| Name | What it is | Where (file:line) | Env-derived / absolute |
|---|---|---|---|
| `/tmp/ryoku-hub.lock` | Flock held for the life of a Hub instance (Super+, single-instance) | `ryoku/shell/ipc/control.go:177-179` **[READ]**; QML callers `ryoku/shell/quickshell/shell/modules/bar/barstyles/qsbar/controlcenter/ControlCenter.qml:215`, `.../providers/actions/catalog.js:35`, `.../modules/desktop/WidgetMenu.qml:118`, `.../welcome/StepCustomize.qml:71`; comment `ryoku/hub/quickshell/shell.qml:44`; `ryoku/apps/ryostore/backend/routing.go:56` (off-disk) **[READ]** | **Absolute `/tmp`** (not env-derived) |
| `/tmp/ryoshot.lock` | Flock single-instance for the screenshot overlay | `ryoku/shell/quickshell/shell/modules/bar/Frame.qml:71`, `.../launcher/.../actions/catalog.js:22`, `.../services/Capture.qml:176` **[READ]** | **Absolute `/tmp`** |
| `/tmp/ryopin.lock` | Flock single-instance for the pin overlay | `ryoku/shell/quickshell/ryoshot/shell.qml:717` **[READ]** | **Absolute `/tmp`** |
| `/tmp/ryoku-keys.lock` | Flock single-instance for the keybind cheatsheet | `ryoku/shell/quickshell/shell/modules/launcher/shared/providers/actions/catalog.js:36` **[READ]** | **Absolute `/tmp`** |
| `/tmp/ryostore.lock`, `/tmp/ryovm.lock` | Flock single-instance for the store / VM apps | `ryoku/apps/ryostore/ryostore.desktop:6`, `ryoku/apps/ryovm/ryovm.desktop:6`, `ryoku/apps/ryostore/backend/routing.go:45` (off-disk) **[READ]** | **Absolute `/tmp`** |
| `$XDG_RUNTIME_DIR/ryoku-qsbar-brightness.lock` | Single-flock serialising rapid brightness taps | `ryoku/shell/quickshell/shell/modules/bar/barstyles/qsbar/RyokuPower.js:26` **[READ]** | Env-derived `$XDG_RUNTIME_DIR`, falls back to `/tmp` |
| `$XDG_RUNTIME_DIR/qylock.<session>.<suffix>` | Lock-screen proof markers (`locked`, `expected`, `proof.lock`) | `ryoku/shell/ipc/actions.go:185-195` (`lockProofPath`/`lockMarker`) **[READ]** | Env-derived `$XDG_RUNTIME_DIR` + `$XDG_SESSION_ID` |
| `$XDG_RUNTIME_DIR/ryoku-power-cutover.lock` | Login/deploy power cutover flock | `ryoku/shell/deploy.sh:33`; `ryoku/cli/internal/doctor/reconcile_lockscreen.go:172` (off-disk) **[READ]** | Env-derived |
| `$XDG_RUNTIME_DIR/ryoku-update.lock` | Updates flock | `ryoku/cli/internal/updater/update.go:269` (off-disk) **[READ]** | Env-derived `XDG_RUNTIME_DIR` |
| `.../ryoku/eq/filter-chain.conf` | (see runtime dirs) pipewire eq config | `ryoku/shell/systemd/user/ryoku-eq.service:13` **[READ]** | `%t` = runtime dir |

#### Q5.3 D-Bus names / interfaces / paths

**Claimed (owned) names — these are "identities" the daemon presents:**

| Name | What it is | Where (file:line) |
|---|---|---|
| `org.gnome.keyring.SystemPrompter` | The daemon **claims this session-bus name**, reimplementing gcr's prompt as an island | `ryoku/shell/ipc/prompter.go:31` (const), `:80` (`RequestName`), `:86` (owner check) **[READ]** |
| `/org/gnome/keyring/Prompter` | Exported object path for the prompter | `ryoku/shell/ipc/prompter.go:32`, `:77` (`Export`) **[READ]** |
| `org.gnome.keyring.internal.Prompter` | Interface implemented (gcr wire contract) | `ryoku/shell/ipc/prompter.go:33`; callbacks/errors `:34-39` **[READ]** |
| `org.kde.StatusNotifierWatcher` | The daemon runs the **system-tray host**; claims this name | `ryoku/shell/ipc/tray.go:32` (name), `:33` (path `/StatusNotifierWatcher`), `:34` (iface), `:139` (`RequestName`) **[READ]** |
| `org.freedesktop.Notifications` | Notification D-Bus provider is **Quickshell itself** (a keep-list feature), not the Go daemon | `ryoku/shell/quickshell/shell/modules/bar/barstyles/qsbar/panels/NotificationPanel.qml:25` (comment), `ryoku/shell/quickshell/shell/services/Notifs.qml:4` (import `Quickshell.Services.Notifications`) **[READ]** |

**Consumed (client) names/interfaces — third-party, must not be renamed:**

| Name | Feature | Where (file:line) |
|---|---|---|
| `org.freedesktop.PolicyKit1(.Authority/.AuthenticationAgent/.Error.Failed)` | polkit auth agent | `ryoku/shell/ipc/polkit.go:43-48` **[READ]** |
| `org.freedesktop.login1(.Manager/.Session)` | suspend/sleep/wake + session lookup | `ryoku/shell/ipc/sleepwake.go:21-25`, `:119`; `ryoku/shell/ipc/polkit.go:489-494`, `:580-581` **[READ]** |
| `org.freedesktop.NetworkManager(.Settings/.Device/.Device.Wireless/.AccessPoint/.Connection.Active/.Settings.Connection)` | network/battery-adjacent status | `ryoku/shell/ipc/network.go:28-38` **[READ]** |
| `org.freedesktop.UPower.PowerProfiles` (+ `org.freedesktop.DBus.Properties`) | power profiles | `ryoku/shell/ipc/powerprofiles.go:26-28`, `:74`, `:191-192` **[READ]** |
| `org.mpris.MediaPlayer2.*` | media/lyrics | `ryoku/shell/quickshell/shell/modules/bar/barstyles/qsbar/modules/MprisArtwork.qml:24`; `ryoku/shell/ipc/music.go` (player option matching) **[READ]** |
| `org.freedesktop.portal.ScreenCast` / `org.freedesktop.portal.Desktop` | portal share-status probe | `ryoku/hub/backend/sharestatus.go:12-18,35` **[READ]** |
| `org.freedesktop.DBus` / `.Properties` | generic | `ryoku/hub/backend/aura.go:109`; `ryoku/shell/ipc/tray.go:37,582`; `ryoku/shell/ipc/sleepwake.go:644,804-806` **[READ]** |
| `org.freedesktop.secrets` / `org.freedesktop.Secret.*` | Secret Service (used by prompter interop + tests; production prompt path) | `ryoku/shell/ipc/e2e_manual_test.go:26,74-81`; `prompter_interop_test.go:64-162` **[READ]** |
| `org.gnome.desktop.interface` | gsettings accent/theme/fonts (wallpaper+matugen) | `ryoku/shell/ipc/matugen.go:1289,1361-1362,1390,1626-1628`; `icons.go:126` **[READ]** |
| `org.quickshell` | **app-id** targeted to raise the Hub window (not a bus name) | `ryoku/shell/ipc/control.go:158-161` **[READ]** |
| `org.kde.syntaxhighlighting` | QML code-block highlighting import | `ryoku/shell/quickshell/shell/components/CodeHighlight.qml:2` **[READ]** |
| `org.libvirt.unix.manage` | polkit action in generated VM domain | `ryoku/hub/backend/gpuapply.go:188` **[READ]** |

#### Q5.4 Runtime directories

| Path | What it is | Where (file:line) |
|---|---|---|
| `$XDG_RUNTIME_DIR/ryoku-idle-output/` | idle-policy state (`lock`, `generation`) | `ryoku/shell/ipc/sleepwake.go:1028-1032` **[READ]** |
| `$XDG_RUNTIME_DIR/ryoku/pins/` | pin captures handed to `ryopin` | `ryoku/shell/CHANGELOG.md:1818` **[UNVERIFIED]** |
| `%t/ryoku/eq/filter-chain.conf` | pipewire equalizer config loaded by `ryoku-eq.service` | `ryoku/shell/systemd/user/ryoku-eq.service:13` **[READ]** |
| `$XDG_RUNTIME_DIR/ryogami-wall` | wall-ui picker runtime dir | `ryoku/shell/ryogami/wall-ui/qml/Config.qml:87` **[READ]** |
| `$XDG_RUNTIME_DIR/ryoku-update.json`, `.../ryoku-update-answer` | update progress island state/answer (Hub shells) | `ryoku/hub/quickshell/pages/UpdatesPage.qml:114-115`; `docs/cli.md:64`, `docs/updates.md:96` **[READ]/[UNVERIFIED]** |
| `$XDG_RUNTIME_DIR/ryoku-rashin/setup.json` | Rashin setup progress (Hub) | `ryoku/hub/quickshell/pages/RashinPage.qml:150`; `docs/rashin.md:357` **[READ]** |
| `$XDG_RUNTIME_DIR/qylock.locked` | lock-screen marker (legacy/CHANGELOG) | `ryoku/shell/CHANGELOG.md:3806`; `ryoku/shell/ipc/lock_test.go:144,151` **[READ]/[UNVERIFIED]** |

#### Q5.5 Config / cache / state filesystem paths

| Path | Feature | Where (file:line) |
|---|---|---|
| `~/.config/ryoku/` (config dir) | base config dir | `ryoku/shell/ryogami/daemon/config.go:53-57` (`ryokuConfigDir()`) **[READ]** |
| `~/.config/ryoku/ryogami.json` | wallpaper daemon config | `ryoku/shell/ryogami/daemon/config.go:60`; `ryoku/cli/internal/doctor/reconcile_retired_wallpaper_keys.go:115` (off-disk) **[READ]** |
| `~/.config/ryoku/shell.json` | the shell's settings store (bar/dock/etc.) | `ryoku/shell/ryogami/daemon/config.go:202,232`; `ryoku/shell/ryogami/wall-ui/qml/wallpaper/WallpaperSelector.qml:52`; `ryoku/shell/ipc/daemon.go:156` **[READ]** |
| `~/.config/ryoku/theme.json` | selected theme | `ryoku/shell/ipc/matugen.go:407,432,451,495`; `ryoku/shell/ryogami/wall-ui/qml/wallpaper/settings/ThemeSettings.qml:21` **[READ]** |
| `~/.config/ryoku/matugen.json` | matugen knobs | `ryoku/shell/ipc/matugen.go:30`; `ThemeSettings.qml:34`; `MatugenSettings.qml:21` **[READ]** |
| `~/.config/ryoku/plugins.json` | plugin enable/placement | `ryoku/shell/ipc/bar.go:124,456` **[READ]** |
| `~/.config/ryoku/keyring.json` | keyring unlock policy | `docs/cli.md:165`; `ryoku/hub/quickshell/schema/LockscreenPage.js:34` **[UNVERIFIED]** |
| `~/.config/ryoku/hub.toml` | Hub persisted state | `ryoku/hub/backend/config.go:11` **[READ]** |
| `~/.config/ryoku/{desktop.json,lighting.json,gpu-presets.json}` | Hub state | `ryoku/hub/backend/desktop.go:18`, `lighting.go:11,53`, `gpupreset.go:226` **[READ]** |
| `~/.config/ryoku/rices/` | rice store | `ryoku/hub/backend/rice.go:18,1165` **[READ]** |
| `~/.config/ryogami-wall/config.json` | wall-ui picker config (skwd keys) | `ryoku/shell/ryogami/daemon/config.go:264-284`; `transitions.go:361-382`; `ryoku/shell/ryogami/wall-ui/qml/Config.qml:16` **[READ]** |
| `~/.cache/ryogami/` | ryogami cache (`colors.json`) | `ryoku/shell/ryogami/daemon/config.go:117-119`; `ryoku/shell/ryogami/wall-ui/data/config.json.example:53` **[READ]** |
| `~/.cache/ryoku/music` | music art/lyrics cache | `ryoku/shell/ipc/music.go:27` **[READ]** |
| `~/.cache/ryoku/colors.json` | the palette file the bridge serves | `ryoku/palette-bridge/main.go:240`; `doctor.sh:5` **[READ]** |
| `~/.cache/{claude,codex,opencode}-usage.json` | AI usage caches (AI feature) | `ryoku/shell/systemd/user/ryoku-ai-usage.service:2` **[READ]** |
| `~/.local/state/ryoku/ryostage/` | ryostage venv + models | `ryoku/shell/scripts/ryostage:24` **[READ]** |
| `~/.local/state/ryoku/{depth,parallax}` | legacy ryostage dirs (adopted by rename) | `ryoku/shell/scripts/ryostage:26-28` **[READ]** |

#### Q5.6 `.desktop` / systemd unit names

| Name | Where (file:line) |
|---|---|
| `ryoku-hub.desktop` (`Name=Ryoku Hub`, `Exec=ryoku-shell hub open`) | `ryoku/hub/ryoku-hub.desktop:3,6` **[READ]** |
| `ryogami-wall.desktop` (`Name=Ryogami Wallpapers`, `Exec=ryogami wallpaper ui`) | `ryoku/shell/ryogami/wall-ui/data/ryogami-wall.desktop:3,6` **[READ]** |
| `ryostore.desktop`, `ryovm.desktop`, `ryoku-nvim.desktop` | `ryoku/apps/ryostore/ryostore.desktop:6`, `ryoku/apps/ryovm/ryovm.desktop:6`, `ryoku/apps/nvim/ryoku-nvim.desktop` (off-disk) **[READ]** |
| `ryoku-shell.service` | `ryoku/shell/systemd/user/ryoku-shell.service` **[READ]** |
| `ryogami.service` | `ryoku/shell/systemd/user/ryogami.service`; CLI refs `ryoku/cli/internal/doctor/reconcile_ryogami_wallpaper.go:26` (off-disk) **[READ]** |
| `ryoku-ai-usage.service` + `.timer` | `ryoku/shell/systemd/user/ryoku-ai-usage.service`,`ryoku-ai-usage.timer` **[READ]** |
| `ryoku-eq.service` | `ryoku/shell/systemd/user/ryoku-eq.service` **[READ]** |
| `ryoku-idle.service`, `ryoku-clamshell.service`, `ryoku-bootstrap.service`, `ryoku-session.target` | `ryoku/shell/systemd/user/` **[READ]** |
| `10-ryoku.conf` (xdg-desktop-portal-gnome drop-in) | `ryoku/shell/systemd/user/xdg-desktop-portal-gnome.service.d/10-ryoku.conf` **[READ]** |
| `ryoku-bootstrap.conf` (niri drop-in) | `ryoku/shell/systemd/user/niri.service.d/ryoku-bootstrap.conf` **[READ]** |
| `ryoku-palette-bridge.service` (`ExecStart=/usr/bin/ryoku-palette-bridge`) | `ryoku/palette-bridge/packaging/systemd/ryoku-palette-bridge.service:7` **[READ]** |
| `ryoku-rashin.service` | `ryoku/rashin/systemd/ryoku-rashin.service` (off-disk) **[READ]** |
| Package names `ryoku-shell`, `ryoku-hub`, `ryogami`, `ryoku-palette-bridge`, `ryoku-desktop`, `ryoku-rashin` | `release/packages/*/PKGBUILD` (off-disk) **[READ]** |

#### Q5.7 Quickshell config names (`qs -c <name>`)

`hub` (`ryoku/shell/ipc/control.go:142`, `crashenv.go:7`), `shell`, `ryoshot`, `ryopin`, `keys`, `keys-hint`, `welcome`, `ryostore`, `ryovm` (dirs under `ryoku/shell/quickshell/`; off-disk `ryoku/apps/*/quickshell`). The Hub is selected by path when `RYOKU_SHELL_DIR` is set (`control.go:138-143`). **[READ]**

---

### Q4 — Network call inventory

Legend for "keep?" uses the Mei keep-list: bar/workspaces/launcher/control-sidebar/clock-date/audio/
brightness/network/battery/tray/notifications/wallpaper+matugen/trimmed ryoku-shell/Settings
appearance+shell.

#### Q4.1 Go shell daemon (`ryoku/shell/ipc/*.go`) — feature output is streamed to QML, so QML never fetches

| Endpoint | file:line | Feature | Keep? |
|---|---|---|---|
| `https://nagerholidays.com/api/v4/Holidays` | `ryoku/shell/ipc/calendar.go:19` **[READ]** | Holiday names in the calendar/clock popout | clock-date-adjacent → keep calendar locally, **disable network (holidays only)** |
| `https://lrclib.net/api/get` | `ryoku/shell/ipc/music.go:37` **[READ]** | Lyrics (exact match) | audio/media — **not on keep-list → disable** |
| `https://lrclib.net/api/search` | `ryoku/shell/ipc/music.go:38` **[READ]** | Lyrics (search) | media — disable |
| `https://api.deezer.com/search` | `ryoku/shell/ipc/music.go:39` **[READ]** | Cover-art fallback | media — disable |
| `https://itunes.apple.com/search` | `ryoku/shell/ipc/music.go:40` **[READ]** | Cover-art fallback | media — disable |
| `https://i.scdn.co`, `https://*.googleusercontent.com`, `https://i.ytimg.com/vi/...` | `ryoku/shell/ipc/music.go:541,543,634,663-664,677-679` **[READ]** | Art URL rewriting/upgrade | media — disable |
| `https://api.open-meteo.com/v1/forecast` | `ryoku/shell/ipc/weather.go:38` **[READ]** | Weather forecast | **weather NOT on keep-list → disable** |
| `https://geocoding-api.open-meteo.com/v1/search` | `ryoku/shell/ipc/weather.go:39` **[READ]** | Location geocoding | weather — disable |
| `https://ipwho.is/` | `ryoku/shell/ipc/weather.go:40` **[READ]** | Keyless IP-geolocation fallback (privacy) | weather — disable **especially this** |
| `https://air-quality-api.open-meteo.com/v1/air-quality` | `ryoku/shell/ipc/weather.go:41` **[READ]** | Air-quality | weather — disable |

No `net/http` calls elsewhere in `ipc/*.go` (network control is D-Bus/NetworkManager, not HTTP). **[READ]**

#### Q4.2 Hub backend (`ryoku/hub/backend/*.go`)

| Endpoint | file:line | Feature | Keep? |
|---|---|---|---|
| `http://127.0.0.1:47616/healthz` | `ryoku/hub/backend/palettebridge.go:122` (also `:131` Endpoint) **[READ]** | Local palette-bridge health for wallpaper/matugen | **keep** (loopback, part of wallpaper+matugen) |
| `https://github.com/ryoku-dev/ryostore/releases/download/rices/` | `ryoku/hub/backend/ricepublish.go:92` **[READ]** | Publish/fetch rices | **not on keep-list → disable** |
| `https://api.openai.com/v1` | `ryoku/hub/backend/voxtype.go:243` **[READ]** | Whisper cloud dictation endpoint written to config | AI dictation — **disable** |
| `127.0.0.1:6742` (TCP OpenRGB SDK) | `ryoku/hub/backend/openrgb.go:23,174`; `lighting.go:1155,1183` **[READ]** | RGB lighting control | not on keep-list → disable |
| `http://libvirt.org/schemas/...` | `ryoku/hub/backend/gpudomain.go:124` **[READ]** | XML **namespace URI** in generated domain (not a fetch) | harmless; GPU/VM only — drop with feature |

#### Q4.3 Shell QML (`ryoku/shell/quickshell/**`)

| Endpoint | file:line | Feature | Keep? |
|---|---|---|---|
| `https://api.duckduckgo.com/?q=...` (via `curl -s --max-time 8`) | `ryoku/shell/quickshell/shell/modules/launcher/shared/providers/web/Web.qml:93`; URL builder `.../web/ddg.js:8` **[READ]** | Launcher instant answers | launcher is kept — online answer optional; **keep or gate off** (browser-open still works) |
| Search URLs opened via `Qt.openUrlExternally` (`google.com`, `duckduckgo.com`, `youtube.com`, `github.com`, `wikipedia.org`, `aur.archlinux.org`, `npmjs.com`) | `.../launcher/shared/providers/web/engines.js:6-13`, `Web.qml:55` **[READ]** | Launcher `?`/`!bang` search (opens browser) | **keep** (user-initiated browser open, no daemon call) |
| `https://speed.cloudflare.com/__down`, `.../__up` (XHR GET/POST) | `ryoku/shell/quickshell/shell/modules/bar/barstyles/qsbar/modules/CloudflareSpeedTest.qml:21-22,106,201,223,278` **[READ]** | Network speed-test widget | network is kept but speed test is an extra widget — **optional; can gate off** |
| `https://litterbox.catbox.moe/resources/internals/api.php` | `ryoku/shell/quickshell/ryoshot/shell.qml:854` **[READ]** | Screenshot/annotation upload (ryoshot) | ryoshot not on keep-list → **disable** |
| `http://localhost:9000` (cobalt) + `yt-dlp` | `ryoku/shell/quickshell/shell/services/Stash.qml:61`; scripts `stash-cobalt.sh:19`; `stash-download.sh:25` **[READ]** | Stash media downloader | not on keep-list → **disable** |
| YouTube/SomaFM streams (`youtube.com/@.../live`, `ice1.somafm.com/...`) | `ryoku/shell/scripts/ryoku-cmd-radio:31-34` **[READ]** | Launcher radio provider | not on keep-list → **disable** |
| `https://api.anthropic.com/api/oauth/usage` | `ryoku/shell/bin/claude-usage:20` **[READ]** | AI usage pill | AI — **disable** (`codex-usage`/`opencode-usage` read local state only) **[READ]** |

#### Q4.4 Hub QML (`ryoku/hub/quickshell/**`)

| Endpoint | file:line | Feature | Keep? |
|---|---|---|---|
| `https://geocoding-api.open-meteo.com/v1/search` (via `curl`) | `ryoku/hub/quickshell/SettingsSheet.qml:998-999` **[READ]** | Weather location search in Settings | weather — **disable** |
| `http://127.0.0.1:<port>` | `ryoku/hub/quickshell/pages/RashinPage.qml:177` **[READ]** | Local Rashin/Hermes backend link | AI — **disable** |
| `https://api.openai.com/v1` (schema string) | `ryoku/hub/quickshell/schema/DictationPage.js:52` **[READ]** | Whisper remote preset | AI — **disable** |
| `https://github.com/...` credit/placeholder URLs | `ryoku/hub/quickshell/pages/CreditsPage.qml:24-55`; `ImportPage.qml:739`; `PluginsPage.qml:527` **[READ]** | Static links (no fetch) | harmless; drop with pages if trimmed |

#### Q4.5 palette-bridge (`ryoku/palette-bridge/**`)

| Endpoint | file:line | Feature | Keep? |
|---|---|---|---|
| `127.0.0.1:47616` (listener; routes `/colors.json`, `/v1/palette`, `/v1/events`, `/healthz`) | `ryoku/palette-bridge/main.go:241,255-258,267` **[READ]** | Serves wallpaper palette to browser integrations | local; wallpaper+matugen — **keep** if browser theming kept, else optional |
| `http://127.0.0.1:47616/v1/events` | `ryoku/palette-bridge/spicetify/ryoku-wallpaper-colors.js:6` **[READ]** | Spotify recolor | optional integration — drop if not wanted |
| `http://127.0.0.1:47616/v1/events` | `ryoku/palette-bridge/zen-extension/background.js:3`; `zen-extension/manifest.json:6` **[READ]** | Zen browser recolor | optional |
| `http://127.0.0.1:47616` | `ryoku/palette-bridge/doctor.sh:6` **[READ]** | Local health check | keep (loopback) |
| `https://upload.wikimedia.org/...` / `https://refact0r.github.io/...` | `ryoku/palette-bridge/templates/vesktop-colors.css:49`; `vesktop/midnight-ryoku.theme.css:7` **[READ]** | CSS assets fetched by Discord/vesktop, not the daemon | optional |

#### Q4.6 ryogami wallpaper daemon + picker (`ryoku/shell/ryogami/**`)

| Endpoint | file:line | Feature | Keep? |
|---|---|---|---|
| `https://wallhaven.cc/api/v1/search` | `ryoku/shell/ryogami/wall-ui/qml/wallpaper/WallhavenService.qml:190` **[READ]** | Online wallpaper search | wallpaper kept; **online source optional → gate off** |
| `https://api.steampowered.com/IPublishedFileService/QueryFiles/v1/` | `ryoku/shell/ryogami/wall-ui/qml/wallpaper/SteamWorkshopService.qml:244` **[READ]** | Steam Workshop wallpapers | optional → gate off |
| `https://raw.githubusercontent.com/ryoku-dev/ryostore/main` | `RyowallsSource.qml:23` **[READ]** | Ryowalls catalogue | optional → gate off |
| `https://motionbgs.com`, `https://moewalls.com`, `https://go.moewalls.com/download.php`, regex on `moewalls.com/wp-content/...` | `RyowallsSource.qml:24-25,201,204,346` **[READ]** | Motion wallpaper scraping | optional → gate off |
| `https://api.github.com/repos/...`, `https://raw.githubusercontent.com/...`, `https://media.githubusercontent.com/media/...`, `https://wsrv.nl/?url=` | `RyowallsSource.qml:130-134,214,228-231` **[READ]** | Repo/thumbnail fetch | optional → gate off |
| (Rust daemon) | none found in `ryoku/shell/ryogami/daemon/*.rs` **[READ]** | — | wallpaper engine itself is offline — **keep** |

---

### Q6 — uv usage

`uv` is a Python project/venv manager. The `ryoku-shell` PKGBUILD hard-depends on it.

| Use | Where (file:line) | Feature it serves | Keep-list? |
|---|---|---|---|
| PKGBUILD `depends=(... 'uv')`, rationale comment | `release/packages/ryoku-shell/PKGBUILD:16-18` **[READ]** | provisions the ryostage Python 3.13 venv | no |
| `uv python install 3.13` / `uv venv` / `uv pip install` | `ryoku/shell/scripts/ryostage:348,357-362,371` **[READ]** | **ryostage** cut-out engine (Subject-in-front / Parallax; rembg + onnxruntime) | **not on keep-list** |
| PKGBUILD `depends=('uv' 'nodejs' 'gcc' ...)` | `release/packages/ryoku-rashin/PKGBUILD:21-29` **[READ]** | Rashin/Hermes installer+runtime | AI — excluded |
| `haveCmd("uv")` preflight | `ryoku/rashin/backend/setup.go:78-86,219` **[READ]** | Rashin preflight | AI — excluded |

**Verdict:** No keep-list feature needs `uv`. Its only shell-package consumer is `ryostage`
(the Stage/depth cut-out effect), which is an extra beyond the base wallpaper+matugen; the other
consumer is Rashin (AI). The base wallpaper engine is the Rust/go `ryogami`, matugen is Go/CLI, and
the picker is pure Rust/QML. If Stage and Rashin are excluded (as the keep-list implies), **drop
`uv` from `ryoku-shell`'s `depends`** and do not ship `ryostage`/`ryoku-rashin`. No other
`ryoku/shell/scripts/*` or `ryoku/shell/bin/*` or systemd unit invokes `uv`/`uvx` **[READ]**.

---

### Rename / redirect table for Mei

Prefix convention: `ryoku` → `mei`; daemon `ryogami` → `mei-wall`. Env vars `RYOKU_*` → `MEI_*`.
Third-party D-Bus and standard paths are **unchanged**.

| Artifact (current) | Kind | Where | Env/abs | Mei action |
|---|---|---|---|---|
| `ryoku-shell.sock` | socket | `ipc/main.go:18` + all QML clients | env `$XDG_RUNTIME_DIR` | → `mei-shell.sock` (update Go + every QML `sockPath`) |
| `ryoku-shell.sock.lock` | lock | `ipc/daemon.go:277` | env | derive from new socket name |
| `ryoku-pill.sock` | dead socket | `ipc/actions.go:113` | env | **delete** (consolidated-shell dead code) |
| `ryogami.sock` | socket | `ryogami/daemon/proto.go:92`, `ipc/ryogami.go:42`, `DaemonClient.qml:396` | env | → `mei-wall.sock` |
| `/tmp/ryoku-hub.lock` | lock | `control.go:179` + 4 QML + `ryostore/routing.go:56` | **abs `/tmp`** | → `/tmp/mei-hub.lock` |
| `/tmp/ryoshot.lock` | lock | Frame.qml:71, catalog.js:22, Capture.qml:176 | **abs `/tmp`** | → `/tmp/mei-shot.lock` (drop if ryoshot excluded) |
| `/tmp/ryopin.lock` | lock | ryoshot/shell.qml:717 | abs | drop (ryopin) |
| `/tmp/ryoku-keys.lock` | lock | catalog.js:36 | abs | → `/tmp/mei-keys.lock` |
| `ryoku-qsbar-brightness.lock` | lock | `qsbar/RyokuPower.js:26` | env | → `mei-qsbar-brightness.lock` |
| `qylock.<sess>.<suffix>` | markers | `ipc/actions.go:185-195` | env+`XDG_SESSION_ID` | → `mei-lock.<sess>.<suffix>` (keep suffix names `locked`/`expected`/`proof.lock`) |
| `ryoku-idle-output/` | runtime dir | `sleepwake.go:1028-1032` | env | → `mei-idle-output/` |
| `ryoku/eq/filter-chain.conf` | runtime path | `ryoku-eq.service:13` | `%t` | → `mei/eq/filter-chain.conf` |
| `ryoku/pins/` | runtime dir | CHANGELOG:1818 | env | → `mei/pins/` |
| `ryoku-update.json`, `ryoku-update-answer` | runtime files | `UpdatesPage.qml:114-115` | env | → `mei-update*.json` |
| `ryoku-rashin/setup.json` | runtime file | `RashinPage.qml:150` | env | drop (Rashin excluded) |
| `/run/polkit/agent-helper.socket` | socket | `polkit.go:69` | **abs, distro-owned** | **KEEP** (belongs to polkit, not Ryoku) |
| `/usr/lib/polkit-1/polkit-agent-helper-1` | path | `polkit.go:61` | abs | **KEEP** |
| `org.gnome.keyring.SystemPrompter` + `/org/gnome/keyring/Prompter` + `org.gnome.keyring.internal.Prompter` | D-Bus name/path/iface | `prompter.go:31-39,77-80` | n/a | **KEEP** (third-party contract; gnome-keyring/gcr drives it) |
| `org.kde.StatusNotifierWatcher` (+ `/StatusNotifierWatcher`) | D-Bus name/path | `tray.go:32-34,139` | n/a | **KEEP** (freedesktop/KDE tray contract, required for tray keep-list) |
| `org.freedesktop.*`, `org.mpris.*`, `org.gnome.desktop.interface` | D-Bus | polkit/network/upower/login1/portal/matugen | n/a | **KEEP** (all third-party) |
| `org.quickshell` | app-id | `control.go:161` | n/a | **KEEP** (Quickshell's own id) |
| `~/.config/ryoku/` + `ryogami.json`,`shell.json`,`theme.json`,`matugen.json`,`plugins.json`,`keyring.json`,`hub.toml`,`desktop.json`,`lighting.json`,`gpu-presets.json`,`rices/` | config | config.go:53-60; matugen.go; bar.go; hub/backend/* | `$XDG_CONFIG_HOME` | → `~/.config/mei/`; `ryogami.json`→`mei-wall.json`; add a one-time migrator (doctor `reconcile_*` already migrates keys) |
| `~/.config/ryogami-wall/config.json` | config | config.go:264-284; Config.qml:16 | `$XDG_CONFIG_HOME` | → `~/.config/mei-wall/config.json` |
| `~/.cache/ryogami/`, `~/.cache/ryoku/{music,colors.json}` | cache | config.go:117-119; music.go:27; main.go:240 | `$XDG_CACHE_HOME` | → `~/.cache/mei-wall/`, `~/.cache/mei/` |
| `~/.local/state/ryoku/ryostage` | state | ryostage:24 | `$XDG_STATE_HOME` | drop with Stage |
| `ryoku-shell.service`, `ryogami.service`, `ryoku-eq/-idle/-clamshell/-bootstrap.service`, `ryoku-session.target`, `10-ryoku.conf`, `ryoku-bootstrap.conf` | systemd units/drop-ins | `ryoku/shell/systemd/user/*` | n/a | rename units to `mei-*`/`mei-wall.service`; keep `PartOf`/`WantedBy` graph |
| `ryoku-ai-usage.service`/`.timer` | systemd | same dir | n/a | **drop** (AI) |
| `ryoku-palette-bridge.service`, `ryoku-rashin.service` | systemd | palette-bridge/rashin | n/a | rename bridge → `mei-palette-bridge`; drop rashin |
| `ryoku-hub.desktop`, `ryogami-wall.desktop`, `ryostore/ryovm/ryoku-nvim.desktop` | .desktop | hub/shell/apps | n/a | rename to `mei-*`; `Exec` follows new binary names |
| `ryoku-shell`, `ryoku-hub`, `ryogami`, package names | binaries/pkgs | PKGBUILDs | n/a | → `mei-shell`, `mei-hub`, `mei-wall` |
| `RYOKU_*` env (`RYOKU_POLKIT_AGENT`, `RYOKU_SHELL_DIR`, `RYOKU_CLIP_PERSIST`, `RYOKU_PLUGINS_DIR`, `RYOKU_PALETTE*`, hub `RYOKU_GPU_*`/`RYOKU_*_ROOT`/`RYOKU_DRYRUN`) | env | `polkit.go:35,180`; `actions.go:20`; `clipboard.go:45`; `bar.go:402`; `palette-bridge/doctor.sh:5-6`; `hub/backend/*` | n/a | → `MEI_*` (update unit `Environment=`, `environment.d/ryoku-session.conf:32`, deploy.sh) |
| `qs -c hub`/`shell`/`ryoshot`/`ryopin`/`keys`/`keys-hint`/`welcome` | Quickshell config names | control.go:142; quickshell/ | n/a | rename dirs if rebranding; `hub`→`mei-hub` config id |
| `127.0.0.1:47616` | palette bridge port | main.go:241; hub palettebridge.go:122; js/manifest | n/a | keep (loopback) or change + update integrations |
| `127.0.0.1:6742`, `localhost:9000` | OpenRGB / cobalt | openrgb.go:23; Stash.qml:61 | n/a | drop with RGB / Stash |

---

### Necessity / exclusions

Keep-list verdicts (what to **disable** or **remove**, not rebrand):

1. **Weather** — `weather.go:38-41` (open-meteo ×3, **`ipwho.is` IP-geolocation**) and Hub
   `SettingsSheet.qml:998-999`. Not on the keep-list. Removing also removes the third-party IP
   lookup (privacy win). Delete the daemon weather service, the `weather` state topic, the
   `Weather*` QML widgets/panels, and the Hub weather settings.
2. **Music lyrics/art** — `music.go:37-40` (lrclib, Deezer, iTunes) and the `scdn.co`/
   `googleusercontent`/`ytimg.com` art rewrites (`music.go:541-679`). If the media widget is kept
   for MPRIS metadata + local art only, strip the HTTP resolution block and the network cache.
   "audio" on the keep-list means volume/device control, not online lyric/art lookup.
3. **AI**: `bin/claude-usage:20` (anthropic), `ryoku-ai-usage.{service,timer}`,
   `hub/backend/voxtype.go:243` (OpenAI Whisper), `hub DictationPage.js:52`,
   `hub RashinPage.qml:177`, `ryoku-rashin` package/unit. Disable all.
4. **Rices/Ryostore publish** — `hub/backend/ricepublish.go:92` (GitHub releases). Not on keep-list;
   the Settings "appearance" surface can stay offline (themes/fonts/colors) but must not fetch rices.
5. **RGB lighting** — `hub/backend/openrgb.go:23,174`, `lighting.go:1155`. Drop with the feature.
6. **ryoshot screenshot upload** — `ryoshot/shell.qml:854` (litterbox). If screenshots are kept,
   strip the upload path; otherwise drop ryoshot entirely (also removes `/tmp/ryoshot.lock`,
   `/tmp/ryopin.lock`).
7. **Stash / media downloader** — `Stash.qml:61` (localhost:9000 cobalt), `stash-download.sh:25`
   (yt-dlp), `stash-cobalt.sh`, `ryoku-cmd-radio:31-34` (YouTube/SomaFM). Drop.
8. **Online wallpaper sources** — `ryogami/wall-ui` `WallhavenService.qml:190`,
   `SteamWorkshopService.qml:244`, `RyowallsSource.qml:23-25,130-231,346` (wallhaven, Steam Workshop,
   moewalls, motionbgs, GitHub raw, wsrv.nl). Wallpaper+matugen is on the keep-list, but the **local**
   engine and matugen need none of these; ship the picker with online sources removed or gated off.
9. **Network speed-test widget** — `CloudflareSpeedTest.qml:21-22`. Optional extra; gate off unless
   wanted under the kept "network" feature.
10. **Launcher web instant-answer** — `Web.qml:93` `/ ddg.js:8`. Launcher is on the keep-list; the
    `?`/`!bang` browser-open paths (`engines.js:6-13`) can stay, but the DDG `curl` fetch is an
    optional online extra — gate off (or leave, low risk, user-initiated).
11. **palette-bridge browser integrations** — spicetify/zen/vesktop files under
    `ryoku/palette-bridge/{spicetify,zen-extension,vesktop}`. The local loopback bridge
    (`main.go:241-258`) is fine; ship integrations only if browser recoloring is wanted.
12. **uv dependency** — drop from `ryoku-shell` `depends` (`PKGBUILD:16-18`) together with
    `ryostage` (Stage cut-out) and Rashin; no keep-list feature needs it.

Unchanged / must-not-touch: `/run/polkit/agent-helper.socket`, `/usr/lib/polkit-1/polkit-agent-helper-1`,
and every `org.freedesktop.*`/`org.kde.StatusNotifierWatcher`/`org.gnome.keyring.*`/`org.mpris.*`
D-Bus name — these are contracts with other software, not Ryoku branding.

---

## 06 — Fonts, assets, QML modules, Qt modules

Cross-cutting inventory for the kept surfaces: the bar (`qsbar`), the launcher,
the control sidebar (`qsbar/controlcenter`), and the Settings "appearance + shell"
pages (Hub `GlobalPage` / `DesktopPage` / `AnimationsPage`, rendered through
`Ryoku.Ui`). Scope is the sparse checkout on disk plus the off-disk trees reachable
with `git show HEAD:<path>`.

Labels: **[TESTED]** observed by running a build/test — none here (Ryoku source is
read-only, nothing built or run). **[READ]** read directly from committed source /
blob sizes. **[UNVERIFIED]** inferred or not confirmed by execution.

Citations are `path:line` for content and `path` + blob bytes for sizes.

---

### Fonts (families, files, packages, fallbacks)

#### Family names the UI hardcodes [READ]

| Family | Declared in | Role |
|---|---|---|
| `Fraunces` | `ryoku/ui/Singletons/Tokens.qml:105`; `ryoku/hub/quickshell/Singletons/Theme.qml` (display); `ryoku/shell/quickshell/shell/services/Theme.qml:213`; launcher `shared/Singletons/Theme.qml:75` | display serif: page titles, hub heads |
| `Space Grotesk` | `Tokens.qml:106` (`ui`, default); hub `Theme.qml` (`font`); shell `Theme.qml:203` (`fontPrimary` default) | UI/body sans (brand) |
| `JetBrainsMono Nerd Font` | hub `Theme.qml` (`mono`); shell `Theme.qml:214`; qsbar `Theme.qml:121`; launcher `Config.qml:97` (`fontFamily` default) | labels, code, nerd glyphs |
| `SpaceMono Nerd Font` | `ryoku/ui/Singletons/Tokens.qml:107` (`mono`, compiled default) | default mono until shell.json overrides |
| `Noto Sans CJK JP` | `Tokens.qml:108` (`jp`); hub `Theme.qml` (`fontJp`); shell `Theme.qml:215` | the 力 seal and every kanji mark |
| `Material Symbols Rounded` | `ryoku/shell/quickshell/shell/components/MaterialIcon.qml:12` | every bar/pill/settings icon ligature |
| `Inter` / `Inter Display` | hub previews e.g. `ClockPreview.qml:124,227,306`; `AioPreview.qml:75` | hub preview widget bodies |
| `Archivo Black` | loaded from a file, `ryoku/hub/quickshell/pages/RashinPage.qml:50` | Rashin page face (Hub, not on the Mei keep list) |

Notes [READ]:
- `Tokens.refreshNamed()` (`Tokens.qml:303-315`) overwrites both `ui` and `mono`
  with `shell.json` `fontFamily` when the user sets a System font, so Space
  Grotesk / SpaceMono are *defaults*, not fixed.
- The seal is text, not an image: `Theme.mark = Config.markText || "\u529b"`
  (`shell/services/Theme.qml:219`, `shell/modules/desktop/Singletons/Theme.qml:84`)
  rendered `font.family: Theme.fontJp` (`shell/components/BrandMark.qml:36-38`).
  A custom image mark is optional (`markSource`, `BrandMark.qml:23-25`).

#### Font FILES actually shipped [READ]

On-disk (inside the checkout, part of the kept modules):

| Path | Bytes |
|---|---|
| `ryoku/shell/quickshell/shell/assets/fonts/abberancy.ttf` | 29220 |
| `ryoku/shell/quickshell/shell/assets/fonts/daydream-demo.otf` | 20216 |
| `ryoku/shell/quickshell/shell/assets/fonts/jf-flat-regular.otf` | 43852 |
| `ryoku/shell/quickshell/shell/assets/fonts/overhead.ttf` | 16264 |
| `ryoku/shell/quickshell/shell/assets/fonts/reckoner-bold.ttf` | 28376 |
| `ryoku/shell/quickshell/shell/assets/fonts/reckoner.ttf` | 23592 |
| `ryoku/shell/quickshell/shell/assets/fonts/sabana-regular.ttf` | 32100 |
| `ryoku/shell/quickshell/shell/assets/fonts/unrealised.ttf` | 42500 |
| `ryoku/shell/quickshell/shell/assets/fonts/vexa-light.ttf` | 65360 |
| `ryoku/shell/quickshell/shell/assets/fonts/vip-rawy-regular.otf` | 37836 |
| `ryoku/shell/quickshell/shell/assets/fonts/xenophobia-nominal.ttf` | 27452 |
| **`ryoku/shell/quickshell/shell/assets/fonts/` total** | **366,768** |
| `ryoku/hub/quickshell/fonts/archivo-black.ttf` | 40544 |

These 11 shell faces are loaded at runtime by `FontLoader` in
`ryoku/shell/quickshell/shell/modules/desktop/Singletons/Fonts.qml` and exposed as
`Fonts.families` to the Hub's widget-font picker; they are bundled so a widget can
name one without a system install. `ryoku/ui/art/` holds no fonts.

#### Packages that provide the system families [READ]

`release/packages/ryoku-desktop/PKGBUILD:168-173` (hard `depends`, official repo):
`ttf-jetbrains-mono-nerd`, `inter-font`, `noto-fonts`, `noto-fonts-cjk`,
`noto-fonts-emoji`, `ttf-material-symbols-variable`.

`system/packages/base.packages:304-323` (ISO pacstrap set): the six above plus
`otf-space-grotesk` and `ttf-maple-mono-nf`, both shipped from `[ryoku]`
(`release/packages/otf-space-grotesk/PKGBUILD`, `release/packages/ttf-maple-mono-nf/PKGBUILD`,
fixed-version prebuilt releases).

`system/packages/aur.packages:52`: `ttf-fraunces-variable` (Fraunces, AUR).

`ryoku-desktop-hyprland/PKGBUILD` carries **no** font packages — it inherits
`ryoku-desktop`.

#### Mandatory vs decorative [READ] + [UNVERIFIED]

- **Mandatory for the kept surfaces**: `Noto Sans CJK JP` (the 力 seal + kanji);
  `Material Symbols Rounded` (every icon — without it `MaterialIcon.qml` renders
  the ligature *name* as text, e.g. "wifi", per the PKGBUILD comment at
  `ryoku-desktop/PKGBUILD:164-167`); `JetBrainsMono Nerd Font` (mono text + nerd
  glyphs); `Space Grotesk` (default UI sans); `Inter` (hub preview bodies).
- **Decorative / page-local**: `Fraunces` (titles — falls back to the default sans,
  titles still read); the 11 bundled `FontLoader` faces and `archivo-black.ttf`
  (widget font picker / Rashin page only).
- **Not referenced by any kept QML**: `ttf-maple-mono-nf` (terminal/code offer
  only), `noto-fonts` / `noto-fonts-emoji` (generic + emoji fallback).
- **Fallback when missing** [UNVERIFIED]: Qt font substitution falls through to
  the platform default sans; a missing CJK face leaves 力 as a tofu box; a missing
  `Material Symbols Rounded` leaves icon slots showing the glyph name. No Ryoku
  code installs a substitute — degradation is Qt's.

---

### Assets needed by the kept surfaces (with sizes)

#### On-disk art shipped inside the kept modules [READ]

Bar / control sidebar:
- `ryoku/shell/quickshell/shell/modules/bar/barstyles/qsbar/assets/` — 11 files,
  **68,506 B** total: `arch-header-arch.png` 10300, `arch-header-linux.png` 8596,
  `bob2.png` 1688, `bob3.png` 41408, `claude.svg` 2000, `codex-cli.svg` 1355,
  `codex.svg` 1306, `gpu-card.svg` 439, `hdd-mark.svg` 287, `omacom-text.png` 932,
  `opencode-mark.svg` 195. Referenced from `qsbar/modules/ClaudeWidget.qml:237-257`,
  `GpuWidget.qml:37`, `panels/AiUsagePanel.qml:449-474`.
- `ryoku/shell/quickshell/shell/modules/bar/barstyles/qsbar/shaders/` —
  `logo-tint.frag.qsb` 1404, `stream.frag` 16277, `stream.frag.qsb` 50516 (**68,197 B**).
- `ryoku/shell/quickshell/shell/components/icons/` — 152 symbolic SVGs, **65,090 B**
  (glyph fallback set, `SymbolIcon.qml:23`).

Launcher:
- `ryoku/shell/quickshell/shell/modules/launcher/shared/art/hands-adam.png`
  **681,800 B** (`HeroShutter.qml:89`, `Preview.qml:64,136`, `RestDashboard.qml:96`).
- launcher dir total (`ryoku/shell/quickshell/shell/modules/launcher/`) = 1,422,832 B
  (includes its own `shared/art/bt/*.png`, `qa/` etc.).

Ryoku.Ui (design system):
- `ryoku/ui/grain.png` **66,409 B** (`Grain.qml:7`, tiled film-tooth).
- `ryoku/ui/art/graces.svg` 54526, `helm.svg` 25541, `justice.svg` 35727.
- `ryoku/ui/shaders/dither.frag` 1281 + `dither.frag.qsb` 4219
  (`DitherImage.qml`), `spectrum.frag` 19414 + `spectrum.frag.qsb` 37499.

Misc (referenced by module code):
- `ryoku/shell/quickshell/reload-cover/assets/logo.png` **1,401 B**
  (`ReloadMedia.qml:64`).
- `ryoku/shell/quickshell/welcome/art/welcome-bg.png` **1,204,630 B**
  (`welcome/Backdrop.qml:19`, welcome screen).
- Hub art (`ryoku/hub/quickshell/art/`): `dither-torii.png` 599229,
  `profile-hero.png` 48737, `roots.png` 765424 (`CreditsPage.qml:94`),
  `tiling-dwindle.gif` 101955 + `tiling-master.gif` 96800 +
  `tiling-scrolling.gif` 133209 (`SettingsSheet.qml:534`).

#### Off-disk `ryoku/assets` referenced [READ]

Sizes from `git ls-tree -r -l HEAD ryoku/assets`:

| Path | Bytes | Referenced by | Needed by kept surfaces? |
|---|---|---|---|
| `ryoku/assets/brand/logo.svg` | 594 | `ryoku-desktop/PKGBUILD:427`, `ryoku/shell/deploy.sh:617` | launcher entry icon (`ryoku-hub.svg`) |
| `ryoku/assets/brand/logo-mark.svg` | 552 | `ryoku-desktop/PKGBUILD:317`, `deploy.sh:609` | fallback app icon |
| `ryoku/assets/brand/logo-mark.png` | 43143 | `hub/pages/FastfetchPage.qml:282` | no (Fastfetch, not kept) |
| `ryoku/assets/brand/fastfetch-emblem.png` | 377909 | `FastfetchPage.qml:281`; `ryoku-desktop/PKGBUILD:93` | no (Fastfetch, not kept) |
| `ryoku/assets/brand/icon.png` | 17969 | installer/branding | no (runtime) |

- Referenced brand set total = **440,167 B**; whole `ryoku/assets/brand/` = 1,591,381 B.
- `ryoku/assets/wallpapers/` **245,026,989 B** (~233.7 MiB) — seeded into
  `~/Pictures/Wallpapers` by the installer (`installation/backend/lib/deploy.sh:303`,
  `ryoku-shell-installer/engine.go:1288`). No QML path hardcodes one; the bar wall
  index reads the user's folder, so this is *content*, not a runtime dependency.
- `ryoku/assets/ryodecors/` **4,165,851 B** (~3.97 MiB) — seeded into
  `~/Pictures/ryodecors` (`deploy.sh:541`), resolved via
  `ryoku/ui/Singletons/Ryodecors.qml`. Consumed by `ProfilePage.qml` / `RashinPage.qml`
  only (**not** on the keep list).
- `ryoku/assets` grand total = **250,784,221 B**.

**Bottom line for the kept surfaces** [READ]: the bar needs the 力 seal (a *font*
glyph, not an asset) plus the on-disk `qsbar/assets`/`icons` SVGs; the launcher
needs `hands-adam.png` + `bt/`; Ryoku.Ui needs `grain.png` + its shaders. **No
runtime QML in the kept surfaces reads an off-disk `ryoku/assets` file.** The only
off-disk brand files that matter are the two SVG icons used for the `ryoku-hub`
desktop entry.

---

### QML modules and qmldir inventory

Every committed `qmldir` and the module it declares (`module` line, or the
directory it is imported as) [READ]:

| qmldir | Module | Notes |
|---|---|---|
| `ryoku/ui/qmldir` | `Ryoku.Ui` | 50 QML + 4 JS types |
| `ryoku/ui/Singletons/qmldir` | `Ryoku.Ui.Singletons` | 12 singletons (Tokens, Ink, Paths, I18n, Spans, Silhouette, VizStyles, Ryodecors, ProfileStore, Spawn, Version, Wm) |
| `ryoku/shell/framebars/qmldir` | `Ryoku.FrameBars` | FrameBars/BarCatalog/MenuCatalog/NacreConfig |
| `ryoku/shell/quickshell/plugins/kit/qmldir` | `Ryoku.PluginKit` | 8 types |
| `ryoku/shell/quickshell/plugins/kit/Singletons/qmldir` | `Ryoku.PluginKit.Singletons` | Theme/Config/Motion/Scheme |
| `ryoku/wm/hyprland/qml/qmldir` | `Ryoku.Wm.Hyprland` | GlobalShortcutBridge, FocusGrabBridge |
| `ryoku/shell/quickshell/shell/services/qmldir` | `shell.services` | ~46 singletons (Theme, Config, Media, Audio, Notifs, Tray, Dock, Capture, …) |
| `ryoku/shell/quickshell/shell/barkit/qmldir` | `shell.barkit` | re-exports of stable bar products/components |
| `ryoku/hub/quickshell/Singletons/qmldir` | (hub singletons dir) | Theme/Updates/SysInfo/LiveStats/Scheme/Settings/UserSchemes/ProviderSchema |
| `ryoku/hub/quickshell/barstudio/qmldir` | `barstudio` | CatalogLabels, ZoneEditor, Nacre* |
| `…/qsbar/qmldir` | (qsbar dir) | BarPlugins/BarSlot/Theme/VariantRoot |
| `…/qsbar/core/qmldir`, `modules/`, `panels/`, `components/`, `controlcenter/{,kit,routes}/qmldir` | (relative dirs) | qsbar internal types |
| `ryoku/shell/quickshell/shell/modules/{desktop,launcher/shared,overview,stage,visualizer,wallpaper}/Singletons/qmldir` | (relative dirs) | per-surface singletons |
| `ryoku/shell/quickshell/{welcome,ryopin,ryoshot}/Singletons/qmldir` | (relative dirs) | aux surfaces |
| `ryoku/shell/ryogami/wall-ui/qml/**/qmldir` | (relative dirs) | Ryogami wall browser |
| `Ryoku.Blobs` | C++ module | **no committed qmldir** — generated by `qt_add_qml_module` (see below) |

Non-kept (lockscreen): `ryoku/lockscreen/qylock/.../imports/{QtGraphicalEffects,QtMultimedia,SddmComponents}/qmldir`.

#### QML imports used by the kept surfaces [READ] (occurrence counts)

`Ryoku.Ui.Singletons` ×345 · `Ryoku.Ui` ×77 · `Ryoku.FrameBars` ×10 ·
`Ryoku.PluginKit` ×5 · `Ryoku.PluginKit.Singletons` ×1 · **`Ryoku.Blobs` ×3**
(`shell/modules/bar/Frame.qml:6`, `shell/modules/bar/popouts/Popout.qml:4`,
`shell/modules/capture/CameraOverlay.qml:7`).

`Quickshell` ×300 · `Quickshell.Io` ×187 · `Quickshell.Wayland` ×69 ·
`Quickshell.Widgets` ×23 · `Quickshell.Services.Mpris` ×14 ·
`Quickshell.Bluetooth` ×14 · `Quickshell.Services.Pipewire` ×5 ·
`Quickshell.Services.UPower` ×4 · `Quickshell.Services.Notifications` ×2 ·
`Quickshell.Networking` ×2 · `Quickshell.WindowManager` ×1.

`QtQuick` ×667 · `QtQuick.Controls` ×40 · `QtQuick.Effects` ×37 ·
`QtQuick.Shapes` ×33 · `QtQuick.Layouts` ×11 · `QtQuick.Dialogs` ×2 ·
`QtQuick.Window` ×1. Also `Qt5Compat.GraphicalEffects` (BrandMark, SymbolIcon,
WidgetSlot, EffectLayer) and `org.kde.syntaxhighlighting`
(`shell/components/CodeHighlight.qml:2`, optional `Loader`).

No `Ryoku.Wm` import appears in the copied kept-surface trees; the bridge module is
installed but the surfaces on disk do not import it (compositor seam lives in the
shell root).

---

### C++ plugin (Ryoku.Blobs) build requirements

`ryoku/shell/plugin/` — total **73,797 B** [READ].

`CMakeLists.txt`:
- `cmake_minimum_required(VERSION 3.28)`; `CMAKE_CXX_STANDARD 20`, `AUTOMOC ON`.
- `find_package(Qt6 6.5 REQUIRED COMPONENTS Quick ShaderTools Multimedia)`
  (`CMakeLists.txt:19`) → **Qt Quick (Qt6::Quick), ShaderTools, Multimedia**.
- `qt_add_qml_module(ryoku-blobs URI Ryoku.Blobs VERSION 1.0 …)`; sources
  `blobgroup`, `blobshape`, `blobrect`, `blobinvertedrect`, `blobmaterial`,
  `camerafeed` (`.cpp/.hpp`).
- `target_link_libraries(ryoku-blobs PRIVATE Qt6::Quick Qt6::Multimedia)`
  (`CMakeLists.txt:42`).
- `qt_add_shaders(ryoku-blobs … GLSL "300es,330" PREFIX "/" FILES shaders/blob.vert shaders/blob.frag)`.
- `$ORIGIN` rpath so the plugin `.so` finds its backing lib in the same dir.

`build.sh` (run on dev/ISO only, never the installed target): requires `cmake`,
`ninja`, and (comment) `qt6-shadertools` + a C++20 compiler + Qt6 dev files;
emits `<dest>/Ryoku/Blobs/{libryoku-blobs.so, qmldir, *.qsb}`.

Committed sources/shaders: `shaders/blob.vert` 617 B, `shaders/blob.frag` 13,394 B;
largest C++ is `blobshape.cpp` 16,821 B.

The `ryoku-blobs` package (`release/packages/ryoku-blobs/PKGBUILD`) has
`depends=('qt6-base' 'qt6-declarative' 'qt6-multimedia')` and
`makedepends=('cmake' 'ninja' 'qt6-shadertools' 'qt6-declarative' 'qt6-multimedia')`,
installs to `/usr/lib/qt6/qml/Ryoku/Blobs`. **[READ]**

`CameraFeed` (plugin) links `Qt6Multimedia`; the three kept consumers are the bar
`Frame` (screen frame) and `Popout`.

---

### Qt modules required

From the three PKGBUILDs [READ]:

- `ryoku-blobs`: `qt6-base`, `qt6-declarative`, `qt6-multimedia`
  (+ build: `cmake`, `ninja`, `qt6-shadertools`).
- `ryoku-desktop`: `qt6-wayland`, `qt5-wayland`, `qt6-5compat`, `qt6-svg`,
  `qt6-imageformats`, `qt6-multimedia`, `qt6-declarative`
  (+ build: `go`, `cmake`, `ninja`, `qt6-base`, `qt6-declarative`). Also pulls
  `quickshell` (the QML runtime) and `syntax-highlighting`.
- `ryoku-desktop-hyprland`: **no** `qt6-*` packages (Hyprland/portal/plugin deps).

Which the **kept surfaces** actually require:

| Qt package | Why the kept surfaces need it |
|---|---|
| `qt6-base` | QtCore/QtGui under everything |
| `qt6-declarative` | `QtQuick`, `QtQuick.Controls`, `.Effects`, `.Shapes`, `.Layouts`, `.Dialogs`, `.Window` |
| `qt6-5compat` | `Qt5Compat.GraphicalEffects` — `BrandMark.qml`/`SymbolIcon.qml` (the 力 seal, symbolic icons) |
| `qt6-svg` | every `.svg` asset: `qsbar/assets/*.svg`, `components/icons/*.svg`, `ui/art/*.svg` |
| `qt6-imageformats` | WebP/AVIF decoders (bar/launcher previews, Hub art) |
| `qt6-multimedia` | video wallpaper previews + Ryoku.Blobs `CameraFeed` |
| `qt6-wayland` | Quickshell's Wayland QPA plugin |
| `qt6-shadertools` | build-time only — bakes `.qsb` (blobs + `ui/shaders`, `qsbar/shaders`) |
| `quickshell` | the QML runtime the whole UI runs on |

---

### Install prefixes / import paths

`ryoku/shell/environment.d/ryoku-session.conf` [READ]:
- `QML_IMPORT_PATH=$HOME/.local/lib/qt6/qml`
- `QML2_IMPORT_PATH=$HOME/.local/lib/qt6/qml`
- (comment: `/usr/lib/qt6/qml` on a package install, `~/.local/lib/qt6/qml` from a
  checkout; a keybind-launched `qs -c <name>` has no other way to reach the modules.)

Dev installers:
- `ryoku/ui/install.sh` — default prefix `~/.local/lib/qt6/qml`, copies to
  `$root/Ryoku/Ui` (arg override supported).
- `ryoku/shell/quickshell/plugins/kit/install.sh` → `Ryoku/PluginKit`;
  `ryoku/shell/framebars/install.sh` → `Ryoku/FrameBars`;
  `ryoku/shell/deploy.sh:556-565` → `Ryoku/Wm/Hyprland`.

Package prefixes [READ] (`/usr/lib/qt6/qml/Ryoku/…`):
- `Ryoku.Ui` ← `ryoku-desktop/PKGBUILD:331-337`
- `Ryoku.PluginKit` ← `ryoku-desktop/PKGBUILD:324-326`
- `Ryoku.FrameBars` ← `ryoku-desktop/PKGBUILD:347-349`
- `Ryoku.Blobs` ← `ryoku-blobs/PKGBUILD` (package())
- `Ryoku.Wm.Hyprland` ← `ryoku-desktop-hyprland/PKGBUILD` (package())

---

### Necessity / exclusions

**Sizes asked for** [READ]:

| Item | Bytes | ~ |
|---|---|---|
| (a) `ryoku/shell/plugin` | **73,797** | 72.1 KiB |
| (b) `ryoku/ui` | **542,810** | 530.1 KiB |
| (c) off-disk `ryoku/assets` **referenced above** — brand icon/emblem set | **440,167** | 429.9 KiB |
| ↳ whole `ryoku/assets/brand/` | 1,591,381 | 1.52 MiB |
| ↳ `ryoku/assets/wallpapers/` (seeded content) | 245,026,989 | 233.7 MiB |
| ↳ `ryoku/assets/ryodecors/` (seeded; not kept) | 4,165,851 | 3.97 MiB |

**Necessity verdicts for the kept surfaces** [READ]/[UNVERIFIED]:

- **Keep (mandatory)**: the four `Ryoku.*` QML modules (`Ui`, `Ui.Singletons`,
  `FrameBars`, `PluginKit`, `PluginKit.Singletons`) and `Ryoku.Blobs`; the system
  fonts `ttf-material-symbols-variable`, `ttf-jetbrains-mono-nerd`,
  `otf-space-grotesk` (or `inter-font`), `noto-fonts-cjk`; the Qt packages
  `qt6-base`, `qt6-declarative`, `qt6-5compat`, `qt6-svg` + `quickshell`.
- **Conditional**: `qt6-imageformats` (only WebP/AVIF previews), `qt6-multimedia`
  (only video wallpaper + Blobs `CameraFeed`), `ttf-fraunces-variable` (titles
  degrade gracefully), `inter-font`/`noto-fonts-emoji` (fallbacks).
- **Exclude / not needed by kept surfaces**: `ttf-maple-mono-nf` (terminal offer);
  the hub `art/` set and `archivo-black.ttf` (Credits/Fastfetch/Rashin pages, not
  kept); `ryoku/assets/ryodecors` (Profile/Rashin only); the 233 MiB wallpaper
  catalog (user content, opt in by seeding a smaller set); `Ryoku.Wm.Hyprland`
  (installed but not imported by the copied surfaces).
- **Blobs is load-bearing, not optional** [UNVERIFIED]: the bar `Frame.qml`
  (`import Ryoku.Blobs`) draws the screen frame with it; dropping `ryoku-blobs`
  breaks the frame. If Blobs were dropped, `Frame.qml`/`Popout.qml` imports and
  the `CameraOverlay` must be removed too.
- **`qt6-shadertools`** is build-time only; the committed `.qsb` files ship, so a
  package install needs no shader compilation. Building Blobs locally (§plugin)
  does require it.
