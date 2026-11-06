# Mei

```
 ███╗   ███╗███████╗██╗
 ████╗ ████║██╔════╝██║
 ██╔████╔██║█████╗  ██║
 ██║╚██╔╝██║██╔══╝  ██║
 ██║ ╚═╝ ██║███████╗██║
 ╚═╝     ╚═╝╚══════╝╚═╝
```

**Lightweight, modular, and visually stunning Quickshell environment** — for
Arch Linux + Hyprland, built by copying, trimming and measuring the
[Ryoku](https://github.com/Ryoku-dev/ryoku) shell.

---

## Why Mei

- **Zero bloat.** Every component was put through a necessity test and
  dependency-traced before it was kept. If it is not on the keep list, it is
  not in the build. Simple as that.
- **~500 MB idle RAM.** Measured on a live 144 Hz session: **482 MB RSS /
  231 MB PSS / ~0.3–0.6 s CPU per 60 s** (live trial, 2026-11-01). A full
  nested session with software rendering sits at **657 MB RSS / 311 MB PSS**
  (Phase 10A, nested only). Not vibes — numbers.
- **Material 3 dynamic theming.** Wallpaper in, palette out: matugen drives
  every kept surface, the terminal, GTK, btop, and more. Change the wallpaper,
  watch the whole desktop re-colour.
- **Fully functional Settings.** Reuses Ryoku Settings' look and UI framework
  with Appearance and Shell pages only. It **never** writes or generates your
  Hyprland config — Mei reads live state, it does not own it.
- **Super+Tab overview.** Expo-style live workspace previews with
  drag-and-drop between workspaces.
- **Measured motion.** A full animation language — durations, easing curves,
  popout/pill/blob behaviour — kept centralised so timings can be tuned in
  one place, and never flattened.

## What's inside

| Area | What you get |
|---|---|
| Bar | The qsbar frame: workspaces, clock, audio, brightness, network, battery, tray, notifications |
| Launcher | Fuzzy-finding app launcher on `Super+Space`, with a live horizon wave |
| Overview | Super+Tab workspace expo (live previews, drag between desktops) |
| Quick settings | Super+Escape sidebar: power, Wi-Fi, Bluetooth, audio, lighting |
| Settings | Appearance & Shell pages (`Super+,`): themes, materials, motion, bar, widgets |
| Wallpaper | Selector + `SUPER+P` picker + matugen palette pass |
| Theming | Material You end-to-end: shell, terminal, GTK, btop |
| Config reload | Settings persist to Mei's own config dir (`~/.config/mei`) |

## Keybinds

| Key | Action |
|---|---|
| `Super + Space` | App launcher |
| `Super + Tab` | Workspace overview |
| `Super + Alt + Tab` | Overview, cycle desktops |
| `Super + Escape` | Quick settings |
| `Super + P` | Wallpaper picker |
| `Super + ,` | Settings |
| `Super + K` | Keybind cheatsheet |
| `Super + L` | Lock the screen |
| `Super + V` | Clipboard history |
| `Super + Return` | Terminal |
| `Super + 1…0` | Focus workspace 1–10 on the current desktop |
| `Super + Shift + W` | Random wallpaper |
| `Super + W` | Close window · `Super + F` Fullscreen · `Super + A` Float |

These ship in the bundled Hyprland Lua config; the authoritative list always
lives in `src/mei-configs/hypr/modules/binds.lua`.

## Quick start

Requirements: an **Arch Linux** machine running **Hyprland**. Everything else
is checked for you — the installer prints exactly what is missing and never
installs anything without asking.

```bash
git clone <repo_url> ~/projects/mei
cd ~/projects/mei
./install.sh
```

`install.sh` is interactive throughout: it checks dependencies, builds the
daemons, the blob plugin and the QML modules, then offers each system change
one at a time — systemd user units, the Hyprland autostart line, the kitty
colour include, your terminal dotfiles, the Hyprland config, wallpapers, and
fonts. Your existing `~/.config/hypr` is never overwritten without an
interactive yes, and existing files are backed up to `*.mei-install.bak`
first. `--dry-run` prints every step and writes nothing; `--help` lists all
flags. Then:

```bash
./mei status    # nothing running yet
./mei start     # join this Hyprland session
```

Log out and back in after enabling autostart, and your desktop is Mei.

## Layout

```
├── install.sh        the cinematic installer (see above)
├── mei               the control script: run/test/verify-untouched
├── src/
│   ├── ryoku/        the Mei tree (adapted from upstream — never regenerated)
│   ├── mei-configs/  bundled Hyprland Lua config + terminal dotfiles
│   └── mei-assets/   wallpapers (empty) + OFL fonts (Space Grotesk, Fraunces)
├── docs/             runbooks: LIVE-CHECKLIST · ROLLBACK · MODULES
├── CHANGES.md        every modification vs upstream
├── CREDITS.md        attribution — read this
└── UPSTREAM.md       the pinned upstream commit
```

## Development

Mei is built and tested in a **nested Hyprland** inside a private session — it
never touches your live desktop:

```bash
./mei test             # nested-session test suite
./mei verify-untouched # prove the live session config hashes are identical
```

`./mei verify-untouched` must pass after any change to the tree — it compares
the live Hyprland/kitty/quickshell configs against a captured baseline.

Honest status: the nested suite and the full cold-start acceptance pass
(**16/16 product items**, one harness defect since fixed) are green; live
measurements exist for the overlay stage. The live full-profile trial is not
complete — see `docs/LIVE-CHECKLIST.md` before you run Mei live, and `docs/ROLLBACK.md`
for the way back. Nothing here has been proven at 144 Hz on your hardware;
that is what the checklist is for.

## Credits and license

Mei is a **modified derivative of [Ryoku](https://github.com/Ryoku-dev/ryoku)**
(pinned commit `98a0368253d9628be72b853985878a5db90e1547`, v0.75.5-beta.20,
"Onogoro"), distributed under the **GNU GPL v3 or later**. Upstream notices
are kept verbatim in `LICENSE` and `NOTICE`; attribution is in `CREDITS.md`;
every modification is recorded in `CHANGES.md`; the pinned upstream commit is
recorded in `UPSTREAM.md`.

Ryoku's frame-blob renderer is adapted from
[Caelestia](https://github.com/caelestia-dots/shell) (GPL-3). Fonts: Space
Grotesk and Fraunces (SIL OFL 1.1); Nerd Fonts for terminal glyph coverage.

Mei is not affiliated with or endorsed by the Ryoku project.
