# Tenkai — Architectural Audit Handbook

Read-only architectural audit and component classification for the Tenkai project (`~/projects/tenkai`).

**Status:** Phases 1–15 fieldwork complete; `ARCHITECTURAL_AUDIT.md` written from that evidence. **Phase 16 (cleanup/disabling) NOT started.** Do not delete, rename, disable, or remove anything in this project until the owner explicitly approves Phase 16.

**Scope boundary:** Everything cited below is inside `~/projects/tenkai`. The live user session and its real config are not touched by this project at any phase; see **Non-negotiable safety rules** in the root `AGENTS.md` and the control script's own safety contract.

**Tone rule:** Every "works" or "lightweight" claim below is either `TESTED` or `UNVERIFIED` and is labelled nested-vs-live where relevant. Measurement claims are only made after a measurement. Stale references are flagged as stale, not silently corrected.

---

## 1. Executive summary

Tenkai is a read-only, nested-session Quickshell desktop audit/harness built by copying and trimming upstream Ryoku source into `src/`, keeping the shell visual identity, and running all runtime state under `.run/`. Its primary deliverable in this tree is the nested-test harness, the read-only baseline/verify machinery, and the control script that enforces HOME/XDG confinement, PATH isolation, and process-safety rules.

The tree is **not** a clean-slate product. It is a reduced Ryoku build with a large amount of bundled-but-disabled or inert material carried for isolation and traceability reasons (shadow stubs, severed hub backends, disabled trayxd-free tray path, disabled Settings→Hyprland writes). The audit must therefore classify components by **what they actually participate in when run**, not by what the upstream tree could do.

**Key conclusions (so far):**

- The only in-process consolidated shell component is the shell itself (`components` slice = `shell` in the supervision logic). The Go daemon (`ryoku-shell`, built as `tenkai-shell`) supervises that single Quickshell component via `exec.Command("qs", qsSelect(name)...)` only for `name == "shell"`.
- The shell Go daemon is the real IPC/broker component. It owns the Unix socket `tenkai-shell.sock`, the `tray`, `media`, `clipboard`, theming, audio, brightness, network, battery, status-notifier-watcher, MPRIS media control, and several other topic workers.
- Tenkai **has no trayxd client or server anywhere in this checkout.** The system tray path is the Go `tray.go` StatusNotifierWatcher implementation + the QML `Tray` singleton. Any report that assumes a trayxd binary exists in this tree is wrong; the tray module surfaces were confirmed present and the `trayxd` directory is absent.
- The Settings app surface is kept only for Appearance + Shell pages, and its Hyprland-config path is explicitly severed through `applyDesktop()` returning `nil`. Settings writes to Tenkai's own config, never to live Hyprland config.
- The `docs/` tree still contains memos referencing `tenkai-configs/` and `tenkai-assets/` as real persisted sets; both are empty in this checkout. The real persisted snapshot set is `docs/baseline/`. This is a stale-reference condition worth noting in any cleanup discussion.

---

## 2. Project inventory

### 2.1 Top-level and layout

- `tenkai` — the 2698-line control script (bash). This is the single entry point for baseline, verify-untouched, verify-prove, env-check, status, run/stop/test, wallpaper, live/start, scrub-check, export-clean, live-stop, live-status, and the env/owned/shadow/system tool lists.
- `AGENTS.md` — root-level; keep list, workflow, honesty/reporting, licensing, non-negotiable safety rules 1–9. **There is no `docs/STATUS.md`, `docs/PARITY.md`, or `docs/AGENTS.md` in this checkout.** The AGENTS doc lives at repo root.
- `src/ryoku/{hub,shell,ui,wm}` — copied/adapted upstream material.
- `src/ryoku/shell/ipc/` — the `ryoku-shell` Go daemon source tree.
- `src/ryoku/shell/quickshell/shell/` — the Quickshell shell entry, services, components, bar, launcher, modules, and singletons.
- `src/ryoku/hub/backend/` — the Hub backend Go tree.
- `src/ryoku/wm/` — the window-manager seam Go tree.
- `src/ryoku/shell/scripts/` — Tenkai-owned shell scripts (7 files).
- `src/ryoku/shell/ryogami/` — ryogami wall-picker/daemon material.
- `src/ryoku/shell/matugen/` — matugen theming config/templates.
- `.run/` — runtime state; XDG overrides, Go dirs, sockets, pids, binaries.
- `docs/` — phase docs, `baseline/`, `tests/`.

### 2.2 The real shell-script surface

There is **no** `src/ryoku/scripts/` directory in this checkout. The real Tenkai-owned shell scripts live under `src/ryoku/shell/scripts/` and there are 7 of them:

- `ryoku-app`
- `ryoku-cmd-brightness`
- `ryoku-restart-audio`
- `ryoku-summon`
- `ryoku-volume`
- `tenkai-app`
- `tenkai-screenshot`

