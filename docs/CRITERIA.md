# CRITERIA — what "done" means for Mei

Every criterion below is either **machine-checkable** (it is a gate in
`./mei accept`, and the gate prints PASS / FAIL / UNVERIFIED with the
evidence) or a **human gate** (only the owner can close it, by doing it).

Run it:

```bash
./mei accept            # the whole gate, from a cold start
./mei accept --list     # the gates and their commands, nothing run
./mei accept --prove    # show that the static gates can fail
```

The gate never touches the owner's live session: every harness runs a nested
compositor with a fake HOME and a private bus, and every synthetic keystroke
goes through `docs/tests/tools/nested-input.sh`, which refuses anything that
is not the nested display.

## The safety gates

| id | what must be true | how it is checked |
|---|---|---|
| S1 | the live session is untouched: the live configs, the kitty hash and the live D-Bus owners are unchanged | `./mei verify-untouched`, before and after the run |
| S2 | no personal values in the tracked tree | `./mei scrub-check` |
| S3 | no Mei process, descendants included, ever holds the live runtime dir or the live display | `docs/tests/leak-check.sh` |
| S4 | no process is ever signalled by name: only recorded PIDs and their descendants | a grep over every tracked script for `pkill`, `killall`, `pidof` (proven able to fail) |
| S5 | the test input tool is fail-closed: it refuses the live display | `docs/tests/input-guard-selftest.sh` |
| S6 | no outbound connection over an idle capture, and no listening TCP or UDP socket | `docs/tests/picker-outbound.sh` plus the sockets of Mei's own processes in a nested session |
| S7 | a clean stop leaves no stray process, socket or lock file | the runtime dir and the process list after `./mei stop` |
| S8 | nothing is written outside `~/projects/mei` | every path the nested session uses (HOME, the XDG dirs, the runtime dir) is read from the live process and must be inside the project |

## The functional gates

| id | what must be true | how it is checked |
|---|---|---|
| F1 | the bar renders and the workspaces match Hyprland across all five | `docs/tests/workspaces.sh` |
| F2 | the launcher opens, searches the real `.desktop` files read-only, launches and closes on Esc | `docs/tests/launcher-check.sh` |
| F3 | the control centre opens on its own, the audio and the brightness answer in 5 % steps and are restored | `docs/tests/control-center-matrix.sh` |
| F8 | the lock is the compositor's own (ext-session-lock-v1), covers every output, refuses a wrong password, releases on the right one, is safe to lock twice, blocks the keybinds, refuses to engage without a usable PAM setup, survives a crash with the compositor's own recovery, and reaches out to nothing | `docs/tests/lock-module.sh`, `docs/tests/session-lock-module.sh`, `docs/tests/lock-ui-outbound.sh` |
| F9 | the idle module dims and restores exactly, locks, sleeps and wakes the display, stubs the suspend, and honours the inhibitors; the ScreenSaver service is claimed only in the full profile and only when the name is free | `docs/tests/idle-module.sh` and the Go test beside it |
| F10 | the power menu: the lock is real, the rest is stubbed under `MEI_TEST` and `MEI_STUB_POWER` | `docs/tests/power-menu.sh` |
| F11 | the OSD, the clipboard, the screenshots (local, no upload), the media keys, the polkit agent (off by default, refusing when another agent exists) | `docs/tests/restored-modules.sh` |
| F13 | `./mei start` is non-interactive and idempotent, `--fallback` runs only when no Mei process is left, `./mei live-stop` stops only its own tree, and the preflight collision check passes against the live baseline | `docs/tests/start-fallback.sh` |

**F4 (notifications), F5 (the tray), F6 (the wallpaper and the palette), F7
(the settings app) and F12 (the module matrix)** are in the owner's criteria
and have no harness of their own yet. They are listed as **TODO** by the
gate, with what each needs, and they are **not** counted as passed. The
big `docs/tests/phase9.sh` run covers parts of them, but a part is not a
gate.

## The quality gates

| id | what must be true | how it is checked |
|---|---|---|
| Q1 | `qmllint` without errors on the kept QML, `go vet`, `go build` and `go test` green, `shellcheck` clean if it is installed | `docs/tests/accept-safety.sh q1` |
| Q2 | no dead code, no duplicate services, no unreferenced file, no personal strings, no `ryoku` name outside the module URIs, the D-Bus names, the polkit paths, the font names and the attribution | `docs/tests/accept-safety.sh q2` (the greps are proven able to fail) |
| Q3 | the reference screenshots (frozen clock, pinned wallpaper) of the bar, the launcher, the quick settings, the settings pages, the notification popup, the tray, the power menu and the lock screen are the same before and after the cleanup | **TODO**: the frozen set has to be taken before the cleanup |
| Q4 | the nested idle RSS, PSS, threads and CPU per 60 s must not be more than 5 % over the last recorded table | run with the Phase 10A harness (`docs/tests/phase10a-measure.py`) |
| Q5 | the documents exist and make no unproven claim: `MODULES.md`, `CHANGES.md`, `CREDITS.md`, `NOTICE`, `UPSTREAM.md`, `PARITY.md`, `LIVE-CHECKLIST.md` and this file | `docs/tests/accept-safety.sh q5` (no "lightweight" without numbers) |

## The human gates

These are **UNVERIFIED by design**. They are on the live checklist and only
the owner can close them; nothing in the harness may pretend otherwise.

| id | what only the owner can do |
|---|---|
| H1 | the lock's accept path with their real password |
| H2 | the lock on their second output |
| H3 | the compositor's inhibitors with a real video playing (the screen must not lock) |
| H4 | the idle with their real panel |
| H5 | the feel at 144 Hz |
| H6 | the horizon line's smoothness |
| H7 | the real tray apps |
| H8 | notifications from real apps |
| H9 | the real audio hardware |
| H10 | Wi-Fi and Bluetooth through the terminal tools (`nmtui`, `bluetoothctl`) — the panel hosts are deferred, and the flags are off |

## The state of the deferral

The network and Bluetooth panel hosts are **deferred**: their flags stay off,
the panels are not built, and Wi-Fi and Bluetooth are handled with `nmtui` and
`bluetoothctl` in a terminal (or the system tray). The panel hosts can come
later without blocking the switch.
