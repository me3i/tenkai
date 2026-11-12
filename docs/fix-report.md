# Fix report — settings pipeline and completion pass

Branch: `fix/settings-and-completion`
Base commit: `b46a07930d87587bdd92bd815df54c6b98500b1a` (`main` at start)
Date: 2026-11-12

Reference Ryoku tree: `Ryoku-dev/ryoku` @
`98a0368253d9628be72b853985878a5db90e1547` (the pin named in `README.md`).
`me3i/ryoku` is not publicly cloneable, so the upstream commit was used.

## What was actually broken

The settings *architecture* was already the right shape, and it works: one
writer (`tenkai-shell` daemon), one socket topic, one file, one watched shell
singleton. The defects were narrower than the brief assumed.

1. **The launcher had no providers.** `apps/Apps.qml` imported
   `Ryoku.Ui.Singletons`, a module Tenkai does not install. `Apps` became
   unavailable, which cascaded to `Providers`, which broke both launcher
   variants. The `providers/qmldir` also listed only `Provider`, so
   `SharedProviders.Providers` could not resolve once the qmldir existed.
   *Fixed:* import `Tenkai.Ui.Singletons`; register `Providers` in the qmldir.

2. **Recurring null-player TypeErrors.** `MprisPanel.qml` read
   `player.trackTitle` / `trackArtist` whenever `active` was true, even in the
   window where the player object was still null.
   *Fixed:* guard both bindings on `mprisPanel.player`.

3. **Dead handler.** `shell.qml` connected `onAuthStepAside` to the `Stash`
   singleton, which declares no such signal; Qt warned on every start and the
   handler could never run. *Fixed:* removed the block.

4. **Orphaned file importing a cut module.** `desktop/MusicVideoPicker.qml` was
   unreferenced and imported `"music"`, which Tenkai intentionally removed, so
   the QML scanner warned every launch. *Fixed:* deleted the file (the desktop
   music widget is out of scope; see `gap-analysis.md` §A).

5. **`visualizer.json` never existed.** The Hub read it on every open (warning)
   and had no file to write on Save. *Fixed:* seed it (and `brand.json`) from
   adapter defaults on first open. First launch creates it; later launches are
   clean.

6. **Missing deliverables.** No `setup/manifest.json`, no `setup/bootstrap.sh`,
   no gap analysis, no standalone autostart helper. *Added.*

## Settings pipeline — what was verified, and how

```
Hub page → Singletons/Settings.qml (applySetting/patch)
         → $XDG_RUNTIME_DIR/tenkai-shell.sock, `call settings.patch`
         → daemon settingsStore.patch (validate, clamp, atomic write)
         → settings frame re-push + ~/.config/tenkai/shell.json
         → shell services/Config.qml FileView (watchChanges) retunes live
```

Measured against the running live session:

| Check | Result |
| --- | --- |
| `settings.patch frameOpacity=0.97` | `{"ok":true}` |
| value in `shell.json` | `0.97` |
| running shell's log, next 1.5 s | 9 new `shell.json` FileView load events — live update, no restart |
| `settings.patch frameThickness=3`, then restart `qs` | daemon frame after restart: `frameThickness = 3`; disk: `3` — persistence survives restart |

The value was restored to the shipped default (`frameThickness = 2`,
`frameOpacity = 1`) after the test.

`Settings.applySetting(path, value)` was added as the one-call UI entry point;
it is `patch` plus the documented invariant that the daemon push is the live
apply. It deliberately does not write Hyprland files.

## Verification actually run

- **Full shell restart, three times** (`kill -TERM` on the supervised `qs`;
  the daemon restarted it automatically). Latest start log
  (`.run/state/tenkai/surfaces/shell.log`) contains **no QML type, syntax,
  binding or TypeError lines**. Remaining lines are Quickshell internals:
  `fileview: got operation finished from dropped operation` and
  `Socket error … PeerClosedError` (normal socket lifecycle), plus
  environment-only fontconfig/PowerProfiles warnings in the sandbox HOME.
  The previous `Type Apps unavailable`, `Providers unavailable`,
  `Ryoku` module, `MusicVideoPicker` import and `onAuthStepAside` warnings are
  gone.
- **Launcher probe** (isolated offscreen Quickshell, real source tree):
  `PROBE_OK apps=true`, both `SharedProviders.Providers` and `Apps` resolve.
- **Hub load, widget section** — no errors; `visualizer.json` seeded on first
  open, second open warning-free.
- **Autostart idempotency** — two `--apply --yes-hyprland` runs against a
  throwaway `HOME`: second run prints "already present" and the file diff is
  empty. The real `~/.config/hypr` was **not** modified.
- **Bootstrap** — empty manifest exits 0; present dependency exits 0; missing
  dependency exits 1 with the pacman line; a step with a `when` guard runs once
  and is skipped on the second `--apply`.
- **JSON/shell syntax** — `python3 -m json.tool setup/manifest.json` and
  `bash -n` on both scripts pass.

## Autostart — state and how to turn it on

Detection on this machine: Hyprland 0.57.2, `hyprctl`, `qs` 0.3.2, `uwsm` and
`systemctl` all present; Hyprland uses the Lua config
(`~/.config/hypr/hyprland.lua`), so the helper targets
`~/.config/hypr/modules/autostart.lua`.

Nothing was written to the live Hyprland config (Tenkai's design invariant).
To enable it, deliberately:

```bash
scripts/tenkai-autostart                                  # print the exact block
scripts/tenkai-autostart --apply --yes-hyprland           # append, with backup
# OR the systemd alternative (units must exist via install.sh step 3):
scripts/tenkai-autostart --systemd --apply
```

`install.sh` step 4 already asks interactively and is idempotent; this helper
adds the same guard as a standalone, non-interactive command.

## Diff against the base

```
 scripts/tenkai-autostart                           | 128 ++++++++++++
 setup/bootstrap.sh                                 | 150 +++++++++++++
 setup/manifest.json                                |   7 +
 src/tenkai_core/hub/quickshell/Hub.qml             |   5 +
 src/tenkai_core/hub/quickshell/Singletons/Settings.qml |   7 +
 .../qsbar/panels/MprisPanel.qml                    |   4 +-
 .../modules/desktop/MusicVideoPicker.qml           | 243 --------------------
 .../launcher/shared/providers/apps/Apps.qml        |   2 +-
 .../launcher/shared/providers/qmldir               |   1 +
 src/tenkai_core/shell/quickshell/shell/shell.qml   |   7 -
 10 files changed, 301 insertions(+), 253 deletions(-)
```

Plus this report and `docs/gap-analysis.md`.

## What could not be verified

- **Clicking the GUI.** There is no automated pointer in this session. Live
  reaction was verified through the daemon/socket/file/log chain and by
  restarting the real shell, not by clicking a control in the Hub. The
  `applySetting` call site is therefore compile-reviewed, not click-tested.
- **Preview pixels.** The previews load without QML errors and bind to
  `pg.draft` (unsaved edits) / live `Config`, but no screenshot comparison was
  performed.
- **Autostart at next login.** The helper was only exercised against a
  throwaway HOME; the real session was not logged out.
- **`setup/manifest.json` is intentionally empty.** The owner has not sent the
  dependency/asset list; no entries were invented. `bootstrap.sh` is complete
  and tested with temporary manifests.
- **Benign Quickshell internals** (`dropped operation`, `PeerClosedError`)
  remain in the log; they are not QML warnings and are not caused by this
  change.