The earlier references to a "4 project scripts" surface are stale. The correct, verified count in this tree is 7.

### 2.3 Qt/Quickshell surfaces

- `shell.qml` — single resident shell instance entry.
- `services/qmldir` — 52 declared singletons.
- `services/*.qml` — 51 service QML files.
- `components/*.qml` + `components/lib/fader.js`.
- bar/barstyles/{kairos,qsbar,sumi}, bar/framebars/{lib,menus,widgets}, bar/popouts, bar/panel.
- launcher/variants/{hero,kairos,main,okshell} + launcher/shared/providers (13 dirs).

### 2.4 Go surfaces

- `src/ryoku/shell/ipc/` — module `ryoku-shell`, Go entrypoint `main.go`.
- `src/ryoku/shell/ipc/vendor/` — vendored dependencies.
- `src/ryoku/shell/ryogami/daemon/` — ryogami Go daemon.
- `src/ryoku/hub/backend/` — Hub backend Go tree.
- `src/ryoku/wm/` — WM seam Go tree.

### 2.5 Asset/config surfaces

- `src/ryoku/shell/matugen/` — `config.toml`, `apps.toml`, `templates/` (27 files).
- `src/ryoku/shell/ryogami/wall-ui/` — bundled picker qml + `data/matugen/templates/` (14 files).
- `docs/baseline/` — 9 snapshot files (the real persisted snapshot set).
- `docs/tests/` — 37 test/helper files.
- `fonts/` — Fraunces (~415KB + ~360KB), SpaceGrotesk (~137KB).

### 2.6 Notable empty/stale locations in this checkout

- `tenkai-configs/` — empty in this checkout.
- `tenkai-assets/` — empty in this checkout.
- Docs memos that reference those dirs are stale; the real snapshot set is `docs/baseline/`.

---

## 3. Dependency and build surfaces

### 3.1 Go dependencies — real, minimal set

**`src/ryoku/shell/ipc/go.mod`:**
- module `ryoku-shell`
- Go 1.26, toolchain `go1.26.5`
- requires:
  - `github.com/godbus/dbus/v5 v5.2.2`
  - `golang.org/x/sys v0.27.0`
  - `ryoku-wm v0.0.0` (replace `../../wm`)

**`src/ryoku/shell/ipc/go.sum`:** 4 lines. Exactly 2 upstream modules + their go.mod hashes (`godbus/dbus`, `golang.org/x/sys`).

**`src/ryoku/shell/ipc/vendor/modules.txt`:** vendored:
- `github.com/godbus/dbus/v5`
- `golang.org/x/sys/unix`
- `ryoku-wm v0.0.0 => ../../wm`

**`src/ryoku/shell/ipc/vendor/ryoku-wm/`:** vendor shim tree, 8 files: `action.go`, `binds.go`, `caps.go`, `client.go`, `cursor.go`, `detect.go`, `reclaim.go`, `state.go`.

**`src/ryoku/wm/go.mod`:** module `ryoku-wm`, Go 1.22, requires `BurntSushi/toml v1.6.0`; vendor subdir present.

So the shell-side Go dependency graph is effectively:
- Go stdlib
- `github.com/godbus/dbus/v5`
- `golang.org/x/sys/unix`
- vendored local `ryoku-wm` (replace `../../wm`)
- `ryoku-wm` itself requires `BurntSushi/toml v1.6.0` (also vendored under `src/ryoku/wm/vendor`).

There is no outbound http/net dependency from the shell daemon for holiday fetching — that path is compiled out in `calendar.go`.

**Hub backend** adds:
- `github.com/BurntSushi/toml v1.6.0`
- `github.com/godbus/dbus/v5 v5.2.2`
- `golang.org/x/sys v0.27.0`
- `ryoku-wm v0.0.0` (replace `../../wm`)
- `ryostore v0.0.0` (replace `../../apps/ryostore/backend`)

**`src/ryoku/hub/backend/go.sum`:** 6 lines.

The Go import scan across `ipc/*.go` (non-test) is noisy when done with naïve `rg` because string-literal fragments match; the true import set, file by file, is Go stdlib + `godbus/dbus/v5` + `golang.org/x/sys/unix` + vendored local `ryoku-wm`. Holiday fetch is compiled out in `calendar.go`.

### 3.2 Build environment

- `GOTOOLCHAIN=local`
- `GOFLAGS=-mod=vendor`
- `GOPATH=$PWD/.run/go`
- `GOCACHE=$PWD/.run/go/cache`
- `GOPROXY=off`
- `CGO_ENABLED=0`
- Build: `nice -n 10 go build -trimpath -p 2`
- Nested tests: `dbus-run-session` + nested Hyprland under `systemd-run --user --scope -p MemoryMax=3G -p CPUQuota=200%` when available, else process-group-only.

