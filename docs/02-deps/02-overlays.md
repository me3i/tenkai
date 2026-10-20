# 02 — Launcher and control sidebar

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

## Launcher

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

### Files

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

### QML imports

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

### Singletons

Declared locally in `shared/Singletons/qmldir:1-12`:

- `Theme` (`Theme.qml`), `Config` (`Config.qml`), `LauncherConfig`
  (`LauncherConfig.qml:6`), `Scheme` (`Scheme.qml`), `Motion`, `Metrics`,
  `Frecency`, `Dispatcher`, `Weather`, `Players`, `Radio`, `Performance`.

Bound from the shell: `shell.services` singletons used by the launcher include
`Icons`, `Bluetooth`, `Perf`, `Media`, `Audio`, `Network`, and `ShellState`
(`services/qmldir:1-56`; referenced in providers and variant files). From
`Ryoku.Ui.Singletons`: `Tokens`, `Wm`, `I18n`, `Spawn`
(`ryoku/ui/Singletons/qmldir`).

### IPC verbs used

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

### Binaries shelled out

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

### Services / daemons

- `ryoku-shell` daemon (`ryoku/shell/ipc/`, Go `main`; socket
  `$XDG_RUNTIME_DIR/ryoku-shell.sock`) — reached only through the `Wm` singleton
  and through spawned `ryoku-shell <verb>` clients `[UNVERIFIED]` for daemon-side
  internals (off-disk beyond `ryoku/shell/ipc/`).
- `ryoku-app` (terminal launcher) and `ryoku-rashin` (AI ask) — helpers, off-disk
  `[UNVERIFIED]`; their PKGBUILDs exist at
  `release/packages/ryoku-rashin/PKGBUILD`.
- `AppLaunch`/`Icons`/`Perf`/`Media`/`Bluetooth`/`Audio`/`Network` singletons
  (shell.services).

### Qt modules

QtQuick, QtQuick.Layouts, QtQuick.Controls, QtQuick.Shapes, QtQuick.Effects,
QtQml.Models; Quickshell core + `.Io`, `.Wayland`, `.Widgets`,
`.Services.Mpris`, `.Bluetooth`.

### Fonts

Launcher text resolves through `shared/Singletons/Theme.qml:76-77`
(`Ui.Tokens.ui` = **Space Grotesk**, `Ui.Tokens.mono` = **SpaceMono Nerd Font**,
`ryoku/ui/Singletons/Tokens.qml:106-107`). The launcher's own config exposes a
`fontFamily` defaulting to **JetBrainsMono Nerd Font**
(`shared/Singletons/Config.qml:56,97`) — read from `shell.json`. Material
Symbols Rounded is used directly by the icon-font variants
(`variants/kairos/Main.qml:245,294`, `variants/okshell/Main.qml:258,305`).

### Assets

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

### Network calls

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

## Control sidebar (Super+Escape) / quick settings

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

### Files

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

### QML imports

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

### Singletons

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

### IPC verbs used

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

### Binaries shelled out

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

### Services / daemons

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

### Qt modules

QtQuick, QtQuick.Shapes, QtQuick.Effects, QtQuick.Dialogs, QtMultimedia,
Qt.labs.folderlistmodel; Quickshell core + `.Io`, `.Wayland`, `.Widgets`,
`.Bluetooth`, `.Networking`, `.Services.Mpris`, `.Services.Pipewire`,
`.Services.Notifications`, `.Services.UPower`; C++ QML module **Ryoku.Blobs**
(`popouts/Popout.qml:4`, `Frame.qml:6`) `[UNVERIFIED]` (built from
`ryoku/shell/plugin`, not in the sparse checkout).

### Fonts

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

### Assets

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

### Network calls

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

## Necessity / exclusions

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
