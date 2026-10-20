# PARITY — serpantinum (the shell in use) vs Mei

Read-only audit, 2026-10-20. Nothing was started, written or sent to the live
session: the owner's sources and Hyprland config were read, and the live state
was read through `busctl`, `hyprctl -j` and `/proc`.

Sources read:

- `~/.local/share/serpantinum/src/quickshell/Shell.qml` (61 lines) and the
  modules it instantiates: `bar/`, `lock/`, `idle/`, `screenshot/`, `clipboard/`,
  `polkit/`, `network/`, `media/`, `notifications/`, `popouts/`, `dock/`,
  `calendar/`, `guide/`, `reusables/`, `Main.qml`, `Runner.qml`.
- `~/.config/hypr/config/{autostart,keybinds,env,monitors,settings,variables}.lua`
  (671 binds, 25 of them dispatching to the `serpantinum` CLI).
- Mei's own tree: `src/ryoku/shell/ipc/` (the daemon) and
  `src/ryoku/shell/quickshell/shell/` (the shell).

## 1. What serpantinum gives the owner today

| function | where it lives | the owner's keybinds |
|---|---|---|
| lock | `lock/Lock.qml` (in-shell screen, PAM) | `XF86PowerOff`, `SUPER+L` (2) |
| idle: dim 120 s, lock 300 s, DPMS 360 s, suspend 600 s, inhibitors honoured | `idle/Idle.qml` + `idle/screensaver_inhibit.py` | none (it is a timeout) |
| screenshot | `screenshot/ScreenshotOverlay.qml` (`grim` to a file, the OCR text to the clipboard) | `Print`, `SHIFT+Print`, `SUPER+Print`, `SUPER+SHIFT+Print` (4) |
| panel toggles: launcher, guide, clipboard, calendar, wallpaper, volume, system, network, music, autohide | `serpantinum msg toggle <panel>` → the shell's popouts | 10 binds |
| volume / mic | `serpantinum volume raise/lower/mute-toggle/mic-toggle` | 4 binds |
| brightness | `serpantinum brightness raise/lower` | 2 binds |
| media keys | `playerctl` (play-pause, prev, next) | 5 binds |
| workspaces | `serpantinum msg workspace` | 2 binds |
| reload | `serpantinum reload` | 1 bind |
| tray, notifications, polkit agent, dock, wallpaper engine, quick actions | `popouts/TrayBase.qml`, `notifications/`, `polkit/`, `dock/`, `Main.qml` | (surfaced through the bar) |

The whole live shell is one process: `bash /usr/local/bin/serpantinumd start`
(`autostart.lua:5`) → `quickshell -p ~/.local/share/serpantinum/src/quickshell/Shell.qml` (PID 949).

## 2. What Mei has for each, and what would collide

| function | Mei today | upstream path | packages | outbound calls | collides with the live shell? |
|---|---|---|---|---|---|
| lock | the daemon has a `lock` verb, but it calls **logind's Lock()** (locks the whole session) and nothing draws a lock screen | `ipc/control.go`, `ipc/daemon.go` | none | none | **yes** — logind Lock() would lock the owner's real session. Not usable as it is |
| idle | **nothing**: no dim, no DPMS, no timeout, no screensaver inhibitor | (upstream `ipc/sleepwake.go` has the logind side only) | none | none | no (nothing to collide with) |
| power menu | the **code exists** (`ipc/session.go`: logout/reboot/shutdown) but `startSession()` is **never called**, so the verbs do not exist and the buttons are dead | `ipc/session.go`, `services/SessionActions.qml` | none | none | no, as long as it stays stubbed; the daemon's verbs would act on the live session if ever enabled live |
| screenshot | the capture **overlay** exists (`modules/capture/CaptureOverlay.qml`) and the daemon has a capture verb, but nothing saves to a file like `grim` does for the owner | `ipc/actions.go`, `modules/capture/` | grim (installed) | none | no |
| volume / brightness OSD | the **surfaces exist** (3 `OsdWindow` + `KeyboardOsdWindow` in `shell.qml`), but the daemon's `startOsd()` (the backlight/volume watcher) is **not called**, so they never fire | `ipc/osd.go`, `modules/osd/` | none | none | no |
| media / now playing | **works**: `startMusic()` runs and the now-playing card showed the owner's real MPRIS session live | `ipc/music.go`, `services/Music.qml` | none (local MPRIS) | none | no (MPRIS is read-only on the bus) |
| media keys | the daemon publishes MPRIS control verbs; the owner's keys call `playerctl`, so Mei needs its own binds | `ipc/music.go` | none | none | no |
| clipboard history | the **surface exists** (`ClipboardSurface`) and the daemon has `startClipboard()`, but it is **not called** → no history | `ipc/clipboard.go`, `modules/clipboard/` | wl-paste (installed) | none | no (a local, bounded history) |
| wallpaper | **works**: the wallpaper module + ryogami, with the reveal shader | `modules/wallpaper/`, `ipc/ryogami.go` | none | none | **yes** — Mei draws its own `wallpaper-bg` layer over the live shell's (only in the full profile, where the old shell is stopped) |
| notifications | **works**: one `NotificationServer` owns `org.freedesktop.Notifications` | `services/Notifs.qml` | none | none | **yes** — the same D-Bus name the live shell owns (the full profile requires the old shell to be stopped) |
| tray | **works**: the daemon's StatusNotifierWatcher host | `ipc/tray.go` | none | none | **yes** — `org.kde.StatusNotifierWatcher` (the full profile requires the old shell to be stopped) |
| polkit agent | the daemon has `startPolkit()` (not called) and the shell has no agent surface | `ipc/polkit.go` | none | none | **yes** — the owner's own shell runs a polkit agent; two agents must never be registered at once |
| network panel | the daemon's `startNetwork()` runs; the **panel UI lives in the bar styles**, so with the bar off it is unreachable | `ipc/network.go`, `barstyles/qsbar/panels/NetworkPanel.qml` | none (NetworkManager over D-Bus) | none | no (read-only paths) |
| bluetooth panel | the daemon's network topic covers BlueZ; the panel UI is bar-hosted | `services/BluetoothDiscovery.qml`, `barstyles/qsbar/panels/` | none (BlueZ over D-Bus) | none | no (read-only paths) |
| night light | **works**: `startNightlight()` runs (a local gamma ramp) | `ipc/nightlight.go` | none | none | no |
| workspaces | the bar's workspace cells track the compositor | `modules/bar/` | none | none | no |
| keypress overlay | the daemon has `startKeypress()` (not called) | `ipc/keypress.go` | none | none | no |
| guide (wellbeing), calendar, dock, quick actions, weather, AI, store | **not in Mei** (trimmed in Phase 6) | — | — | — | excluded by the owner |