### 3.3 Shell binaries and `.run/bin`

`src/ryoku/shell/ipc/main.go` is the daemon build entry. It exports the CLI surface:
- `ryoku-shell daemon`
- `ryoku-shell __clip-ingest` (internal `wl-paste --watch` helper)
- `ryoku-shell theme catalog` (standalone, compiled-in catalog)
- `ryoku-shell matugen-preview <path>` (standalone generator; no daemon round trip)
- `ryoku-shell icons ...` (standalone icon index)
- `ryoku-shell browser-host` (WebExtension native-messaging host; standalone; reads `colors.json`)
- `ryoku-shell <command>` (forwards to daemon over socket)

Home guard: the binary derives the expected home from its own executable path and refuses to run if `HOME` is not Tenkai's `.run/home`. A binary copied elsewhere fails closed.

`.run/bin` total ~33MB, 30 entries:
- 4 real binaries:
  - `tenkai-hub` (~10MB)
  - `tenkai-shell` (~9.7MB)
  - `ryogami` (~6.9MB)
  - `tenkai-wm-hyprland` (~6.4MB)
- 1 small shim: `matugen` (4KB)
- 18 tiny stubs (4KB each)
- 7 symlinks to `src/ryoku/shell/scripts/`:
  - `tenkai-app`
  - `tenkai-screenshot`
  - `ryoku-cmd-brightness`
  - `ryoku-app`
  - `ryoku-summon`
  - `ryoku-volume`
  - `ryoku-restart-audio`

Many large ryoku-family stubs exist only to block resolution to live system `/usr/bin` copies.

---

## 4. IPC and daemon surface

### 4.1 Socket and IPC topology

- Socket name: `tenkai-shell.sock`
- Socket path: `XDG_RUNTIME_DIR/tenkai-shell.sock`, falling back to `/tmp/tenkai-shell.sock`.
- Client form: `ryoku-shell <command>` forwards to the daemon over the Unix socket.
- Hyprland keybinds use the client form.

### 4.2 `IpcHandler` / `IpcRouter` topic split

Shell-side `IpcHandler` targets: `shell`, `visualizer`, `keypresses`, `qsbar`.

`IpcRouter` targets: `lifecycle`, `layout`, `tenkai.system-update`, `reactor`, `theme`, `picker`.

Daemon paths used: `shellIpc`, `pillIpc`, `ipcCall`, `ipcCallN`, `dispatch`, `route`, `surfaceCommands`.

### 4.3 `pillSockPath` / `pillIpc`

Retained for tests; dead in production.

### 4.4 Supervised components

In this tree, the in-process consolidated shell is the only supervised component:
- `components` slice = `[{"shell", true}]`
- `supervise` only runs `exec.Command("qs", qsSelect(name)...)` for `name == "shell"`.

---

## 5. Session lifecycle and harness

### 5.1 `cmd_run`

`cmd_run` generates `.run/session.sh`:
- `dbus-run-session`
- nested Hyprland on the host socket only
- ryogami daemon (if `modules.wallpaper != false`)
- `tenkai-shell daemon`

Reject rule: nested `HYPRLAND_INSTANCE_SIGNATURE` must not equal the baseline signature.

Resource cap: `systemd-run --user --scope -p MemoryMax=3G -p CPUQuota=200%` when available, else process-group-only.

### 5.2 `cmd_wallpaper`

Drives `ryogami wallpaper` via `.r/ryogami.sock` with fake-HOME XDG env.

### 5.3 `cmd_test`

Runs the nested acceptance gate (`docs/tests/accept.sh`).

### 5.4 `cmd_verify_untouched`

Re-hashes the watched config/cache trees and re-checks live-session state.

### 5.5 `cmd_verify_prove`

Proves each check can fail with doctored inputs.

### 5.6 `cmd_env_check`

Launches nothing. Runs the session script's own `env -i` scrub and prints resulting environment names plus `command -v` resolution of every inventoried command. Fails on forbidden env names or resolution outside `.run/bin` and the fixed system list. `--prove` injects a fake `ryoku-*` binary on a throwaway PATH and requires the rules to fail, then removes it and requires them to pass.

### 5.7 `cmd_status`

Shows whether a Tenkai test session started by this script is running.

### 5.8 `cmd_stop`

Only signals recorded PIDs whose `/proc/<pid>/cmdline` contains `$TENKAI_DIR`. No name-based killing.

### 5.9 `cmd_accept`

Runs the acceptance gate.

### 5.10 `cmd_wm_seam` / compositor seam usage

The daemon uses the wm seam verbs for: Hyprland `hyprctl eval` script evaluation in `daemon.go`, tray/clipboard/theme workers, stray reaping, window/summon/focus actions, config reload decisions, cursor reassert, and several module enable/disable paths. The seam verbs are compositor-neutral by construction.

---

