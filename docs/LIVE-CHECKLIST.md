# LIVE-CHECKLIST — what only you can verify

Short, ordered, and each item says what to do, what must happen, what to do if
it fails, and how to roll back. Do it with **the previous shell still installed** (the
overlay stage), so every failure is recoverable.

Before you start: keep a **second terminal open** and know that `Ctrl+Alt+F3`
gives you a TTY. Every item below is safe to abort from there.

---

## Stage 1 — overlay (about 10 minutes, your old shell keeps running)

```bash
cd ~/projects/mei
./mei verify-untouched
./mei live --profile overlay
```

Compare the claim table it prints with the live-session table in
`docs/PARITY.md`: every name, socket and layer namespace must read **free**.

| # | do | must happen | if it fails | rollback |
|---|---|---|---|---|
| 1 | `hyprctl dispatch 'hl.dsp.global("ryoku:launcher")'` | Mei's launcher opens over your desktop; your own bar stays exactly where it was | the launcher is modal: it takes an exclusive keyboard grab, so your own clicks dismiss it and your keys land in its search box. That is expected. If it does not open at all, close it with Esc and report it | Esc, then `./mei live-stop` |
| 2 | watch the launcher's **horizon line** (the wave in the card) for a few seconds | it moves smoothly. It repaints about 24 times a second on a 144 Hz panel (Phase 10B), so it is *not* a 144 Hz animation any more. Judge it: smooth, or a visible step? | if it stutters, say so: the fix is to raise the repaint rate, and the line is on the final checklist either way | Esc |
| 3 | type `a browser` in the launcher and press Enter | a browser opens **with your real profile** (your bookmarks, your history, your extensions). Mei's launcher now hands every app your real HOME | if a browser opens blank, the launcher still gives apps Mei's fake home: stop, and the fix is in `mei-app` | close the window, `./mei live-stop` |
| 4 | `hyprctl dispatch 'hl.dsp.global("ryoku:quicksettings")'` | Mei's control centre opens. It has its own surface host now, so it opens with the bar off as well | if it does not open, that is a new fault: report it | if it opens, check the audio readout shows your real sink | Esc, `./mei live-stop` |
| 5 | look at your own bar, tray and notifications throughout | no flicker, no hiccup, no toast you did not ask for | a flicker means the two shells fight over a layer surface: report which one | Esc, `./mei live-stop` |
| 6 | press Esc | the launcher closes cleanly and your desktop is yours again | if Esc does not close it, the pointer is over the card: click the scrim | Esc, `./mei live-stop` |

Then:

```bash
./mei live-stop
./mei verify-untouched
busctl --user list | grep -E 'Notifications|StatusNotifierWatcher'
```

Both names must still belong to your **own live shell** (the same pid as before),
and your shell must look exactly as it did.

---

## Stage 2 — full (Mei replaces your shell; give it a calm hour)

```bash
<your previous shell's stop command>          # your own shell's stop command
cd ~/projects/mei
./mei live --profile full  # it prints what it will do, then waits for YES
```

**Before you type YES**, check the preflight table: every name Mei will claim
must be free now that your old shell is stopped.

