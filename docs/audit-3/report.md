# Audit-3 report

Date: 2026-11-12. Branch: `audit-3/gestures-fish-scale-followups` (no push).

## Result

| request | finding | status |
|---|---|---|
| 3-finger workspace swipe | brief's `workspace_swipe*` options removed in Hyprland 0.57 | implemented with `hl.gesture`, live + repo |
| fish as login shell | already the passwd shell; but PATH had a quoted-tilde bug | fixed PATH live + repo, no chsh |
| force scale 1.00x | autoscale DPI buckets chose 1.5 | helper pinned to 1.0, live monitor at 1, cursor zoom 1 |
| audit-2 followups | no UI controls for two settings; unverified items; retry audit | documented, no new code where none was provable |
| suite | 18 checks | 0 failures |

## Changes

1. `src/tenkai-configs/hypr/modules/gestures.lua` (new) — `hl.gesture` with
   3 fingers/horizontal/workspace plus the six tuning knobs.
2. `src/tenkai-configs/hypr/hyprland.lua` — requires `modules.gestures` after
   `modules.touchpad`.
3. `src/tenkai-configs/hypr/modules/misc.lua` — `cursor.zoom_factor = 1.0`.
4. `src/tenkai-configs/hypr/scripts/tenkai-monitor` — `dpiscale()` returns
   `1.0`; autoscale no longer produces 1.25–2.0.
5. `src/tenkai-configs/terminal/fish/config.fish` — unquoted `~/.local/bin`
   so fish expands it.
6. `tests/run-all.sh` — `static/fish-config-valid`, `runtime/gestures-enabled`,
   `runtime/scale-is-1`; banner audit-3.
7. `docs/audit-3/` — preflight, gestures, fish, scale, followups, report,
   unverified, persistence block.

No source outside these areas was changed; no settings UI was invented.

## Test suite

Final run: **18 checks, 0 failures**, exit 0. Evidence in
`tests/evidence/<timestamp>/` (run `20261112-051148`).

The suite reloads Hyprland config; that clears the runtime-only `eval` state.
The gesture knobs and cursor zoom were therefore reapplied **after** the last
suite run and verified again (`set: true`, no config errors, monitor scale 1).
This is exactly why the gesture module must be installed for persistence; see
`gestures.md`.

| check | result |
|---|---|
| static/shell-scripts-parse | PASS |
| static/json-parse | PASS |
| static/go-build | PASS |
| static/qml-lint | PASS |
| static/scrub-check | PASS |
| static/no-personal-strings | PASS |
| static/no-ryoku-imports | PASS |
| static/no-ryoku-namespaces | PASS |
| static/referenced-docs-exist | PASS |
| static/fish-config-valid (new) | PASS |
| bootstrap/idempotent | PASS |
| autostart/idempotent | PASS |
| runtime/shell-starts-clean | PASS |
| runtime/workspace-switch-via-bar-pill | PASS |
| runtime/settings-apply-5-keys | PASS |
| runtime/icons-all-resolve | PASS |
| runtime/gestures-enabled (new) | PASS |
| runtime/scale-is-1 (new) | PASS |

`runtime/gestures-enabled` checks the live knobs (`set: true`) and the absence
of config errors. It cannot construct `hl.gesture`, introspect gesture
registration, or press a key; the physical swipe stays UNVERIFIED.

> Errata (audit-4): this paragraph originally claimed the test also proved the
> constructed `hl.gesture` call succeeds. The test never made that call.
`runtime/scale-is-1` fails on any monitor scale ≠ 1.0 or cursor zoom ≠ 1.0.

## Live repairs (with backups)

- Gestures applied with `hyprctl eval` (`hl.gesture`, `hl.config`); live knobs
  all `set: true`, `hyprctl configerrors` empty. `hyprctl keyword` does not work
  under this Lua config manager ("unknown request").
- Monitor eDP-1 set to scale 1 (1920x1080@144 preserved); `cursor:zoom_factor`
  set to 1.0.
- Installed the fixed `tenkai-monitor` to `~/.config/hypr/scripts/`
  (`tenkai-monitor.pre-audit3.bak`) and ran `autoscale` once: it kept eDP-1 at
  scale 1 and generated `~/.config/hypr/monitors.lua` (did not exist before;
  the helper's normal generated output, not a hand edit). Its reload cleared
  the runtime-only gesture/zoom eval state; both were reapplied and re-verified.
  Gesture/zoom persistence still requires installing the repo modules.
- Fixed the live fish config PATH
  (`config.fish.pre-audit3.bak`); `fish -n` passes.
- Did **not** write `~/.config/hypr` config modules/keybinds, did not run
  `chsh`, and did not touch `QT_SCALE_FACTOR`/`GDK_SCALE`/`GDK_DPI_SCALE`.

## Known gaps

See `unverified.md`: physical swipe, Super+N key event, the two settings with no
UI control, gesture persistence until the module is installed, TTY1, manual
scale profiles, and no visual screenshot.
