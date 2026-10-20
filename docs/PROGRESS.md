# PROGRESS — the final build pass

One line per item: what it is, where it stands, what is next. The resume point
is the last line.

## Items

| item | state | evidence / what is missing |
|---|---|---|
| 0. input safety | **TESTED (nested)** | `docs/tests/tools/nested-input.sh` is the only way a nested test sends a key or a pointer event: it resolves the display under Mei's nested runtime, refuses the live socket (by path and by name), prints the resolved socket path and exits 3 on a refusal. `docs/tests/input-guard-selftest.sh` proves both ways with a stub tool and never connects to a compositor. Every harness caller goes through it: `idle-module.sh`, `lock-module.sh`, `launcher-check.sh`, `terminal-check.sh`, `step4.sh`. |
| 1. idle + the ScreenSaver service | **TESTED (nested)** | `docs/tests/idle-module.sh` passes end to end: the ScreenSaver name is offered on the nested bus and the live bus is untouched, a fake client's Inhibit holds the idle off and the release resumes it, the dim and the exact restore work against the harness seam (`MEI_BRIGHTNESS_FAKE`), the display goes to sleep on idle and wakes on activity, the suspend is stubbed, and the idle locks the screen (a wrong password is refused). The slot refusal has its own test: `src/ryoku/shell/ipc/screensaver_test.go` proves it both ways (a stand-in owner keeps the slot, a free slot is taken). |
| 1. the real session lock (ext-session-lock-v1) | **TESTED (nested)** | `docs/tests/session-lock-module.sh`: the compositor confirms the lock and calls it **secure**, the old surface lock is gone, a wrong password is refused and the lock stays, the right one releases it, locking twice keeps one lock, a broken PAM setup refuses to engage, and the crash case keeps the session locked until the compositor's own `hl.clear_crashed_lockscreen()` clears it. `docs/tests/lock-module.sh` passes with the protocol lock too. |
| 2. the network and Bluetooth hosts | **NOT STARTED** | the panels are still bar-hosted. The pattern is the control centre's own host (`modules/controlcenter/ControlCenterHost.qml`). |
| 4. certify (a full cold-start `phase9.sh`) | **NOT RUN** | the last full run was 16/17 with item 7's harness defect fixed and re-validated; the restored-component suites pass (`docs/tests/restored-modules.sh`, now with the idle suite in it). |
| 5. live readiness (the checklist and the switch-over guide) | **PARTLY DONE** | `docs/LIVE-CHECKLIST.md` has the lock in detail, the TTY recovery and the one-page switch-over guide; it still needs the idle items, the new panel hosts and the final "every remaining difference" list. |

## The keystroke incident (what actually reached the live session)

A virtual keyboard in the harness inherited the caller's `WAYLAND_DISPLAY`, so
the keys it sent went to the owner's live session. It was disclosed and fixed,
but the earlier runs sent more than the first disclosure said:

- the lock test ran 11 times before the fix (8 in the earlier session, 2 from
  an earlier day, 1 in this session). Each run typed `abc`+Enter twice: once
  for the wrong password and once for the verifier seam.
- the idle test ran 4 times before the fix. Each run typed `a` once, and
  `abc`+Enter once.

So roughly thirty short sequences reached the live session. What they can do
depends on what had the focus there: in a shell, `abc`+Enter runs an empty
command; in a text field, it leaves `abc` behind. The owner checked their own
terminals and history, which is the right way to close this out.

The guard now makes that class of mistake impossible: every synthetic input in
a nested test resolves under Mei's nested runtime, so the live socket cannot
be reached by name at all, and a refusal is loud (exit 3) instead of silent.

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

## What the session lock pass settled (worth keeping)

- Quickshell 0.3.2 does ship `WlSessionLock` and `WlSessionLockSurface` (they
  are in the plugin's types, not in a module of their own).
- `WlSessionLock`'s **default property is its surface**: anything else declared
  inside the lock object is taken for the surface, and the lock refuses to
  engage ("WlSessionLock.surface does not create a WlSessionLockSurface"). The
  lock object is therefore wrapped in an `Item`.
- The compositor writes the lock state back into the `locked` property, which
  breaks a QML binding: the shell's state has to be pushed into it
  imperatively, or the lock never engages.
- The root of the surface component has to be the `WlSessionLockSurface`
  itself.
- Hyprland 0.56.2 has the protocol (`CExtSessionLockManagerV1`), keeps the
  session locked when the lock client dies, and answers
  `hl.clear_crashed_lockscreen: session is not locked` when there is no
  crashed lock to clear. The recovery is
  `hyprctl dispatch 'hl.clear_crashed_lockscreen()'`.

## Still unverified (for the live checklist, not for the code)

- The compositor's **own** idle inhibitors (a video player, a call, Firefox)
  are honoured through the monitor's `respectInhibitors`, but that path could
  not be proven in the nested session: a one pixel surface did not hold an
  `IdleInhibitor` there. The D-Bus inhibitors (the apps that ask through
  `org.freedesktop.ScreenSaver`) are enforced by the module itself and are
  proven.
- The idle dim, lock, DPMS and suspend on the owner's real session, with the
  real backlight and the real timers.
- The lock's **accepted** path with the owner's own password (the nested
  harness uses the verifier seam; the refusal path is a real PAM round trip).
- The lock on **more than one output**: the nested session has a single
  output, so the second screen of the owner's session is a live check.

## Part 2 (distribution) — not started

`MEI_MODE`, the relocatable paths, `install.sh` / `uninstall.sh` / `./mei doctor`,
the assets and licences, the README and the CI workflow, and the no-VM install
checks. `docs/PUBLISH-NOTES.md` already describes how to publish from a clean
export.

## The lock screen's look (2026-10-21)

The lock screen is the **orbital dial** from Ryoku's own clockwork lockscreen
theme, taken from upstream and adapted (`modules/lock/OrbitalClock.qml`): the
dial with its two rings of ticks, the spotlight that follows the minute and
the second, the big hour numeral and the date, and the theme's pill shape for
the password field. The greeter's parts (the SDDM components, the user and
session models, the fingerprint hint, the reveal and the windup) are not a
session lock and were left out; the bundled Outfit font is not redistributed,
because upstream ships it without a licence file (the system font is used
instead, and CREDITS.md says so).