| # | do | must happen | if it fails | rollback |
|---|---|---|---|---|
| 1 | **the lock, first** — open a **second terminal** first, then trigger the lock (`hyprctl dispatch 'hl.dsp.global("ryoku:lock")'`) | Mei asks the compositor to lock the session: the lock covers every output with a clock and a password field, the bar and the launcher must be unreachable, and a key press must not reach any window. A wrong password is refused; the right one unlocks. **Never try this without the second terminal open** | if the lock cannot be unlocked, `Ctrl+Alt+F3` → log in → `hyprctl dispatch 'hl.clear_crashed_lockscreen()'` → then `<your previous shell's start command>` (your old shell) | the TTY is the escape; it always is. The session stays locked on purpose if the shell dies, and that one command clears it |
| 2 | leave the desktop alone for 3 minutes | the screen dims, then locks, then the display sleeps — with Mei's own timeouts, and an app playing video must hold it off | if the screen sleeps while you are typing, the idle timers are wrong: report the times you saw | TTY |
| 3 | open the launcher (your SUPER + D) and search for `a browser` | it opens with your real profile, as in stage 1 | as in stage 1 | close it |
| 4 | the **bar**: watch it for a minute at 144 Hz | the workspace cells match Hyprland, the clock is right, the widgets are readable, and nothing flickers. The pill/motion animation must be smooth | a stutter in the bar is a different problem from the launcher's wave: say which | `./mei live-stop`, then `<your previous shell's start command>` |
| 5 | the **launcher's horizon line**, again | smooth | as in stage 1 | as in stage 1 |
| 6 | the **sidebar**: open it, move the volume, look at the brightness | the audio readout shows your real sink, the volume moves it, the brightness moves your panel and comes back to where it was | if the brightness does not come back, set it by hand and report it | as above |
| 7 | the **OSD**: press the volume and brightness keys | the popups appear with the right value and the same motion as before | no OSD means the feed is not running: report | as above |
| 8 | the **media keys** with a browser playing something | play/pause, next and previous work on the real session | the daemon's `music.track` verb may be wrong for your player: report which key did what | as above |
| 9 | the **clipboard** (SUPER + C) | the history shows what you copied, it is bounded, and clear-all empties it | if it is empty, the selection watcher is not seeing the host clipboard: report | as above |
| 10 | the **wallpaper picker** (SUPER + P) | it offers **only** your own Pictures/Wallpapers folder. Nothing from Wallhaven, a game launcher or any other service, and nothing leaves the machine | if a network source appears, stop and report it at once: that is a hard stop | as above |
| 11 | the **network panel** on your real Wi-Fi | it shows your real connections. Do **not** connect or disconnect anything yet | if it cannot read the list, report it | as above |
| 12 | the **Bluetooth panel** | it shows your devices. Do not pair or unpair anything | if it cannot read the list, report it | as above |
| 13 | the **polkit prompt** (run `pkexec true` in a terminal) | Mei's prompt appears, takes your password, and the command runs. Only one agent is ever registered: if your old shell were still running, the new one must refuse | if two prompts appear, or none, report it at once | as above |
| 14 | the **tray** with your real apps, including **your VPN app** and **a game launcher** | their icons appear, the menus open and close, and the icons are the ones you expect | a missing icon is a missing SNI host: report which app | as above |
| 15 | **notifications** from a real app (a chat message, a download) | it arrives, looks right, and its actions work | if nothing arrives, the notification server is not claiming the name: report it | as above |
| 16 | the **power menu** in the control centre | the buttons are there. **Logout, reboot and shutdown are stubbed in the first live trial** (MEI_STUB_POWER=1), so pressing them must log a stub and do nothing. The lock button is the only real one | if a power button really reboots the machine, that is a hard stop: report it at once | as above |
| 17 | the **wallpaper** (SUPER + P → pick one) | it appears smoothly, the colours re-theme without a flash or a black screen | a black screen is a hard stop: `Ctrl+Alt+F3` and restore | TTY |
| 18 | **workspaces**: SUPER + 1..0 | the compositor switches and Mei's bar follows | if the bar does not follow, the workspace sync is broken: report it | as above |

Then:

```bash
./mei live-stop
<your previous shell's start command>          # your old shell back
```

---

## The lock, in detail

Mei's lock **is the compositor's session lock** (Hyprland's ext-session-lock-v1):
the shell asks the compositor to lock the session and gives it a surface with
the clock and the password field. What that means:

| | Mei's lock |
|---|---|
| what it covers | the whole session, every output: no other client can draw over it and no key press reaches a window |
| how it unlocks | the account password, checked against PAM by the daemon, and then the shell tells the compositor to unlock |
| if the lock client crashes | the session **stays locked by design**. Hyprland keeps the lock until it is told otherwise (`CSessionLockManager::clientLocked`), because a lock that opens by itself is not a lock. The recovery is below, and it is one command |
| what the compositor says | `active secure`: the compositor confirms the lock and calls it secure |

**The PAM service the live lock uses** and the files it reads:

- the service is **`login`** (`/etc/pam.d/login`), which on Arch includes
  `pam_unix.so`, so the account's hash in `/etc/shadow` is what is checked;
- the helper (`src/ryoku/shell/scripts/mei-lock-verify`) reads **nothing else**
  and writes **nothing**; it opens the service file and asks libpam;
- the password travels from the lock screen to the daemon on the control
  socket's **own line**, and from there into the helper's **standard input** —
  never in argv, never in the environment, never in a file, never in a log;
- `MEI_LOCK_PAM_SERVICE` can name a different service (a *name*, not a path:
  libpam resolves it inside the system PAM directory, so a project-local PAM
  service would need root and is not possible here);
- `./mei lock-selftest` checks all of it without locking anything: the helper
  exists, the service file is readable, and a real PAM round trip with a
  deliberately wrong password comes back as a refusal.

**If the lock cannot be opened, it does not open.** The lock asks the daemon
whether the PAM setup is usable *before* it covers the screen; if it is not,
the lock refuses and says so in a notification. A lock you cannot open is a
way to lose the session, so that case is a refusal, not a lock.

**The remaining risk, stated plainly:** the harness can prove that a wrong
password is refused (that is a real PAM round trip against the real `login`
service) and that the lock's state machine works, but the *accepted* path
needs your own password. That is why the lock is the first item of the full
stage.

**If the screen goes blank and the lock is up:** Ctrl+Alt+F3 (or F2) gives you
a TTY, log in as `mei`, and run

```bash
bash ~/projects/mei/docs/revert-to-previous-shell.sh
```

which stops Mei and starts <your previous shell> again. Ctrl+Alt+F2 returns to the
graphical session. Your data is never at risk: Mei writes only inside
`~/projects/mei/.run`.

**If the lock screen is there but nothing moves** (the shell died while the
lock was up, so the compositor is still holding a lock whose client is gone):
the compositor's own function clears that, and it is the only thing that can:

```bash
hyprctl dispatch 'hl.clear_crashed_lockscreen()'
```

The answer is the line the function prints. Two answers matter:

- `hl.clear_crashed_lockscreen: session is not locked` — there was no crashed
  lock to clear, so the session is already usable: go back with Ctrl+Alt+F2;
- `session is locked with a client, refusing to unlock` — the shell is still
  alive and still holds the lock. Kill it from the TTY and run the command
  again:

  ```bash
  pkill -f 'qs -p .*quickshell/shell'
  hyprctl dispatch 'hl.clear_crashed_lockscreen()'
  ```

The command always ends with `hl.dispatch: expected a dispatcher` on the line
after the answer. That is the dispatch complaining about the function's return
value; the answer above it is the one to read.

---

## Switching over (one page)

Do this only after the overlay stage and the full stage have both felt right,
and keep the previous shell installed for a few weeks afterwards.

1. **Back up first** (you do this, not the agent):
   ```bash
   tar czf ~/the previous shell-backup.tar.gz ~/.local/share/the previous shell ~/.config/hypr
   ```
2. **In `~/.config/hypr/config/autostart.lua`**, comment out your line:
   ```lua
   # hl.exec_cmd("<your previous shell's start command>")
   ```
   and add Mei's:
   ```lua
   hl.exec_cmd("~/projects/mei/mei start --fallback \"<your previous shell's start command>\"")
   ```
   `mei start` never asks a question, does nothing if Mei is already running,
   and refuses (with a log line and a non-zero exit) if your old shell still
   owns the notification or tray name, so a double start cannot happen. The
   `--fallback` only runs when no Mei process is left, so the two shells are
   never both running.
   **Do not add `--real-power` yet.** Without it, logout, reboot and suspend
   stay stubbed and only the lock is real. Add `--real-power` when you have
   tried logout and suspend by hand and they behaved.
3. **Log out and back in** (or run `<your previous shell's stop command>` and then Mei's line).
4. **The revert**, whenever you want it: `SUPER + SHIFT + R` (the rescue bind
   in `docs/keybinds-for-mei.lua`, which depends on no shell at all), or
   ```bash
   bash ~/projects/mei/docs/revert-to-the previous shell.sh
   ```
   That stops Mei and starts <your previous shell>. It deliberately does **not** edit
   your Hyprland config: the autostart line stays a manual step, so nothing
   rewrites your configuration behind your back. Uncomment your
   `hl.exec_cmd("<your previous shell's start command>")` line and comment Mei's, then log out
   and back in.
