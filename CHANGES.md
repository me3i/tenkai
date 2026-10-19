# CHANGES.md — modifications vs upstream Ryoku

Pinned upstream: see `UPSTREAM.md`. Mei is built by copying and adapting upstream files into
`src/`; every modification is recorded here, newest first.

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
