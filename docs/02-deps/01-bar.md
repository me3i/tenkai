# 01 — Top bar (qsbar) and its widgets

Phase-2 dependency map of the Ryoku top bar in bar style `qsbar` and the bar
widgets on the Mei keep list: workspaces, clock/date, audio indicator,
brightness, network, battery, system tray, notifications indicator.

Scope of evidence: read-only trace of the pinned upstream checkout at
`/home/mei/projects/mei/upstream` (Ryoku v0.75.5-beta.20, commit 98a0368).
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

## Files

### Style selection / configuration
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

### Bar/frame core — `ryoku/shell/quickshell/shell/modules/bar/`
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

### qsbar style — `…/modules/bar/barstyles/qsbar/`
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

### Keep-list widget components — `…/qsbar/modules/`
- `WorkspaceWidget.qml` (608), `ClockWidget.qml` (63), `AudioWidget.qml` (92),
  `AudioData.qml` (31), `BrightnessWidget.qml` (174), `NetworkWidget.qml` (277),
  `BatteryWidget.qml` (202), `TrayWidget.qml` (130), `NotificationWidget.qml` (61),
  `NotificationSilenceWidget.qml` (45). `[READ]`
- Shared primitives the keep-list uses: `UiText.qml` (12), `IconText.qml` (14),
  `TooltipMixin.qml` (31), `PacmanMarker.qml` (workspace "pacman" style), plus
  `ReactorLayer.qml`/`ParticleStream.qml`/`StreamShader.qml` for the gap animation
  (part of the bar surface, motion keep-list). `[READ]`

### Services the keep-list binds to — `…/shell/services/`
- `Tray.qml`, `Network.qml`, `Notifs.qml`, `Icons.qml`, `Config.qml`; plus the
  notification server inside `…/qsbar/panels/NotificationPanel.qml`. `Audio.qml`
  and `Battery.qml` exist but are **not** used by the bar widgets (see below). `[READ]`
- `ryoku/ui/Singletons/Wm.qml` — the `Wm` singleton the workspace widget reads
  (module `Ryoku.Ui.Singletons`, `qmldir` `singleton Wm Wm.qml`). `[READ]`

Note: everything above is on disk in the sparse checkout. No off-disk
`git show` was required; the few assets with no in-tree reference are noted under
**Assets**.

---

## QML imports

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

## Singletons

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

## IPC verbs used

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

## Binaries shelled out

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

## Services / daemons

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

## Qt modules

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

## Fonts

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

## Assets

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

## Network calls

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

## Necessity / exclusions

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
