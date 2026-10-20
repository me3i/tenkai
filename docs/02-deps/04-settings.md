# 04 — Settings (ryoku-hub): appearance + shell pages only

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

## App structure and nav groups

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

## Keep-list pages (appearance + shell) mapped to real files

Every page below has **no row with `src:"desktop.json"`** (so it is a shell
section), and its writes land in Mei's own config dir. Global motion keys live in
`shell.json` under `theme.motion.*` and are written through the daemon seam, not
the hypr draft (`pages/AnimationsPage.qml:154-159`).

### Global (`global` → `GlobalPage.qml`)
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

### Desktop (`desktop` → `DesktopPage.qml`)
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

### Bar Studio (`bar-studio` → `BarStudioPage.qml`)
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

### Launcher (`launcher` → `LauncherPage.qml`)
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

### Widgets (`widgets` → `WidgetsPage.qml`)
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

### Animations — **shell-motion half only** (`animations` → `AnimationsPage.qml`)
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

## Must-remove pages (compositor config editors)

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

## What Settings writes

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

## The Hyprland write path to sever

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

## Backend inventory

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

## QML imports

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

## Singletons

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

## IPC verbs used / binaries shelled out

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

## Services / daemons

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

## Qt modules

**[READ]** `QtQuick`, `QtQuick.Controls`, `QtQuick.Shapes`,
`Qt.labs.folderlistmodel`, plus the Quickshell modules `Quickshell`,
`Quickshell.Io`. No QtNetwork/QtWebEngine usage in the Hub frontend.

## Fonts

**[READ]** `Singletons/Theme.qml:53-56` names Fraunces (display), Space Grotesk
(UI), Noto Sans CJK JP (kanji marks), JetBrainsMono Nerd Font (mono). One font
is bundled: `hub/quickshell/fonts/archivo-black.ttf`. Font lists for the
`fontFamily` pickers are read live via `fc-list` (`GlobalPage.qml:48`,
`WidgetsPage.qml:94`). I18n text uses `Ryoku.Ui.Singletons.I18n`.

## Assets

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

## Network calls

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

## Necessity / exclusions

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
