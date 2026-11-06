# Tenkai · 天界

```
╔════╗ │  ████████╗███████╗███╗   ██╗██╗  ██╗ █████╗ ██╗
║    ║ │  ╚══██╔══╝██╔════╝████╗  ██║██║ ██╔╝██╔══██╗██║
║ 天 ║ │     ██║   █████╗  ██╔██╗ ██║█████╔╝ ███████║██║
║ 界 ║ │     ██║   ██╔══╝  ██║╚██╗██║██╔═██╗ ██╔══██║██║
║    ║ │     ██║   ███████╗██║ ╚████║██║  ██╗██║  ██║██║
╚════╝ │     ╚═╝   ╚══════╝╚═╝  ╚═══╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝
```

**The Celestial Lite version of Ryoku Quickshell.** Lightweight, modular, and
visually stunning — for
Arch Linux + Hyprland, built by copying, trimming and measuring the
[Ryoku](https://github.com/Ryoku-dev/ryoku) shell.

---

## Why Tenkai

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
  Hyprland config — Tenkai reads live state, it does not own it.
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
| Config reload | Settings persist to Tenkai's own config dir (`~/.config/tenkai`) |

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
lives in `src/tenkai-configs/hypr/modules/binds.lua`.

## Quick start

Requirements: an **Arch Linux** machine running **Hyprland**. Everything else
is checked for you — the installer prints exactly what is missing and never
installs anything without asking.

```bash
git clone <repo_url> ~/projects/tenkai
cd ~/projects/tenkai
./install.sh
```

`install.sh` is interactive throughout: it checks dependencies, builds the
daemons, the blob plugin and the QML modules, then offers each system change
one at a time — systemd user units, the Hyprland autostart line, the kitty
colour include, your terminal dotfiles, the Hyprland config, wallpapers, and
fonts. Your existing `~/.config/hypr` is never overwritten without an
interactive yes, and existing files are backed up to `*.tenkai-install.bak`
first. `--dry-run` prints every step and writes nothing; `--help` lists all
flags. Then:

```bash
./tenkai status    # nothing running yet
./tenkai start     # join this Hyprland session
```

Log out and back in after enabling autostart, and your desktop is Tenkai.

## Layout

```
├── install.sh        the cinematic installer (see above)
├── tenkai               the control script: run/test/verify-untouched
├── src/
│   ├── ryoku/        the Ryoku shell tree, adapted by Tenkai (never regenerated from scratch)
│   ├── tenkai-configs/  bundled Hyprland Lua config + terminal dotfiles
│   └── tenkai-assets/   wallpapers (empty) + OFL fonts (Space Grotesk, Fraunces)
├── docs/             runbooks: LIVE-CHECKLIST · ROLLBACK · MODULES
├── CHANGES.md        every modification vs upstream
├── CREDITS.md        attribution — read this
└── UPSTREAM.md       the pinned upstream commit
```

## Development

Tenkai is built and tested in a **nested Hyprland** inside a private session — it
never touches your live desktop:

```bash
./tenkai test             # nested-session test suite
./tenkai verify-untouched # prove the live session config hashes are identical
```

`./tenkai verify-untouched` must pass after any change to the tree — it compares
the live Hyprland/kitty/quickshell configs against a captured baseline.

Honest status: the nested suite and the full cold-start acceptance pass
(**16/16 product items**, one harness defect since fixed) are green; live
measurements exist for the overlay stage. The live full-profile trial is not
complete — see `docs/LIVE-CHECKLIST.md` before you run Tenkai live, and `docs/ROLLBACK.md`
for the way back. Nothing here has been proven at 144 Hz on your hardware;
that is what the checklist is for.

## Credits and license

Tenkai is a **modified derivative of [Ryoku](https://github.com/Ryoku-dev/ryoku)**
(pinned commit `98a0368253d9628be72b853985878a5db90e1547`, v0.75.5-beta.20,
"Onogoro"), distributed under the **GNU GPL v3 or later**. Upstream notices
are kept verbatim in `LICENSE` and `NOTICE`; attribution is in `CREDITS.md`;
every modification is recorded in `CHANGES.md`; the pinned upstream commit is
recorded in `UPSTREAM.md`.

Ryoku's frame-blob renderer is adapted from
[Caelestia](https://github.com/caelestia-dots/shell) (GPL-3). Fonts: Space
Grotesk and Fraunces (SIL OFL 1.1); Nerd Fonts for terminal glyph coverage.

Tenkai is not affiliated with or endorsed by the Ryoku project.
