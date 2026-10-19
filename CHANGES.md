# CHANGES.md — modifications vs upstream Ryoku

Pinned upstream: see `UPSTREAM.md`. Mei is built by copying and adapting upstream files into
`src/`; every modification is recorded here, newest first.

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
