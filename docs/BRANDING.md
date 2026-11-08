# BRANDING.md — the result of the `Ryoku|ryoku` sweep

Sweep command (as specified):

```
git grep -n -I "Ryoku\|ryoku" -- 'src/*.go' 'src/*.qml' 'src/*.js' \
  'src/*.lua' 'src/*.toml' 'src/*.cmake' 'src/**/CMakeLists.txt'
```

**Before: 682 lines / 255 files. After the renames below: 640 lines / 219 files.**

Nothing was renamed blindly. Each remaining string is one of five kinds, and
only the first kind was actionable.

## 1. Renamed here (the `(b)` hits) — 43 items

| What | Count | Commits |
| --- | --- | --- |
| Layer-shell namespaces produced by the shell (`tenkai-frame`, `-frame-edge`, `-widgets`, `-visualizer`) plus the 4 consumers (`tenkai` script, 4 test harnesses) | 8 occurrences | `1092cc0` (B1) |
| Every other `WlrLayershell.namespace: "ryoku-*"` producer and its in-repo consumers (`decoration.lua` notifications rule, niri `overviewBackdropNamespace` const, `tenkai` claim table) | 39 producers in 37 files | this commit (B6) |
| Go module `ryoku-wm` → `tenkai-wm`, 3 vendor trees, `modules.txt`, provider prefix | 54 files | `8e3930d` (B5) |

Deliberately **not** renamed, with the reason:

* `ryoku-wallpaper`, `ryoku-livewall` in the decoration rule — those namespaces
  belong to external wallpaper tools, not to this shell.
* `ryoku-keys`, `ryoku-keys-hint` — the keys module was removed in the
  reduction, so nothing produces these; the rules are inert. Left so the file
  still describes a live Ryoku session correctly (`COMPAT`).

## 2. Comments that name upstream (309 lines)

Every hit of this kind is attribution or an upstream-path reference ("the print
filter (ryoku/hyprland/shaders/)", "ryoku-cmd-folders builds a small …"). These
are `(a)` in the brief only in the sense that the *path* is stale; deleting them
would delete the record of where a behaviour came from, which `NOTICE` and
`CHANGES.md` depend on. They are left as documentation.

## 3. External binaries called through `command -v` / `exec` (49 + most of 238)

`ryoku-shell`, `ryoku-hub`, `ryoku-cmd-*` (`ryoshot`, `folders`, `nightlight`,
`game-mode`, `caffeine`, `radio`, `screenrecord`), `ryoku-power`, `ryoku-gpu`,
`ryoku-i18n`, `ryoku-host`, `ryoku-bt-audio`, `ryoku-mic`, `ryoku-session-intro`,
`ryoku-idle`, `ryoku-pkg-aur-add`, `ryoku-cursor-material-recolor`,
`ryoku-rashin` (35 references). These are programs installed by Ryoku packages
on the owner's machine, or (for `ryoku-rashin`) a terminal the shell launches.
Renaming the string does not rename the installed program, so these are `(c)`:
kept, listed in `docs/COMPAT.md` where they are a hard dependency.

## 4. Persisted keys, style ids and embedded markers (17 + 10)

* `themeRyokuApps` — settings JSON key (`COMPAT`, `docs/COMPAT.md`).
* `frameBars.style = "ryoku-frame"` — stored bar-style id, written and read from
  `shell.json`/rice JSON. Renaming it needs a settings migration.
* `>>> ryoku-import >>>` markers — written *into* the user's dotfiles by the
  import feature (`import_apply.go`). Renaming orphans every existing block.

## 5. Fallback paths (13)

`~/.config/ryoku/...`, `~/.cache/ryoku/...` are read **after** the Tenkai path in
`decoration.lua` (e.g. `pcall(dofile, ~/.cache/tenkai/hypr-colors.lua)` then the
Ryoku path). They exist for hybrid installs and are `(c)`.

## What is still visible to the user

`hyprctl layers` will list `tenkai-*` only after the shell is restarted — the
running session still maps the old names, and nothing here restarts it. The
`ryoku-rashin` / `ryoku-cmd-*` names in `~/.config` paths are unchanged on
purpose (see above).
