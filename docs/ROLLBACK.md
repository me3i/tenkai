# Rollback — what Tenkai writes, and how to undo it

Deleting the checkout removes the shell, the daemons, the QML tree and the Go
binaries in one command:

```bash
./tenkai stop          # only signals PIDs ./tenkai recorded, whose cmdline names this checkout
rm -rf ~/projects/tenkai
```

That is **not** the whole story. `install.sh` can also write outside the checkout,
and each of those writes is a separate prompt. This document lists every path, so
a rollback can undo them too. Line numbers refer to `install.sh` at the commit this
file was written against.

## What `install.sh` can write, by step

Everything below happens only after an interactive `y` at that step's prompt.
`--dry-run` writes nothing. `--yes` answers the non-Hyprland prompts, but it never
answers steps 4 and 7, which are interactive-only by design.

| Step | Path written | How | Backup |
| --- | --- | --- | --- |
| 3 | `~/.config/systemd/user/tenkai-shell.service` | `install -m 0644` (`write_unit`, install.sh:512) | none; rewritten only when content differs |
| 3 | `~/.config/systemd/user/tenkai-hub.service` | same | none |
| 3 | — | `systemctl --user daemon-reload` only (install.sh:588) | n/a |
| 4 | `~/.config/hypr/modules/autostart.lua` | one `hl.on("hyprland.start", …)` hook appended (install.sh:603) | none; the whole step is interactive y/N |
| 5 | `~/.config/kitty/kitty.conf` | one `include` line appended (install.sh:665-673) | `kitty.conf.tenkai-install.bak` |
| 5 | `~/.cache/tenkai/kitty-colors.conf` | written at runtime by the palette pass, not by the installer | none |
| 6 | `~/.config/kitty/{kitty.conf,current-font.conf,current-theme.conf,user.conf}` | `copy_config`, whole-file copy (install.sh:722-725) | `<file>.tenkai-install.bak` |
| 6 | `~/.config/fish/config.fish` | `copy_config` (install.sh:746) | `<file>.tenkai-install.bak` |
| 6 | `~/.config/fish/conf.d/*` | `copy_config` per file (install.sh:747-751) | `<file>.tenkai-install.bak` |
| 6 | `~/.config/starship.toml` | `copy_config` (install.sh:755) | `<file>.tenkai-install.bak` |
| 6 | `~/.config/fastfetch/*` | `install -m 0644` per file (install.sh:763-791) | `<file>.tenkai-install.bak` |
| 7 | `~/.config/hypr/**/*.lua` (the bundled tree, `src/tenkai-configs/hypr`) | per-file copy (install.sh:816+) | `<file>.tenkai-install.bak` |
| 7 | `~/.config/hypr/modules/keyboard.lua` | seeded once; never overwritten afterwards (install.sh:820-822) | none (by design: it is user-owned) |
| 8 | `~/Pictures/Wallpapers/*` | `install -m 0644`, bundled images only (install.sh:946-991) | existing file → `<name>.tenkai-install.bak` |
| 9 | `~/.local/share/fonts/tenkai/*.ttf` | `install -m 0644`, Space Grotesk + Fraunces (install.sh:1001+) — **no prompt**, then `fc-cache -f` on that directory | none, new directory |

`MARK='tenkai-install'` (install.sh:51) is the suffix used for every backup:
`<path>.tenkai-install.bak`.

Notes that matter for a clean rollback:

- The units are **written, not enabled**. `install.sh` never runs `systemctl --user
  enable`; enabling is left to the user, and the units are documented as an
  alternative to the autostart hook (install.sh:509-511).
- `~/.config/kitty` is never *created* by step 5: if there is no `kitty.conf`, it
  only prints the line for you to add (install.sh:657-660).
