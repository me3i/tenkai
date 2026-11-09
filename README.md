# Tenkai

A standalone Quickshell shell forked from Ryoku.

## What Tenkai is

Tenkai is a modified, reduced derivative of [Ryoku](https://github.com/Ryoku-dev/ryoku),
pinned at commit `98a0368253d9628be72b853985878a5db90e1547` (v0.75.5-beta.20). It keeps
Ryoku's Quickshell shell — the look, the motion, the frame bar — and removes
components that did not pass a necessity test or were off the keep list.

The result is one Quickshell process (`qs -p shell`) plus two small daemons
(`tenkai-shell`, `ryogami`). There is no second shell process, no lock screen
daemon, and no background service that reaches outside the machine. Settings
persist to Tenkai's own config dir and read Hyprland state only; Tenkai never
writes or generates Hyprland config.

Every claim in this README is backed by a grep in `src/tenkai_core/` or a
measurement in `docs/PROJECT-CLOSEOUT.md`. Nothing here is an estimate.

## What's included

All of these have a grep hit in `src/tenkai_core/`. The file or directory is
named in parentheses.

- **Frame bar** — the top bar with workspace pills and status widgets.
  `src/tenkai_core/shell/quickshell/shell/modules/bar/` and
  `barstyles/qsbar/`.
- **Workspaces** — workspace pills in the bar (`RailWorkspaces.qml`,
  `WorkspaceWidget.qml`), a workspace overview panel (`WorkspacePanel.qml`),
  and workspace state in `shell.qml` via `Wm.focusedWorkspace`.
- **App launcher** — `modules/launcher/Launcher.qml`, imported in `shell.qml:21`.
- **Control center / quick settings** — `modules/controlcenter/ControlCenterHost.qml`,
  imported in `shell.qml:19`, surfaced on `SUPER+ESCAPE` and the screenshot key.
- **Clock** — a clock widget on the desktop (`modules/desktop/clock/Clock.qml`),
  a clock widget in the bar (`barstyles/qsbar/modules/ClockWidget.qml`),
  a clock in the frame-rail (`framebars/widgets/RailClock.qml`), and a
  `Config.clockEnabled` toggle in `Desktop.qml`.
- **Audio** — volume OSD (`shell.qml:306` `osdVolumeLoader`, `kind: "volume"`),
  an audio service (`services/Audio.qml`), and an audio-bars service
  (`services/AudioBars.qml`).
- **Brightness** — backlight control (`modules/bar/BrightnessControl.qml`),
  a brightness OSD (`shell.qml:322` `osdBrightnessLoader`, `kind: "brightness"`),
  and `Devices.qml:setBrightness` (ddcutil + brightnessctl).
- **Network** — a Network service (`services/Network.qml`, reads the daemon
  `network` topic), a Network popout (`modules/bar/popouts/NetworkPopout.qml`),
  and a network menu item in `FrameMenuManager.qml:96`. Network is read-only
  status (Wi-Fi, WireGuard, DNS); it does not change connections.
- **Battery** — a Battery service (`services/Battery.qml`, reads UPower's
  `displayDevice`).
- **System tray** — a Tray service (`services/Tray.qml`, reads the daemon `tray`
  topic), and `tenkai-shell` claims `org.kde.StatusNotifierWatcher`
  (`shell/ipc/tray.go`).
- **Notifications** — a NotificationServer that owns `org.freedesktop.Notifications`
  (`shell/quickshell/shell/modules/notifications/`), gated by
  `Config.moduleOn("notifications")` and a `GetNameOwner` guard in `Notifs.qml`.
- **Wallpaper + matugen theming** — a wallpaper module (`modules/wallpaper/`,
  `Wallpaper.qml`) driven by the `ryogami` daemon, and a matugen config block
  in `services/Config.qml:219` (`theme.matugen: { preference, scheme_type, mode, contrast }`).
  The matugen app-suite fan-out is off: only `config.toml` is rendered, never
  `apps.toml` or toolkit configs.
- **Animations** — a motion page in Settings (`hub/quickshell/pages/AnimationsPage.qml`,
  edits `theme.motion.scale` and `theme.motion.reduce`), a motion service
  (`services/Motion.qml`), and spring integration in the frame-blob plugin
  (`shell/plugin/blobrect.cpp`).
- **Settings app** — Tenkai's hub (`hub/`), with the Appearance page
  (`pages/VisualsPage.qml`: theme, blur, shadow, gaps, borders, screen shader —
  runtime-only via `hyprctl eval`, never writes `~/.config/hypr`) and the Shell
  pages (`pages/GlobalPage.qml`: language, regional formats, location, system font;
  `pages/SessionPage.qml`: autostart and env). Plus an Animations page and a
  Bar Studio page. Settings persist to Tenkai's config dir and read Hyprland
  state only.
- **Camera** — a Camera service (`services/Camera.qml`) and a Camera overlay
  (`modules/capture/CameraOverlay.qml`).
- **Region capture** — a capture module (`modules/capture/`, `Capture.qml`,
  `CaptureOverlay.qml`) and the `tenkai-screenshot` script
  (`shell/scripts/tenkai-screenshot`), which takes `region` or `full` screenshots
  locally via grim/slurp/wl-copy/notify-send.

## What's not included

Cut features. Use Ryoku for these.

- **Visualizer** — no `modules/visualizer/` in this tree.
- **Equalizer** — audio here is volume and playback bars only; no EQ.
- **Keypress overlay** — no keypress-overlay module.
- **Overview backdrop** — the workspace overview is a panel (`WorkspacePanel.qml`);
  the visualizer-backed overview backdrop was removed (`shell.qml:205`).
- **Desktop widgets (plugin suite)** — the desktop module carries the Clock as its
  only built-in widget (`Desktop.qml:84` — `addItems` lists only `clock`). Plugin
  desktop widgets read from `Registry.plugins` but no plugin manifests ship in
  this tree, so the slot exists but nothing installs into it.
- **Stage engine** — no `modules/stage/` in this tree.

## Verified numbers

Measured once, in a nested test session on 2026-11-09, fresh session, 60s warm-up,
launcher closed, idle. Full report: `docs/PROJECT-CLOSEOUT.md`.

| Process | RSS |
|---|---|
| `qs -p shell` (Tenkai) | 556 MB |
| `tenkai-shell` daemon | 26 MB |
| `ryogami` daemon | 8 MB |
| `wl-paste` | 2 MB |
| **Total** | **578 MB** |

Ryoku comparable processes (`ryoku-shell` + `qs` + `ryogami`) on the same machine:
767 MB. Delta: −189 MB (−25%).

This is a single snapshot, not a benchmark. The 450 MB target was not met; the
honest floor for this feature set is 550–600 MB. Further reduction requires
cutting keep-list features.

## Install / Run

Verify each command against the script first: `grep -nE 'cmd_(run|start|stop|live|test|verify_untouched|scrub_check|live_stop|live_status)' tenkai`.

```bash
git clone https://github.com/me3i/tenkai.git ~/projects/tenkai
cd ~/projects/tenkai
./install.sh              # interactive: deps, build, system changes one at a time
./install.sh --dry-run    # print every step, write nothing
./install.sh --help       # list all flags
```

After install:

```bash
./tenkai run              # nested isolated test session (one qs + two daemons)
./tenkai stop             # stop the test session
./tenkai verify-untouched # prove live config untouched after the test
./tenkai scrub-check      # prove no personal setup is tracked in the tree
./tenkai test             # nested-session test suite
./tenkai live --profile overlay   # try over the live desktop (asks before each change)
./tenkai live-stop        # stop a live profile run
./tenkai live-status      # status of a live profile run
./tenkai start            # non-interactive join for the autostart line
./tenkai status           # show the running Tenkai session, if any
```

Log out and back in after enabling autostart, and the desktop is Tenkai.

## Requirements

Proven by `install.sh` (the `check_pkg` and `check_build` lists) and the
`go.mod`/`CMakeLists.txt` files in `src/tenkai_core/`.

- **Arch Linux** with **Hyprland** (checked by `install.sh`: `check_pkg hyprland Hyprland`).
- **Quickshell** (`qs`) — `check_pkg quickshell qs`.
- **Go** — `go 1.26` for `tenkai-shell` and `tenkai-hub`
  (`src/tenkai_core/shell/ipc/go.mod`, `hub/backend/go.mod`); `go 1.22` for
  `tenkai-wm` and `ryogami` (`wm/go.mod`, `shell/ryogami/daemon/go.mod`).
- **CMake ≥ 3.28** and **Qt6** (Declarative + ShaderTools + Multimedia) —
  `src/tenkai_core/shell/plugin/CMakeLists.txt:10`, `install.sh` step 2.
- **ninja**, **gcc**, **python3**, **jq** — build tools, `install.sh` `BUILD_MISSING`.
- **grim** + **slurp** + **wl-clipboard** — region/full screenshots, build+run deps.
- **wireplumber** (`wpctl`) — audio.
- **NetworkManager** (`nmcli`) — network status reads.
- **brightnessctl** — brightness control.
- **upower** — battery readout.
- **fish** + **starship** — the owner's terminal config that `install.sh` step 6
  installs (a complete install depends on them).

`install.sh` never runs sudo; it prints the `pacman -S` line and stops.

## Known limitations

- **450 MB target not met.** Measured idle is 578 MB; honest floor for this
  feature set is 550–600 MB. Further reduction requires cutting keep-list features
  (camera, region, notifications, or others) — user decision, not a technical
  blocker. Source: `docs/PROJECT-CLOSEOUT.md`.
- **Single measurement.** The 578 MB figure is one snapshot from one nested
  session. It is not a range, not a benchmark, and not repeated across sessions.
- **Two shells cannot coexist.** Tenkai claims `org.freedesktop.Notifications` and
  `org.kde.StatusNotifierWatcher`. If another shell already owns either name, the
  relevant service backs off rather than fighting for it (`DBUS.md`, option B), but
  the two shells still cannot both own the standard names in one session.
- **Network is read-only.** Network status (Wi-Fi, WireGuard, DNS) is shown; the
  shell does not connect, disconnect, or change networks.
- **Settings never writes Hyprland config.** Appearance changes are runtime-only
  via `hyprctl eval`; a Hyprland reload reverts them. Shell page changes persist
  to Tenkai's config dir, not to `~/.config/hypr`.

## Attribution & licence

Tenkai is distributed under the **GNU General Public License version 3 or later
(GPL-3.0-or-later)**. The `LICENSE` at the repo root is byte-identical to upstream
at the pinned commit (sha256 `3972dc9744f6499f0f9b2dbf76696f2ae7ad8af9b23dde66d6af86c9dfb36986`).

`NOTICE` reproduces the upstream notice of the pinned commit byte for byte
(34 lines, sha256 `062137be76c0d594a089130445ad82495e745b67cdf677aa71be065d40635732`),
followed by a clearly delimited Tenkai addendum.

Components Tenkai ships and their provenance:

- **Ryoku** — the whole tree is a fork of Ryoku, pinned at
  `98a0368253d9628be72b853985878a5db90e1547`. URL:
  <https://github.com/Ryoku-dev/ryoku>. `UPSTREAM.md`.
- **QS Bar (Quickshell Rise)** by HANCORE-linux — the bar style, MIT.
  `src/tenkai_core/shell/quickshell/shell/modules/bar/barstyles/qsbar/`, credit at
  line 1 of `Scene.qml`. Repo: <https://github.com/HANCORE-linux/quickshell-dots>.
- **Caelestia shell** — frame-blob rendering and parts of the motion curves, GPL-3.0.
  `src/tenkai_core/shell/plugin/` (`blobshape.cpp`, `blobrect.cpp`, `blobgroup.cpp`, …).
  Repo: <https://github.com/caelestia-dots/shell>.
- **DankMaterialShell** by Avenge Media LLC — portions of the display configuration UI,
  MIT, copyright 2025 Avenge Media LLC. `src/tenkai_core/hub/`.
- **OkShell** by John Oberhauser — configurable frame-bar layout, rail/widget catalogue
  and Bar Studio workflow, GPL-3.0.
  <https://github.com/JohnOberhauser/OkShell/tree/87a9d09d923163cd03f396a395be3bb02b335b6e>.
- **Wallpaper picker UI** by liixini — MIT, copyright 2026 liixini.
  `src/tenkai_core/shell/ryogami/wall-ui/`, `LICENSE` ships beside the code.
- **Fonts** — Space Grotesk, Fraunces (roman + italic), Archivo Black: all SIL OFL 1.1.
  Eleven bundled display faces upstream shipped (Abberancy, Daydream, JF Flat, Overhead,
  Reckoner + Bold, sabana, Unrealised, VEXA Light, VIP Rawy, Xenophobia) were removed on
  2026-11-08 because their licences are personal-use, proprietary, or unstated.
  Per-file audit in `docs/ATTRIBUTION.md`.
- **Sound effects** — 5 `.oga` files from the freedesktop.org sound theme, with upstream
  credits (Boulanger, Bukvic, horsthorstensen, McCallister) in `NOTICE`.

Tenkai is not affiliated with, endorsed by, or connected to the Ryoku project.

Full per-file attribution: `docs/ATTRIBUTION.md`. Changes vs upstream: `CHANGES.md`.
Every modification is enumerated there.

## Development

Repo layout:

```
├── install.sh              installer (interactive)
├── tenkai                  control script (run / stop / test / verify-untouched /
│                           scrub-check / live / start / status / live-stop / live-status)
├── src/
│   ├── tenkai_core/        the Ryoku shell tree, adapted by Tenkai
│   ├── tenkai-configs/     bundled Hyprland Lua config + terminal dotfiles
│   └── tenkai-assets/      wallpapers and OFL fonts
├── docs/                   checklists, runbooks, baseline, PROJECT-CLOSEOUT.md
├── CHANGES.md              every modification vs upstream
├── CREDITS.md              attribution summary
├── UPSTREAM.md             pinned upstream commit + fork summary
├── NOTICE                  upstream copyright/licence notices + Tenkai addendum
├── LICENSE                 GNU GPL v3
└── .gitignore              excludes .run/, build/, *.o, *.so, *.bin, compiled binaries
```

Build: `./install.sh` step 2 builds the daemons, the blob plugin, and assembles the
QML modules under `.run/qml/`. The Go modules are at
`src/tenkai_core/shell/ipc/`, `hub/backend/`, `wm/`, `shell/ryogami/daemon/`. The
blob plugin CMake is at `src/tenkai_core/shell/plugin/CMakeLists.txt` (minimum 3.28).

Rollback point: the tree at tag `v1.0.0` is commit `461c3789b0621c3777b7e982dde85a455bf617fb`.
`git reset --hard 461c3789b0621c3777b7e982dde85a455bf617fb` returns to it.

## Status

**v1.0.0**, tagged `461c3789b0621c3777b7e982dde85a455bf617fb`, pushed to `origin/main`.
Standalone Quickshell shell, single `qs -p shell` process, verified 578 MB idle.
No roadmap. No features planned.
