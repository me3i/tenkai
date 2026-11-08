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
| `ryoku-frame` | `src/tenkai_core/hub/backend/schemes.go` (`applyTenkaiTheme`), `src/tenkai_core/shell/framebars/FrameBars.js` (`normalize`) | It is the frame-bar style id already stored in every existing `shell.json`. The normaliser only accepts `slate-frame` and `ryoku-frame`, so renaming the id silently resets users to the default style. | Producer and consumer are both in this repo, so a migration is possible; until it is written the id stays. `schemes_test.go:56` still skips the assertion for this style. |
| `ryoku-cursor-material-recolor` | `src/tenkai_core/hub/backend/desktop.go:282` | Helper shipped by a Ryoku system package. Tenkai does not ship it; `.run/bin/ryoku-cursor-material-recolor` is a Tenkai stub that exits 127 so the call can never reach the live binary. | `.run/bin/ryoku-cursor-material-recolor` header says "tenkai-stub". |

## Not compat, already fixed

* `ryoku-wm` — the Go module was renamed to `tenkai-wm` and the vendored copies
  regenerated, because both producer and consumer live in this tree and the
  vendored copies were still asking for `ryoku-wm-hyprland` while `install.sh`
  installs `tenkai-wm-hyprland`.

## Known remaining `ryoku-*` strings

After the sweep in `a12d5bc`, no `WlrLayershell` namespace producer carries the old
prefix (`grep -rn 'namespace: *"ryoku-' --include='*.qml' .` returns nothing), and
the only surviving settings value is `frameBars.style = "ryoku-frame"`, listed in
the table above. Everything else left is one of: an attribution comment, an
external program name guarded by `command -v`, a fallback read path for hybrid
installs, or an `ryoku-import` marker already written into users' dotfiles. The
full classification is in `docs/BRANDING.md`.
