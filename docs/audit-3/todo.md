# TODO / FIXME and latent retry audit

## Code markers

```
grep -rn 'TODO\|FIXME' --include='*.qml' --include='*.js' --include='*.lua' --include='*.go' src/
```

78 hits, **all under `src/**/vendor/`** (BurntSushi/toml and golang.org/x/sys).
No non-vendor TODO/FIXME remains in code the user runs. Nothing had to be
moved into this file from shipped source.

## Remaining retry loops

Every service that subscribes to a daemon topic:

| service | topic | daemon implements it | `topicMissing` stop |
|---|---|---|---|
| Clipboard | clipboard | yes | no (not needed) |
| Holidays | calendar | **no** | yes |
| Music | music | yes | no |
| Network | network | yes | no |
| Nightlight | nightlight | yes | no |
| OsdFeed | osd | yes | no |
| Polkit | polkit | yes | no |
| PowerProfiles | powerprofiles | **no** | yes |
| Tray | tray | yes | no |
| Updates | updates | **no** | yes |
| Weather | weather | **no** | yes |
| Wm | wm | yes | no |

The seven without `topicMissing` subscribe to topics the daemon registers, so
they retry only while the daemon is genuinely down — the intended behaviour.
They would exhibit the old warning storm if their topic were later removed;
they are left as-is rather than adding unused error handling to working paths.

Also checked: `settings` and `wallpaper` subscribers exist outside
`services/*.qml` and target implemented topics. No other socket retry loop was
found.

## Follow-up candidates (not bugs blocking this pass)

- The Hub Displays page can still apply an explicit scale above 1.0 from a
  saved profile; see `scale.md` caveat.
- `launcherTarget` / shell-level `screenShader` still have no UI control; see
  `unverified.md`.
- TTY1 fish auto-exec remains an explicit opt-in.