- **Step 9 is the one step that writes without asking.** Fonts go to
  `~/.local/share/fonts/tenkai/` and `fc-cache` runs on that directory whether or
  not you said yes to anything else. A plain build run therefore does touch the
  home directory; this audit hit exactly that, and `./tenkai verify-untouched`
  reported it (FAIL, `.local/share/fonts/tenkai` new since baseline) until the
  directory was removed. Treat the font install as an opt-out-by-not-running.
- Nothing is installed with `sudo`, no package is installed, no system-wide file
  is touched, and no process outside the checkout is signalled.

## Undoing those writes by hand

```bash
# units written by step 3 (remove only if you did not enable them yourself)
systemctl --user disable --now tenkai-shell.service tenkai-hub.service 2>/dev/null
rm -f ~/.config/systemd/user/tenkai-{shell,hub}.service
systemctl --user daemon-reload

# backups: every *.tenkai-install.bak next to a file the installer replaced
find ~/.config ~/Pictures/Wallpapers -name '*.tenkai-install.bak' -print

# fonts and runtime cache created by Tenkai
rm -rf ~/.local/share/fonts/tenkai ~/.cache/tenkai
```

Restoring a backup means moving `<file>.tenkai-install.bak` back over `<file>`.
Choose deliberately: several of these files may have been edited by you after the
install, and the backup is the pre-install state.

## The `verify-untouched` caveat — read this

`./tenkai verify-untouched` compares the live session against `docs/baseline/`.
**That directory is not tracked and does not exist in a fresh clone** (verified:
`git ls-files docs/baseline` prints nothing). It is a snapshot of one real
session — process list, D-Bus names, `XDG_RUNTIME_DIR`, Hyprland instance
signature — so it is deliberately kept out of git (see `docs/PRIVACY.md`).

Consequences:

- On a fresh clone the check has **no baseline** and cannot pass by itself. It
  says so rather than reporting PASS; take the baseline first with
  `./tenkai baseline` (writes `docs/baseline/` locally) if you want the guarantee.
- A watched name held by a process **from this checkout** is a FAIL, not a note.
  Until 2026-11-08 it was accepted as "attributable", which meant a live Tenkai
  session would pass a check whose whole purpose is proving Tenkai is not in the
  live session. `./tenkai verify-prove` now has a fixture for that case.
- The PASS this repository's own audit recorded was produced on the machine that
  had a baseline, with the live session running **Ryoku**: the watched names are
  owned by `ryoku-shell.service`, so they classify as EXTERNAL, and the only new
  entry since baseline was the font directory above. It is evidence that Tenkai was
  not running in the live session, not that a sandbox was proven; see
  `docs/DBUS.md`.

## If Tenkai ever touches something outside these paths

That is a bug, not a rollback situation: stop using it, keep the checkout as
evidence, and report what changed.

## Boot policy (why Tenkai becomes the default desktop)

Fixed Ryoku boot auto-launch is driven by the systemd **user** target
`ryoku-session.target`, **not** by `/usr/bin/start-hyprland`. Read directly,
`/usr/bin/start-hyprland` is an ELF launcher that only resolves the exec path
given in `/usr/share/wayland-sessions/hyprland.desktop`
(`Exec=/usr/bin/start-hyprland`); it does not fire any Ryoku commands.

Making Tenkai the login default therefore requires:

1. Mask the Ryoku target so nothing can start it at user-session boot:
   `systemctl --user mask ryoku-session.target`
2. Point the TTY1 login shell at the Hyprland compositor via fish
   (`~/.config/fish/config.fish`, end of file):

   ```fish
   # Automatically launch Hyprland on TTY1
   if test -z "$DISPLAY"; and test -z "$WAYLAND_DISPLAY"; and test "$XDG_VTNR" = 1
       exec start-hyprland
   end
   ```

Reboot then lands on TTY1's standard `login:` prompt; login on TTY1 execs
Hyprland, and Tenkai's session launcher takes the desktop. No SDDM autologin
is required for any of this (a login prompt is the requested UX) — SDDM
itself is unnecessary for TTY1 booting since systemd's getty provides it.
