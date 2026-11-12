# Gap analysis — Ryoku @ 98a0368 vs Tenkai

Date: 2026-11-12
Branch: `fix/settings-and-completion`

## Reference source (reproducible)

`me3i/ryoku` does not resolve over HTTPS (authentication prompt / no public
repository), so the reference is the upstream named by `README.md` and
`UPSTREAM.md`:

- repo: <https://github.com/Ryoku-dev/ryoku>
- pinned commit: `98a0368253d9628be72b853985878a5db90e1547`
  (`README.md` calls this `v0.75.5-beta.20`)
- fetched as a tarball into `/tmp/ryoku-ref/ryoku-98a0368253d9628be72b853985878a5db90e1547`
- the tag `v0.75.5-beta.20` was not verified separately; the commit id is the
  authoritative reference and every comparison below is against that tree.

Tenkai's tree is `src/tenkai_core/{shell,hub,ui,wm,apps}`; Ryoku's is
`ryoku/{shell,hub,ui,wm,apps}`. Component diffs:

| component | differing entries |
| --- | --- |
| shell | 645 |
| hub | 141 |
| ui | 29 |
| wm | 60 |
| apps | 77 |
| **files only in Ryoku** | **298** |

## A. Intentional lite-ification — leave removed

These exist in Ryoku and are deliberately absent from Tenkai. Re-adding them
would undo the lite build.

| Ryoku component | Why it is out of scope |
| --- | --- |
| `lockscreen/` (+ `hub/quickshell/pages/LockscreenPage.qml`, `schema/LockscreenPage.js`) | no lock-screen daemon in Tenkai |
| `niri/` | Tenkai is Hyprland-only |
| `browser/`, `cli/`, `apps/ryovm`, `apps/tools` | external tooling, not the shell |
| `palette-bridge/` | matugen fan-out to third-party apps is off |
| `apps/{bash,btop,fish,ghostty,kitty,nvim,yazi,zsh,…}` | terminal dotfiles ship under `src/tenkai-configs/terminal` instead |
| `apps/ryostore/backend/*` | store backend; Tenkai keeps only the catalog UI |
| `shell/quickshell/{ryopin,ryoshot,keys,keys-hint,reload-cover}` | extra daemons/surfaces cut |
| `shell/modules/stage`, `shell/modules/visualizer` | stage engine and visualizer cut |
| `shell/modules/capture/KeypressOverlay.qml` | keypress overlay cut |
| `shell/modules/desktop/{aio,music,notes,stats,weather}` | desktop widgets cut; Clock is the only built-in widget |
| `shell/modules/osd/KeyboardOsd*.qml` | on-screen keyboard overlay cut |
| `hub/backend/{gpu,gpuhook,gpumode,gpumux,gpuvm,lock,voxtype}.go` | GPU VM/mux and lock/voice backends out of scope |
| Ryoku systemd units (`ryoku-*`) | Tenkai ships its own `tenkai-shell.service` / `tenkai-hub.service` |

Known consequence, recorded but not "fixed" by importing: the Hub still exposes
settings surfaces whose live counterpart was cut (Visualizer subtab, desktop
widget grid). The previews are standalone mockups, so they render, but the shell
does not draw those widgets. That is a scope decision, not a broken import.

## B. Stub / whitecoded

The mission's grep (`TODO|FIXME|hardcod|/home/|placeholder|stub` over
`*.qml`/`*.js`) returns **zero TODO/FIXME**. Remaining hits are ordinary UI
`placeholderText`, comments, and empty `MouseArea { onClicked: {} }` click
blockers (intentional event shields in `LauncherPage.qml` and
`CompositorSwitchSheet.qml`). No source file hardcodes a `/home/<user>` path;
the only `/home/` strings are in the two untracked install logs at the repo
root (`tenkaifinal.txt`, `tenkairun.txt`), which are not source.

`return null` hits in `Hub.qml`, `PluginsPage.qml` are ordinary "nothing
selected" guards, not stubs.

## C. Missing import / type resolution — the real defects

Found in the running shell's Quickshell log
(`/run/user/1000/quickshell/by-id/1p4w37dot/log.qslog`):

1. **`apps/Apps.qml` imported `Ryoku.Ui.Singletons`.** Tenkai renamed the
   module to `Tenkai.Ui.Singletons` and does not install a `Ryoku` module
   (`/usr/lib/qt6/qml/Ryoku*` absent; `.run/qml` contains only `Tenkai`).
   Result: `Type Apps unavailable` → `Providers.Providers unavailable` → the
   whole launcher provider stack fails to load.
   **Fixed** in `apps/Apps.qml`; verified with an isolated Quickshell probe:
   `PROBE_OK apps=true`.

2. **`providers/qmldir` declares only `Provider`.** Adding a `qmldir` disables
   implicit discovery for the directory, so `SharedProviders.Providers` (used by
   both launcher variants) could not resolve. **Fixed** by adding
   `Providers Providers.qml`. Same probe now resolves both types.

3. **`MprisPanel.qml` dereferenced a null player.** The log showed repeated
   `TypeError: Cannot read property 'trackTitle'/'trackArtist' of null` when
   `mprisPanel.active` was true but the player object had not arrived yet.
   **Fixed** by guarding on `mprisPanel.player` in both bindings.

4. **`visualizer.json` never existed.** `Hub.qml`'s `vizFV` read it and warned
   on every Hub launch, and the Visualizer Save path had no file to write.
   **Fixed** by seeding the adapter defaults on first open
   (`Component.onCompleted: if (!vizFV.text()) vizFV.writeAdapter()`). First
   launch creates it; subsequent launches are warning-free. `brand.json` gets
   the same first-open guard.

5. `DesktopPage.qml`'s `Connections { function onInvalidatePageWork() }` warned
   once because the page's `hub` property is assigned by `Loader.onLoaded` after
   the page is constructed. The signal exists on the Hub and the connection
   binds once `hub` arrives; this is transient and was left alone.

## D. Settings pipeline — actual data flow

There is **one** writer for `shell.json`: the `tenkai-shell` daemon
(`shell/ipc/settings.go`). The Hub never opens the file.

```
Hub page → Singletons/Settings.qml (patch/reset/applySetting)
         → unix socket $XDG_RUNTIME_DIR/tenkai-shell.sock
         → daemon settingsStore.patch (validate, clamp, atomic write)
         → settings frame re-push + file write
         → shell Config.qml FileView (watchChanges) retunes live
```

Verified live against the running session:

- `settings.patch {"path":"frameOpacity","value":0.97}` returned `{"ok":true}`;
- `~/.config/tenkai/shell.json` (`.run/config` in the live sandbox) gained
  `"frameOpacity": 0.97`;
- the running shell's log gained nine fresh `shell.json` FileView load events in
  the next 1.5 s, i.e. the running shell picked the value up with no restart.

Flat "look" keys (`frameOpacity`, `fontScale`, `barStyle`, `launcherTarget`,
`screenShader`, …) are daemon **passthrough** keys: the daemon accepts, persists
and re-pushes them verbatim, which is why the Hub's Bar Studio live edits reach
`Config.qml`. Schema keys (`theme.motion.*`, `qsbar.*`, `clipboard.*`) are
validated contract keys. Both paths converge on the same file and the same frame.

The only settings-related gap found was the missing `visualizer.json` seed
(above); with it, Settings writes, live reaction and restart persistence all
hold.