## 6. Baseline / verify machinery

### 6.1 Watched trees

**Fatal on hash diff:**
- `~/.config/quickshell`
- `~/.config/hypr`
- `~/.config/kitty`
- `~/.config/btop`
- `~/.config/qt6ct`
- `~/.config/gtk-3.0`
- `~/.config/gtk-4.0`

**Warn only:**
- `~/.cache/ryoku`
- `~/.cache/matugen`

These two cache trees are rewritten every few seconds by the live desktop's own music/clipboard/palette/matugen services (owner decision 2026-10-31, revised 2026-11-04). They are WARN only.

Any change under the watched `~/.config` trees, and any changed path outside both the config and cache sets, stays fatal. `verify-prove` shows both halves can fail.

### 6.2 D-Bus ownership attribution

A change of owner PID for a watched well-known D-Bus name is resolved on the bus (`GetNameOwner` → `GetConnectionUnixProcessID`), because `busctl`'s own column prints `-` across PID namespaces.

A change whose new PID is the MainPID of a live systemd user unit is external churn: printed with the unit and WARN.

Any change that cannot be attributed that way is fatal.

Connection IDs (`:1.NNN`) and app-owned names (`steam`, `protonvpn`, `kitty`, `firefox`, …) are ignored. Other process diffs are informational unless `--strict`.

### 6.3 Baseline snapshot set

Real persisted snapshot set is `docs/baseline/` (9 files):
- `config-hashes.sha256` (~952KB)
- `config-symlinks.txt`
- `dbus-names.txt` (~16KB)
- `dbus-watched.tsv`
- `env.txt`
- `new-name-watch.txt`
- `ps-full.txt` (~66KB)
- `quickshell-instances.txt`
- `session-processes.txt`

---

## 7. Settings app and config writing boundary

### 7.1 Keep boundary

Settings app: Appearance + Shell pages only.

### 7.2 Hyprland config write boundary

Settings must never write or generate Hyprland config.

This is enforced by the severed `applyDesktop()` in `src/ryoku/hub/backend/desktop.go`. That function is disabled, not deleted, and currently returns `nil`.

The file explicitly notes:
- `applyDesktop` is the one function that materialises Hyprland config (`settings.lua` / `rebinds.lua` / `user_edits`) and reloads the compositor.
- Tenkai's Settings must never do either.
- The body is preserved in a comment for restoration if ever needed.

A related note in `import_apply.go` (layer writes) documents the importer path: ingested Hyprland binds/rules land in `desktop.json` + a `user.lua` raw block, the provider regenerates the compositor config from `desktop.json`, and `applyDesktop()` is called after writes. In this tree, the import path still exists in code but `applyDesktop()` is severed, so the Settings/Hub config-write boundary the audit cares about is intact.

### 7.3 Settings persistence

Settings persist to Tenkai's own config dir, not to the live session's Hyprland config.

---

## 8. Animations and motion language

The full motion language is kept:
- durations
- easing curves
- transitions
- popout/pill/blob behaviour

Animations are kept centralised so timing can be tweaked in one place. They are never flattened.

---

## 9. Hub backend — kept vs non-kept

### 9.1 What the Hub keeps for Tenkai

For this audit, the Hub keep surface is the Appearance + Shell-backed features that Tenkai keeps:
- desktop/window-manager settings store: `~/.config/ryoku/desktop.json` (single writer)
- live cursor/setLiveCursor/setLiveCursorFromStore path from store
- active palette accent path via `ryoku-hub lighting accent` (shell-side call in `theming.go`)
- icon enumeration through `EnumIcons` with icon roots including `/usr/share/icons` (read-only enum), `X11/xkb/rules` parsing for layouts/variants
- rice/fastfetch emblem reapplications and fastfetch config read/write within Tenkai's own config
- theme/ryogami wallpaper repaint path and `gsettings set org.gnome.desktop.interface font-name`

### 9.2 What the Hub contains but Tenkai does not keep

The Hub backend still contains code for features **not** on the keep list. These are reported as present-but-not-kept:
- GPU passthrough: `gpuhook.go` (modprobe vfio-pci, sysfs writes), `gpuvm.go` (virsh, looking-glass-client, virtio-win.iso paths), `gpumode.go`, `gputune.go` (ryoku-power, nvidia-smi), `gpumux.go` (ryoku-gpu-mux), `gpuapply.go` (pkexec, pacman, ryoku-pkg-aur-add).
- Lighting: `lighting.go`, `lightingfx.go` (openrgb, asusd, qmk; systemctl --user, systemd-run).
- Voxtype: `voxtype.go` (voxtype, systemctl --user, /usr/bin/voxtype symlink note).
- Import/apply: `import_apply.go` (git clone, snapper, luac, hyprland.conf ingest, user.lua writes, fastfetch, fish, generic drop tier), `import_undo.go`.
- Shell preference: `shellpref.go` (usermod, chsh, /etc/passwd, /etc/shells reads).
- Cursor material recolor: `ryoku-cursor-material-recolor` spawned from `desktop.go` save path.
- Fastfetch emblem helpers, rice apply paths, etc.