**Mei's live layer surfaces** (measured): `ryoku-frame` (bar), `ryoku-widgets`
(transparent desktop layer), `ryoku-visualizer`, `launcher`, `ryoku-control`,
`ryoku-osd`. The live shell's: `wallpaper-bg`, `quickshell` (bar), `qs-floating-overlay`.

**Global shortcuts:** the live session registers **none** over the protocol
(`hyprctl globalshortcuts` says "none"), so Mei's 13 `ryoku:*` names collide with
nothing.

**Keyboard grabs:** Mei's launcher and control centre take an **exclusive**
keyboard grab while they are open, so the owner's keys go to Mei while they are
open (measured live). A blocker for a side-by-side profile, harmless in the full
profile.

**Idle inhibitors:** the owner's idle uses `org.freedesktop.ScreenSaver`
(`idle/screensaver_inhibit.py`); Mei's idle would have to do the same, and the
two must not fight over it (the old shell is stopped in the full profile).

## 3. Classification

**MUST** (the owner would notice it missing, or every desktop needs it):

1. **LOCK** — an in-shell lock with a PAM prompt. Mei's logind-based `lock` verb
   is not acceptable: it locks the owner's real session, and the nested test
   could never prove it. Needs its own PAM client.
2. **IDLE** — dim / lock / DPMS / suspend timeouts with inhibitors honoured.
   Nothing exists in Mei.
3. **POWER MENU** — the session verbs are not registered, so the buttons are
   dead. The code is already written (`ipc/session.go`); it needs wiring, the
   sidebar buttons, and the two stubs.
4. **SCREENSHOTS** — a `grim` capture to the owner's Pictures folder plus the
   clipboard, with a notification. Mei's capture overlay is a recorder, not this.
5. **OSD** — the volume and brightness popups. The surfaces exist; the daemon's
   watcher does not run.
6. **MEDIA KEYS** — local MPRIS (no network), plus the now-playing card that
   already works.
7. **CLIPBOARD HISTORY** — local, bounded, text and image, clear-all.
8. **WALLPAPER PICKER** — the owner's own folder only, no Wallhaven/Steam.
9. **NETWORK PANEL** — status and list over NetworkManager D-Bus; connect and
   disconnect stay UNVERIFIED for the owner.
10. **BLUETOOTH PANEL** — status and device list over BlueZ D-Bus; toggle and
    pair stay UNVERIFIED for the owner.
11. **POLKIT AGENT** — restored but gated: off in dev mode and in the overlay
    profile, on only in the full profile, and only when no other agent is
    registered.
12. **NIGHT LIGHT** — already present and working; keep it, no work.

**SHOULD** (cheap and clean): the bar-hosted **network and bluetooth panels need
their own host** the way the control centre just got one (otherwise they are
unreachable with the bar off); the keypress overlay (the daemon's code is
there, but it is a "nice to have").

