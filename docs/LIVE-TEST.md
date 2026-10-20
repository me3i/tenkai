# LIVE-TEST.md — running Mei on your own desktop

Read this whole file before you start. It is a runbook for **you**, not for the
harness: the agent never runs any of it, and `./mei live` is built so that a
mistake in one stage cannot damage the other.

Two stages:

| stage | what runs | your old shell | how long |
|---|---|---|---|
| **1. overlay** | Mei's launcher, quick settings and Settings only | keeps running, keeps its bar, its tray, its notifications and its wallpaper | ~10 minutes |
| **2. full** | all of Mei: bar, launcher, quick settings, Settings, tray, notifications, wallpaper | **stopped** first; Mei takes its place | as long as you want |

Never do stage 2 before stage 1 is clean.

---

## 1. What your current shell is, and what it owns

Read-only investigation, 2026-10-20, no changes made.

**How your live Quickshell starts:**

```
quickshell -p $HOME/.local/share/the previous shell/src/quickshell/Shell.qml
```

Its process chain is:

```
846  Hyprland --watchdog-fd 4                 <- the live compositor
910    bash /usr/local/bin/<your previous shell's start command> <- started by the autostart
949      quickshell -p .../the previous shell/src/quickshell/Shell.qml
```

The autostart line lives in your own Hyprland config:

```lua
-- ~/.config/hypr/config/autostart.lua:5
hl.exec_cmd("<your previous shell's start command>")
```

**What your live shell owns that Mei would collide with** (owner in brackets):

| what | owner | notes |
|---|---|---|
| `org.freedesktop.Notifications` | your live shell | the notification daemon — **Mei would take this name in the full profile** |
| `org.kde.StatusNotifierWatcher` | your live shell | the tray watcher — **Mei would take this name in the full profile** |
| `org.kde.StatusNotifierHost-<your shell>` | your live shell | its own SNI host; app-owned, ignored |
| layer surface `wallpaper-bg` (1920x1080) | your live shell | your wallpaper |
| layer surface `quickshell` (the bar, at the top edge) | your live shell | your bar, at the top edge |
| layer surface `qs-floating-overlay` (1920x1080) | your live shell | your full-screen transparent overlay |
| global shortcuts over the protocol | **none** | `hyprctl globalshortcuts` says "none", so Mei's `ryoku:*` names are free |
| 671 key binds | your Hyprland config | all of them dispatch to your own shell (`the previous shell ...`) |
| your wallpaper | your live shell (it draws the layer itself) | no hyprpaper/swww is running |

Mei's overlay profile claims **none** of the names above: its D-Bus names, its
screen edge and its wallpaper are all off, and its layer namespaces
(`launcher`, `ryoku-control`, `ryoku-osd`) do not exist in your session.
`./mei live --profile overlay` prints that table and checks it against your
live session before it starts anything.

**Your brightness keys are in your own config** (this also explains the two
brightness steps that appeared during Phase 10B — nothing in the harness ever
wrote the backlight):

```lua
-- ~/.config/hypr/config/keybinds.lua:26
hl.bind("XF86MonBrightnessDown", hl.dsp.exec_cmd("the previous shell brightness lower"), { locked = true })
```

---

## 2. The two commands (copied from your config, **not yet run**)

**Stop your current shell:**

```bash
<your previous shell's stop command>
```

*Copied from `/usr/local/bin/<your previous shell>` (its `stop` verb), which your
autostart line `hl.exec_cmd("<your previous shell's start command>")` starts. Not yet run by the
agent — check that it reads as the command you expect before you use it.*

**Bring it back:**

```bash
<your previous shell's start command>
```

*Copied from your own autostart line in `~/.config/hypr/config/autostart.lua:5`.
Not yet run by the agent.*

If `<your previous shell's stop command>` leaves anything behind, `<your previous shell> status` tells you
what it thinks is running.

---

## 3. Stage 1 — overlay (your old shell keeps running)

```bash
cd ~/projects/mei
./mei live --profile overlay
```

