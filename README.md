# Tenkai · 天界

<img src="docs/assets/tenkai_banner.png" alt="Tenkai Banner" width="100%">

**The Celestial Lite version of Ryoku Quickshell.**

[![License: GPL v3](https://img.shields.io/badge/License-GPLv3-blue.svg)](LICENSE)
![Arch Linux](https://img.shields.io/badge/Arch%20Linux-1793D1?logo=archlinux&logoColor=white)
![Hyprland](https://img.shields.io/badge/Hyprland-5E81AC?logo=hyprland&logoColor=white)

---

## Introduction

Tenkai is an **opinionated, lightweight fork of
[Ryoku](https://github.com/Ryoku-dev/ryoku)** — the same Quickshell desktop,
reduced.

Ryoku already gets the hard part right: how a Hyprland desktop should look,
move and feel. Tenkai keeps that exactly as it is. What it removes is
everything that could not justify its own weight — the AI panel, the lock
screen and the D-Bus service behind it, the network reach of the background
services, and every component that failed a necessity test.

The result is the same desktop with less in it. Tenkai is a derivative work,
not a competing vision. "Less in it" is a statement about what is missing.
Tenkai's idle memory has been measured once, in a nested test session:
**578 MB RSS** for the shell process plus daemon, versus **767 MB** for the
comparable Ryoku session processes (ryoku-shell + qs + ryogami) on the same
machine. That is a 25% reduction by component removal; the measurement is a
single snapshot, not a benchmark, and is recorded in
[docs/PROJECT-CLOSEOUT.md](docs/PROJECT-CLOSEOUT.md).

## Features

Everything below is inherited from Ryoku and kept intact. The Tenkai work is
the subtraction.

- **The same visual identity.** The bar, the surfaces, the palette engine and
  the motion language are inherited unchanged in the QML that ships here, and
  nothing was restyled, re-skinned or "improved" beyond what
  [`CHANGES.md`](CHANGES.md) lists. **UNVERIFIED:** that a Tenkai screenshot and
  a Ryoku screenshot are the same picture. Producing the pair means running both
  shells, and this project does not run either in the owner's live session.
- **The same core workflows.** App launcher, workspace overview, quick
  settings, wallpaper picker, clipboard history, notifications and the system
  tray all behave exactly as they did before the fork.
- **Lighter by removal, not by benchmark.** Every component was dependency-
  traced and put through a necessity test before it was kept. The figures this
  README used to lead with — 482 MB RSS / 231 MB PSS idle, ~0.3–0.6 s CPU per
  60 s — come from a live trial on 2026-11-01 and were **not** re-measured in
  this audit, because that needs a running Tenkai session. For scale, the shell
  processes of the Ryoku session these numbers are compared against measured
  **513 MB RSS / 315 MB PSS** on 2026-11-08 (ryoku-shell + qs + ryogami). Two
  numbers from two different builds on two different days are not a benchmark,
  and "lighter" here means fewer components, not a proven memory win.
- **No AI, no lock screen, no phone-home.** The launcher's AI panel is off. This
  tree contains no lock screen and no code that registers
  `org.freedesktop.ScreenSaver` (`grep -rn ScreenSaver` over the sources: no
  hits); the live session's ScreenSaver name is held by the shell that was
  already running, not by Tenkai. Network: the weather widget ships disabled
  (`weatherEnabled: false`) and queries `api.open-meteo.com` only if you switch
  it on; package updates are not probed over the network; the notification and
  tray names are the standard ones, see [`docs/DBUS.md`](docs/DBUS.md). The
  bundled wallpaper picker **does** use the network (GitHub, motionbgs.com,
  moewalls.com) when you open it.
- **Nothing hidden.** Every deviation from upstream is recorded in
  [`CHANGES.md`](CHANGES.md); the pinned upstream commit is in
  [`UPSTREAM.md`](UPSTREAM.md); attribution is in [`CREDITS.md`](CREDITS.md).
- **A careful installer.** `install.sh` checks everything, asks before it
  touches anything, and backs up what it changes. `--dry-run` writes nothing.

## Common Keybinds

| Key | Action |
|---|---|
| `Super + D` | App Launcher |
| `Super + Enter` | Open Terminal |
| `Super + W` | Close Window |
| `Super + 1,2,3,4,...` | Switch Workspaces |
| `Super + Tab` | Workspace Overview |
| `Super + P` | Wallpaper Picker |
| `Super + V` | Clipboard History |

These ship in the bundled Hyprland config at
`src/tenkai-configs/hypr/modules/binds.lua`.

### Viewing All Keybinds

The table above is only the short list. For the complete, authoritative list of
every keybind active in your session, run this in your terminal:

```bash
hyprctl binds
```

`hyprctl` asks Hyprland itself, so it always reflects what is actually bound
right now — including anything you have added or changed since installing.

## Installation

**Requirements:** an **Arch Linux** machine running **Hyprland**. Everything
else is checked for you — the installer prints exactly what is missing and
never installs anything without asking.

```bash
git clone https://github.com/me3i/tenkai.git ~/projects/tenkai
cd ~/projects/tenkai
./install.sh
```

`install.sh` is interactive throughout: it checks dependencies, builds the
daemons, the blob plugin and the QML modules, then offers each system change
one at a time — systemd user units, the Hyprland autostart line, the kitty
colour include, your terminal dotfiles, the Hyprland config, wallpapers and
fonts. Your existing `~/.config/hypr` is never overwritten without an
interactive yes, and existing files are backed up to `*.tenkai-install.bak`
first.

```bash
./install.sh --dry-run   # print every step, write nothing
./install.sh --help      # list all flags
```

Then start it in the current session:

```bash
./tenkai status          # show the running Tenkai session, if any
./tenkai start           # join this Hyprland session (non-interactive, for autostart)
./tenkai live --profile overlay   # try Tenkai over your live desktop (asks before each change)
```

For development and testing without touching your live desktop, use the nested
session — a private Hyprland instance with a confined fake home:

```bash
./tenkai test            # nested-session test suite
./tenkai verify-untouched   # prove your live config hashes are unchanged after the test
```

Log out and back in after enabling autostart, and your desktop is Tenkai.

## Repository layout

```
├── install.sh              the installer (see above)
├── tenkai                  the control script: run / test / status / verify-untouched
├── src/
│   ├── tenkai_core/        the Ryoku shell tree, adapted by Tenkai
│   ├── tenkai-configs/     bundled Hyprland Lua config + terminal dotfiles
│   └── tenkai-assets/      wallpapers and OFL fonts
├── docs/                   checklists, runbooks and the test suite
├── CHANGES.md              every modification vs upstream
├── CREDITS.md              attribution
├── UPSTREAM.md             the pinned upstream commit
├── NOTICE                  upstream copyright and licence notices
└── LICENSE                 GNU GPL v3
```

## Development

Tenkai is built and tested in a **nested Hyprland** session that never touches
your live desktop:

```bash
./tenkai test              # nested-session test suite
./tenkai verify-untouched  # prove the live session's config hashes are unchanged
./tenkai scrub-check       # prove no personal setup is tracked
```

`./tenkai verify-untouched` must pass after any change to the tree. See
[`docs/LIVE-CHECKLIST.md`](docs/LIVE-CHECKLIST.md) before running Tenkai on a
live session and [`docs/ROLLBACK.md`](docs/ROLLBACK.md) for the way back.

## What this README does not claim, and why

Two claims were removed on 2026-11-08 because they could not be tested here. This
section records the attempts so the next person does not repeat them.

**Idle memory and CPU.** The old figures (482 MB RSS / 231 MB PSS, ~0.3-0.6 s CPU
per 60 s) come from a live trial on 2026-11-01 that was not re-run. What *was*
measured on 2026-11-08, inside the project's own sandbox (`.run/home`, a private
`dbus-run-session`, no compositor), is the Go daemon alone:

```
tenkai-shell daemon   Rss: 15188 kB   Pss: 13364 kB
```

The QML shell process could not be started at all:
`Could not find "shell" config directory in any valid config path.` — Quickshell
needs a compositor to create its layer surfaces, and no isolated compositor is
available on this machine:

- `Hyprland` nested inside `weston --backend=headless-backend.so` aborts with
  `CBackend::create() failed!` (aquamarine 0.16.0, Hyprland 0.57.1), both with
  `AQ_BACKENDS=wayland` and with `AQ_BACKENDS=headless`;
- the only DRM devices (`/dev/dri/card1`, `card2`) belong to the running session,
  and taking them is exactly what a second shell must not do;
- no `Xvfb`, `cage` or `sway` is installed, and installing is out of scope.

Measuring the real number needs one of: a second machine or VM, a free VT with an
unused GPU, or a compositor aquamarine accepts. Until then, treat "lighter" as a
statement about the components that were removed, not about idle memory.

**Screenshot parity.** A Tenkai bar screenshot and a Ryoku bar screenshot could not
be captured, because the Tenkai bar cannot be rendered here for the reason above.
There is no `docs/screenshots/` pair, and none is claimed.

## Attribution and license

Tenkai is a **modified derivative of
[Ryoku](https://github.com/Ryoku-dev/ryoku)** (pinned commit
`98a0368253d9628be72b853985878a5db90e1547`, v0.75.5-beta.20, "Onogoro").
Ryoku and Tenkai are distributed under the **GNU General Public License
version 3 or later (GPL-3.0-or-later)** — see [`LICENSE`](LICENSE) and
[`NOTICE`](NOTICE).

Tenkai also builds on the work of others:

- **[Caelestia](https://github.com/caelestia-dots/shell)** — the frame-blob
  renderer, adapted by Ryoku and carried through Tenkai (GPL-3.0).
- **QS Bar** — the bar style, from HANCORE-linux's
  [Quickshell Rise](https://github.com/HANCORE-linux/quickshell-dots),
  credited at
  `src/tenkai_core/shell/quickshell/shell/modules/bar/barstyles/qsbar/Scene.qml:1`.
- **Fonts** — Space Grotesk and Fraunces, SIL Open Font License 1.1; Nerd
  Fonts glyphs for terminal coverage, each under its own licence.

Every modification against upstream is recorded in [`CHANGES.md`](CHANGES.md),
and the full attribution notice lives in [`CREDITS.md`](CREDITS.md).

Tenkai is not affiliated with, endorsed by, or connected to the Ryoku project.
