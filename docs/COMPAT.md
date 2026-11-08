# COMPAT.md — strings that must keep an old name

Some `ryoku` strings in this tree are not branding. They are lookup keys for
something outside the repository: a directory on disk, a file already written by
an earlier build, or a helper binary shipped in a system package. Renaming them
breaks the feature silently, so each one is marked with a `// COMPAT:` comment at
its definition and listed here.

| String | Where | Why it cannot be renamed | Evidence |
| --- | --- | --- | --- |
| `Bibata-Material-Ryoku` | `src/tenkai_core/wm/cursor.go` (`CursorThemeMaterial`), and the vendored copies | It is the name of a cursor theme installed on disk by a Ryoku package. `ResolveCursorTheme` returns it for the stored `DYNAMIC` sentinel, and the compositor looks the directory up by that exact name. | `ls /usr/share/icons \| grep Bibata` shows `Bibata-Material-Ryoku` and no `Bibata-Material-Tenkai`. The rebrand commit `b76cc00` had renamed this constant; it was restored here. |
| `themeRyokuApps` | `src/tenkai_core/hub/backend/matugen.go`, `src/tenkai_core/shell/ipc/matugen.go` (JSON tags) | It is the on-disk key in the stored settings (`shell.json` / matugen overrides). Renaming it means every existing settings file is read as "option missing". The Go identifier is already `ThemeTenkaiApps`. | Both producer and consumer are in this repo, so a migration *could* be written; until one exists the key stays. |
| `Managed by Ryoku` | `src/tenkai_core/hub/backend/hwcaps.go` (`hookInstalled`) | The marker was written into `etc/libvirt/hooks/qemu` by earlier builds on real machines. The check accepts both markers so an existing hook is recognised as Tenkai's. | `git grep "Managed by Tenkai"` shows the new builder; the old string is only accepted, never written. |
| `ryoku-cursor-material-recolor` | `src/tenkai_core/hub/backend/desktop.go:282` | Helper shipped by a Ryoku system package. Tenkai does not ship it; `.run/bin/ryoku-cursor-material-recolor` is a Tenkai stub that exits 127 so the call can never reach the live binary. | `.run/bin/ryoku-cursor-material-recolor` header says "tenkai-stub". |

## Not compat, already fixed

* `ryoku-wm` — the Go module was renamed to `tenkai-wm` and the vendored copies
  regenerated, because both producer and consumer live in this tree and the
  vendored copies were still asking for `ryoku-wm-hyprland` while `install.sh`
  installs `tenkai-wm-hyprland`.

## Known remaining `ryoku-*` strings

The bar-style identifier `frameBars.style = "ryoku-frame"` is a stored settings
value (see `CHANGES.md`), and the panel/tray layer namespaces listed in the
rebrand sweep still carry the old prefix. Both need a settings migration, not a
rename; they are tracked in `docs/BRANDING.md`.
