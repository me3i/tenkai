# Phase 4 — Extraction Plan (Mei)

**Status:** plan only. No code changed, nothing installed, nothing built, no process
started. Everything below is derived by reading the pinned upstream tree
(`upstream/` @ `98a0368253d9628be72b853985878a5db90e1547`, v0.75.5-beta.20) and the
host's installed packages.

Labels: **[TESTED]** ran it and saw the result · **[READ]** read it in a file ·
**[REPORTED]** upstream says so · **[UNVERIFIED]** not yet proven, must be checked in
Phase 6.

Isolation contract (unchanged): nothing outside `~/projects/mei` is created, modified
or signalled; `~/.config/{quickshell,hypr}` and the live session are never touched;
no sudo, no install, no build in this phase.

---

## 0. Housekeeping done in this phase (report)

| Action | Result |
|---|---|
| Spot-check `RYOKU_POLKIT_AGENT` gate | Confirmed at `upstream/ryoku/shell/ipc/polkit.go:35-40` **[READ]** |
| Spot-check qsbar `NotificationServer` | Confirmed at `.../bar/barstyles/qsbar/panels/NotificationPanel.qml:26` **[READ]** |
| Revert `25ba6a6` | `git revert --no-edit 25ba6a6` → commit `00b4511`. `./mei` is strict again: a watched D-Bus owner-PID change is **always fatal**; no signature-based downgrade. **[TESTED]** |
| Extend `verify-untouched` | `CONFIG_WATCH_DIRS` now also hashes `~/.config/{kitty,btop,qt6ct,gtk-3.0,gtk-4.0}` and `~/.cache/ryoku`. Fixed a latent `pipefail` bug found while doing it (a missing watched dir made `find` exit 1 and aborted the script); it now passes only existing dirs. **[TESTED]** |
| Refresh baseline | `./mei baseline --force` → `docs/baseline/` recaptured `2026-10-19T13:39:25+05:30` after the owner's session restart, so the strict process/D-Bus diff is valid again. **[TESTED]** |
| Gate | `./mei verify-untouched` → **PASS** (hashes unchanged, processes/D-Bus match baseline). Commit `a8b0b2a`. **[TESTED]** |

Baseline hash coverage today: 8 files `~/.config/hypr`, 2 `~/.config/kitty`, 1
`~/.config/qt6ct` (the other four watched trees are currently empty or absent — that
is fine; a tree that appears later shows up as added lines and fails the diff).

---

## 1. HOME-confinement (item 1)

### Method

```
grep -rnE 'Quickshell\.env\("HOME"\)|env\("HOME"\)|"/home/|"/\.config|"/\.cache|"/\.local|"~/|/tmp/ryoku|/tmp/mei|/run/polkit' \
  ryoku/shell/quickshell/shell ryoku/ui ryoku/shell/ipc ryoku/shell/ryogami \
  ryoku/hub/quickshell ryoku/hub/backend --include=*.qml --include=*.js --include=*.go --include=*.sh
```

Raw extraction (581 hits incl. vendor/tests) → `.run/phase4-home-grep.txt`; filtered
(excluding `vendor/`, `_test.go`, `qa/`) → `.run/phase4-home-real.txt` (**236** hits).
Pattern counts in the filtered set: `env("HOME")` ×191, `"/.config` ×71, `"~/` ×57,
`"/.local` ×28, `"/.cache` ×24, `"/home/` ×9, plus hard-coded `/tmp/ryoku-*`.

### Resolution rule

Everything that matters is built as `Quickshell.env("XDG_*") || HOME + "/.…"` or
`os.Getenv("XDG_*")` fallback to `HOME`. Two independent redirects therefore cover it:

1. **Fake HOME** `~/projects/mei/.run/home` — catches *every* `HOME`-derived path,
   including code that ignores `XDG_CONFIG_HOME` (the Phase-3 hole). Examples:
   `shell.qml:141` (`HOME/.cache/ryoku/hypr-perf.json`),
   `modules/visualizer/Singletons/Scheme.qml:124/133/142`,
   `ipc/matugen.go` `matugenCacheHome()`/`matugenDataHome()`,
   `ipc/widgetwatch.go` `ryokuConfigDir()`, `ui/Singletons/Paths.qml`,
   `ui/Singletons/Wm.qml` (`XDG_RUNTIME_DIR||/tmp` + `ryoku-shell.sock`).
2. **XDG redirects** into `.run/{config,cache,state,data}` — catches XDG-first code
   and pins the runtime socket dir (so `ryoku-shell.sock`/`ryogami.sock` land in the
   project too).

### Table — file:line, what it touches, how it is handled

