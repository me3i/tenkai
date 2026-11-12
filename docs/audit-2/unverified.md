# UNVERIFIED / not claimed

Each item is something this audit could not prove, with the reason.

1. **`launcherTarget` UI click-through.** No shipped control exists: the QS
   Bar ↔ Quick Settings switch in `QuickSettingsHome.qml` is commented out
   because the "studio" target is outside the lite keep list. The key writes,
   reads, persists and is consumed by `LauncherWidget`/`CcRail`, but no UI path
   was exercised. Setting it through IPC is verified.
2. **`screenShader` shell-level UI path.** Hub Visuals edits Hyprland's
   `decoration:screen_shader` (a different key). The shell `screenShader` key is
   applied live and persisted via IPC, but has no control, so no click-through.
3. **Super+N key events.** No input-injection tool was available. The helper
   the binds exec was run directly (focus 3 → 3, focus 1 → 1), and the bar's
   IPC path was tested; the physical key press itself was not synthesised.
4. **Window move/movesilent.** Implemented and syntax-checked; no window was
   moved to confirm visually.
5. **Reboot / login default.** The ROLLBACK TTY1 fish block is not installed
   (`fish.md`); no reboot was performed and `~/.config/hypr` was not rewritten.
   The installed helper script was replaced (with a `.pre-audit2.bak` backup);
   the keybind file was not touched.
6. **Glyph-level icon screenshot.** Fontconfig resolution inside the shell's
   environment is verified; no compositor screenshot was taken (no Chrome, no
   screenshot tool used in this pass).
7. **Prior branch claims.** `fix/settings-and-completion` was re-audited, not
   trusted. Its parent commit is an ancestor of this branch; the two workspace
   root causes above were still present on it.
8. **A full clean-machine `./tenkai run`.** The live session used the existing
   `.run` tree plus manual fontconfig repair; bootstrap and autostart were run
   idempotently in a temporary HOME by the suite, not a full graphical reboot.
