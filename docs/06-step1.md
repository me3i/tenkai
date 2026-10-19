# Phase 6 step 1 — bar + workspaces (nested)

Status: **step 1 complete and stopped here for review.** No launcher, control
sidebar, notifications, Settings, wallpaper menu, or matugen re-theming yet.

## What was built

| Artifact | Path | Source |
|---|---|---|
| Shell QML | `src/ryoku/shell/quickshell/shell/` | upstream `ryoku/shell/quickshell/shell` |
| Plugin kit QML | `src/ryoku/shell/quickshell/plugins/kit/` | upstream `…/plugins/kit` |
| Design system | `src/ryoku/ui/` | upstream `ryoku/ui` |
| Frame-bar schema | `src/ryoku/shell/framebars/` | upstream `ryoku/shell/framebars` |
| WM module + provider | `src/ryoku/wm/` | upstream `ryoku/wm` |
| Daemon | `src/ryoku/shell/ipc/` | upstream `ryoku/shell/ipc` (tests stripped) |
| Blobs plugin | `src/ryoku/shell/plugin/` | upstream `ryoku/shell/plugin` |
| matugen config | `src/ryoku/shell/matugen/config.toml` | reduced to `[config]` only |

Built offline (vendored deps, `nice -n 10`, `-p 2`):

- `.run/bin/mei-shell` — daemon (15.6 MB)
- `.run/bin/mei-wm-hyprland` — compositor provider (6.7 MB)
- `.run/qml/Ryoku/{Ui,FrameBars,PluginKit,Blobs,Wm/Hyprland}` — QML modules
  assembled from `src/` + `.run/build/blobs`.

## Modifications vs upstream (all recorded in `CHANGES.md`)

1. **Rename table** (`RYOKU_*` → `MEI_*`, `ryoku-shell.sock` → `mei-shell.sock`,
   `~/.config|cache|state/data/…/ryoku` → `…/mei`, provider binary
   `ryoku-wm-<name>` → `mei-wm-<name>`, hub lock out of `/tmp` into
   `$XDG_RUNTIME_DIR`). Deliberately **not** renamed: `Ryoku.*` QML module URIs,
   D-Bus names, font names, `ryogami`.
2. **Daemon bootstrap trimmed** (`src/ryoku/shell/ipc/daemon.go`): only
   settings, tray, music-topic, network (system-bus read), nightlight (state
   write only), paint worker, matugen knobs, WM watch, and the shell component.
   Removed: weather/updates/calendar HTTP, keypress (`/dev/input`), clipboard,
   polkit agent, session, power sounds, sleep/wake, auto power saver, leds/hub,
   ryogami, stage.
3. **Hyprland write capabilities cut** (`src/ryoku/wm/hyprland/caps.go`):
   `CapLiveConfigEval`, `CapConfigReload`, `CapPaletteBorder` removed.
4. **Provider event-socket fallback** (`src/ryoku/wm/hyprland/watch.go`): if
   `.socket2.sock` is absent, poll `hyprctl` at 500 ms. Needed only for nested
   tests (see Finding 1); the live session keeps the event-driven path.
5. **Desktop widget layer disabled** (`shell.qml`): `active: false`,
   `widgetsEnabled: false`. Off-list (not in the keep list); re-enable by
   flipping the two flags.
6. **Hub lock** (`src/ryoku/shell/ipc/control.go`) moved from `/tmp` to
   `$XDG_RUNTIME_DIR/mei-hub.lock`.

## Confinement (every nested run)

- fake `HOME` = `.run/home`, XDG dirs = `.run/{config,cache,state,data,rt}`.
- private D-Bus (`dbus-run-session`).
- nested Hyprland config `.run/hypr/nested.conf` (hyprlang `.conf`; verified
  accepted by 0.56.2).
- `systemd-run --user --scope -p MemoryMax=3G -p CPUQuota=200%` wrapper.
- `./mei stop` signals only recorded PIDs whose `/proc/<pid>/cmdline` contains
  the project path.
- refusal: `session.sh` compares the **nested** signature against the baseline
  and exits before starting the daemon/shell if they are equal.

## Findings

1. **Hyprland's event socket was silently disabled** in the nested session:
   `$XDG_RUNTIME_DIR/hypr/<sig>/.socket2.sock` was 111 bytes, over the 107-byte
   UNIX limit (Hyprland log: `Socket2 path is too long. (2) IPC will not work.`).
   Every directory under `.run/` is too long (project path alone is 22 chars,
   signature is 61). Fixed by exposing `.run/rt` through the short symlink
   `.r` for the child's `XDG_RUNTIME_DIR` (106 bytes) plus the poll fallback.
   **This does not affect the live session**, whose runtime dir is
   `/run/user/1000`.
2. The host **rebooted at 16:29** (kernel 7.2.9 → 7.2.11) during this phase.
   Config hashes were unchanged; the baseline was re-captured (see
   `CHANGES.md`). Hyprland 0.56.2-4 / Quickshell 0.3.2-1 / Qt 6.12.0 did not
   change.

## Test result (`./mei test`, exit 0)

| Check | Result |
|---|---|
| `verify-untouched` before launch | **PASS** |
| guard: nested signature ≠ live baseline | **TESTED** |
| bar renders (layer surfaces mapped) | **TESTED** — `ryoku-frame`, `ryoku-frame-edge`, `quickshell` |
| shell QML log: no load/type errors | **TESTED** |
| workspaces match nested compositor | **TESTED** — nested 3 / daemon topic 3 (one run); 1/1 (another) |
| multi-workspace cells + active pill moves | **TESTED manually** — 5 cells, pill moved 5 → 2 (`.run/shots/`) |
| animations visible | **UNVERIFIED** — a still capture cannot show motion |
| daemon up | **TESTED** |
| zero outbound TCP from Mei PIDs | **TESTED** |
| clean shutdown, no stray processes | **TESTED** |
| `verify-untouched` after launch | **PASS** |

Expected nested-session noise (not errors): PipeWire/Pulse unavailable (the
fake runtime dir has no audio socket), portal registration, and unbuilt
off-list helpers (`ryoku-shell icons`, `ryostage`, `ryoku-eq`).

## What to look at in the nested window

- Top bar: wordmark, workspace cells, audio, clock/date, tray.
- `SUPER+1` / `SUPER+2` / `SUPER+3`: the active pill should move between cells.
- Check the **real** bar and notifications for the first minute of a nested
  run; if they flicker or restart, stop and report exactly what was seen.

## Still open / next step

- Wordmark still reads **RYOKU** (upstream brand). Decide whether Mei rebrands
  it to MEI; not changed unilaterally.
- `NotificationPanel` still probes the foreign
  `~/.cache/qs-rise-notifications.json`; removal is in the notifications step.
- Reduce the copied module tree once imports are proven (currently the full
  shell tree is present, with off-list surfaces disabled rather than deleted).
- Step 2 (launcher) not started.
