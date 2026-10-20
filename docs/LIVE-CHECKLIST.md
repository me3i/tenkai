# LIVE-CHECKLIST — what only you can verify

Short, ordered, and each item says what to do, what must happen, what to do if
it fails, and how to roll back. Do it with **serpantinum still installed** (the
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
| 3 | type `Firefox` in the launcher and press Enter | Firefox opens **with your real profile** (your bookmarks, your history, your extensions). Mei's launcher now hands every app your real HOME | if Firefox opens blank, the launcher still gives apps Mei's fake home: stop, and the fix is in `mei-app` | close the window, `./mei live-stop` |
| 4 | `hyprctl dispatch 'hl.dsp.global("ryoku:quicksettings")'` | Mei's control centre opens. It has its own surface host now, so it opens with the bar off as well | if it does not open, that is a new fault: report it | if it opens, check the audio readout shows your real sink | Esc, `./mei live-stop` |
| 5 | look at your own bar, tray and notifications throughout | no flicker, no hiccup, no toast you did not ask for | a flicker means the two shells fight over a layer surface: report which one | Esc, `./mei live-stop` |
| 6 | press Esc | the launcher closes cleanly and your desktop is yours again | if Esc does not close it, the pointer is over the card: click the scrim | Esc, `./mei live-stop` |

Then:

```bash
./mei live-stop
./mei verify-untouched
busctl --user list | grep -E 'Notifications|StatusNotifierWatcher'
```

Both names must still be **PID 949**, and your shell must look exactly as it did.

---

## Stage 2 — full (Mei replaces your shell; give it a calm hour)

```bash
serpantinumd stop          # your own shell's stop command
cd ~/projects/mei
./mei live --profile full  # it prints what it will do, then waits for YES
```

**Before you type YES**, check the preflight table: every name Mei will claim
must be free now that your old shell is stopped.

| # | do | must happen | if it fails | rollback |
|---|---|---|---|---|
| 1 | **the lock, first** — open a **second terminal** first, then trigger the lock (`hyprctl dispatch 'hl.dsp.global("ryoku:lock")'`) | Mei's lock screen covers the desktop with a clock and a password field. The bar and the launcher must be unreachable. A wrong password is refused; the right one unlocks. **Never try this without the second terminal open** | if the lock cannot be unlocked, `Ctrl+Alt+F3` → log in → `serpantinumd start` (your old shell) | the TTY is the escape; it always is. Mei's lock is its own surface, so it can never lock the session itself |
| 2 | leave the desktop alone for 3 minutes | the screen dims, then locks, then the display sleeps — with Mei's own timeouts, and an app playing video must hold it off | if the screen sleeps while you are typing, the idle timers are wrong: report the times you saw | TTY |
| 3 | open the launcher (your SUPER + D) and search for `Firefox` | it opens with your real profile, as in stage 1 | as in stage 1 | close it |
| 4 | the **bar**: watch it for a minute at 144 Hz | the workspace cells match Hyprland, the clock is right, the widgets are readable, and nothing flickers. The pill/motion animation must be smooth | a stutter in the bar is a different problem from the launcher's wave: say which | `./mei live-stop`, then `serpantinumd start` |
| 5 | the **launcher's horizon line**, again | smooth | as in stage 1 | as in stage 1 |
| 6 | the **sidebar**: open it, move the volume, look at the brightness | the audio readout shows your real sink, the volume moves it, the brightness moves your panel and comes back to where it was | if the brightness does not come back, set it by hand and report it | as above |
| 7 | the **OSD**: press the volume and brightness keys | the popups appear with the right value and the same motion as before | no OSD means the feed is not running: report | as above |
| 8 | the **media keys** with Firefox playing something | play/pause, next and previous work on the real session | the daemon's `music.track` verb may be wrong for your player: report which key did what | as above |
| 9 | the **clipboard** (SUPER + C) | the history shows what you copied, it is bounded, and clear-all empties it | if it is empty, the selection watcher is not seeing the host clipboard: report | as above |
| 10 | the **wallpaper picker** (SUPER + P) | it offers **only** your own Pictures/Wallpapers folder. Nothing from Wallhaven, Steam or any other service, and nothing leaves the machine | if a network source appears, stop and report it at once: that is a hard stop | as above |
| 11 | the **network panel** on your real Wi-Fi | it shows your real connections. Do **not** connect or disconnect anything yet | if it cannot read the list, report it | as above |
| 12 | the **Bluetooth panel** | it shows your devices. Do not pair or unpair anything | if it cannot read the list, report it | as above |
| 13 | the **polkit prompt** (run `pkexec true` in a terminal) | Mei's prompt appears, takes your password, and the command runs. Only one agent is ever registered: if your old shell were still running, the new one must refuse | if two prompts appear, or none, report it at once | as above |
| 14 | the **tray** with your real apps, including **ProtonVPN** and **Steam** | their icons appear, the menus open and close, and the icons are the ones you expect | a missing icon is a missing SNI host: report which app | as above |
| 15 | **notifications** from a real app (a chat message, a download) | it arrives, looks right, and its actions work | if nothing arrives, the notification server is not claiming the name: report it | as above |
| 16 | the **power menu** in the control centre | the buttons are there. **Logout, reboot and shutdown are stubbed in the first live trial** (MEI_STUB_POWER=1), so pressing them must log a stub and do nothing. The lock button is the only real one | if a power button really reboots the machine, that is a hard stop: report it at once | as above |
| 17 | the **wallpaper** (SUPER + P → pick one) | it appears smoothly, the colours re-theme without a flash or a black screen | a black screen is a hard stop: `Ctrl+Alt+F3` and restore | TTY |
| 18 | **workspaces**: SUPER + 1..0 | the compositor switches and Mei's bar follows | if the bar does not follow, the workspace sync is broken: report it | as above |

Then:

```bash
./mei live-stop
serpantinumd start          # your old shell back
```

---

## If the screen goes blank

1. `Ctrl+Alt+F3` (or F2) — a TTY. Your session is still running behind it.
2. Log in as `mei`.
3. Bring the old shell back:
   ```bash
   serpantinumd start
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
- [ ] the tray glyphs and menus of ProtonVPN and Steam
- [ ] the real audio hardware (the sink, the mic) and the brightness slider on the real panel
- [ ] the wallpaper reveal and the re-colour on the real display
- [ ] whether Mei's bar fits your real 1920x1080 panel
- [ ] the idle timeouts you actually want (dim, lock, DPMS, suspend) and the inhibitor behaviour
- [ ] the lock screen's look, and that it never locks you out