| file:line | touches | handled by |
|---|---|---|
| `shell/shell.qml:141` | `$HOME/.cache/ryoku/hypr-perf.json` (write) | fake HOME + rename `ryoku`→`mei` |
| `shell/modules/visualizer/Singletons/Scheme.qml:124,133,142` | `~/.cache/ryoku/colors.json`, `~/.config/ryoku/{shell,theme}.json` (read/watch) | fake HOME + rename |
| `shell/modules/stage/Singletons/Config.qml:108` | `~/.config/ryoku/stage.json` | module is cut (§2) |
| `ui/Singletons/Paths.qml` | `~/.config/ryoku/recording.json`, `$HOME/Videos`, `RYOKU_SHELL_RECORDINGS_DIR` | fake HOME + rename; recording off |
| `ui/Singletons/Wm.qml:22` | `$XDG_RUNTIME_DIR/ryoku-shell.sock` | XDG redirect + rename socket |
| `ipc/widgetwatch.go:33 ryokuConfigDir()` | `$XDG_CONFIG_HOME/ryoku` | XDG redirect + rename dir |
| `ipc/matugen.go:1757/1764/1771` | `$XDG_CACHE_HOME|$HOME/.cache`, `…/ryoku`, `…/matugen` | fake HOME + XDG + rename |
| `ipc/settings.go:1076` | sole writer of `~/.config/ryoku/shell.json` | fake HOME + XDG + rename |
| `ipc/theming.go` (`matugenColorsPath`) | `~/.cache/ryoku/colors.json`, `tones.json` | fake HOME + XDG + rename |
| `ipc/actions.go:113` | `$XDG_RUNTIME_DIR/ryoku-pill.sock` | pill = off-list (§2) |
| `ipc/prompter.go:80` | D-Bus `org.gnome.keyring.SystemPrompter` | fake session bus (§6); name must not change |
| `launcher/.../actions/catalog.js:35` | `/tmp/ryoku-hub.lock` (flock) | **repath → `$XDG_RUNTIME_DIR/mei-hub.lock`** |
| `launcher/.../actions/catalog.js:36` | `/tmp/ryoku-keys.lock` (flock) | **repath → `$XDG_RUNTIME_DIR/mei-keys.lock`** |
| `controlcenter/ControlCenter.qml:215` | `/tmp/ryoku-hub.lock` | **repath** (same as above) |
| `qsbar/Theme.qml:2176` | `/tmp/ryoku-screenrecord-filename` | recording off-list (§2) |
| `ipc/control.go:179` | `flock -n -o /tmp/ryoku-hub.lock qs …` | **repath → `$XDG_RUNTIME_DIR/mei-hub.lock`** |
| `qsbar/Theme.qml:2300,2327,3567` | `$RYOKU_PATH||/usr/share/ryoku` (plugin manifests) | set `MEI_PATH`→project; idle/notif-plugin checks cut |
| `ipc/polkit.go:69` | `/run/polkit/agent-helper.socket`, `/usr/lib/polkit-1/…` | system, agent disabled — **accepted** |
| `qsbar/modules/NetworkWidget.qml:208`, `panels/NetworkPanel.qml:1405` | `/sys/class/net/$IFACE/wireless` (read) | system read — **accepted** |
| `ipc/network.go` etc. | `/etc/hostname`, `/usr/share/zoneinfo` (reads) | system reads — **accepted** |

### What fake HOME cannot handle (must be fixed by edit or accepted)

1. **Hard-coded absolute `/tmp/ryoku-*`** — 4 sites (`catalog.js:35,36`,
   `ControlCenter.qml:215`, `control.go:179`, `Theme.qml:2176`). A fake HOME does not
   move these. **Fix:** repath to `$XDG_RUNTIME_DIR/mei-*` (or `$MEI_DIR/.run/tmp/…`)
   in Phase 6. This is the only true "writes outside the project" class.
2. **`/run/polkit/agent-helper.socket`** and `/usr/lib/polkit-1/polkit-agent-helper-1`
   — polkit-owned; the agent is disabled (`MEI_POLKIT_AGENT` unset), so these are
   never opened. Accepted, not a Mei path.
3. **`/sys/…`, `/etc/hostname`, `/usr/share/zoneinfo`, `/usr/share/icons`** — read-only
   system queries (network device type, hostname, timezones, icon theme). Accepted.
4. **Env leakage that overrides HOME-derived defaults** — if the real session exports
   `XDG_VIDEOS_DIR`, `XDG_PICTURES_DIR`, `XDG_DOCUMENTS_DIR`, `XDG_DATA_DIRS`,
   `STEAM_*`, `RYOKU_*`, `QS_*`, they would leak in. **Fix:** `./mei` launches with a
   **curated, cleared environment** (`env -i` + an explicit allowlist), so no stray
   XDG/Steam/Ryoku variable survives.
5. **Real user data the kept surfaces legitimately read** (wallpaper picker images).
   Not a leak — but under a fake HOME they vanish. **Fix:** read-only `bind`/
   symlink the real `~/Pictures/Wallpapers` (and `~/Pictures/livewalls` if the owner
   wants live sources listed, stills-only rendering) into `.run/home/Pictures/`.

### Fake-home seed manifest (`./mei` creates before every run)

```
.run/home/.config/            # Mei config (.config/mei/{shell.json,theme.json,matugen.json,…})
.run/home/.cache/mei/         # colors.json, tones.json, hypr-perf.json
.run/home/.local/share/       # Mei data
.run/home/.local/state/       # Mei state
.run/home/.local/share/fonts # project fonts (§8)
.run/home/Pictures/Wallpapers -> ~/Pictures/Wallpapers   (read-only)
.run/home/Videos              # empty; recording off
```
Set: `HOME=.run/home`, `XDG_CONFIG_HOME=.run/config`, `XDG_CACHE_HOME=.run/cache`,
`XDG_STATE_HOME=.run/state`, `XDG_DATA_HOME=.run/data`,
`XDG_RUNTIME_DIR=.run/rt`. (Belt-and-braces: even the XDG vars point inside the
project, so a QML `XDG_CONFIG_HOME || HOME/.config` resolves inside either way.)

---

## 2. File manifest (item 2) — what is copied into `src/`

`src/` mirrors the upstream layout under `src/ryoku/…` so relative imports and the
`shellDir/..` hub path (`control.go:140`) keep working. Everything not listed is
**excluded**.

### Tier A — copy verbatim (required, no edit)