### 9.3 Real external calls in hub backend (verified)

Hub backend spawns:
- `ryoku-cursor-material-recolor` (desktop.go save path)
- `ryoku-gpu` / `tenkaiGpuBin()`
- `git clone`
- `snapper`
- `luac`
- `ffmpeg`
- `voxtype`
- `systemctl`
- `modprobe`
- `openrgb`
- `systemd-run`
- `hyprctl eval` / `hyprctl binds`
- `looking-glass-client`
- `virsh`
- `ryoku-idle`
- `ryoku-gpu-mux`
- `ryoku-pkg-aur-add`
- `pacman -S/-Si/-Q`
- `usermod`
- `pkexec`
- `fastfetch`
- `rsvg-convert` / `magick` / `convert`
- `tenkai-shell theme` / `tenkai-shell gkt`
- `ryogami wallpaper repaint`
- `gsettings set org.gnome.desktop.interface font-name`

Many of these live in features not on the keep list. The audit must not collapse that distinction.

---

## 10. QML services, singleton surface, and sidecar processes

### 10.1 Singleton surface

`services/qmldir` declares 52 singletons, including:
- `ShellState`, `ServiceLoader`, `Theme`, `Scheme`, `Config`, `Motion`, `Perf`, `Media`, `Music`, `AudioBars`, `Recorder`, `Battery`, `Network`, `Nightlight`, `Notifs`, `Audio`, `Equalizer`, `Tray`, `Dock`, `DockPreview`, `MusicPreview`, `BarProducts`, `Devices`, `Weather`, `Updates`, `Camera`, `Keypresses`, `Toggles`, `VoiceBars`, `Capture`, `Clipboard`, `Events`, `Holidays`, `Flags`, `Keyring`, `Idle`, `KeyboardLayout`, `OsdFeed`, `Polkit`, `PowerProfiles`, `Session`, `SessionActions`, `Stash`, `Sysinfo`, `BluetoothDiscovery`, `BtLink`, `ScreenTime`, `Needle`, `StatsFeed`, `AppLaunch`, `Icons`.

### 10.2 Service files present

51 `services/*.qml` files, including `ServiceLoader.qml`, `Theme.qml`, `Config.qml`, `AudioBars.qml`, `AppLaunch.qml`, `Audio.qml`, `Devices.qml`, `Capture.qml`, `Recorder.qml`, `Equalizer.qml`, `Icons.qml`, `VoiceBars.qml`, `ScreenTime.qml`, `Events.qml`, `BtLink.qml`, `Camera.qml`, `Tray.qml`, `Network.qml`, `Nightlight.qml`, `Keyring.qml`, `PowerProfiles.qml`, `Music.qml`, `Idle.qml`, `Holidays.qml`, `Updates.qml`, `Session.qml`, `Media.qml`.

There are duplicate theme-related singletons referenced across desktop/overview/wallpaper/visualizer stage `Config.qml` files — a duplication worth noting rather than silently "fixing".

### 10.3 `shell.qml` surface

`shell.qml` imports:
- `shell.services`
- `modules/{visualizer,stage,wallpaper,desktop,visualizer,bar,controlcenter,dock,launcher,overview,clipboard,osd,notifications,capture,confirm}`
- `Ryoku.Ui.Singletons`
- `QtQuick`, `Quickshell`, `Quickshell.Io`, `Quickshell.Wayland`
- module singletons: `VizCfg`, `StageCfg`, `WallCfg`

It uses `LazyLoader` for dock/launcher/overview/clipboard/osd/capture/camera/keypress/confirm, plus `ServiceLoader` and `Process` (cava, wallpaper).

### 10.4 Process/execDetached call sites (verified span)

Process/execDetached call sites were captured across:
- `shell.qml`
- `AudioBars.qml` (Process cava)
- `AppLaunch.qml` (tenkai-app)
- `Audio.qml` (pactl)
- `Devices.qml` (ddcutil/brightnessctl/ryoku-hw-backlight/nvibrant)
- `Capture.qml` (grim/wl-copy/tenkai-shell clip-copy)
- `Recorder.qml` (slurp/kill/ryoku-cmd-screenrecord/studiorecord/discord-compress/edit-recording)
- `Equalizer.qml` (ryoku-eq get)
- `Icons.qml` (tenkai-shell icons)
- `VoiceBars.qml`, `ScreenTime.qml`, `Events.qml`, `BtLink.qml`, `Camera.qml` (mkdir and related)

