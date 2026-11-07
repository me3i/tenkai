# AGENTS.md — Tenkai (reduced Ryoku shell, personal build)

Tenkai is a reduced, modular, standalone shell built by **copying and trimming the real
upstream Ryoku source** (https://github.com/Ryoku-dev/ryoku). It must run on the owner's
existing Arch + Hyprland session (user `mei`). Priorities, in order:

1. Visual quality and animations, 2. reuse original code, 3. works independently on the
existing system, 4. strict no-bloat reduction, 5. modular, 6. measured performance.

## Layout

- `upstream/` — the original Ryoku source (if cloned). **READ-ONLY. Never edit.** It was
  removed in Phase 17 to save space; clone it again if you need to reference the original source.
- `src/` — the Tenkai tree (copies/adaptations from that source live here).
- `docs/` — install/verify runbooks: `LIVE-CHECKLIST.md`, `LIVE-TEST.md`, `MODULES.md`,
  `ROLLBACK.md`, `revert-to-previous-shell.sh`, `tests/`, `baseline/` snapshots (not tracked).
- `tenkai` — control script (`baseline`, `verify-untouched`, `status`, `run`, `stop`, `test`).
- `.run/` — all runtime state: XDG overrides (`config/`, `cache/`, `state/`, `data/`), Go dirs
  (`go/`), sockets, pids. Git-ignored. **Deleting `~/projects/tenkai` must be a complete rollback**;
  nothing Tenkai-related may live elsewhere.

## Non-negotiable safety rules

1. Nothing outside `~/projects/tenkai` may be created, modified or killed by anything Tenkai-related.
   Never touch `~/.config/quickshell`, `~/.config/hypr`, autostart entries, or the live session.
2. No sudo, no installs, no system-wide changes. Before any install, list the exact commands
   and wait for explicit approval.
3. Never run Ryoku installer/distro tooling (`cli/`, `installation/`), never enable systemd
   units, never add keybinds to the real Hyprland config, never change startup entries.
4. Live-session isolation: Tenkai never runs in the owner's live session during development.
   Tests run only in a nested Hyprland window launched inside `dbus-run-session` with Tenkai's own
   config. `./tenkai test` must refuse to start if the nested `HYPRLAND_INSTANCE_SIGNATURE` equals
   the baseline one. Every `hyprctl` call in tests targets the nested instance explicitly.
5. Process safety: never `pkill`/`killall`/`qs kill` by name. `./tenkai` records the PIDs it
   started in `.run/pids`; `./tenkai stop` only signals recorded PIDs whose `/proc/<pid>/cmdline`
   contains `$TENKAI_DIR`.
6. Resource caps: test sessions under `systemd-run --user --scope -p MemoryMax=3G
   -p CPUQuota=200%` when available, else `nice`/`ulimit`. Compile with `nice -n 10` and `-j2`;
   Go/C++ builds only inside the project.
7. Shared hardware: audio and brightness act on real hardware — small steps, restore original
   values. Network is read-only status. Suspend/poweroff/reboot/logout/lock are stubbed in test
   mode. Notification/tray tests fire inside the nested session only.
8. After every test run `./tenkai verify-untouched`; it must PASS (live config hashes identical to
   `docs/baseline/`).
9. Nested testing cannot prove 144 Hz smoothness or real GPU behaviour — those go to the owner
   via `docs/LIVE-TEST.md`. Never start a second shell in the real session, never run a
   live-session test.

## Necessity test (applies to every component)

Keep a component only if **(a)** it is on the keep list below, or **(b)** a kept component
cannot function without it, **proven with a file-level dependency trace**. For each kept item
record: why it is needed, RAM/CPU cost, and the process/daemon it spawns. If in doubt, leave it
**OFF** and list it as "optional, disabled". Report every exclusion so the owner can opt back in.

## Keep list (initial — each must still pass the code-level check in Phase 1–3)

- Top bar (qsbar), workspaces, launcher, control sidebar / quick settings, clock/date, audio,
  brightness, network, battery, system tray, notifications.
- Wallpaper selector + matugen theming.
- `ryoku-shell` Go daemon, trimmed to the components Tenkai keeps.
- **Animations**: full motion language (durations, easing curves, transitions, popout/pill/blob
  behaviour), kept centralised so timing can be tweaked in one place. Never flattened.
- **Settings app**: reuse Ryoku Settings' look and UI framework, but only Appearance and Shell
  pages. **Settings must never write or generate Hyprland config** (disable hub `settings.lua`
  generation and every hypr write). Tenkai reads Hyprland state only. Settings persist to Tenkai's own
  config dir.

## Workflow

- Work phase by phase (see `docs/`); **STOP for approval** where the owner marked it
  (Phase 3 review, Phase 5 before installs/destructive changes).
- Copy and adapt from the original Ryoku source (if cloned); never regenerate components
  "from scratch". Trace
  dependencies before removing; prefer disabling over deleting. Rename/de-brand only where
  needed; keep attribution and upstream notices.
- Commit after every phase, with a message stating what changed and how it was verified.

## Honesty / reporting rules

- Never claim "works" or "lightweight" without a test or measurement. Mark every result
  **TESTED** or **UNVERIFIED** (and nested vs live).
- Cite real file paths for every claim. Mark guesses "uncertain".
- Record excluded things and how to opt back in.

## Licensing

Keep upstream notices; maintain `CHANGES.md` (modifications vs upstream) and `UPSTREAM.md`
(repo URL + pinned commit). Flag any redistribution obligations in Phase 3.