| # | upstream dir | files / size | component | dependency reason |
|---|---|---|---|---|
| A1 | `ryoku/ui/` | 76 / 712K | design system | `Ryoku.Ui` + `Ryoku.Ui.Singletons` are imported by every kept surface; `Singletons/{Wm,Tokens,Paths,I18n,Spawn,Scheme…}` are load-bearing (`Wm` reads the daemon `wm` topic + ext-workspace; `Tokens` holds app motion). |
| A2 | `ryoku/shell/framebars/` | — | bar schema | `Ryoku.FrameBars` imported by `services/Config.qml`, `bar/*`, hub `barstudio` (bar config schema/catalogs). |
| A3 | `ryoku/shell/quickshell/plugins/kit/` | — | plugin kit | `Ryoku.PluginKit` module; `plugins/kit/Singletons/Config.qml` imports FrameBars. |
| A4 | `ryoku/wm/hyprland/qml/` | 3 | wm bridge | `Ryoku.Wm.Hyprland` global-shortcut + focus-grab bridges; cut down to read-only use. |
| A5 | `ryoku/shell/quickshell/shell/assets/` | 11 / 380K | shell assets | icons/art referenced by kept surfaces; prune to referenced files in Phase 6. |
| A6 | `ryoku/shell/quickshell/shell/utils/` | 5 / 24K | shell core | shared helpers imported by services. |
| A7 | `ryoku/shell/quickshell/shell/barkit/` | 1 / 8K | bar kit | `shell.barkit` module. |
| A8 | `ryoku/shell/quickshell/shell/modules/wallpaper/` | 87 / 424K | wallpaper reveal | `Wallpaper.qml`, `WallpaperFrame.qml`, `Backdrop.qml`, `reveal.frag(.qsb)`, `Singletons/` — the still wallpaper + reveal shader (kept). |
| A9 | `ryoku/shell/quickshell/shell/modules/notifications/` | 2 / 32K | notifications | popups; pairs with `services/Notifs.qml`. |
| A10 | `ryoku/shell/quickshell/shell/modules/bar/barstyles/qsbar/` | 283 → pruned | bar/qsbar | the top bar, workspaces, quick-settings/control-center, panels, widgets. `barstyles/{kairos,sumi}` excluded. |
| A11 | `ryoku/shell/quickshell/shell/modules/launcher/` (`shared/` + `variants/main/`) | 113 → pruned | launcher | the app launcher. `variants/{hero,kairos,okshell}` excluded. |
| A12 | `ryoku/shell/quickshell/shell/modules/visualizer/Singletons/` | 14 → Singletons only | palette | `Scheme.qml` is the shell palette singleton; the visual effect item is excluded (OFF). |
| A13 | `ryoku/shell/ipc/` (pruned, see §3) | 477 → pruned | daemon | the trimmed control plane. `vendor/` + `_test.go` excluded from the build set but `vendor/` is **kept on disk** so the build is offline (`-mod=vendor`). |
| A14 | `ryoku/wm/` (pruned: read/watch only) | — | wm provider | `ryoku-wm` module + `hyprland` read/watch + caps; used by the daemon and `ryogami`. |
| A15 | `ryoku/shell/ryogami/` | 169 / 1.9M | wallpaper daemon | `ryogami` daemon + `wall-ui/qml` reveal picker; stills only. |
| A16 | `ryoku/hub/quickshell/` (pruned to 5 pages, §3) | 117 → pruned | Settings app | `Hub.qml`, `Singletons/`, `barstudio/`, `schema/` (5 pages), reused `ui/` widgets. |
| A17 | `ryoku/hub/backend/` (pruned) | 466 → pruned | Settings backend | `ryoku-hub` binary; settings store client + appearance/desktop apply (no hypr writes). |
| A18 | `ryoku/shell/matugen/` | 29 / 204K | theming | minimal `config.toml` (§7); templates **not** copied. |

### Tier B — copy then edit (Phase 6, same commit as the copy)

| # | file | edit |
|---|---|---|
| B1 | `ryoku/shell/quickshell/shell/shell.qml` | drop `import`/instantiation of `dock`, `desktop`, `overview`, `clipboard`, `osd`, `capture`, `confirm`, `stage`, and the `Visualizer` item — keep `Wallpaper`, `Frame`/bar, `Launcher`, `NotificationPopups`. |
| B2 | `ryoku/shell/quickshell/shell/services/` | keep the singleton set below; delete the rest from `services/qmldir` + tree. |
| B3 | `ryoku/shell/ipc/*.go` | §3 trim (wm apply cut, settings path, topic removal, renames). |
| B4 | `ryoku/hub/quickshell/pages/` + `schema/` | keep 5 pages (below); drop the other 27 page files + their schema files. |
| B5 | QML module URIs `Ryoku.*` | **not renamed** (see §4). |

**Kept service singletons** (`services/qmldir`) — everything else cut:
`ShellState, ServiceLoader, Theme, Scheme, Config, Motion, Perf, Media, Music,
AudioBars, Battery, Network, Audio, Tray, Notifs, Sysinfo, AppLaunch, Icons,
KeyboardLayout, SessionActions (stub), ScreenTime`.
Cut: `Recorder, Capture, Clipboard, Camera, Dock, DockPreview, Updates, Events,
Holidays, Flags, Keyring, Polkit, PowerProfiles, Session, BluetoothDiscovery,
BtLink, Needle, StatsFeed, VoiceBars, Equalizer, Nightlight, Stash, MusicPreview,
BarProducts, Weather, Devices, Keypresses, OsdFeed, Toggles`.
**[UNVERIFIED]** — Phase 6's first bar commit confirms the import graph and deletes
any singleton that turns out to be a transitive dependency of a kept surface.

