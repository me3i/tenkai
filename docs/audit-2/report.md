# Audit-2 report

Date: 2026-11-12. Branch: `audit-2/fix-workspaces-settings-icons` (no push).

## Result

All three user-facing breakages had reproducible causes, and all three are fixed
in the repo plus repaired in the live session where a safe live fix was
possible.

| area | root cause | status |
|---|---|---|
| Workspace pills/clicks dead | vendored wm client looked for `mei-wm-*`; `Wm.caps` all false | fixed |
| Super+N dead | `tenkai-workspace` required `tenkai wm status` and exited 0 doing nothing | fixed |
| Settings not applying | wm-gated settings were dropped with the same false caps; no generic write/apply seam | fixed |
| Missing icons | Material Symbols font not installed; sandbox fontconfig did not see user fonts | fixed |
| Error wall | 3 subscriber sockets retried unimplemented topics every 2 s (772 warnings/start) | fixed |

## Changes

1. `src/tenkai_core/shell/ipc/vendor/tenkai-wm/client.go` — provider prefix
   `mei-wm-` → `tenkai-wm-` (both lookup sites).
2. `src/tenkai-configs/hypr/scripts/tenkai-workspace` — optional seam, Hyprland
   fallback, Lua dispatch with classic fallback, full focus/move/hide/scratch.
3. `Config.qml` — generic `patch(path, value)`.
4. `shell.qml` — `setSetting`, `getSetting`, `workspaceSwitch`, `listSurfaces`.
5. `Holidays/PowerProfiles/Updates/Weather.qml` — stop retrying on
   `err unknown topic`.
6. `tenkai` — provision `.run/data/fonts` and link the Material Symbols font
   into the sandbox fontconfig; scrub self-match avoided by splitting literals.
7. Four legacy docs sanitized so `./tenkai scrub-check` passes (the gate was
   already failing before this pass).
8. `tests/run-all.sh`, `tests/runtime/start-shell.sh`, `tests/allowlist.txt`.

## Test suite

```
tests/run-all.sh            # all checks; non-zero on FAIL
tests/run-all.sh --static-only
```

Result of the final run: **0 failures**.

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
| bootstrap/idempotent | PASS |
| autostart/idempotent | PASS |
| runtime/shell-starts-clean | PASS |
| runtime/workspace-switch-via-bar-pill | PASS |
| runtime/settings-apply-5-keys | PASS |
| runtime/icons-all-resolve | PASS |

Evidence: `tests/evidence/<timestamp>/` (per-run directory; the log segment
since the last `Launching config`, settings disk/live values, icon match,
workspace transitions).

The QML lint check treats only an `error:` diagnostic as failure: this qmllint
exits 255 for unresolved external imports on valid files, which would otherwise
mark the whole tree failed.

## Live repairs performed (safe set)

- Rebuilt and installed `.run/bin/tenkai-shell`; restarted the daemon/shell.
- Installed the fixed `tenkai-workspace` helper to
  `~/.config/hypr/scripts/` (backup `*.pre-audit2.bak`).
- Created the sandbox fontconfig file and linked Material Symbols into
  `.run/data/fonts`; installed the font user-locally.
- Did **not** modify `~/.config/hypr` keybinds; the block for a tree without
  them is in `hypr-keybinds-to-add.lua`.
- Did not change `launcherTarget`, run `chsh`, or rewrite the `./tenkai`
  launcher beyond font provisioning.

## Known gaps

See `unverified.md`. The two settings without any UI control
(`launcherTarget`, `screenShader`) are verified at the IPC/config/live level,
not by clicking a control; this is stated in `settings.md` rather than claimed
as UI-verified.