Several services reach the daemon via `tenkai-shell.sock`: `Tray.qml`, `Network.qml`, `Nightlight.qml`, `Keyring.qml`, `PowerProfiles.qml`, `Music.qml`, `Idle.qml`, `Holidays.qml`, `Updates.qml`, `Session.qml`, `Media.qml`.

### 10.5 Tray — no trayxd here

This tree has **no** trayxd client or server. There is no `src/ryoku/shell/trayxd/` directory.

The system tray path is:
- `src/ryoku/shell/ipc/tray.go` — Go StatusNotifierWatcher implementation, StatusNotifierItem registration, dbusmenu tree walking, icon resolution, tray item activation/context menu/scroll/menu events.
- `src/ryoku/shell/quickshell/shell/services/Tray.qml` — QML singleton that subscribes to the daemon `tray` topic over `tenkai-shell.sock` and exposes click intents back to the daemon.

`Tray.qml` imports only `QtQuick`, `Quickshell`, `Quickshell.Io`. It does not import or reference any trayxd binary. Tray icon resolution is the Go precedence chain in `resolveTrayIcon`: item-supplied `icon_theme_path` → ambient theme name → nearest ARGB pixmap converted to RGBA → generic `application-x-executable-symbolic` fallback. The ARGB→RGBA conversion is pure Go `image` + `image/png` code with no external imaging library at that site.

There is a tray-symbolic.svg asset (`components/icons/tray-symbolic.svg`) and several tray-facing QML panels in the bar styles (TrayPanel, TrayMenu, TrayWidget, RailTray, TrayFlyout), but none of those pull in a trayxd client.

---

## 11. Audio, brightness, network, battery, notifications

### 11.1 Audio

- `audiowatch.go` uses `pactl list sink-inputs` and `pactl subscribe`.
- `control.go` drives `wpctl` for per-edge bar toggle and mute toggles.
- Audio bars in `AudioBars.qml` run `Process cava`.
- There is **no** `libpulse-simple` / `pa_simple` / direct Pulse connect in `ipc/*.go` or in the vendored `ryoku-wm` shim. Audio daemon code uses `pactl`/`wpctl` as CLI tools, not a linked Pulse client library.

### 11.2 Brightness

- `control.go` drives `ryoku-cmd-brightness`.
- `osd.go` reads `ryoku-hw-backlight`.
- `Devices.qml` reaches brightnessctl/ddcutil/ryoku-hw-backlight/nvibrant.

### 11.3 Network

- `network.go` uses `nmcli` + D-Bus.

### 11.4 Battery

- Battery surface present in the keep list and in the singleton/BarProducts module tree. No special external bridge beyond the daemon topic.

### 11.5 Notifications

- Notifications surface present in the keep list; `Notifs.qml` and the daemon notification path reach the daemon via `tenkai-shell.sock`.

---

## 12. System and project scripts

### 12.1 Project scripts (7, under `src/ryoku/shell/scripts/`)

- `ryoku-app` — zen/kitty/nautilus fallbacks, `jq`, `notify-send`
- `ryoku-cmd-brightness` — brightnessctl/ddcutil/flock/ddcutil detect
- `ryoku-restart-audio` — ryoku-host svc/timeout/wpctl/usbreset/sudo
- `ryoku-summon` — tenkai wm act window.summon
- `ryoku-volume` — wpctl
- `tenkai-app` — jq, kitty fallback, TENKAI_APP_HOME live-env handoff
- `tenkai-screenshot`

### 12.2 System tools list

`TENKAI_SYSTEM_TOOLS` in the control script enumerates the ordinary system tools the kept QML, Go daemons, project scripts, and session script spawn. Each must resolve inside `.run/bin` or the fixed system list under `env-check`.

The list includes, among others: Hyprland, bash, basename, brightnessctl, busctl, cat, chmod, chown, cliphist, comm, cp, curl, cut, date, dbus-daemon, ddcutil, df, diff, dirname, env, ffmpeg, file, find, flock, foot, fprintd-list, git, gsettings, grep, grim, head, hyprctl, id, jq, kill, kitty, ln, ls, makoctl, magick, mkdir, modinfo, modprobe, nice, nl, notify-send, nvidia-smi, openrgb, awk, pacman, pactl, paste, pgrep, pkg-config, pkexec, printf, ps, python3, qs, quickshell, rsvg-convert, sed, seq, setsid, sh, snapper, sort, strip, systemctl, tail, timeout, touch, tr, true, uname, uniq, usermod, virsh, voxtype, wc, wl-copy, wl-paste, wpctl, xargs, xdg-open, yes, zenity, playerctl, nmcli, rfkill, qmk_hid, slurp, systemd-run, fastfetch, luac, gpk, python3, diff, realpath, readlink, sha256sum, sleep.

A name that is simply not installed reports MISSING and does not fail the check, because the call sites handle absence. A name that resolves somewhere disallowed always fails.