It prints:

* the names, sockets and layer surfaces Mei will claim, and whether your live
  session already owns any of them (it refuses to start if one collides);
* the shell pid, the monitor log path, and the commands that open the launcher
  and the quick settings.

The **monitor starts by itself** with `./mei live` — there is no second command
to run. It writes `.run/logs/live-monitor-<stamp>.log` and `.csv` every 5 s.

**Opening the surfaces** (run these yourself, from your own terminal — no
Hyprland config change is needed, and none is made):

```bash
hyprctl dispatch 'hl.dsp.global("ryoku:launcher")'      # the launcher
hyprctl dispatch 'hl.dsp.global("ryoku:quicksettings")'  # the quick settings
```

**Note the syntax.** Your Hyprland config is **Lua**, so the bare
`hyprctl dispatch global ryoku:launcher` is a Lua syntax error there
(`'\'' )' expected near 'ryoku'`) and does nothing. The explicit
`hl.dsp.global("...")` form is the one that works — that is the same form the
nested harness uses. (The *shortcut* itself is registered by Mei's shell over
the global-shortcuts protocol, so no config bind is needed either way.)

Why that works without touching your config: Mei's shell registers the
shortcut names `ryoku:launcher` / `ryoku:quicksettings` with the compositor
over the **global-shortcuts protocol**, not through a config bind. That was
verified in the nested session with the config bind removed: the dispatch still
opened the launcher. The fallback, if the compositor ever refuses the dispatch:

```bash
qs ipc --pid <the shell pid printed by ./mei live> call shell openSurface "" launcher
```

### Stage 1 checklist (short)

- [ ] `./mei live --profile overlay` starts and prints "No collision".
- [ ] Your own bar, tray, wallpaper and notifications are **still there and
      unchanged** — Mei is a guest here.
- [ ] `hyprctl dispatch global ryoku:launcher` opens Mei's launcher over your
      desktop; Esc closes it.
- [ ] The launcher opens a real app (kitty) **with your real profile**: the
      terminal shows your own home, your own PATH, your own dotfiles.
- [ ] The quick settings opens; the audio readout shows your real sink and the
      brightness slider shows your real panel value.
- [ ] Nothing appeared that you did not ask for: no bar, no wallpaper change,
      no notification toast, no tray icon.
- [ ] `~/projects/mei/.run/logs/live-monitor-*.log` is filling in (CPU and RSS
      every 5 s).
- [ ] `./mei live-stop` stops Mei; your shell is untouched.

---

## 4. Stage 2 — full (Mei replaces your shell)

```bash
cd ~/projects/mei
./mei live --profile full
```

It **refuses** while your current shell still owns
`org.freedesktop.Notifications` or `org.kde.StatusNotifierWatcher` — that is
the point: it will not fight your running shell for the same names.

So the order is:

```bash
<your previous shell's stop command>          # your shell's own stop command
cd ~/projects/mei
./mei live --profile full  # prints what it will do, then waits for YES
```

It prints what it is about to do and waits for you to type `YES`.

**What the full profile changes** (all of it inside the project or in your
session's own runtime, nothing in your config files):

- it takes `org.freedesktop.Notifications` and `org.kde.StatusNotifierWatcher`
  on the live bus;
- it draws the wallpaper, the bar, the tray and the notification column;
- it starts ryogami with the live-display guard **explicitly overridden**
  (`MEI_ALLOW_LIVE_DISPLAY=1` — set only by `--profile full`; every other path
  still refuses);
- the power actions are **stubbed** for this first trial: logout, reboot,
  suspend and shutdown all log `[mei-stub] suppressed` instead of running.
  **Lock stays real.** (They are inert in this build anyway: the daemon does
  not register the session verbs, so the sidebar's power buttons do nothing
  either way. The stub is there so that stays true if that ever changes.)
- every file it writes stays in `~/projects/mei/.run`; apps it launches get
  your **real** HOME and XDG variables;
- your Hyprland config is never written.

### Stage 2 checklist (long)

- [ ] `<your previous shell's stop command>` stops your old shell; your bar and wallpaper are
      gone (that is expected — Mei draws its own now).
- [ ] `./mei live --profile full` refuses while the old names are owned, and
      starts after you type YES.
- [ ] **Bar**: it fits your 1920x1080 panel; the workspace cells match
      Hyprland; the clock is right; the widgets are readable.
- [ ] **At 144 Hz**: the bar's pill/motion animation is smooth (no stutter,
      no double image), and the launcher's **horizon line** — the wave inside
      the launcher's card — moves smoothly. *This is the one to look at: the
      wave now repaints about 24 times a second instead of once per frame
      (Phase 10B), and the nested numbers say the picture is unchanged, but
      only your display can settle it.*