The upstream theme is under Ryoku's GPL-3.0-or-later, and the adapted clock
keeps the attribution in its header. The clock only runs while the lock is up:
it lives in the lock's surface.

`docs/tests/lock-ui-outbound.sh` proves that the lock's QML has no outbound
call, no network asset and no bundled file, and that the check itself can
fail. The screenshots (nested only) are in `.run/shots/lock-before.png` and
`.run/shots/lock-after.png`.

The other lock-screen visuals upstream has: the clockwork theme is the only
one in the tree, and it is the only look Mei took. The rest of the greeter
(SDDM's own components, the input form, the fingerprint hint) is a login
screen, not a session lock.

## What the orbital theme depends on, and what it animates

Checked in the upstream tree, not guessed:

| what it needs | what it is | in Mei's lock? |
|---|---|---|
| `SddmComponents 2.0` | the greeter's own components (the action buttons, the text sizes) | no — a greeter's parts |
| `Qt5Compat.GraphicalEffects` | one `OpacityMask` for the circular reveal | no — the reveal is the greeter's |
| `Qt.labs.folderlistmodel` | finding the bundled font | no — the font is not bundled |
| the Outfit font | the typeface | no — upstream ships it without a licence file, so the system font is used |
| the `i18n` reader (an `XMLHttpRequest` over `file://`) | the translated strings | no — the lock has three strings of its own |
| the `sddm` object | the greeter's session API (users, fingerprint, power) | no |
| a 16 ms timer | the smooth second hand | **yes** — and only while the lock is up: the clock lives in the lock's surface |
| the windup, the boom, the sparks | the greeter's entry animation | no — a lock should not flash at you |
| the needle cursor's pulse | the input's cursor | **yes** |
| the hint's fade | the input's hint | **yes** |
| the UNLOCK label's hover | the input's button | **yes** |
| the circular reveal (`OpacityMask`) | the greeter's wipe-in | no |

## The acceptance gate (STEP 1, 2026-10-21)

`./mei accept` (docs/tests/accept.sh) runs every machine-checkable criterion
and prints one table: the gate id, the name, PASS / FAIL / UNVERIFIED and the
evidence path. `docs/CRITERIA.md` holds the list and says what each gate
checks. The human gates (the lock's accept path, the second output, the
compositor's inhibitors, the real panel, the 144 Hz feel, the horizon line,
the real tray apps, the real notifications, the real audio hardware, and
Wi-Fi and Bluetooth through the terminal tools) are UNVERIFIED by design.

Gates with no runnable check yet are listed as TODO with what they need, and
are not counted as passed: F4 (notifications), F5 (the tray), F6 (the
wallpaper and the palette), F7 (the settings app), F12 (the module matrix),
Q3 (the frozen screenshots) and Q4 (the idle table).

The network and Bluetooth panel hosts are DEFERRED: the flags stay off, the
panels are not built, and `nmtui` and `bluetoothctl` are the fallback. That
is written into `docs/LIVE-CHECKLIST.md`, together with the list of every
remaining difference from your previous shell.

## Where to resume

**Item 2, the network and Bluetooth hosts.** Hosts that do not live in the
bar (the control centre's own host is the pattern:
`modules/controlcenter/ControlCenterHost.qml`), reusing the QML that is
already there, with the module flags `network_panel` and `bluetooth_panel`,
talking to NetworkManager and BlueZ over D-Bus. The read paths have to be
TESTED nested; connect, disconnect, toggle and pair only if a fake NM and a
fake BlueZ can be built on the private bus, otherwise UNVERIFIED. The real
connections and the real adapter are never touched. If a host cannot be made
to work in six iterations, disable its flag cleanly, mark it BLOCKED and put
the terminal fallback (`nmtui`, `bluetoothctl`) in the docs.

After that: the certification run (one full cold-start `phase9.sh`, the idle
measurement table, zero outbound at idle, `./mei baseline --force`) and the
live readiness pass over `docs/LIVE-CHECKLIST.md`.