### 12.3 Tenkai-owned and shadow names

Tenkai-owned names: `tenkai-shell`, `tenkai-hub`, `tenkai-wm-hyprland`, `ryogami`, `tenkai-app`, `tenkai-screenshot`, `ryoku-cmd-brightness`, `ryoku-app`, `ryoku-summon`, `ryoku-volume`, `ryoku-restart-audio`, `matugen`.

Shadow names: the live system's `/usr/bin` has a real program for each ryoku-family name Tenkai does not own, so `.run/bin` must carry an inert stub for it instead.

### 12.4 Ryoku-family names

The tenkai-family name sweep across kept QML/Go/project scripts (excluding vendor and tests) catches:
- the full `ryoku*`/`ryogami*`/`ryostore*`/`ryostage*` name set used by exec.Command/Process command arrays/execDetached
- the two bare-name fallbacks used when `TENKAI_SHELL_DIR` is empty: `services/Equalizer.qml:21` and `modules/stage/…/StageBackend.qml:16`
- `ryoku-eq` and `ryostage` from the bare-name fallback references

---

## 13. Component classification A–H

The classification below is per-component, using the keep list verbatim. Where a component is kept, state the keep reason, RAM/CPU cost where known, and the process/daemon it spawns. Where it is excluded or optional, state that and how to opt back in.

### A. qsbar / top bar

**Classification:** Kept.

**Evidence path:** `src/ryoku/shell/quickshell/shell/modules/bar/`, barstyles, framebars, panel, popouts; shell.qml imports `modules/bar` and `modules/controlcenter`.

**What it does in this tree:** the bar module drives the top bar surface and style variants; bar-side tray widgets exist in barstyles/qsbar and kairos. qsbar carries thumbnail-heavy carousels (MediaBrowserPanel/Carousel/Hearthstone, ImageCarouselPanel/Carousel/Hearthstone) that use `bash -c … ffmpegthumbnailer … / magick …`.

**Why kept:** top bar is on the keep list.

**Cost:** resident shell surface cost; bar-on sessions keep one control centre hosted by the bar; bar-off sessions keep the control centre as its own surface host via LazyLoader.

**Note:** the thumbnailing carousels are a candidate perf/security hotspot to call out explicitly; no measurement has been taken yet in this tree, so it must be marked UNVERIFIED until measured.

### B. workspaces

**Classification:** Kept.

**Evidence path:** workspaces/seam verbs in `wm` and the shell's workspace state; Hyprland-compositor seam usage in the daemon.

**Why kept:** workspaces is on the keep list.

**Cost:** in-process shell state cost; seam verbs are compositor-neutral.

### C. launcher

**Classification:** Kept.

**Evidence path:** `modules/launcher` in shell.qml; launcher variants; `AppLaunch.qml` via tenkai-app; `tenkai-app` project script.

**Why kept:** launcher is on the keep list.

**Spawns:** `tenkai-app` script (jq, kitty fallback, TENKAI_APP_HOME live-env handoff).

### D. control sidebar / quick settings

**Classification:** Kept.

**Evidence path:** `modules/controlcenter`; `ControlCenterHost` in shell.qml; bar styles carry the same panel when the bar is on.

**Why kept:** control sidebar / quick settings is on the keep list.

**Cost:** control centre is built only when the bar is off; with the bar on, the same panel is hosted by the bar, so exactly one control centre exists.

### E. clock/date

**Classification:** Kept.

**Evidence path:** clock/date surface is part of the keep list; present in the bar/control centre style surfaces.

**Why kept:** clock/date is on the keep list.

### F. audio

**Classification:** Kept.

**Evidence path:** `Audio.qml`, `AudioBars.qml`, `Equalizer.qml`, `audiowatch.go`, `control.go`.

**Why kept:** audio is on the keep list.

**Spawns:** `pactl` (audiowatch), `wpctl` (control), `cava` (AudioBars Process), `ryoku-eq` get (Equalizer bare-name fallback).

**Cost:** `pactl subscribe` event-stream cost; periodic re-check when pactl absent.

### G. brightness

**Classification:** Kept.

**Evidence path:** `Devices.qml`, `control.go`, `osd.go`, `ryoku-cmd-brightness`, `ryoku-hw-backlight`.

**Why kept:** brightness is on the keep list.

**Spawns:** `ryoku-cmd-brightness`, brightnessctl/ddcutil/ryoku-hw-backlight/nvibrant paths.

### H. network, battery, system tray, notifications, wallpaper selector + matugen theming

**Classification:** Kept (all on the keep list).

**Network:**
- Evidence: `Network.qml`, `network.go` (nmcli + D-Bus).

**Battery:**
- Evidence: battery surface in keep list; present in singleton/BarProducts module tree.