- [ ] **Launcher**: opens with the bound key; the search finds your real
      apps; opening one runs it with **your real profile** (your home, your
      PATH, your dotfiles, your fonts).
- [ ] **Quick settings**: the audio readout shows your real sink and the
      volume slider moves it; the brightness slider moves your real panel
      (and comes back to where it was); the network and battery entries show
      your real hardware.
- [ ] **Notifications**: a real notification arrives (from any app) and looks
      right; the actions on it work.
- [ ] **Tray**: icons appear for your real apps, including **your VPN app** and
      **a game launcher**; the menus open and close.
- [ ] **Wallpaper**: setting one reveals it smoothly; the colours re-theme
      (matugen) without a flash or a black screen.
- [ ] **Lock** only: the lock action works. Do **not** try logout, reboot or
      shutdown in the first trial — all of them are stubbed on purpose (they
      log `[mei-stub] suppressed` and nothing happens), and the lock is the
      one action that stays real.
- [ ] `live-monitor-*.log` shows the CPU and RSS; compare them with the
      nested numbers below.
- [ ] `./mei live-stop` stops Mei; then `<your previous shell's start command>` brings your old
      shell back and everything is as it was.

---

## 5. If the screen goes blank

1. **Ctrl+Alt+F3** (or F2) — the virtual console. Your session keeps running
   in the background; this is a console switch, not a crash.
2. Log in as `mei` at the console.
3. Restore one of:
   ```bash
   cd ~/projects/mei && ./mei live-stop     # stop Mei
   <your previous shell's start command>                       # bring your old shell back
   ```
4. If the console is unusable, reboot: `systemctl reboot`.

Your data is never at risk here: Mei writes every file it owns inside
`~/projects/mei/.run`, and your own shell's state is in your own home.

---

## 6. The numbers to compare against

The nested Phase 10A table (`.run/logs/phase10a-20261020-150253.log`) is the
baseline, but remember two things: the nested session renders in software, and
your panel is 144 Hz while the nested output was 60 Hz.

| state | Mei total RSS | PSS | CPU per 60 s |
|---|---:|---:|---:|
| idle | 611,760 kB | 345,024 kB | 1.60 s |
| launcher open | 645,380 kB | 375,245 kB | 19.65 s (before Phase 10B) |
| launcher open, after Phase 10B | ~645,000 kB | ~375,000 kB | 13.45 s (nested) |
| Settings open | 1,032,392 kB | 492,573 kB | 1.92 s |
| your live Quickshell 949 (reference) | 585,064 kB | 419,087 kB | 0.84 s |

The live monitor writes a line every 5 s:

```
.run/logs/live-monitor-<stamp>.log    # human readable, with a TOTAL line
.run/logs/live-monitor-<stamp>.csv    # the same numbers, per process
```

---

## 7. What is still unproven

- 144 Hz smoothness and animation feel (your eyes only).
- The real tray glyphs and menus of your VPN app and a game launcher.
- Real audio hardware writes and the brightness slider on the real panel.
- The wallpaper reveal and re-colour on the real display.
- Whether the bar fits your real 1920x1080 panel.
- The launcher's horizon line after the Phase 10B repaint change (see above).