**Kept Settings pages (5)** with their schema files:
`GlobalPage` (General→`shell.json`), `DesktopPage` (Appearance→`brand.json`/viz),
`BarStudioPage` (Bar→`shell.json`), `LauncherPage` (Launcher→`launcher.json`),
`AnimationsPage` (Motion→`theme.motion.*`).
Cut pages (27): `Addons, AppOverrides, Connections, Credits*, Dictation, Displays,
Fastfetch, Gpu, Import, Input, Keybinds, LayerRules, Lockscreen, Performance*,
Plugins, Profile, Rashin, Recording, Session, Updates, Widgets*, WindowManager,
WindowRules, HeroEditor, LightingTab, ProfileToolbar, StoreWidgetCard`
(`*` = optional-disabled, can return later). All hypr-writing schema
(`KeybindsPage`, `WindowRulesPage`, `LayerRulesPage`, `DisplaysPage`, `InputPage`,
`LockscreenPage`) is cut, which severs the Settings→Hyprland write chain at source.

**Excluded outright** (not copied): `ryoku/hyprland/`, `ryoku/palette-bridge/`,
`ryoku/shell/quickshell/{reload-cover,ryoshot,keys-hint}`, `ryoku/shell/livewall/`,
`ryoku/shell/ryogami/daemon` live-video paths, `ryoku/shell/systemd/`,
`ryoku/shell/plugin` (copied only as the built artifact, not source), all `qa/`,
all `docs/`, every `*_test.go` / `*.test.mjs`, i18n catalogs, `ryoku/apps/`.

---

## 3. Daemon trim plan (item 3)

### Topics/verbs that STAY

| topic | why |
|---|---|
| `settings` | re-pointed at `~/.config/mei/shell.json` (sole writer); feeds the Settings app + bar config. |
| `bar`, `barstyle`, `menu` | bar layout/widget config. |
| `theme` | matugen palette apply (fixed schemes; `theme catalog` static). |
| `audio`, `brightness` | real, small-step, restore in tests. |
| `hub`, `dock`(status only) | open/close the Settings window. |
| `status`, `ping`, `signature`, `quit`, `reload` | liveness/teardown. |
| `wm` (read only) | publishes the watch snapshot the `Wm` singleton consumes for workspaces/focus residue. |

### Topics/verbs that are CUT

`keybinds`/rebind, `monitors`/`displays`, `gpu`, `vm`, `polkit` (compiled but
unregistered), `updates`, `recording`/`screenrecord`, `capture`, `clipboard`,
`stage`, `nightlight`, `idle`, `ai-usage`, `eq`, `game`, `lock`/`unlock-prepare`/
`suspend*` (stubbed to no-op), `weather`, `plugin(s)`, `voice`, `sound`,
`lock-quiesce`. Driven by deleting their `start*()` calls in `daemon.go bootstrap()`
and the topic handlers.

### The wm/hyprland **apply** chain cut (file:line edits)

Invariant after the cut: **no byte under `~/.config/hypr` is ever written, and no
`hyprctl`/live-eval that mutates compositor state is ever issued.** Reads stay
(workspaces are on the keep-list).

| file:line | what it does today | edit |
|---|---|---|
| `ryoku/wm/hyprland/caps.go:31-32` | claims `CapLiveConfigEval`, `CapConfigReload` | **remove both** (and `CapPaletteBorder` at `:47`) → every `d.wmc.Can(…)` guard returns false |
| `ryoku/wm/hyprland/act.go:169` | `ActionConfigReload` → reloads Hyprland | make it a no-op returning nil |
| `ryoku/wm/hyprland/act.go:245-260` + `setBorderColors:527` | `ActionBorderColors` → writes colour into Hyprland | no-op |
| `ryoku/wm/hyprland/apply.go:56-66` | writes `settings.lua` + `rebinds.lua`, then reloads | **neuter**: delete the two `writeOverlayLua` calls; `apply()` returns empty `Written` |
| `ryoku/wm/hyprland/config_settings.go:796,804` | writes `settings.lua` referencing `~/.cache/ryoku/hypr-colors.lua` | not reached once `apply()` is neutered; remove the writeOverlayLua helper's target |
| `ryoku/shell/ipc/theming.go:184-185,214-215` | `ActionConfigReload` after palette | guard now false (caps) — no edit needed beyond caps |
| `ryoku/shell/ipc/theming.go:233,250` | `CapLiveConfigEval` + `Preview` | guard false |
| `ryoku/shell/ipc/matugen.go:1319-1326` | `Can(CapPaletteBorder)` then `ActionBorderColors` | guard false |
| `ryoku/shell/ipc/matugen.go:589` | `ActionCursorReassert` (+ cursor recolor helper) | drop the goroutine; cursor recolor off |
| `ryoku/shell/ipc/sleepwake.go:1104` | `output.power on` | stub (sleep/wake off) |
| `ryoku/shell/ipc/session.go:34` | `ActionSessionExit` (logout) | stub (never logout) |
| `ryoku/shell/ipc/wmclient.go:18-30` | generic `wm.act` call from QML | keep the topic, but every action now no-ops via caps + stubs |
| `ryoku/shell/ipc/control.go:161` | `ActionAppFocus` (focus hub window) | **keep** (focus only, no config write) |

