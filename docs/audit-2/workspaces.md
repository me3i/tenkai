# Workspace switching

## Two independent root causes

### 1. Every `Wm.caps` was false

`src/tenkai_core/shell/ipc/vendor/tenkai-wm/client.go` looked for the provider
binary as `mei-wm-<provider>` (lines 49 and 59). The shipped binary is
`tenkai-wm-hyprland`, so capability detection failed with:

```
mei-wm-hyprland caps: exec: "mei-wm-hyprland": executable file not found in $PATH
```

All `Wm.caps` came back false. The bar's workspace pills and any wm-gated control
therefore dropped every click silently. Fixed to `tenkai-wm-`; after rebuilding
the daemon the live `wm` frame reports `provider: hyprland`,
`workspaces: true`, `screenShader: true`.

### 2. The keybind helper exited successfully doing nothing

`src/tenkai-configs/hypr/scripts/tenkai-workspace` began with `ryoku_bin=...
tenkai` and required `tenkai wm status` before dispatching. When that command is
absent/failing the helper returned 0 without moving anything, so Super+1..0
looked bound but were dead.

The helper now:

- treats the `tenkai wm` seam as optional (`seam_status`);
- falls back to reading Hyprland directly for workspace model/capability;
- dispatches with `hyprctl dispatch 'hl.dsp.focus({ workspace = N })'` (the form
  this Hyprland 0.57.2 Lua config accepts) and falls back to the classic
  `workspace N` words if Lua dispatch is rejected;
- implements `focus`, `move`, `movesilent`, `hide`, `scratch` and `desktop`
  (the old file mentioned only `ryoku-workspace`).

## Live installation

The repo copy and the installed copy had diverged: `~/.config/hypr/scripts/
tenkai-workspace` was still the old failing version. It was replaced (backup:
`tenkai-workspace.pre-audit2.bak`) with the fixed script. No keybind file was
rewritten — the installed `binds.lua` already matches the repo bundle and calls
`$HOME/.config/hypr/scripts/tenkai-workspace`.

Verification of the actual helper:

```
~/.config/hypr/scripts/tenkai-workspace focus 3  -> activeworkspace 3
~/.config/hypr/scripts/tenkai-workspace focus 1  -> activeworkspace 1
```

## Bar pills and IPC

- `ShellIpcHandler.workspaceSwitch <n>` calls the same focus path as a pill.
- `tests/run-all.sh` calls it over `qs ipc`, then asserts
  `hyprctl activeworkspace` changed 1→2 and back 2→1. PASS.

## Hyprland block

`docs/audit-2/hypr-keybinds-to-add.lua` contains the workspace module. The
audited live config already has `require("modules.binds")`, so nothing needs to
be pasted there; the file is the block for a tree that lacks it, and it was not
written into `~/.config/hypr` by this audit.

## Limitations

- The Super+number key events themselves were not synthesised (no input
  injection tool in this session); the helper they exec was tested directly and
  the bar-IPC path was tested end to end.
- Workspace `move`/`movesilent` are implemented and syntax-checked, not
  visually exercised.
