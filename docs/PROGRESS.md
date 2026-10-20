# PROGRESS — the final build pass

One line per item: what it is, where it stands, what is next. The resume point
is the last line.

## Items

| item | state | evidence / what is missing |
|---|---|---|
| 1. idle + the ScreenSaver service | **UNVERIFIED (code written, not tested)** | `src/ryoku/shell/quickshell/shell/services/Idle.qml` (the state machine), `src/ryoku/shell/ipc/screensaver.go` (the D-Bus service), the daemon's `startScreensaver()` and the brightness harness seam (`MEI_BRIGHTNESS_FAKE`). The daemon builds; the QML lints. **The nested test does not exist yet.** |
| 2. the real session lock (ext-session-lock-v1) | **NOT STARTED** | the surface lock is still in place and is **not a secure lock**. Quickshell ships `WlSessionLock` and Hyprland's binary has `CExtSessionLockManagerV1`; the protocol version has to replace the surface lock, with the crash case and the lock-restore option checked in the binary. |
| 3. the network and Bluetooth hosts | **NOT STARTED** | the panels are still bar-hosted. The pattern is the control centre's own host (`modules/controlcenter/ControlCenterHost.qml`). |
| 4. certify (a full cold-start `phase9.sh`) | **NOT RUN** | the last full run was 16/17 with item 7's harness defect fixed and re-validated; the nine restored-component suites pass (`docs/tests/restored-modules.sh`). |
| 5. live readiness (the checklist and the switch-over guide) | **PARTLY DONE** | `docs/LIVE-CHECKLIST.md` has the lock in detail, the TTY recovery and the one-page switch-over guide; it still needs the idle items, the new panel hosts and the final "every remaining difference" list. |

## Part 2 (distribution) — not started

`MEI_MODE`, the relocatable paths, `install.sh` / `uninstall.sh` / `./mei doctor`,
the assets and licences, the README and the CI workflow, and the no-VM install
checks. `docs/PUBLISH-NOTES.md` already describes how to publish from a clean
export.

## Where to resume

**Item 1, the nested test.** The idle module is written but unproven, and an
unproven idle module is worse than none: it dims, locks and suspends. The next
step is `docs/tests/idle-module.sh`, with these cases:

1. the config: `.run/config/mei/idle.json` with `{"enabled":true,"dim":3,"lock":6,
   "dpms":9,"suspend":12,"dimPercent":40}`, and `MEI_BRIGHTNESS_FAKE` pointing
   at a file under `.run` (the daemon writes the steps there instead of the
   panel, so the owner's backlight is never touched);
2. dim: after the threshold the fake brightness file drops, and on activity it
   comes back to exactly the value before;
3. lock: the `ryoku-lock` layer appears;
4. DPMS: `wm.act {"action":"output.power","args":["off"]}` answers ok (the
   provider maps it to `hl.dsp.dpms({ action = "off" })`, verified in the
   provider's source), and "on" wakes it;
5. suspend: stubbed (the daemon logs the stub; the machine must not suspend);
6. the inhibitor: a fake client calls `Inhibit` over the private bus, the idle
   actions stop firing, `UnInhibit` resumes them;
7. the refusal: with the name already held (a second daemon on the same bus
   with a different runtime dir), the second one logs that the slot is held and
   does not take it — the stand-in owner proves the check can fail.

Then the preflight claim table and the leak monitor need the
`org.freedesktop.ScreenSaver` name added, and `MEI_SCREENSAVER_NAME=1` has to
be exported by the **full** live profile only (never the overlay, never dev).