5. **If the screen is blank:** Ctrl+Alt+F3, log in, run the revert script,
   Ctrl+Alt+F2 to come back.

**What you lose by turning the previous shell off** (the full list, with what each
would cost to add, is in `docs/PARITY.md`): the wellbeing guide, the calendar,
the quick-actions palette, the autohide toggle, the SUPER+SHIFT+number
move-a-window bind, the image editor on SHIFT+Print, and (until it is built)
Mei's own idle timeouts. The tray, notifications, wallpaper, popouts, dock,
network and Bluetooth panels, screenshots, OSD, media keys, clipboard, the
power menu and the lock all exist in Mei.

---

## If the screen goes blank

1. `Ctrl+Alt+F3` (or F2) — a TTY. Your session is still running behind it.
2. Log in as `mei`.
3. Bring the old shell back:
   ```bash
   <your previous shell's start command>
   ```
   or, if Mei is the one that is stuck:
   ```bash
   cd ~/projects/mei && ./mei live-stop
   ```
4. `Ctrl+Alt+F2` (or F1) to come back to the graphical session.

Your data is never at risk: Mei writes every file it owns inside
`~/projects/mei/.run`, and your old shell's state is in your own home.

---

## The final checklist (things that are not worth a live run)

- [ ] the launcher's **horizon line** smoothness at 144 Hz (stage 1 item 2, stage 2 item 5) — *not judged yet*
- [ ] the tray glyphs and menus of your VPN app and a game launcher
- [ ] the real audio hardware (the sink, the mic) and the brightness slider on the real panel
- [ ] the wallpaper reveal and the re-colour on the real display
- [ ] whether Mei's bar fits your real 1920x1080 panel
- [ ] the idle timeouts you actually want (dim, lock, DPMS, suspend) and the inhibitor behaviour
- [ ] the lock screen's look, and that it never locks you out

