# PROGRESS — the final build pass

One line per item: what it is, where it stands, what is next. The resume point
is the last line.

## Items

| item | state | evidence / what is missing |
|---|---|---|
| 1. idle + the ScreenSaver service | **TESTED (nested)** | `docs/tests/idle-module.sh` passes end to end: the ScreenSaver name is offered on the nested bus and the live bus is untouched, a fake client's Inhibit holds the idle off and the release resumes it, the dim and the exact restore work against the harness seam (`MEI_BRIGHTNESS_FAKE`), the display goes to sleep on idle and wakes on activity, the suspend is stubbed, and the idle locks the screen (a wrong password is refused). The slot refusal has its own test: `src/ryoku/shell/ipc/screensaver_test.go` proves it both ways (a stand-in owner keeps the slot, a free slot is taken). |
| 2. the real session lock (ext-session-lock-v1) | **NOT STARTED** | the surface lock is still in place and is **not a secure lock**. Quickshell ships `WlSessionLock` and Hyprland's binary carries the protocol. Two findings from the idle pass, read out of the binary and not guessed: the strings `hl.clear_crashed_lockscreen` and "session is locked with a client, refusing to unlock" are in it, so there is a way to clear a crashed lock and the compositor refuses to unlock a session that has a lock client. |
| 3. the network and Bluetooth hosts | **NOT STARTED** | the panels are still bar-hosted. The pattern is the control centre's own host (`modules/controlcenter/ControlCenterHost.qml`). |
| 4. certify (a full cold-start `phase9.sh`) | **NOT RUN** | the last full run was 16/17 with item 7's harness defect fixed and re-validated; the restored-component suites pass (`docs/tests/restored-modules.sh`, now with the idle suite in it). |
| 5. live readiness (the checklist and the switch-over guide) | **PARTLY DONE** | `docs/LIVE-CHECKLIST.md` has the lock in detail, the TTY recovery and the one-page switch-over guide; it still needs the idle items, the new panel hosts and the final "every remaining difference" list. |

## What the idle pass settled (worth keeping)

- Quickshell's `IdleMonitor.timeout` is in **seconds**, not milliseconds
  (measured: a timeout of 2 flips the idle state after about two seconds, a
  timeout of 5000 never does).
- `FileView.text` is a **method** in this Quickshell (`text()`), not a
  property; reading it as a property silently broke the config.
- The compositor's idle-notify and the DPMS dispatcher work in the nested
  session: `hl.dsp.dpms({ action = "off" })` is accepted (`hl.dpms` exists as
  a string in the binary but is not callable in Lua).
- The idle timeouts are Mei's own (`~/.config/mei/idle.json`), the defaults are
  dim 120 s / lock 300 s / DPMS 360 s / suspend 600 s, and the module flag is
  `idle` (missing = ON).
- The ScreenSaver service is only offered where `MEI_SCREENSAVER_NAME=1` is
  set, which only the **full** live profile does; it takes the name with
  DoNotQueue, so it never fights another agent for it.

## Still unverified (for the live checklist, not for the code)

- The compositor's **own** idle inhibitors (a video player, a call, Firefox)
  are honoured through the monitor's `respectInhibitors`, but that path could
  not be proven in the nested session: a one pixel surface did not hold an
  `IdleInhibitor` there. The D-Bus inhibitors (the apps that ask through
  `org.freedesktop.ScreenSaver`) are enforced by the module itself and are
  proven.
- The idle dim, lock, DPMS and suspend on the owner's real session, with the
  real backlight and the real timers.

## Part 2 (distribution) — not started

`MEI_MODE`, the relocatable paths, `install.sh` / `uninstall.sh` / `./mei doctor`,
the assets and licences, the README and the CI workflow, and the no-VM install
checks. `docs/PUBLISH-NOTES.md` already describes how to publish from a clean
export.

## Where to resume

**Item 2, the real session lock.** Replace the shell's own surface lock with
ext-session-lock-v1 through Quickshell's `WlSessionLock`, keep the PAM
refusal-to-engage check, and prove in a nested session that all outputs are
covered, the prompt and the clock show, a wrong password is refused, the right
one unlocks (the verifier seam), locking twice is safe, and the keybinds do
not reach the windows while the lock is up. Then the crash case: kill the lock
client in a throwaway nested session, record what the compositor does, and use
the binary's own `hl.clear_crashed_lockscreen` for the recovery. The exact TTY
recovery steps go into `docs/LIVE-CHECKLIST.md` and into the revert script's
output. If it cannot pass in six iterations, keep the surface lock, mark it
BLOCKED, and say plainly that it is not a secure lock.
