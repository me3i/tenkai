# Settings: five keys, end to end

## The seam

All five keys live in `~/.config/tenkai/shell.json` (inside the sandbox:
`.run/config/tenkai/shell.json`) and are exposed by
`src/tenkai_core/shell/quickshell/shell/services/Config.qml`.

`Config.qml` gained a generic `patch(path, value)` that updates the singleton,
writes the file and pushes the settings frame to the shell socket. The shell's
`ShellIpcHandler` (`shell.qml`) exposes:

- `setSetting <key> <value>` — writes the key and runs the key's live side
  effect. `screenShader` is routed through `Config.setScreenShader`;
  `launcherTarget` through `Config.setLauncherTarget`; everything else through
  `Config.patch`.
- `getSetting <key>` — reads the live singleton value (JSON-quoted).

The Hub's `Settings.qml` is the UI seam: `BarStudioPage` edits
`frameThickness`, `frameOpacity` and `barStyle` with `fedit()` →
`hub.stageLive` → `Settings.patch`, so the bar updates while the control is
moved, not on Save.

## Verification

`tests/run-all.sh` sets each key to a non-default value through `qs ipc call
shell setSetting`, reads it back with `getSetting`, checks `shell.json` on disk,
then restores the default. Full run (2026-11-12):

| key | set | live | disk |
|---|---|---|---|
| frameThickness | 3 | 3 | 3 |
| frameOpacity | 0.94 | 0.94 | 0.94 |
| barStyle | sumi | sumi | sumi |
| launcherTarget | quick | quick | quick |
| screenShader | grain | grain | grain |

Persistence across a shell restart was verified separately: after a `qs`
restart all five values were still returned by `getSetting` and present in
`shell.json` (the test restores defaults afterwards).

## UI path, honestly

| key | Hub/shell control | UI → live verified |
|---|---|---|
| frameThickness | Bar Studio frame section | code path read; IPC equivalent verified |
| frameOpacity | Bar Studio opacity slider (line ~627) | code path read; IPC equivalent verified |
| barStyle | Bar Studio style cards | code path read; IPC equivalent verified |
| launcherTarget | **none** — the QS Bar/Quick Settings switch is commented out because the "studio" panel is outside the lite keep list | **UNVERIFIED** |
| screenShader | Hub Visuals edits Hyprland's `decoration:screen_shader`; the shell-level `screenShader` key has no control | **UNVERIFIED** |

`launcherTarget` still has live consumers (`LauncherWidget`, `CcRail`) and the
setting now writes/reads correctly, but no shipped control offers it, so no
click-through test is possible without inventing UI. `screenShader` is applied
live through `wm.act decoration.screenShader` and persisted, but only the IPC
entry point drives the shell-level key.

These two are listed in `unverified.md`; they are not claimed as UI-verified.
