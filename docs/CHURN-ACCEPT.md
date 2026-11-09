# Churn Acceptance — Tenkai External Churn

## Evidence
Lsof audit run during idle session (30s after launch, launcher closed):

- `lsof +D ~/.cache/ryoku/` → empty (no Tenkai PIDs have open files in live ryoku cache)
- `lsof +D ~/.config/ryoku/` → empty (no Tenkai PIDs have open files in live ryoku config)
- Tenkai PIDs (ryogami daemon, tenkai-shell daemon) have files open ONLY in:
  - `~/.run/bin/` (binaries)
  - `~/.run/logs/` (log files)
  - `~/.run/state/` (state)
  - socket files in `/home/mei/projects/tenkai/.r/`

## External churn accepted
The following directories are read-only for Tenkai:
- `~/.config/quickshell/` — live ryoku shell config (read at startup via ryogami.sock IPC)
- `~/.cache/ryoku/` — live ryoku cache (read-only during session; wall-ui kill means no writes)
- `~/.config/hypr/` — live Hyprland config (read-only state queries via hyprctl)
- `/run/user/1000/` — live session runtime (WAYLAND_DISPLAY is NOT handed down; Tenkai uses its own nested compositor)

## Tenkai's own churn
Tenkai writes to its own `.run/` directory only:
- `.run/logs/` — session/damon/hyprland logs
- `.run/state/` — state (sockets, pid files)
- `.run/config/` — forced XDG config override

## Wallpaper
The wallpaper (1004017-colorized.png) is rendered via Desktop.qml Backdrop (in-shell Image)
with ryogami daemon publishing to ryogami.sock. No wall-ui picker runs. No hyprpaper/swaybg.
The wallpaper file is in `~/.cache/ryoku/wallpaper/` but is only READ by Tenkai; no writes.

## Verification
Run `./mei verify-untouched` (or equivalent) after every test run to confirm:
- Live config hashes are unchanged from `docs/baseline/`
- No new files created in live session directories
- No processes spawned in live session (except the nested test env)

## Rollback
Delete `~/projects/tenkai/` for complete rollback. Nothing Tenkai-related lives elsewhere.
See `docs/ROLLBACK.md`.
