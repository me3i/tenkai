# Rollback

Mei is designed so that rollback is one command: **`rm -rf ~/projects/mei`**.

## What Mei creates outside `~/projects/mei`

- **Nothing.** No sudo, no packages installed, no systemd units enabled, no autostart entries,
  no keybinds added to the real Hyprland config, no files in `~/.config`, `~/.cache`, `~/.local`
  or `/tmp`.

## What to do before deleting

1. Stop any test session: `./mei stop` (only signals PIDs that `./mei` itself recorded and whose
   cmdline contains the project path).
2. Confirm the live session was never touched: `./mei verify-untouched` → must print `PASS`
   (config hashes identical to `docs/baseline/`).
3. Delete: `rm -rf ~/projects/mei`.

## Known ephemeral runtime artifacts (Phase 6 watch item — currently none)

- Quickshell creates its own small runtime directory under `$XDG_RUNTIME_DIR/quickshell/`
  (e.g. `/run/user/1000/quickshell/by-id/<id>`). The owner's live Quickshell already has one.
  Phase 6 must confirm that a nested Mei Quickshell either (a) reuses this mechanism with
  `mei`-specific names and cleans up on exit, or (b) gets an explicit override. Until then no
  Mei-related file exists there.
- Any leftover directory under `$XDG_RUNTIME_DIR/quickshell/` whose owning PID is gone may be
  deleted manually; never delete one while its PID is alive.

## If Mei ever touches something outside the project

That is a bug in Mei, not a rollback situation: stop using Mei, do not delete the project
(evidence), and report what changed.
