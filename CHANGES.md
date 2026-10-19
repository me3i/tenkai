# CHANGES.md — modifications vs upstream Ryoku

Pinned upstream: see `UPSTREAM.md`. Mei is built by copying and adapting upstream files into
`src/`; every modification is recorded here, newest first.

## Phase 6 — step 6: notifications (one server, DND, actions)

Exactly one `NotificationServer` in the shell. The qsbar flyout stopped being a second one: it
raced the kept server for `org.freedesktop.Notifications` and wrote a private
`~/.cache/qs-rise-notifications.json` outside the project.

### What changed

| File | Change |
|---|---|
| `src/ryoku/shell/quickshell/shell/services/Notifs.qml` | unchanged; it remains the only `NotificationServer` (`Notifs.qml:230`) |
| `.../barstyles/qsbar/panels/NotificationPanel.qml` | rewritten as a view over `Services.Notifs.history`: no server, no cache, no live map (`+17 / -139`) |
| `.../barstyles/qsbar/VariantRoot.qml` | qsbar IPC for tests/keybinds: `notifications(open)`, `dnd(on)`, `notifDismissLatest()`, `notifClearAll()`, `notifInvoke(id,key)`, `notifState()` |
| `mei` (test template) | the session writes `$DBUS_SESSION_BUS_ADDRESS` to `.run/bus`, so a harness reaches the nested bus without guessing its path |

`notifInvoke` exists because Quickshell's server does not implement D-Bus `InvokeAction`: actions
are invoked in-process (`action.invoke()`), the only path by which an `ActionInvoked` leaves the
process. `notify-send -A` implies `--wait` and blocks, so the harness backgrounds the sender and
then invokes.

`Notifs.dnd` is bound from `Flags.dnd` in `shell.qml:634`; the persisted `flags.json` (fake HOME)
is the single DND state, so the IPC toggle and the UI toggle agree.

`clearAll()` leaves `expire_timeout 0` popups on screen, matching upstream `dismiss_all`. The
harness asserts that as a contract.

### Verification

Two consecutive clean runs on the committed tree: `.run/logs/step6-050659.log` and
`step6-050728.log`, both `RESULT: PASS`, 39 `TESTED`, 0 `FAIL`.

| Test | Result |
|---|---|
| one server | TESTED: `grep -rn NotificationServer src/` -> `services/Notifs.qml:230` only |
| cache writer removed | TESTED: no `qs-rise-notifications.json` anywhere under the fake HOME |
| nested bus owner | TESTED: Mei shell pid owns `org.freedesktop.Notifications` on the private bus |
| live bus untouched | TESTED: live owner still pid 949 before and after (`docs/baseline/dbus-watched.tsv`) |
| capabilities | TESTED: `body`, `actions`, `icon-static` |
| popup / urgency x3 / long body | TESTED arrive; appearance UNVERIFIED |
| flyout, dismiss, clear | TESTED: 4 -> 3 on dismiss; clear emptied history and closed popups |
| DND on/off | TESTED: popups stay 0 while on, history still records; popup returns when off |
| `-t 0` | TESTED: still on screen after 6 s, stays out of history |
| actions | TESTED: sender saw `ActionInvoked 'later'` (exit 0, output `8 later`) |
| icon | TESTED sent (`icon-static`, 1523 B); rendering UNVERIFIED |
| outbound | TESTED: both shell pids own no tcp/udp socket |
| shutdown | TESTED: clean stop, no strays; verify-untouched PASS at both ends |

Screenshots: `.run/shots/step6-03-normal-popup.png` through `step6-12-actions.png`.

Owner-only (UNVERIFIED): popup motion, card look, icon rendering, palette taste, 144 Hz.

## Phase 6 — step 5 fixes (owner review): HOME guard, wallpaper wrapper, name scan, weather off

Committed separately before notifications, as requested. Two consecutive clean harness runs:
`.run/logs/step5-041051.log` and `.run/logs/step5-041136.log`, both `RESULT: PASS`, zero `FAIL`
lines, verify-untouched PASS at both ends.

### a. HOME guard in every state-writing binary

`homeGuard()` is the first statement of `main()` in all four binaries: `mei-shell`
(`src/ryoku/shell/ipc/main.go`), `ryogami` (`src/ryoku/shell/ryogami/daemon/main.go`), `mei-hub`
(`src/ryoku/hub/backend/main.go`) and `mei-hub`'s sibling provider `mei-wm-hyprland`
(`src/ryoku/wm/hyprland/main.go`). It derives the allowed home from the executable path
(`<project>/.run/bin/<binary>` -> `<project>/.run/home`), so a binary copied anywhere else fails
closed; `HOME` unset also fails. It applies to client verbs too (`ryogami wallpaper`, `mei-hub
config get`), because a client with the real HOME resolves the real cache dir — the precise shape
of the step-5 incident.

Same guard shape in four files rather than a shared package: the four live in three separate Go
modules and a shared internal package would add a fourth import path for ~20 lines. Revisit only
if a fifth consumer appears.

### b. `./mei wallpaper <path|next|prev|random>`

New subcommand in `mei`; pins `HOME`, `MEI_HOME`, `XDG_CONFIG_HOME`, `XDG_CACHE_HOME`,
`XDG_STATE_HOME`, `XDG_DATA_HOME` and `XDG_RUNTIME_DIR` to the nested values, resolves the path
with `realpath`, requires the session (`$PID_FILE` + `.r/ryogami.sock`) and calls the ryogami CLI.
The harness now changes both wallpapers through it, so it is exercised on every run.

### c. verify-untouched: new entries since baseline

`docs/baseline/new-name-watch.txt` records the paths under `~/.cache`, `~/.local/state`,
`~/.local/share` and `~/.config` (depth 3) whose *path segment* starts with `mei`, `ryoku` or
`ryogami`; `verify-untouched` re-scans, diffs, prints additions and fails on any. Removals are
INFO (cleanup is allowed).