Because the capabilities are removed, the daemon can stay mostly unedited: the
`Can()`/`Caps()` guards already gate the writers. The explicit `apply.go` neutering is
the hard guarantee. **Phase 6 verification:** run the nested session and `inotifywait`
the (project) hypr tree + `strace -f -e trace=write` the daemon for any
`~/.config/hypr` path; expect none.

### Settings persistence (replaces Hyprland config writes)

- `settings.go:1076` → `newSettingsStore(filepath.Join(meiConfigDir(), "shell.json"))`
  where `meiConfigDir()` = `$XDG_CONFIG_HOME/mei` (renamed from `ryokuConfigDir()`).
- The Settings app never writes files directly: it calls the daemon `settings` topic
  over `mei-shell.sock`. Persistence is therefore a single `shell.json` (+
  `theme.json`, `launcher.json`, `matugen.json`) under the **fake-home** config dir.
- No `settings.lua`/`rebinds.lua`/`hypr-colors.lua` is generated (chain above is cut).

### Network: compiled-out vs hard-disabled

- Kept: **read-only** state (`nmcli`/D-Bus reads for the status widget).
- Hard-disabled: any mutation. `network.go:750` (`nmcli connection import`) and the
  hub `ConnectionsPage` + `pkexec` connection editor are cut; the daemon's connect/
  disconnect verbs, if present, are removed/hard-refused. **[UNVERIFIED]** — Phase 6
  greps `network.go` for `connect|disconnect|up|down|modify` verbs and confirms none
  are reachable.

---

## 4. Rename table (item 4)

Applied surface = `ryoku*` prefixes (env vars, dirs, sockets, locks). `ryogami`
(not `ryoku`-prefixed) keeps its name.

### Renamed

| upstream | Mei | exact files |
|---|---|---|
| `RYOKU_SHELL_DIR` | `MEI_SHELL_DIR` | `ipc/actions.go:20`, `ipc/*` (28 refs), `deploy`-free launch |
| `RYOKU_PATH` | `MEI_PATH` | `qsbar/Theme.qml:2300,2327,3567` |
| `RYOKU_WM`, `RYOKU_STATE_PATH`, `RYOKU_POLKIT_AGENT`, `RYOKU_GPU_BIN`, `RYOKU_STAGE_ENGINE`, `RYOKU_SCREENRECORD_DIR`, `RYOKU_SCREENSHOT_DIR`, `RYOKU_PLUGINS_DIR`, `RYOKU_KEYRING_*`, `RYOKU_LIVE_DBUS`, `RYOKU_SYSFS_ROOT`, `RYOKU_PAM_FILE`, … | `MEI_*` | the files that reference each (mostly cut with their feature) |
| `~/.config/ryoku` | `~/.config/mei` | `ipc/widgetwatch.go:33` `ryokuConfigDir()`, `ui/Singletons/Paths.qml`, `…/Scheme.qml` |
| `~/.cache/ryoku` | `~/.cache/mei` | `ipc/matugen.go` (`matugenColorsPath`), `shell.qml:141`, `Scheme.qml:124` |
| `~/.local/share/ryoku` | `~/.local/share/mei` | `ipc/matugen.go` (`matugenDataHome` consumers), `Theme.qml` i18n fallback |
| `ryoku-shell.sock` | `mei-shell.sock` | `ipc/main.go:18` `sockName`, `ui/Singletons/Wm.qml:22`, `hub/backend/daemonclient.go:30`, `ryogami/daemon/daynight.go:100` |
| `/tmp/ryoku-hub.lock` | `$XDG_RUNTIME_DIR/mei-hub.lock` | `ipc/control.go:179`, `launcher/…/catalog.js:35`, `ControlCenter.qml:215` |
| `/tmp/ryoku-keys.lock` | `$XDG_RUNTIME_DIR/mei-keys.lock` | `launcher/…/catalog.js:36` |
| `/tmp/ryoku-screenrecord-filename` | — (recording cut) | — |
| `ryoku-shell`, `ryoku-hub` binaries | `mei-shell`, `mei-hub` | build output names; `findHubBin()` `theming.go:25-26` (`LookPath("ryoku-hub")`) → `mei-hub` |
| `~/.config/quickshell/<name>` | `qs -p <project>` (unchanged names `shell`,`hub`) | `ipc/actions.go:49` `qsSelect` uses `-p` when `MEI_SHELL_DIR` set |
| systemd units `ryoku-shell.service`, `ryogami.service` | **not used** (direct exec, no units) | — |

### Must NOT change

- D-Bus names: `org.kde.StatusNotifierWatcher` (tray), `org.gnome.keyring.SystemPrompter`
  (prompter), `org.freedesktop.{Notifications,portal.*,secrets,ScreenSaver,...}`.