## What is still different from your previous shell

Everything here is a difference you would notice in the first hour. Nothing
else is missing: the bar, the launcher, the quick settings, the settings app,
the wallpaper and the palette, the notifications, the tray, the media keys,
the OSD, the clipboard, the screenshots, the polkit prompt, the power menu,
the idle timeouts and the lock are all in Mei and tested nested.

| difference | what it means for you | status |
|---|---|---|
| **Wi-Fi and Bluetooth are not in Mei** | the panels were deferred, so use `nmtui` and `bluetoothctl` in a terminal (or the system tray's own menu). Your connections, your VPN and your adapter are never touched by Mei | DEFERRED, by your decision |
| **the screen recording** | Mei does not record the screen. If you never record, nothing is missing; if you do, the old shell's tool is still installed | your call |
| **the lock's accept path** | Mei's lock is the compositor's own now, so a crash leaves the session **locked** (that is the point). The recovery is one command from a TTY, and it is written down above | UNVERIFIED: only you can type your password |
| **the lock on a second output** | the nested session has one output, so the second screen of your session is untested | UNVERIFIED: yours to check |
| **the compositor's inhibitors** | a video player that holds an idle-inhibit keeps the machine awake; Mei's own D-Bus inhibitors are proven, the compositor's are not | UNVERIFIED: play a video and see |
| **the idle with your real panel** | the dim and the exact restore are proven against a file, not against your backlight | UNVERIFIED: yours to watch |
| **the feel at 144 Hz** | nothing nested can prove how it feels | UNVERIFIED: yours to feel |
| **the horizon line's smoothness** | the wave repaints on 0.35 px of movement (about 24 times a second, so it never misses a frame at 144 Hz) | UNVERIFIED: yours to see |

## The terminal fallbacks, for the deferred panels

- `nmtui` — the network connections, the same as NetworkManager's own tool.
- `bluetoothctl` — the adapter, the paired devices, the pairing itself.
- The system tray's own menu still shows the network and the Bluetooth items
  that your previous shell put there, as long as it is running.

Neither tool is started by Mei, and Mei never changes a connection, a VPN or
an adapter.