**SKIP**: the guide (wellbeing), the calendar, the dock (Mei has one, off by
default), quick actions, weather, AI, store, updates, telemetry, and anything
that makes an outbound call the owner did not ask for. The owner's exclusion
list names music as well; the reading used here is that the **networked** music
extras are excluded while the **local** MPRIS now-playing card and the media
keys stay (they are local, the owner uses them daily, and they cost no
outbound call). The owner should correct this reading if it is wrong.

## 4. The order of work

| step | what | state |
|---|---|---|
| 0 | the control centre stops depending on the bar | **done** (`3ac455c`, `docs/tests/control-center-matrix.sh` 3/3) |
| A | this audit | **done** (this file) |
| B1 | power menu: register the session verbs, wire the sidebar, keep both stubs | **done** (`c7046dd`, `docs/tests/power-menu.sh` 20/20) |
| B2 | OSD: start the daemon's watcher so the existing surfaces fire | **done** (`cdc074b`, `docs/tests/osd-module.sh` 5/5) |
| B3 | clipboard history: start the daemon's topic, bound it, clear-all | **done** (`86634d4`, `docs/tests/clipboard-module.sh` 8/8) |
| B4 | polkit agent: start it behind a flag, off in dev and overlay | **done** (`2a7e6e2`, `docs/tests/polkit-module.sh` 6/6) |
| B5 | media keys: the daemon's verbs plus the keybind snippet | **done** (`fd1a178`, a Go test with a fake MPRIS player) |
| B6 | screenshots: a `grim` capture to Pictures plus the clipboard | **done** (`b63a6c0`, `docs/tests/screenshot-module.sh` 8/8) |
| B10 | lock: an in-shell PAM lock that cannot touch the live session | **done** (`620d232`, `fa2a29b`, `docs/tests/lock-module.sh` 15/15) |
| B7 | wallpaper picker: the owner's folder only | **open**: the wallpaper module and its menu exist; the picker's own sources still have to be checked for outbound calls |
| B8 | network and bluetooth panels: their own host, read-only paths | **open**: the panels are bar-hosted, so they need a host like the control centre's |
| B9 | idle: dim/lock/DPMS/suspend with inhibitors | **open**: the only one that is new code rather than restored code |
| C | the keybind snippet, the profiles, MODULES.md, LIVE-CHECKLIST.md | **done** for the snippet and the checklist (`53ea469`); the module matrix needs the new components |
| D | the full test loop and the idle measurement table | running |

B7, B8 and B9 are the three still open. B7 and B8 are wiring, B9 is new code.

## What you lose, and what it would cost to add

Every serpantinum feature with no Mei equivalent, and the one-line cost of each.
Nothing here is decided: the list is for you to pick from. The "your binds" column
names the binds in your own config that depend on the feature.

| feature | your binds that depend on it | what Mei has instead | the cost to add it |
|---|---|---|---|
| wellbeing guide (the focus daemon, the wellbeing panel) | `SUPER + H` (`serpantinum msg toggle guide`) | nothing | a small daemon that tracks focus and session time, plus a panel page: about a day |
| calendar | `SUPER + S` (`serpantinum msg toggle calendar`) | nothing (the calendar was trimmed; it is also in your exclusion list) | a calendar panel reading the same local sources your shell does: about a day |
| quick-actions palette (the floating action panel) | none directly (it is bound to nothing in your config) | the launcher and the control centre cover most of it | a floating panel with the actions you had: half a day |
| bar autohide toggle | `SUPER + A` (`serpantinum msg toggle autohide`) | Mei's bar has an autohide setting in the config (`Config.normalizedFrameBars`), but no shortcut to flip it | one shortcut that flips the setting: about an hour |
| move a window to a workspace with `SUPER + SHIFT + number` | `SUPER + SHIFT + 1..0` | **nothing needed**: Hyprland can do this itself, with no shell at all. The dispatcher is in the binary (`movetoworkspace`, `moveWindowToWorkspace`); the classic form is `hyprctl dispatch movetoworkspace 2` | one line in your keybinds: `hl.dsp.exec_cmd("hyprctl dispatch movetoworkspace " .. ws)` — and the Lua form would be the same thing through `hl.dsp` |
| image editor on `SHIFT + Print` | `SHIFT + Print` (and `SUPER + SHIFT + Print`) | Mei's `mei-screenshot` takes the picture (full screen or a dragged region), puts it in the clipboard and announces it | point the bind at an editor you already have (a one-line change), or a small editor surface: an hour |
| idle timeouts (dim, lock, DPMS, suspend) | none (they are a timeout, not a bind) | **not built yet**: this is the one real gap | a state machine over Quickshell's idle-notify (the API is there: `IdleMonitor` with `isIdle` and `respectInhibitors`), four timeouts and four actions: about a day |