- Polkit paths: `/run/polkit/agent-helper.socket`, `/usr/lib/polkit-1/polkit-agent-helper-1`.
- QML module URIs `Ryoku.Ui`, `Ryoku.FrameBars`, `Ryoku.PluginKit`, `Ryoku.Wm.Hyprland`,
  `Ryoku.Blobs` — they resolve from the **project** `QML2_IMPORT_PATH`, so no collision
  exists and renaming them would touch every `import` for no safety gain. (Deliberate
  non-rename; the user's rename list was sockets/locks/env/units.)
- `ryogami` / `RYOGAMI_*` (wallpaper daemon identity) — not `ryoku*`.
- Font family names (the QML asks for them by name).
- `quickshell` / `qs` binary names (external tool).

---

## 5. Build plan (item 5)

### Installed vs required

| upstream needs | installed | verdict |
|---|---|---|
| **Quickshell repo package** (not `quickshell-git`; it links Qt private API) — `PKGBUILD:87`, comment:19 **[READ]** | `quickshell 0.3.2-1` | **match**; keep the repo package |
| Qt ≥ 6.5 (Blobs `CMakeLists` `find_package(Qt6 6.5 …)`) **[READ]** | Qt 6.12.0 (base/declarative/shadertools/svg/multimedia/wayland/imageformats/5compat) | **ok** |
| Go 1.26 (`ipc`), 1.26.4 + `toolchain go1.26.5` (`hub`) **[READ]** | not installed; repo `go` = **1.27.2** ≥ 1.26.5 | install `go` |
| CMake ≥ 3.28 + Ninja + gcc (Blobs) **[READ]** | cmake **absent**; ninja/gcc present | install `cmake` |
| `matugen` (palette: `matugen image <img> … --json hex --dry-run`) **[READ]** `matugen.go:157-188` | `matugen 4.2.0-1` | **ok** |
| `ffmpeg`, `imagemagick`, `jq`, `brightnessctl`, `wireplumber`, `networkmanager` | all present | **ok** |
| Fonts | none of the Ryoku faces | install (§8) |

Version-drift note: upstream pins **no** Quickshell version; it builds against
whatever the repo ships at release time. Quickshell 0.3.2 vs a config authored
against an unknown 0.3.x is the **top build risk** **[UNVERIFIED]**.

### Commands (project-local, capped, offline)

```bash
MEI=/home/mei/projects/mei
export GOTOOLCHAIN=local GOFLAGS=-mod=vendor \
       GOPATH=$MEI/.run/go GOCACHE=$MEI/.run/go/cache \
       CGO_ENABLED=0
mkdir -p "$MEI/.run/bin" "$MEI/.run/qml"

# daemon
( cd "$MEI/src/ryoku/shell/ipc"    && nice -n 10 go build -trimpath -p 2 -o "$MEI/.run/bin/mei-shell" ./ )
# settings backend
( cd "$MEI/src/ryoku/hub/backend"  && nice -n 10 go build -trimpath -p 2 -o "$MEI/.run/bin/mei-hub"   ./ )
# wallpaper daemon
( cd "$MEI/src/ryoku/shell/ryogami/daemon" && nice -n 10 go build -trimpath -p 2 -o "$MEI/.run/bin/ryogami" ./ )

# Blobs C++/QML plugin
cmake -S "$MEI/src/ryoku/shell/plugin" -B "$MEI/.run/build/blobs" -G Ninja -DCMAKE_BUILD_TYPE=Release
nice -n 10 cmake --build "$MEI/.run/build/blobs" -j2
# -> "$MEI/.run/build/blobs/qml/Ryoku/Blobs"

# assemble pure-QML modules onto one import path
cp -a "$MEI/src/ryoku/ui"                      "$MEI/.run/qml/Ryoku/Ui"
cp -a "$MEI/src/ryoku/shell/framebars"         "$MEI/.run/qml/Ryoku/FrameBars"
cp -a "$MEI/src/ryoku/shell/quickshell/plugins/kit" "$MEI/.run/qml/Ryoku/PluginKit"
mkdir -p "$MEI/.run/qml/Ryoku/Wm"; cp -a "$MEI/src/ryoku/wm/hyprland/qml" "$MEI/.run/qml/Ryoku/Wm/Hyprland"
cp -a "$MEI/.run/build/blobs/qml/Ryoku/Blobs"  "$MEI/.run/qml/Ryoku/Blobs"
export QML2_IMPORT_PATH="$MEI/.run/qml"
```

Wrap long builds in `systemd-run --user --scope -p MemoryMax=3G -p CPUQuota=200%`
(available) when running under `./mei`.

**Avoidable:** `ryoku/shell/livewall` (C / wlr-layer-shell) is **not built** — live
video is disabled; stills only. Skip it entirely.

### `pacman -S` list (the owner runs this; Phase 5 gate)

```
sudo pacman -S --needed go cmake \
  ttf-jetbrains-mono-nerd inter-font noto-fonts noto-fonts-cjk noto-fonts-emoji \
  ttf-material-symbols-variable
```

| package | dl | installed | why | avoidable? |
|---|---|---|---|---|
| `go` | 42.29 MiB | 226.64 MiB | build the 3 Go binaries | build-only; needed |
| `cmake` | 14.92 MiB | 101.44 MiB | build `Ryoku.Blobs` | build-only; needed |
| `ttf-jetbrains-mono-nerd` | 11.11 MiB | 231.92 MiB | mono + the Nerd glyphs the bar uses | needed |
| `inter-font` | 3.48 MiB | 14.27 MiB | secondary UI face | needed |
| `noto-fonts` | 27.86 MiB | 106.81 MiB | fallback sans | needed |
| `noto-fonts-cjk` | 188.75 MiB | 298.79 MiB | the 力 seal + CJK fallback | **avoidable** — swap the mark glyph → drops 299 MiB |
| `noto-fonts-emoji` | 9.18 MiB | 10.18 MiB | emoji in notifications | optional |
| `ttf-material-symbols-variable` | 9.14 MiB | 31.67 MiB | Material icons throughout | needed |

Total ≈ **307 MiB download / ~1.02 GiB installed**.

**Not in any official repo (AUR or manual):** `otf-space-grotesk` (**the default UI
sans — essential**), `ttf-fraunces-variable` (decorative display). Options:
(a) AUR helper; or (b) drop the OFL files into the **project** font dir (§8) — no
AUR, and keeps them visible only to Mei. Fraunces can be skipped (falls back to the
UI sans) at a small fidelity cost.

---

## 6. Nested test environment (item 6)

`./mei test` (Phase 6 build of the stub) does:

1. **Guard** — refuse to run if `HYPRLAND_INSTANCE_SIGNATURE` equals the baseline
   signature in `docs/baseline/env.txt` (i.e. we are inside the real session). Also
   refuse if `WAYLAND_DISPLAY` points at a socket outside `.run`.
2. `dbus-run-session -- bash -c '<whole nested session>'` — gives a private session
   bus, so `org.freedesktop.Notifications`, the tray watcher, and the prompter are
   **Mei's alone**; the live session is untouched.
3. Inside: export the fake HOME + XDG redirects (§1) and a **cleared** env, then
   `Hyprland -c "$MEI/.run/hypr/nested.conf"` — nested because `WAYLAND_DISPLAY` of
   the *host* is inherited into the nested process group only (it opens a window in
   the host). The nested instance publishes its own
   `HYPRLAND_INSTANCE_SIGNATURE`; **every** `hyprctl` in the test exports
   `HYPRLAND_INSTANCE_SIGNATURE=$nested` explicitly.
4. Start `mei-shell daemon` with `MEI_SHELL_DIR=$MEI/src/ryoku/shell`, then run the
   pass/fail check, then tear down (SIGTERM only PIDs whose `/proc/<pid>/cmdline`
   contains `$MEI`).

**Config format for Hyprland 0.56.2:** both formats work — **[TESTED]**
`Hyprland --verify-config --config probe.conf` and `… probe.lua` both printed
`config ok` (isolated env, `env -i`, project paths). The nested instance will use a
plain **hyprlang `nested.conf`** (simplest, no Lua runtime deps):

```
general { border_size = 1 }
exec-once = mei-shell daemon        # or started by ./mei itself
bind = SUPER, Q, exit,
bind = SUPER, T, exec, mei-shell hide
bind = SUPER, 1, workspace, 1
```

Binds live only inside the nested config, so they exist only in the nested instance.

**Leak guards (defence in depth):**
- `HYPRLAND_INSTANCE_SIGNATURE` for the nested session is captured and re-exported for
  every `hyprctl`; a bare `hyprctl` (no signature) would hit the real one, so `./mei`
  never calls it without the explicit signature.
- The nested `XDG_RUNTIME_DIR=.run/rt` means even the *socket path* used by
  `Hyprland` is inside the project; the real `/run/user/<uid>/hypr/…` is never opened.
- `./mei` refuses if `$XDG_RUNTIME_DIR` outside `.run` is about to be used.
- After teardown: `./mei verify-untouched` must PASS (hashes + watched D-Bus owners).
- Hyprland writes its log to `$XDG_STATE_HOME`; with the redirect that is
  `.run/state/hyprland.log` (an earlier probe with no `XDG_STATE_HOME` tried
  `/hyprland.log` — so the redirect is required, not optional) **[TESTED]**.

---

## 7. matugen (item 7)

**Is matugen required?** Yes — the palette is generated by shelling out:
`matugen image <img> -t <scheme> -m <dark|light> --contrast … --prefer … --json hex
--dry-run` (`ipc/matugen.go:157-188`, `runMatugenCapture:774`) **[READ]**. `matugen
4.2.0` is installed **[TESTED]**.

**Minimal `config.toml`** (shipped to `~/.config/mei/matugen/config.toml`):

```toml
[config]
```

That is the whole file. Consequence: when the daemon calls `matugen -c config …`
(`matugenRender:1253`) there are **no `[templates.*]`**, so matugen renders nothing
and writes nothing to `~/.config/{kitty,btop,qt6ct,gtk-3.0,gtk-4.0}` or
`~/.cache/ryoku/*`. The upstream `post_hook` (folder icons, cursor recolor) is also
not present, so it never runs. (Upstream's shipped `config.toml` has 6 templates + a
`post_hook`, and `apps.toml` has 22 more — all **not copied**.)

**How colours reach the shell:** the Go control plane owns `colors.json`; after
generating the palette it writes `~/.cache/mei/colors.json` (base16 for the legacy
reader, camelCase Material-3 roles for `Theme.qml`/`Tokens.qml`) and
`~/.cache/mei/tones.json` (`matugen.go:573,690,594`) **[READ]**. Every kept QML
singleton watches that file (`visualizer/Singletons/Scheme.qml:124` etc.). So the
palette path is `wallpaper → matugen (scheme math) → Go writes colors.json → QML file
watch → surfaces`. With a fake HOME this is `.run/home/.cache/mei/colors.json`, i.e.
inside the project **[UNVERIFIED]** until built.

---

## 8. Fonts (item 8)

**Needed faces** (from `Theme.qml`/`Tokens.qml` + `fc-match`):
`Space Grotesk` (default UI sans, **essential**), `Fraunces` (display/decorative),
`JetBrainsMono Nerd Font` (mono + bar glyphs), `Material Symbols Rounded` (icons),
`Inter` (secondary), `Noto Sans`/`Noto Sans CJK JP` (fallback; 力 seal),
`Noto Color Emoji`. (`fc-match` currently falls back to Nimbus for all of them
**[TESTED]**.)

**Visibility only to Mei — project-local fontconfig.** `./mei` sets:

```
HOME=$MEI/.run/home
XDG_DATA_HOME=$MEI/.run/data
FONTCONFIG_FILE=$MEI/.run/home/.config/fontconfig/fonts.conf
```

and writes a `fonts.conf` that includes the system config plus the project face dir:

```xml
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
<fontconfig>
  <include>/etc/fonts/fonts.conf</include>
  <dir>/home/mei/projects/mei/fonts</dir>
</fontconfig>
```

Then `fc-cache -f` against **that** `FONTCONFIG_FILE` only (never the user cache).
System families still resolve (via `<include>`), but nothing is installed into the
user's font path. The AUR/manual faces (Space Grotesk, Fraunces) go into
`$MEI/fonts/` as OFL files, so they exist **only** for Mei.

**Licences:** Space Grotesk, Fraunces, Inter, JetBrains Mono, Noto — **OFL**;
Material Symbols — **Apache-2.0**; Nerd Fonts patches — OFL. All redistributable with
their licence files. **Redistribution flag:** upstream bundles 11 display-font faces
and `components/icons/` **with no licence file** — fine for local use; if Mei is ever
published, those must be replaced or licensed. (Kept as-is locally; recorded in
`UPSTREAM.md`.)

---

## 9. Ordered Phase 6 build steps (item 9)

Each step = one commit; after each, `./mei verify-untouched` and the nested test.

| step | build | pass/fail test | commit |
|---|---|---|---|
| 6.0 | scaffold `src/` copy (Tier A) + renames (§4) + `mei-shell.sock` + fake-home seed | `go build` ×3 succeed offline; `mei-shell --help` prints | `phase6: scaffold src + renames` |
| 6.1 | **bar + workspaces**: copy `qsbar`, prune `shell.qml` to `Wallpaper`+`Frame`, keep service singletons | nested session: bar paints, workspace cells track `hyprctl` workspace changes, clock/audio/brightness/network/battery/tray widgets render; **no write** to `~/.config/hypr` (inotify/strace) | `phase6: bar + workspaces` |
| 6.2 | **launcher**: wire `modules/launcher` (`shared`+`variants/main`) to a bar/keybind, `AppLaunch` | nested: launcher opens, filters apps, launches a harmless app (`kitty`/`true`), closes; no leftover processes | `phase6: launcher` |
| 6.3 | **control sidebar / quick settings**: `qsbar/controlcenter` + `panels` | nested: sidebar opens/closes, quick toggles reflect live state; brightness/audio step + restore | `phase6: control sidebar` |
| 6.4 | **settings app**: `mei-hub` + 5 pages | nested: Settings opens, edits shell.json/theme.json in the fake home only; no hypr write | `phase6: settings (5 pages)` |
| 6.5 | **wallpaper + matugen**: `ryogami` stills, minimal `config.toml`, colors.json | nested: wallpaper applies, `colors.json` regenerates on switch, no write to kitty/btop/qt6ct/gtk | `phase6: wallpaper + theming` |
| 6.6 | **notifications + tray**: `Notifs.qml` only (qsbar server removed) | nested: `notify-send` → popup; tray item appears; no `qs-rise-notifications.json` write | `phase6: notifications + tray` |
| 6.7 | **motion/tokens audit**: prove `Motion.qml` is the single scalar source | nested: theme.motion.* edits change durations; no flat/duplicated constants | `phase6: motion centralised` |

---

## 10. Risks, rollback, UNVERIFIED (item 10)

**Risks**
1. **Quickshell 0.3.2 drift** — config authored against an unknown 0.3.x; QML API
   changes (WindowManager, Blobs, IpcHandler) could fail to load. Mitigation: 6.1 is
   the canary.
2. **Blobs plugin build** — needs cmake + Qt 6.5+; the plugin is optional for the bar
   to render but the frame/melt uses it. Mitigation: 6.1 fails loudly if missing.
3. **`Ryoku.*` module assembly** — the import path copy must be exactly
   `Ryoku/{Ui,FrameBars,PluginKit,Wm/Hyprland,Blobs}`; a mislaid module gives
   "module not installed".
4. **Go `toolchain go1.26.5`** — with local 1.27.2 and `GOTOOLCHAIN=local` it uses
   local; if a mismatch appears, `GOTOOLCHAIN` must not silently fetch over network.
5. **CJK size** — `noto-fonts-cjk` is 299 MiB for one seal glyph.
6. **Settings→hypr write regression** — the guarantee is the capability removal +
   `apply.go` neuter; the test harness (inotify + hash watch) must catch any regression.
7. **Rebuild churn** — nothing is installed system-wide, so a bad build can never
   affect the live session.

**Rollback:** `rm -rf ~/projects/mei`. Nothing was installed system-wide, no unit
enabled, no autostart entry, no config touched — deletion is complete and safe.
`docs/ROLLBACK.md` covers the optional package removals (only if the owner chooses to
uninstall the Phase 5 packages).

**UNVERIFIED until built (must be re-labelled in Phase 6)**
- Quickshell 0.3.2 loads the pruned configs.
- The exact kept-service-singleton closure (import graph).
- NotificationServer arbitration winner (Phase-3 open item).
- `colors.json` reaching the shell under the fake HOME.
- ryogami stills-only run with live/depth disabled.
- No `~/.config/hypr` / kitty / btop / qt6ct / gtk / `~/.cache/ryoku` writes from the
  cut apply chain (proved by inotify + `./mei verify-untouched`).
- Exact RAM/CPU per process (Phase 8).
- Whether any kept surface reads `hypr-colors.lua` (currently believed not).
- Bundled-font + icon-set licence provenance (redistribution only).

---

*Phase 4 ends here. No install, no build, no code change beyond the approved `./mei`
housekeeping. STOP for review; Phase 5 is the package-list gate.*