**System tray:**
- Evidence: `tray.go` StatusNotifierWatcher + dbusmenu + icon resolution + `Tray.qml` singleton; no trayxd binary in this tree.
- Why kept: system tray is on the keep list.
- Note: trayxd-free path is what this tree actually runs. Any claim that trayxd is part of this build is wrong for this checkout.

**Notifications:**
- Evidence: notifications surface in keep list; daemon notification path over `tenkai-shell.sock`.

**Wallpaper selector + matugen theming:**
- Evidence: `modules/wallpaper`; `ryogami` daemon + wall-ui; `matugen/` config + 27 templates; `src/ryoku/shell/ryogami/wall-ui/data/matugen/templates/` (14 files); matugen shim in `.run/bin` enforcing TENKAI config only.
- Why kept: wallpaper selector + matugen theming is on the keep list.
- Kat: shim refuses live `~/.config/matugen` path; Tenkai seeds only the kitty template of the matugen output set.

---

## 14. Settings app (Appearance + Shell only)

### 14.1 Classification

**Classification:** Kept, scoped to Appearance + Shell pages.

**Evidence path:** Hub backend desktop store + theme/rice/import surfaces; `applyDesktop()` severed.

**Why kept:** Settings app Appearance + Shell pages are on the keep list.

**What is kept:** desktop/wm store (`desktop.json`), cursor theme/size from store, active accent via `ryoku-hub lighting accent`, icon enum, fastfetch emblem/config within Tenkai's config, theme/ryogami repaint and gsettings font.

**What is explicitly excluded:** Settings must never write or generate Hyprland config. `applyDesktop()` is disabled (returns `nil`) rather than deleted; its body is preserved in a comment for restore.

**Persistence:** settings persist to Tenkai's own config dir.

**Note:** the duplicate theme singletons across desktop/overview/wallpaper/visualizer stage `Config.qml` are a duplication to record, not a defect to silently fix.

---

## 15. Animation and motion language (kept, centralised)

**Classification:** Kept, centralised, never flattened.

**Evidence path:** `Motion.qml` singleton; `shell.qml` import of `modules/visualizer`, `modules/stage`, and `Ryoku.Ui.Singletons`; per-frame spring and scene-graph MultiEffects for menu glass blur and blobs; `QS_DROP_EXPENSIVE_FONTS` and render-loop pragmas.

**Why kept:** animations are on the keep list and must not be flattened.

---

## 16. Not started — Phase 16 cleanup

**This phase is NOT started.**

No cleanup, disabling, renaming, deletion, or opt-in enabling has been performed in this turn or this audit write-up. The report stops here for explicit owner approval before any Phase 16 work.

If the owner approves Phase 16, the next step is to review this report's explicit "optional/disabled" and "duplicate" notes, trace each proposed change with a file-level dependency trace, prefer disabling over deleting, and commit after every phase.

---

## Appendix A. Stale-reference conditions to flag

- `tenkai-configs/` and `tenkai-assets/` are empty in this checkout; several docs memos reference them as though they hold real persisted sets. The real persisted snapshot set is `docs/baseline/`.
- `src/ryoku/scripts/` does not exist in this checkout; the real Tenkai-owned project scripts are the 7 files under `src/ryoku/shell/scripts/`. Earlier references to a "4 project scripts" surface are stale.
- AGENTS.md lives at repo root; there is no `docs/STATUS.md`, `docs/PARITY.md`, or `docs/AGENTS.md` in this checkout.

## Appendix B. What this audit did not do (honesty markers)

- No live-session measurement of 144 Hz smoothness or real GPU behaviour; those go to the owner via `docs/LIVE-TEST.md`. Nested testing cannot prove those.
- No measurement yet of the qsbar thumbnail carousel perf/security cost; marked UNVERIFIED.
- No new app built, no new dependency added, no file deleted or renamed in this audit write-up.
- No claims of "works" or "lightweight" without either a test or a clear UNVERIFIED marker.

---

## Appendix C. How to opt back in

For each excluded/optional item, the opt-back-in path is:

- trayxd-based tray: add the trayxd client/server sources and build steps to the project and re-point the tray surface at them. This tree currently has none.
- any hub feature not on the keep list (GPU passthrough, voxtype, openrgb, import/qmk, asusd, fastfetch importer, shellpref, etc.): these are present in the Hub backend code but not kept by Tenkai's Settings/app scope; re-enabling is a keep-list expansion decision, not a bug fix.
- hub `applyDesktop()` restore: return the documented body in `src/ryoku/hub/backend/desktop.go` (and related reload paths), then re-evaluate the Settings→Hyprland write boundary against the keep list. This is intentionally disabled now.

---

## Next step from here

I have written `ARCHITECTURAL_AUDIT.md` and stopped before Phase 16. If you want to proceed, tell me what Phase 16 cleanup/disable/rename you want to attempt, and I will do it with file-level dependency traces and commits per phase — and only after your explicit approval.
