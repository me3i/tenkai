# Shell IPC

Transport: Unix socket `/run/user/<uid>/tenkai-shell.sock`, newline-delimited.
A client sends one line per command:

```
subscribe <topic>
call <method> <json-arg>
```

The daemon replies with one JSON line per frame/result. Quickshell's `Socket`
element speaks this directly; tests use `qs ipc --pid <shell-pid> call shell ...`.

## Handlers added for this audit

In `shell.qml`, `ShellIpcHandler`:

| method | argument | effect |
|---|---|---|
| `setSetting` | `["key", value]` | writes `shell.json`, applies live side effect |
| `getSetting` | `"key"` | returns current live value (JSON) |
| `workspaceSwitch` | `n` | focuses workspace `n` through the wm seam |
| `listSurfaces` | — | returns the 11 surface ids |

`Config.qml` also gained `patch(path, value)` so a key can be changed without a
dedicated setter.

## Examples

```bash
p=$(pgrep -f '^qs -p .*/tenkai_core/shell/quickshell/shell$' | head -1)
qs ipc --pid "$p" call shell getSetting 'frameOpacity'
qs ipc --pid "$p" call shell setSetting '["frameOpacity", 0.94]'
qs ipc --pid "$p" call shell workspaceSwitch 2
qs ipc --pid "$p" call shell listSurfaces
```

Note the PID pattern is anchored (`^qs`). An unanchored `pgrep -f` also matches
the test's own command line and returns the caller's process, whose environment
is not the shell's.

## Why IPC rather than synthetic clicks

The shell has no accessibility tree available to this session, and pointer
injection would test Qt's hit-testing rather than Tenkai's logic. The IPC
handlers call exactly the functions the bar controls call (`Config.patch`,
`Config.setScreenShader`, the wm focus action), so they are the UI-equivalent
automation point. The remaining gap — keys with no control at all — is recorded
in `settings.md` and `unverified.md`.