Deviation from the literal instruction, with evidence: a bare substring match is unusable on this
host — it flags `~/.config/google-chrome/MEIPreload` (Chrome DRM), `~/.cache/fish/namei.fish`,
`~/.local/share/Steam/friends/GameInviteNotification.res` and
`~/.local/share/applications/mimeinfo.cache`. Verified that the anchored rule still catches both
real incident paths (`~/.cache/ryogami`, `~/.local/state/mei-wallpaper`), and that creating
`~/.cache/ryogami` flips the check to FAIL and removing it flips it back to PASS.

### d. Re-run with the `Frame.qml` edit

Honest count: the two clean runs before this commit were made **before** the `Frame.qml` edit, so
the committed step-5 state had zero clean runs. Now it has two.

### e. Weather tiles hidden (disabled, not deleted)

- `bar/framebars/menus/MenuWeather.qml`: `visible: false` at the root, so the clock menu, the
  (unreachable) quick-settings weather page and the weather frame widget collapse together.
- `bar/barstyles/qsbar/panels/DashboardPopup.qml`: `weatherUi: false` gates the three weather
  islands (`heroTile`, `metricsTile`, `graphTile`). The clock island remains; the right column
  below it is now empty by design.
- The bar's own `WeatherWidget` was already zero-width since step 4, so the bar is unchanged.

## Phase 6 — step 5: wallpaper + matugen theming

Scope: ryogami stills-only, the wallpaper -> palette path, Mei's minimal matugen config, and
removal of every app-theming fan-out. Verified: `.run/tools/step5.sh` ->
`.run/logs/step5-025738.log` (PASS) and the final run (PASS with the wallpaper/launcher
assertions). Screenshots in `.run/shots/step5-*.png`.

### Copied / not copied

- `src/ryoku/shell/ryogami/daemon/` copied from `upstream/ryoku/shell/ryogami/daemon`
  (536 KB, vendor included) and built to `.run/bin/ryogami`.
- **`ryogami/wall-ui/` is NOT copied** (114 files). The picker shell brings Wallhaven/Steam
  browser services (outbound) and upstream's `pkill -f "quickshell .*<qml>"` launch path; it
  needs its own pruned step. Its `ui` verb is refused instead (below).

### Stills only (video + depth off)

- `config.go` `wallPrefs()`: `Enabled: false` hard-coded; `shell.wallpaper.video_enabled` is no
  longer read. `apply.go` `applyWallpaper()` refuses any non-`static` type before doing work.
- `verbs.go` `depthVerb()` refuses `depth set` / `depth clear`. The shell's stage/depth worker
  only cuts for a stage effect, and Mei enables none.
- `process.go` `launch()`: upstream's `pkill -f "quickshell .*"+qml` removed (Mei never kills by
  name).

### Display guard (refuses the live session)

- `daemon.go` `guardDisplay()`, called at the top of `runDaemon()`: requires
  `MEI_HOST_WAYLAND_SOCKET` (handed in by `./mei run` as the host's resolved socket) plus
  `XDG_RUNTIME_DIR` and `WAYLAND_DISPLAY`; refuses when
  `$XDG_RUNTIME_DIR/$WAYLAND_DISPLAY` equals the live socket, and fails closed when the host
  value is unset. Logged on success: `ryogami: display guard ok (<nested> != live <host>)`.

### Renames

- `~/.config/ryoku` -> `~/.config/mei` (`meiConfigDir()`, `config.go`, `transitions.go`);
  `ryoku-shell.sock` -> `mei-shell.sock` (`daynight.go`);
  `~/.local/state/ryoku-wallpaper[.json]` -> `mei-wallpaper[.json]` (`apply.go`).
  The `ryogami` name and `RYOGAMI_*` variables stay (not `ryoku*`).

### The wallpaper actually paints now

- `shell.qml`: `Desktop.active` false -> **true** (kept `widgetsEnabled: false`). The wallpaper
  painter and reveal shader (`WallpaperMod.Backdrop`) live *inside* the Desktop surface, so
  step 1's `active: false` left the screen showing Hyprland's built-in wallpaper. Every tile,
  the glass backdrop and the plugin repeater stay gated on `widgetsEnabled`, so no widget
  layer is enabled.

### The palette follows the wallpaper

- `ipc/daemon.go` `bootstrap()`: added `go d.watchRyogami()`. It was never started, so a
  wallpaper change never rescheduled the palette pass (found in this step; the daemon had been
  generating a palette only when `matugen.json` changed).

### matugen: minimal config, no app fan-out

- `src/ryoku/shell/matugen/config.toml` is now `[config]` + an **empty `[templates]`**.
  matugen 4.2.0 rejects a file containing only `[config]` (`TOML parse error ... missing field
  templates`), verified by running it directly; the empty table renders nothing. `./mei run`
  seeds it to `$XDG_CONFIG_HOME/mei/matugen/config.toml`.
- `matugenTemplateDir()` -> `$XDG_CONFIG_HOME/mei/matugen`; the render pass uses that path
  directly (no filtered cache copy). Both invocations are logged:
  `matugen scheme: matugen image …` and
  `matugen render: matugen -c <config> json <carrier>`.
- Disabled: the `apps.toml` render (22 app templates), `blankGtk()`, the cursor-recolor
  goroutine (`ryoku-cursor-material-recolor` + `ActionCursorReassert`), and every part of
  `matugenReload()` except `nudgePalette()` (no gsettings/libadwaita accent, no gtk-theme
  flip, no `pkill -USR1 kitty`, no KDE colours). Upstream bodies are kept commented in place.
- `matugenEnsureDirs()` trimmed from 24 app directories to `cache/mei` + `cache/matugen`.
- `src/ryoku/shell/matugen/{apps.toml,templates/}` remain but are unreferenced.

### Palette bridge off

- `hub/backend/palettebridge.go` `runPaletteBridge()` refuses every verb, including `status`,
  so the hub can never install, enable or restart `ryoku-palette-bridge.service` against the
  real user manager. Nothing listens on 127.0.0.1:47616, and neither binary contains the port
  string.

### Picker entry points (no dead controls)

- `bar/Frame.qml`: the `"wallpaper"` surface request is dropped (it called
  `ryogami wallpaper ui`). `launcher/.../actions/catalog.js` still names that verb, but the
  Actions provider is disabled (step 2 decision), so it cannot fire.

### Confinement

- The generated `.run/session.sh` sets `XDG_CACHE_HOME=$HOME/.cache` (the fake HOME), so the
  palette lands at `$HOME/.cache/mei/{colors,tones}.json` exactly as specified, and starts
  ryogami with the guard environment, recording its pid; `./mei stop` terminates the session
  process group.

### Test assets

- `.run/wall/{wall-1-warm.jpg,wall-2-green.png,wall-3-purple.jpg}` — 228 KB total, copied
  read-only from `~/Pictures/Wallpapers` (never written back). `prepare_nested_home()`
  symlinks `~/Pictures/Wallpapers` into the fake HOME read-only.

## Phase 6 — step 4 amendments (owner decisions 2026-10-20)

Three follow-ups the owner asked for before approving step 5. Verified with
`.run/tools/step4b.sh` → `.run/logs/step4b-022341.log` (PASS) and the screenshot
`.run/shots/step4b-hub-generic-general.png`, `.run/shots/step4b2-launcher-open.png`.

### 1. The daemon can no longer reach the network (compiled out)

Weather, music and calendar are off the keep list and "zero outbound connections" is a stated
goal, so the HTTP client is **removed from the daemon**, not merely left dormant:

- `src/ryoku/shell/ipc/weather.go`: dropped `net/http` + the `http.Client`; `getJSON` is a stub
  that returns `wxErrNetwork` ("mei: outbound network disabled"). Every weather poll lands on its
  existing error path.
- `src/ryoku/shell/ipc/music.go`: dropped `net/http` + the `http.Client`; `cacheArt` returns a
  cached cover if one exists (never fetches) and `getJSON` (lyrics/canvas) is a stub.
- `src/ryoku/shell/ipc/calendar.go`: dropped `net/http` + the `http.Client`; the holiday-service
  fetch is compiled out (a cached year is still served, even stale; with no cache the year is
  unavailable). The dead `calendarAPI`/`baseURL` were removed too.
- Proven: `go list -deps` on the daemon does **not** contain `net/http` (only `net`, for unix
  sockets); `grep` finds no `http.Client` outside comments; at runtime neither the daemon, the
  shell nor the hub owned a tcp/udp socket (`ss -tunp`, three pids). Inert URL *strings* remain in
  the binary (they are data inside the now-unreachable resolvers), but no transport is linked.

### 2. "CHANGE ON MAP" hidden

`src/ryoku/hub/quickshell/SettingsSheet.qml`: the timezone row's `CHANGE ON MAP` button is
`visible: false` (it did nothing; the timezone is display-only). Kept in place, not deleted.

### 3. The launcher's weather widget is off (it was already offline)

The launcher's own `Weather` singleton was hard-disabled in step 2 (`online: false`; fetch,
locate and cache-replay all return early; the refresh `Timer` is off), so it made **no calls**;
it was rendering a date-only readout. Now the dead UI is gone as well:

- `launcher/variants/main/Preview.qml`: `showWeather` forced `false` (it was drawing a hardcoded
  "21°C / Clear sky" placeholder in the Settings preview).
- `launcher/variants/hero/Preview.qml`: both weather blocks `visible: false`.
- `hub/quickshell/pages/LauncherPage.qml`: the "Show weather" and "Weather units" rows are
  commented out (they controlled a widget that can no longer appear).
- `hub/quickshell/pages/GlobalPage.qml`: the General page drops the `weatherLocation` and
  `weatherUnit` rows (the former claimed "empty reads it from your IP" and did nothing).
- `bar/barstyles/qsbar/modules/WeatherWidget.qml`: `implicitWidth: 0`, so the bar's G8 island
  reserves no space for the data-less weather slot (the wrapper's `visible: width > 0.5` hides it).

**Still data-less and reported, not changed:** the bar's dashboard popup (`DashboardPopup.qml`)
and the clock menu's `MenuWeather` still have weather tiles. They were already empty before this
change (the daemon never started the weather topic); hiding them means a bento/column layout
change, so it is left for the owner to call.

## Phase 6 — step 4: Settings app (`mei-hub`)

Manifest scope (`docs/04-plan.md` 6.4): the Ryoku Settings app, copied to `src/ryoku/hub` and
kept as **five pages only** — General, Appearance, Bar, Launcher, Motion. It persists to
`$XDG_CONFIG_HOME/mei` and **cannot write Hyprland config**. Everything else is **disabled, not
deleted** (original blocks are kept commented in place).

### Pages and rail

- `quickshell/Hub.qml`: `groups` reduced to
  `GENERAL:[global]` + `DESKTOP:[desktop(Appearance), bar-studio(Bar), launcher(Launcher),
  animations(Motion)]`; the original catalogue is kept as a commented block and the line above
  records how to restore it. Default `section` changed `"windowmanager"` → `"global"` (the old
  default was a disabled page). The masthead `UPDATES` chip is `visible:false` (Updates page off
  list); `FILES` stays (it only lists paths). `sectionAvailable()` now returns false for any
  section not in the active rail, which also stops a persisted `hub.toml` section (e.g.
  `displays`) resurrecting a disabled page.
- Page titles aligned with the rail: `GlobalPage` "Global/GLOBAL" → "General/GENERAL",
  `DesktopPage` "Desktop/DESKTOP" → "Appearance/APPEARANCE", `BarStudioPage` "Bar Studio" → "Bar",
  `LauncherPage` "App Launcher" → "Launcher", `AnimationsPage` "Animations" → "Motion" (and its
  blurb no longer points at the disabled "Advanced" section).
- Rebrand: "Mei Settings" window title, `M` mark / "Mei" name, `mei-hub` binary/config verbs,
  `mei-shell.sock`, `~/.config|.cache|.state/mei` paths, lock `$XDG_RUNTIME_DIR/mei-hub.lock`.
  `Ryoku.*` QML URIs, D-Bus names, font names and the Go module names are intentionally unchanged.

### Hyprland writer severed (owner requirement: Settings never writes Hyprland config)

- `Hub.qml`: `hyprGet`/`hyprDefaultsGet` are pinned `running:false`; `requestReloadCoverPrune` is a
  no-op; the `requestQuit` reload-cover prune is commented out.
- `backend/desktop.go`: `runDesktop` refuses `save|preview|restore|set-rebind` with the new
  `errWMWriteDisabled`; `applyDesktop()`/`reloadDesktop()` in `Hub.qml` are no-ops.
- `backend/schemes.go`: the `pkill -USR1 kitty` recolour is commented out.
- No `settings.lua`, `rebinds.lua` or `user_edits/` is produced anywhere (verified by `find` over
  the whole fake HOME and the fake config dir).

### Motion page (kept, must drive real animation)

- `MOTION` (Hyprland window editor) and `FOCUS FLASH` cards are `visible:false`; `animPresetGet`
  is pinned off. The **SHELL MOTION** card is kept: `theme.motion.scale` (Speed) and
  `theme.motion.reduce`, which `src/ryoku/ui/Singletons/Tokens.qml` reads for every `dur()`.
- Those two keys are written live via `Settings.patch`, so they are outside the hub's
  draft/save ledger. `Hub.qml:resetDefaults()` now also calls `Settings.reset("theme.motion")`,
  otherwise RESET TO DEFAULTS left the shell's motion changed.

### Off-list things disabled in the kept pages

- `pages/BarStudioPage.qml`: the **BAR STYLE** card (`styleSect`, `visible:false`) is fed by
  RyoStore's `barstyles` catalogue. Its `ryostore catalog` process is pinned `running:false` and
  `browseBarStyles()` no longer shells out to `ryostore`.
- `quickshell/SettingsSheet.qml`: the weather-city search called
  `curl https://geocoding-api.open-meteo.com/...`; the debounce no longer issues that request.
  (Weather is not on the keep list; the field/popup stays but does not go online.)
- `pages/DesktopPage.qml` already hides the Clipboard tab and the boot `reloadCover` row
  (both off list). `GlobalPage`'s timezone picker and shell restart were already made
  display-only/no-op in this step.

### Rename misses fixed in kept shell surfaces

- `shell/services/Icons.qml`: the tray/app icon index ran `$MEI_SHELL_DIR/ipc/ryoku-shell`, which
  never exists now (the daemon is built to Mei's bin dir) and failed on every start; it now
  resolves `mei-shell` by name, so the icon index actually loads.
- `shell/modules/bar/barstyles/qsbar/Theme.qml`: Wi-Fi/Bluetooth launch
  `ryoku-shell hub open connections` → `mei-shell ...`.
- `shell/services/Capture.qml`: `ryoku-shell clip-copy` / `ryoku-shell sound shutter` →
  `mei-shell ...`.

## Phase 6 — step 3: control sidebar / quick settings

Manifest scope (`docs/04-plan.md` 6.3): the `SUPER+ESCAPE` quick-settings sidebar
(`modules/bar/framebars/menus/MenuQuickSettings.qml` + `quicksettings/`) and the qsbar control
centre (`barstyles/qsbar/controlcenter/`). Kept sections: clock/date, battery, audio,
brightness, **read-only** network. Everything else is **disabled, not deleted**; opt back in by
uncommenting the marked block.

### Quick-settings surface

- `shell/framebars/MenuCatalog.js`: `quickSettingsModules` keeps only `home`; `notifications`,
  `weather`, `capture`, `media`, `stage` are commented out. `quickSettingsDefaults` →
  `["home"]`. A persisted `shell.json` listing the old modules normalises back to `home`
  (`FrameBars.quickSettingsModulesFor`), so no runtime config edit is needed. The module QML
  files stay on disk.
- `.../menus/quicksettings/QuickSettingsHome.qml`:
  - Power actions routed through the `SessionActions` singleton instead of spawning directly:
    lock (`Mei.lock()`), reboot/shutdown (daemon, stub-able). The old direct
    `Quickshell.execDetached(["mei-shell","lock"])` / `["systemctl","reboot"|"poweroff"]` are gone.
  - The `QS Bar Settings ↔ Quick Settings` surface-segment switch is commented out (it retargets
    the bar logo at a panel outside this step's scope).
  - Section `"Connect"` → `"Network"`. The Wi-Fi `QsTile` is now a **read-only status** tile: its
    `onToggled`/`hasPage`/`onPageRequested` were removed, so the Wi-Fi detail page (which
    toggles) is unreachable. Wi-Fi/Bluetooth/VPN are never toggled anywhere in this surface.
  - Bluetooth, Airplane, Night light, Keep awake, Do not disturb and Gaming tiles are commented
    out (a QML `Grid` still lays out invisible children, so `visible:false` alone would reserve
    their 64px rows and push the audio section off-panel).
  - Media hero, calendar month grid and the system monitor are commented out.
  - The power-profile segment is commented out; the empty `powerDock` column stays so the
    Flickable above still anchors to `powerDock.top`.
- `.../menus/QsTabRail.qml`: the Lens / OCR / QR / colour-picker rail buttons are commented out —
  they spawn `ryoku-cmd-*` helpers Mei does not build (dead buttons). "Mei Settings" stays and now
  spawns `mei-shell hub open`.

### Test-mode power stub (host safety)

- `shell/quickshell/shell/services/SessionActions.qml`: new
  `testMode: Quickshell.env("MEI_TEST") === "1"`. `run(action)` and the new `lock()` log
  `[mei-stub] suppressed …` and return without spawning anything when `MEI_TEST=1`.
- `shell/ipc/session.go`: `testStubbed()` guard in `runSessionAction` and in the `session.logout`
  closure — the daemon refuses to exec `systemctl`/`wm.ActionSessionExit` when `MEI_TEST=1`.
- `mei` (control script): the generated `session.sh` exports `export MEI_TEST=1` (nested tests
  only; a real run does not set it). The nested config adds
  `bind = SUPER, ESCAPE, global, ryoku:quicksettings`. (The writer keeps an existing
  `nested.conf`; it was regenerated so the new bind lands.)

### Kanji → English (CJK face not installed)

Glyphs replaced 1:1, same `font.family`/`pixelSize`/layout (fontconfig falls back to a Latin
face). No CJK glyph is rendered anywhere in the kept surfaces.

- `.../controlcenter/kit/Routes.js`: route glosses 帶/印/配置/部品/台/有志 →
  `BAR`/`SEAL`/`LAYOUT`/`PARTS`/`DOCK`/`PEERS`; header comment updated.
- `.../controlcenter/routes/*.qml`: per-card `kana` seals → English (`POSITION`, `MOTION`,
  `FORM`, `SURFACE`, `GAPS`, `HUE`, `IMPORT`, `ADD`, `BEHAVIOUR`, `PINNED`, `MARK`, `TEXT`,
  `NUMBERS`, `DOTS`, `SAMPLE`, `PARTS`; `LayoutRoute` 引入 → `IMPORT`).
- `.../controlcenter/kit/CcWorkspacePreview.qml`: workspace numerals 一二三四五 → `1..5`.
- `src/ryoku/ui/Empty.qml`: the 空 ornament → `M` (brand mark); comment updated.

### Binary rebrand completion

Quoted executable literals `"ryoku-shell"` → `"mei-shell"` across the shell QML
(`StageBackend`, `QsTabRail`, `RailStatus`, `LayoutWidget`, `PanelChat`, `WidgetMenu`, `Icons`).
These would otherwise be dead (`ryoku-shell` was renamed to `mei-shell` and no symlink exists).
`MenuQuickActions.qml` power actions were also routed through `SessionActions`
(`Frame.qml` lock likewise), so **every** reachable power action passes the test stub.

Verification (nested; two consecutive clean runs, `.run/logs/qs-iter{3,4}.log`): sidebar opens on
`ryoku:quicksettings` and closes; shows exactly clock/date, battery, audio out/in, brightness
reading 23%, and a read-only Wi-Fi tile (real SSID); control centre opens via
`qs ipc call qsbar settings bars` with English glosses; one shell instance; no tcp/udp sockets;
no PipeWire connection (real audio untouched); brightness step 23%→28%→restored (trap); no QML
errors; `verify-untouched` PASS before and after. Details in `docs/loop-log.md`.

## Phase 6 — step 2: launcher (app search only)

Manifest scope (`docs/04-plan.md` A11): `modules/launcher/shared` + `variants/main`. The
launcher opens on the compositor global shortcut `ryoku:launcher` (bound to `SUPER+SPACE` in
the nested test config), searches real XDG `.desktop` entries and launches them. Network and
off-list providers are **disabled, not deleted**.

- `.../launcher/catalog.json`: `default`/`fallback` `hero`/`okshell` → `main`; only the `main`
  variant entry remains. The `hero`/`kairos`/`okshell` files stay on disk but are never loaded
  (physical prune deferred).
- `.../launcher/shared/providers/Providers.qml`: instantiates `Apps` only. Removed
  imports/instances for `Actions`, `Web`, `Radio`, `Packages`, `Script`, `Snippets`, `Find`,
  `Calc`, `Mpris`, `Recent`, `Windows` and their aliases. The `/` command mode is disabled with
  the Actions provider (owner decision): `variants/main/Launcher.qml` pins `actionMode: false`,
  its `providerSet.actions` category `Binding` is commented out, and `SearchRow.qml`'s hint is
  now "Search apps". The provider files remain on disk.
- `.../launcher/variants/main/SearchRow.qml`: placeholder "Search apps, type / for commands" →
  "Search apps" (the command mode is off).
- `.../launcher/shared/Singletons/LauncherConfig.qml`: default `variant` `hero` → `main`;
  `showWeather` default `true` → `false`.
- `.../launcher/shared/Singletons/Weather.qml`: added `readonly property bool online: false`;
  `fetchWeather()`/`loadLoc()` return early; `Component.onCompleted` no longer replays the
  cache or starts the IP lookup; the refresh `Timer` runs only when `online`. No Open-Meteo /
  ip-api request is ever made; the dashboard keeps its date-only readout.
- `.../launcher/shared/Singletons/Radio.qml`: added `readonly property bool enabled: false`;
  `refresh()` returns early, so the `ryoku-cmd-radio status` probe is never spawned. The
  singleton stays because `variants/main/{Launcher,NowPlaying,RadioAside}.qml` bind its state.
- `.../launcher/variants/main/Launcher.qml`: `askMode` hard `false` (the `\` RASHIN AI panel is
  off-list; it would open `http://127.0.0.1:3600`).
- `mei` (control script): `session.sh` exports a read-only `XDG_DATA_DIRS` pointing at the
  owner's real `~/.local/share` (+ flatpak export) and the system dirs, so the launcher lists
  the same `.desktop` files as the live session; writes still go to the fake `XDG_DATA_HOME`.
  The nested config gains `bind = SUPER, SPACE, global, ryoku:launcher`.
- Test harness only (git-ignored, `.run/tools/`): `vkbd` (a `zwp_virtual_keyboard_v1` client)
  and `launcher-check.sh`, so real keystrokes drive the launcher search field in the nested
  session.

Verification (nested; two consecutive clean runs, `.run/logs/launcher-iter{1,2}.log`): opens on
the bound shortcut; lists real system **and** user `.desktop` apps; launches `kitty` inside the
nested session (fake HOME, `.r` runtime, nested Wayland); frecency under `.run/state/mei/`; Esc
closes; one shell instance; no tcp/udp sockets; no radio probe; no QML errors;
`verify-untouched` PASS before and after. Details in `docs/loop-log.md`.

## Phase 6 — rebrand (RYOKU → MEI, user-visible only)

Scope: visible branding in kept surfaces; QML module URIs (`Ryoku.*`), D-Bus
names, env prefixes, and `ryogami` stay as-is. Attribution kept/added.

### Wordmark (bar left module)

- `src/ryoku/shell/quickshell/shell/modules/bar/barstyles/qsbar/Theme.qml`
  - `launcherLogoText` default `"ryoku"` → `"mei"`; `launcherLogoIcon` default
    `"ryoku"` → `"mei"`.
  - text options: `"ryoku"` removed, `"mei"` added first.
  - icon options: `"mei"` added; `"ryoku"` kept as a backward-compatible id.
  - icon glyph map: `"ryoku": 0x529B` (CJK 力) → `"mei"/"ryoku": 0xEE99`
    (Nerd Font "mark" seal). `launcherLogoIconFont()` now always returns the
    mono font, so **no surface needs `noto-fonts-cjk`**.
  - font/size/weight/spacing of the wordmark unchanged: `mono` (JetBrains Mono
    Nerd Font), 12 px, Bold, letter-spacing 2. `MEI` is simply the uppercase of
    the id, via the existing `launcherLogoTextLabel()`.
- `.../qsbar/modules/LauncherWidget.qml`: comment only (Mei brand mark).

### The 力 seal → plain `M`

- `.../overview/Singletons/Config.qml`, `.../desktop/Singletons/Config.qml`,
  `.../services/Config.qml`: `markText` default `"力"` → `"M"`; `name`
  `"Ryoku"` → `"Mei"`.
- `.../overview/Singletons/Theme.qml`, `.../desktop/Singletons/Theme.qml`,
  `.../services/Theme.qml`: mark fallback `"\u529b"` → `"M"`; brand-name
  fallback `"Ryoku"` → `"Mei"`.
- `.../overview/BrandMark.qml`, `.../desktop/BrandMark.qml`,
  `.../components/BrandMark.qml`: glyph font `Theme.fontJp` → `Theme.mono`.
- `.../launcher/variants/main/BrandMark.qml`, `.../launcher/variants/main/Preview.qml`:
  hard-coded `"力"` → `"M"`.
- `.../qsbar/controlcenter/CcRail.qml`: masthead `"\u529b"` → `"M"`,
  font `Tokens.jp` → `Tokens.mono`; wordmark and barcode `"RYOKU"` → `"MEI"`.
  (Route *glosses* in the same file still use CJK kanji; that is step-3 scope,
  not the wordmark/seal.)

### Other visible strings in kept surfaces

- `shell.qml`: keybind description "Toggle the Ryoku frame bar…" → "Mei".
- `.../framebars/menus/QsTabRail.qml`: tooltip "Ryoku Hub" → "Mei Settings".
- `.../qsbar/modules/UpdateWidget.qml`: "Ryoku is up to date" / "Ryoku update"
  → "Mei …" (widget is off-list but visible if enabled).
- `.../qsbar/modules/ParticleStream.qml`: update particle "RYOKU" → "MEI".
- `.../controlcenter/routes/IdentityRoute.qml`: wordmark preview `"RYOKU"` →
  `"MEI"`; icon preview `"\u529b"` → `"M"`.
- `.../controlcenter/ControlCenter.qml`: "outside Ryoku" → "outside Mei".
- `.../controlcenter/routes/CommunityRoute.qml`: "Ryoku does not review" →
  "Mei does not review".
- `.../launcher/catalog.json`: description → "Mei's live palette".
- `.../launcher/shared/providers/actions/catalog.js`: "Ryoku Settings" →
  "Mei Settings".
- `.../bar/panel/PanelChat.qml`: "the Ryoku source" → "the Mei source".

Runtime brand file `.run/config/mei/brand.json` (git-ignored) patched to
`{"markText":"M","name":"Mei"}` so the fake-home run agrees with the new
defaults; it regenerates from source anyway.

### Attribution (added, not removed)

- Copied `upstream/LICENSE` → `LICENSE` and `upstream/NOTICE` → `NOTICE`
  (verbatim; the clone itself is git-ignored, so these were not previously in
  the repository).
- Added `CREDITS.md`: Mei is a modified derivative of Ryoku under
  GPL-3.0-or-later; QS Bar (Quickshell Rise) credit; font licences.
- `UPSTREAM.md` retained; the QS Bar credit comment in
  `qsbar/Scene.qml:1` retained.

## Phase 6 step 1 — bar + workspaces (code + build + nested test)

Deliverable: `docs/06-step1.md`. Stop point: launcher/sidebar/notifications/Settings not started.

### Copied into `src/` (upstream = `98a0368`, v0.75.5-beta.20)

- `ryoku/shell/quickshell/{shell,plugins}` → `src/ryoku/shell/quickshell/{shell,plugins}`
- `ryoku/ui` → `src/ryoku/ui`; `ryoku/shell/framebars` → `src/ryoku/shell/framebars`
- `ryoku/wm` → `src/ryoku/wm`; `ryoku/shell/{ipc,plugin,matugen}` → `src/ryoku/shell/…`
- Upstream `tests/`, `qa/`, CI files stripped. Vendored Go deps kept so builds are offline.

### Source modifications

- `src/ryoku/wm/hyprland/caps.go`: removed `CapLiveConfigEval`, `CapConfigReload`,
  `CapPaletteBorder` (Mei never writes Hyprland config).
- `src/ryoku/shell/ipc/daemon.go`: `bootstrap()` reduced to `startSettings`, `startTray`,
  `startMusic`, `startNetwork`, `startNightlight`, `paintWorker`, `watchMatugenKnobs`, `startWM`,
  `startComponents`. Removed weather/updates/calendar, keypress, clipboard, polkit, session,
  power sounds, sleep/wake, auto power saver, leds/hub, ryogami, stage.
- `src/ryoku/shell/ipc/control.go`: hub lock moved from `/tmp/ryoku-hub.lock` to
  `$XDG_RUNTIME_DIR/mei-hub.lock`.
- `src/ryoku/wm/hyprland/watch.go`: if `.socket2.sock` is missing, poll `hyprctl` every 500 ms
  (`socketExists`, `pollOnce`). Only reachable in the nested test (see below); the live session
  keeps the event-driven path.
- `src/ryoku/shell/quickshell/shell/shell.qml`: `Desktop` → `active: false`,
  `widgetsEnabled: false` (desktop clock/calendar is off-list).
- `src/ryoku/shell/matugen/config.toml`: reduced to `[config]` — no templates, no post-hook, so
  matugen cannot write into the owner's home.
- Renames (source-wide): `RYOKU_*` → `MEI_*` (SHELL_DIR/PATH/POLKIT_AGENT/STATE_PATH/
  SCREENRECORD_DIR/SCREENSHOT_DIR/PLUGINS_DIR/WM), `ryoku-shell.sock` → `mei-shell.sock`,
  `ryoku-pill.sock` → `mei-pill.sock`, `ryoku-reload-cover` → `mei-reload-cover`,
  `ryoku-hub.lock` → `mei-hub.lock`, `local/share/ryoku` → `local/share/mei`,
  `ryoku-wallpaper` → `mei-wallpaper`, `ryoku-plugins-place` → `mei-plugins-place`,
  Go package `ryoku` → `mei`, provider `ryoku-wm-<name>` → `mei-wm-<name>`.
  Deliberately **not** renamed: `Ryoku.*` QML module URIs, D-Bus names, polkit paths, font
  names, `ryogami`.

### `./mei` (control script)

- New `run` / `test` / `stop`-integration: fake `HOME=.run/home`, `XDG_*=.run/{config,cache,
  state,data,rt}`, private `dbus-run-session`, nested `Hyprland -c .run/hypr/nested.conf`.
- New `stop`: signals only recorded PIDs whose `/proc/<pid>/cmdline` contains `$MEI_DIR`;
  `run` refuses to clobber a session that is still alive.
- Resource cap: `systemd-run --user --scope -p MemoryMax=3G -p CPUQuota=200%` when available
  (fallback: process group only).
- Stale runtime cleaning (`rt/hypr`, `rt/quickshell`, sockets) before each launch.
- Short symlink `.r → .run/rt` exported as `XDG_RUNTIME_DIR` for the child. Hyprland names its
  event socket `$XDG_RUNTIME_DIR/hypr/<61-char signature>/.socket2.sock`; the 107-byte UNIX
  limit was exceeded (111 bytes) and Hyprland silently disabled Socket2. `.r` makes it 106.
  All bytes still land under `.run/rt`. `.r` added to `.gitignore`.

### Build (offline, `nice -n 10`, `-p 2` / `-j2`)

- `.run/bin/mei-shell` (~15.6 MB), `.run/bin/mei-wm-hyprland` (~6.7 MB).
- Blobs plugin via cmake/ninja → `.run/build/blobs/qml/Ryoku/Blobs`.
- QML modules assembled at `.run/qml/Ryoku/{Ui,FrameBars,PluginKit,Blobs,Wm/Hyprland}`.
- Fake-home fontconfig at `.run/home/.config/fontconfig/fonts.conf` (system config + Google
  Fonts `SpaceGrotesk[wght].ttf`, `Fraunces[…].ttf` fetched from the OFL repo).

### Verification

- `./mei test` exit 0 twice; `./mei verify-untouched` **PASS** before and after.
- Bar layer surfaces mapped (`ryoku-frame`, `ryoku-frame-edge`, `quickshell`); QML log has no
  load/type errors; workspaces nested 3 / daemon topic 3 (match); pixel capture 950×1024;
  zero outbound TCP from Mei PIDs; clean shutdown, no stray processes.
- Manual multi-workspace check: 5 cells, active pill moved from cell 5 to cell 2 on a nested
  `workspace 2` dispatch.
- **UNVERIFIED**: animation smoothness/visibility (still capture only), real GPU/144 Hz,
  audio (no PipeWire socket in the fake runtime dir), tray/network content (private bus).

### Baseline

- Host rebooted at 16:29 (kernel 7.2.9 → 7.2.11). Config hashes were unchanged; the baseline
  was re-captured (`./mei baseline --force`). Hyprland 0.56.2-4 / Quickshell 0.3.2-1 / Qt 6.12.0
  unchanged, so the `.conf` verification still holds.

## Phase 4 — extraction plan (plan only; no code, no installs, no builds)

- Wrote `docs/04-plan.md` (10 sections): HOME-confinement trace + fixes, the exact `src/`
  manifest, the daemon trim, the rename table, the build plan + `pacman -S` list with sizes,
  the nested test design, the minimal matugen config, fonts, the ordered Phase 6 steps, and
  risks/rollback/UNVERIFIED.
- **Housekeeping (approved):**
  - Reverted `25ba6a6` (`00b4511`) — `./mei` stays strict.
  - Extended `verify-untouched` to also hash `~/.config/{kitty,btop,qt6ct,gtk-3.0,gtk-4.0}` and
    `~/.cache/ryoku`. This exposed a latent `pipefail` bug (a missing watched dir made `find`
    exit 1 and aborted the script); fixed by passing only existing dirs.
  - Re-ran `./mei baseline --force` after the owner's session restart; `./mei verify-untouched`
    → **PASS**. Commits `00b4511` (revert) + `a8b0b2a` (hash set + re-baseline).
- Key Phase 4 findings (detail in `docs/04-plan.md`):
  - **Fake HOME closes the XDG hole**: nearly every path is `HOME + "/.…"` or `XDG_*`; the only
    true "outside project" writes left are four hard-coded `/tmp/ryoku-*` sites → repath to
    `$XDG_RUNTIME_DIR/mei-*`. `/run/polkit`, `/sys`, `/etc` reads are system, accepted.
  - **Hyprland 0.56.2 accepts both `.conf` and `.lua`** `[TESTED]` via isolated
    `--verify-config` → the nested session uses a plain `hyprland.conf`.
  - **wm apply chain cut**: remove `CapLiveConfigEval`/`CapConfigReload`/`CapPaletteBorder`
    (`ryoku/wm/hyprland/caps.go:31-32,47`) and neuter `apply.go:56-66` (`settings.lua` +
    `rebinds.lua`). Reads (workspaces, via ext-workspace + the daemon `wm` topic) stay.
  - **matugen is required** (palette is `matugen image … --json hex`); minimal `config.toml` is
    just `[config]` so no template ever targets the owner's home. Installed `matugen 4.2.0` ok.
  - **Versions**: Quickshell 0.3.2 (repo) + Qt 6.12.0 + Hyprland 0.56.2 + Go-to-be(1.27.2) all
    satisfy upstream; `cmake` + `go` + fonts missing. Rename list applied (env/sockets/locks/dirs);
    `Ryoku.*` QML module URIs deliberately **not** renamed.
- No install, no build, no code change beyond the approved `./mei` housekeeping.

## Phase 3 — classification (read-only; no code, no installs, no builds)

- Wrote `docs/03-classification.md`: every component, file group, daemon, Settings page, font
  and asset classified essential / optional-disabled / removable / uncertain, each with the
  necessity-test reason, a RAM/CPU estimate + whether it spawns a process, and its dependents.
  Includes the "bloat found" and "opted out, can re-enable" lists, licensing/credits (incl.
  the GPL-3.0 obligations and the unlicensed bundled fonts/icons redistribution flag), and the
  proposed Mei Settings-page list (5 kept: General, Appearance, Bar, Launcher, Motion).
- Added `docs/02b-gaps.md` because `docs/02-deps.md` was missing two items the owner required:
  (a) a mapping of **all 32** page files (28 nav + 4 helpers) to what each writes, and (b) the
  full list of daemons/processes the kept features need **with a process count** (3 resident:
  `ryoku-shell` → `qs -c shell`, and `ryogami`).
- Resolved the five open items by reading code (detail in `docs/03-classification.md` §1):
  1. **Dual `NotificationServer`** — real; both are instantiated
     (`services/Notifs.qml:230` and `barstyles/qsbar/panels/NotificationPanel.qml:26` via
     `VariantRoot.qml:251`). Keep `services/Notifs.qml` (integrated: popups, DND, menus); the
     qsbar panel's server also writes a foreign `~/.cache/qs-rise-notifications.json` → remove.
  2. **Polkit** — the agent is gated behind `RYOKU_POLKIT_AGENT=1` (`ipc/polkit.go:35-40`);
     test mode must simply not set it (Mei runs the daemon directly → never registers).
  3. **matugen** — `colors.json`/`tones.json` are written by the daemon's Go code, not by any
     template, so the kept palette needs **zero** templates. Every shipped template
     (`config.toml` 6 + `apps.toml` 22) targets the owner's home → **REMOVE**; plan is a bare
     Mei `config.toml` (`[config]` only, no templates, no post_hook) with `XDG_*` redirected.
  4. **Palette bridge** — HTTP on `127.0.0.1:47616` (`-listen` flag), loopback-only by default,
     not file-based; only browser/app theming uses it → optional-disabled.
  5. **ryogami** — live video runs a `ryogami-live` player per output (`[REPORTED] ~40–60 MB
     RSS`), depth adds a shader + map; both disable cleanly while keeping still images. The
     reveal shader lives in the kept Quickshell process (idle-zero, fires only on change) → keep.
- New confinement finding: many kept-module QML `FileView` paths are built as
  `Quickshell.env("HOME") + "/.config"` and therefore ignore `XDG_CONFIG_HOME`; the XDG redirect
  alone does not contain them. Flagged as **uncertain** — must be closed in Phase 6.
- ~~Hardened `./mei verify-untouched` for a live-session restart~~ — **REVERTED in Phase 4**
  (commit `00b4511`). This was an unapproved change to a safety script; `./mei` is strict again:
  a watched D-Bus owner-PID change is always fatal, full stop. The owner's session restart is
  handled by re-running `./mei baseline --force`, not by weakening the check.
- `./mei verify-untouched` → PASS (config hashes unchanged; D-Bus churn informational post-restart).

## Phase 2 — dependency mapping (read-only; no code, no installs, no builds)

- Wrote `docs/02-deps.md` (consolidated) from six read-only traces in `docs/02-deps/`
  (`01-bar`, `02-overlays`, `03-wallpaper-theming`, `04-settings`, `05-names-network-uv`,
  `06-fonts-qt-assets`). Nothing under `upstream/` was modified; no builds, no installs.
- Resolved the seven questions (detail in `docs/02-deps.md`):
  - matugen runs from the `ryoku-shell` daemon (`ipc/matugen.go:775`), triggered by the ryogami
    `wallpaper` topic; it writes `~/.cache/ryoku/{colors.json,tones.json,hypr-colors.lua}` and
    (via templates) `~/.config/{kitty,btop,qt6ct}`. matugen's `config.toml` hardcodes `~/.config`,
    so Phase 6 must generate a Mei config; the hypr template lands in cache, not the hypr dir.
  - Full IPC verb list + topic list recorded; audio/battery/notifications are in-process
    (PipeWire/UPower/Quickshell), only `network`/`tray`/`wm`/`settings`/`wallpaper` are daemon topics.
  - Kept features need **no** off-disk `ryoku/assets` (only the two brand logos, 1,146 B).
  - Network inventory: all outbound calls belong to off-keep-list features; keep-list traffic is
    loopback palette-bridge only.
  - Rename/redirect table: `ryoku*`→`mei*`, `ryogami`→`mei-wall`; KEEP polkit + freedesktop/KDE
    D-Bus names and `/run/polkit/agent-helper.socket`.
  - `uv` is needed only by `ryostage`/Rashin (off-list) → dropped.
  - Wallpaper: keep `ryogami` (Option B reworks ~9 files and loses reveal/live/depth; matugen
    dominates measured bytes).
- `./mei verify-untouched` → PASS after the phase.

## Phase 1 — read-only audit (still no upstream source touched)

- Read-only audit of the pinned upstream, written to `docs/01-audit.md`. No file outside
  `~/projects/mei` was created/modified/killed; no installs; no repo scripts run.
- `upstream/` working tree narrowed to a sparse checkout (see `UPSTREAM.md`); content unchanged
  (same pinned commit), only which paths are materialised changed.
- Key findings for later phases (full detail in `docs/01-audit.md`):
  - The Settings→Hyprland writer is `ryoku/wm/hyprland` (`settings.lua`/`rebinds.lua` +
    `hyprctl reload`), invoked by `ryoku-hub`; disabling it is a code change, not a flag.
  - Wallpaper is a separate daemon (`ryogami`), not part of `ryoku-shell`.
  - Config/cache/state are XDG-derived (redirectable); `/tmp/ryoku-hub.lock` and
    `/run/polkit/agent-helper.socket` are absolute and not redirectable.
  - Motion is centralised in `services/Motion.qml` (shell) + `ui/Singletons/Tokens.qml` (apps),
    but not fully — see §8.
  - Missing toolchain/fonts: `go`, `cmake`, `uv`, and all seven UI font roles.
- Verified `./mei verify-untouched` → PASS after the audit.

## Phase 0 — project scaffold (no upstream source touched yet)

- Created project layout: `AGENTS.md`, `docs/`, `src/`, `.run/`, `./mei` control script.
- Captured read-only live-session baseline (`docs/baseline.txt`, `docs/baseline/`) and
  `./mei verify-untouched`.
- `upstream/` cloned at pinned commit (see `UPSTREAM.md`); never edited.
