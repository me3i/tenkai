# 03 — Wallpaper and theming (matugen)

Dependency map for the wallpaper → palette path in upstream **Ryoku**
(`0.75.5-beta.20` @ `98a0368253d9628be72b853985878a5db90e1547`), read from the
sparse checkout at `~/projects/mei/upstream/` (read-only) plus off-disk trees via
`git show HEAD:<path>`. Scope: the `ryogami` wallpaper daemon (`ryoku/shell/ryogami/`),
the shell palette pipeline (`ryoku/shell/ipc/`), the shell QML that paints it
(`ryoku/shell/quickshell/shell/modules/wallpaper/`), the matugen config/templates
(`ryoku/shell/matugen/`), the palette consumers (`ryoku/ui`, qsbar `Theme.qml`), and
the optional `palette-bridge`.

Labels: **[TESTED]** I ran the command in this session; **[READ]** read from
committed source / blob sizes; **[UNVERIFIED]** inferred or not confirmed by
execution. Nothing here was built or run against the Ryoku tree. Citations are
`path:line` for content and `path` + bytes for sizes.

**Headline correction (the brief's premise is wrong):** matugen is **not** run by
`ryoku/shell/ryogami/daemon/`. It is run by the **`ryoku-shell` Go IPC daemon** in
`ryoku/shell/ipc/matugen.go`. The `ryogami` PKGBUILD comment still says "matugen
(palette on apply)" (`release/packages/ryogami/PKGBUILD`), and `ryogami.go`'s header
still calls ryogami "the Rust wallpaper daemon"; both are stale — the daemon is Go
(`ryoku/shell/ryogami/daemon/go.mod`) and it never invokes matugen.

---

## Pipeline overview

One image change drives two independent consumers: the pixels (ryogami → QML
backdrop) and the palette (`ryoku-shell` daemon → matugen → `colors.json` →
singletons). [READ]

1. **Trigger.** The bar image carousel shells out
   `["ryogami","wallpaper","set",path]`
   (`ryoku/shell/quickshell/shell/modules/bar/barstyles/qsbar/panels/ImageCarouselCarousel.qml:225`,
   `…/ImageCarouselPanel.qml:216`, `…/ImageCarouselHearthstone.qml:223`); the picker
   runs `ryogami wallpaper ui` (`…/qsbar/panels/…`, `bar/Frame.qml:72,406`) and the
   keybinds run `ryogami wallpaper ui` / `ryogami wallpaper random`
   (`ryoku/hyprland/modules/binds.lua:62-63`). The picker itself calls the JSON-RPC
   `wall.apply` (`ryoku/shell/ryogami/wall-ui/qml/services/DaemonClient.qml:188-203`).
2. **ryogami applies + publishes.** `wallpaperVerb` (`ryoku/shell/ryogami/daemon/verbs.go:25-102`)
   → `applyWallpaper` → surface republish. It persists `~/.cache/ryogami/outputs.json`
   (`apply.go:184,277`) and `~/.local/state/ryoku-wallpaper` (`apply.go:200-208,236-239`),
   then publishes one coalesced `{default, outputs}` frame on the **`wallpaper`
   topic** of `$XDG_RUNTIME_DIR/ryogami.sock` (`proto.go:9-12,87-93`).
3. **Shell QML renders the pixels.** `Wallpaper.qml` subscribes
   (`write("subscribe wallpaper\n")`, `…/wallpaper/Wallpaper.qml:56,65-89`), parses
   the frame (`WallpaperFrame.qml:19-40`), and `modules/desktop/Desktop.qml:431`
   instantiates `WallpaperMod.Backdrop`, which reveals the image through a GPU
   shader (`Backdrop.qml:414-445`) or plays a live clip with QtMultimedia
   (`Backdrop.qml:447-461`). The shell root wires the bridge in `shell.qml:177-193`.
4. **`ryoku-shell` daemon mirrors the topic.** `watchRyogami`
   (`ryoku/shell/ipc/ryogami.go:188-227`) connects to the same socket and
   `consumeRyogamiFrames` (`:163-182`) computes `srcChanged`; on a change it calls
   `d.scheduleTheme()` (`:178-180`).
5. **Theme pass.** `scheduleTheme` (`ryoku/shell/ipc/theming.go:157-162`) pokes a
   buffered channel; `paintWorker` (`theming.go:171-225`) picks the current still and
   calls `d.matugenApply(pic)` (`theming.go:208`, `matugen.go:556-607`).
6. **matugen, two passes** (see Q1). The Go daemon authors `~/.cache/ryoku/colors.json`
   itself (`matugen.go:573`) and fans the same palette into the app templates
   (`matugenRenderTemplates`, `matugen.go:1145-1183`).
7. **Reload / push.** `matugenReload` (`matugen.go:1284-1301`) sets gsettings, pokes
   kitty, and `nudgePalette()` pushes `qs -c shell ipc call theme reload`
   (`matugen.go:1310-1312` → `ipc/actions.go:58-77` → `IpcRouter.qml:104-109`).
8. **Consumers read the palette.** Every `Scheme.qml`, `Theme.qml` and `Tokens.qml`
   watches `~/.cache/ryoku/colors.json` with a `FileView` (see *Singletons*).

A fixed named theme short-circuits step 5-6: `paintWorker` runs
`matugenApplyStatic` from the theme catalog instead (`theming.go:178-195`,
`matugen.go:681-700`), so the two sources never write `colors.json` on one trigger.

---

## Q1 — Who runs matugen, and what it writes

**Answer: the `ryoku-shell` Go daemon, in `ryoku/shell/ipc/matugen.go`.** ryogami
never touches matugen. The trigger is a `wallpaper`-topic frame change mirrored by
`ipc/ryogami.go`, not a matugen call inside the wallpaper daemon.

matugen is installed `[TESTED]` (`matugen 4.2.0-1`, `/usr/bin/matugen`). The daemon
runs it in **two passes** [READ]:

**Pass 1 — scheme generation (stdout only, `--dry-run`):**

```
matugen image <img> -t <schemeType> -m <dark|light>
        --contrast <c> --lightness-dark <ld> --lightness-light <ll>
        --source-color-index <i> --prefer <pref> --json hex --dry-run
```

argv built in `matugenArgs` (`matugen.go:157-190`); executed by `runMatugenCapture`
(`matugen.go:774-783`). `schemeType` defaults to `scheme-tonal-spot` (`:79`); `mode`
is resolved by `resolveMode` from the knobs (`light|dark|sun|smart`, `:209-228`);
`prefer` is required (the installed matugen refuses non-interactive source pick
without it). A video wallpaper is first sampled to a PNG still by `liveFrame`
(`theming.go:74-104`, via `ffmpeg`) because "matugen decodes images only"
(`matugen.go:552-563`). Stdout is parsed by `parseMatugenPalette` (`:788-823`) and
`parseMatugenTones` (`:830-859`).

**Pass 2 — templating (writes files):**

```
matugen -c <filtered-config.toml> json <carrier.json>
```

`matugenRender` (`matugen.go:1249-1256`). The filtered config is the shipped
`config.toml` (+ `apps.toml` when app-theming is on) with only the roster-enabled
`[templates.*]` blocks (`filterMatugenConfig`, `:1121-1138`;
`matugenRenderFiltered`, `:1235-1245`). The carrier is `matugenShellPalette` wrapped
in matugen's nested shape (`matugenCarrier`, `:1024-1061`), written to
`~/.cache/ryoku/matugen-carrier.json` (`:1148-1149`).

**Everything the pipeline writes** [READ]:

| Path | Written by | Citation |
|---|---|---|
| `~/.cache/ryoku/colors.json` | **the Go daemon**, not matugen (base16 + camelCase M3 roles) | `matugen.go:573` (write), `:1011-1019` (shape), `:1782-1784` (path) |
| `~/.cache/ryoku/tones.json` | Go daemon (six tonal ramps) | `matugen.go:594`, `:1788-1790` |
| `~/.cache/ryoku/matugen-carrier.json` | Go daemon (pass-2 carrier) | `matugen.go:1148-1149` |
| `~/.cache/ryoku/active-config.toml`, `active-apps.toml` | Go daemon (filtered configs) | `matugen.go:1240-1244` |
| `~/.cache/ryoku/hypr-colors.lua` | matugen (template `hypr`) | `matugen/config.toml:15-17` |
| `~/.cache/ryoku/share-picker.css` | matugen (template `sharepicker`) | `matugen/config.toml:26-28` |
| `~/.cache/ryoku/kdeglobals-colors.conf` | matugen (template `kde`); Go merges into `~/.config/kdeglobals` | `matugen/config.toml:44-46`; merge `matugen.go:1421-1453` |
| `~/.config/kitty/current-theme.conf` | matugen (template `kitty`) | `matugen/config.toml:11-13` |
| `~/.config/btop/themes/ryoku.theme` | matugen (template `btop`) | `matugen/config.toml:19-21` |
| `~/.config/qt6ct/colors/ryoku.conf` | matugen (template `qt6ct`) | `matugen/config.toml:30-32` |
| GTK / Discord / Obsidian / Zed / … (21 blocks) | matugen, only when app-theming on | `matugen/apps.toml` (whole file) |
| `~/.config/ryoku/matugen.json` | **read/watch**, written by Hub/wall-ui, not matugen | `matugen.go:1773-1777`; watch `:1730-1746` |

Template output roots are pre-created by `matugenEnsureDirs` (`matugen.go:1794-1829`).
`~/.cache/ryoku/colors.json` is authored by the Go control plane on **both** the
wallpaper path (`:573`) and the static-theme path (`:690`) — matugen itself never
writes it. This is the single file every Quickshell singleton watches.

Side effects of a pass (not files): `matugenReload` runs
`gsettings set org.gnome.desktop.interface color-scheme/gtk-theme/accent-color`,
`pkill -USR1 -x kitty` (`matugen.go:1284-1301,1356-1363,1372-1391`), and the
`qt6ct` template's `post_hook` runs `ryoku-cmd-folders` and
`ryoku-cursor-material-recolor` (`matugen/config.toml:33-39`). `applyFont`
(`matugen.go:1623-1632`) is the same shape for fonts.

---

## Files

| Path (relative to `upstream/`) | Role |
|---|---|
| `ryoku/shell/ipc/matugen.go` | the matugen pipeline: scheme gen, `colors.json`/`tones.json`, carrier, template fan-out, reload, knobs, all path helpers |
| `ryoku/shell/ipc/theming.go` | `scheduleTheme`, `paintWorker`, `liveFrame`, `frameOffset`, `wallState` |
| `ryoku/shell/ipc/ryogami.go` | shell→ryogami socket bridge, `watchRyogami`, `consumeRyogamiFrames`, `depthPublish` |
| `ryoku/shell/ipc/actions.go` | `ipcCall` / `qsSelect` (`qs -c <cfg> ipc call …`) |
| `ryoku/shell/matugen/config.toml` | core template map (kitty, hypr, btop, sharepicker, qt6ct, kde) |
| `ryoku/shell/matugen/apps.toml` | app-suite template map (gtk3/4, discord, obs, zed, heroic, telegram, steam, cava, ghostty, micro, papirus, fish, yazi, obsidian, zathura, alacritty, tmux, sidra, ryotunes) |
| `ryoku/shell/matugen/templates/` | the matugen input templates |
| `ryoku/shell/ryogami/daemon/{main,daemon,verbs,rpc,proto,config,apply,surface,store,topics,scan,livewall,effects,grade,optimize,upscale,playlist,daynight,transitions}.go` | the wallpaper daemon (own Go module, stdlib-only) |
| `ryoku/shell/ryogami/wall-ui/` | the vendored skwd-wall picker (QML + matugen templates for previews + services) |
| `ryoku/shell/livewall/livewall.c` + `build.sh` | the C `ryogami-live` video-wallpaper layer-shell player |
| `ryoku/shell/quickshell/shell/modules/wallpaper/{Wallpaper,WallpaperFrame,Backdrop,OverviewBackdrop}.qml` + `reveal.frag(.qsb)` + `skwd/` | the shell-side topic bridge and reveal renderer |
| `ryoku/ui/Singletons/Tokens.qml`, `…/Singletons/Scheme.qml`, `…/qsbar/Theme.qml` | palette consumers |
| `ryoku/shell/systemd/user/{ryogami,ryoku-shell}.service` | the two session units |
| `ryoku/palette-bridge/main.go` | optional localhost HTTP palette bridge (SPA integrations) |
| `docs/theming.md` | upstream's own description of the pipeline |

---

## QML imports

Wallpaper + palette path only [READ]:

| File | Imports |
|---|---|
| `shell/modules/wallpaper/Wallpaper.qml:3-5` | `QtQuick`, `Quickshell`, `Quickshell.Io` |
| `shell/modules/wallpaper/WallpaperFrame.qml:1` | `QtQuick` |
| `shell/modules/wallpaper/Backdrop.qml:3-5` | `QtQuick`, `QtMultimedia`, `"Singletons"` |
| `shell/modules/desktop/Desktop.qml:20` | `import "../wallpaper" as WallpaperMod` |
| `shell/shell.qml:17-18` | `modules/wallpaper`, `modules/wallpaper/Singletons` |
| `ui/Singletons/Tokens.qml` | `QtQuick`, `Quickshell`, `Quickshell.Io` (+ `Ryoku.Ui` types) |
| `shell/modules/bar/barstyles/qsbar/Theme.qml:1-8` | `QtQuick`, `Quickshell`, `Quickshell.Io`, `Ryoku.Ui.Singletons`, `shell.services` |
| `shell/ryogami/wall-ui/qml/Colors.qml:1-4` | `QtQuick`, `Quickshell`, `Quickshell.Io`, `"services"` |

`Quickshell.Io` is what provides the `FileView`/`Socket`/`Process` primitives the
whole path rests on. `Backdrop.qml` is the only file on the path that needs
`QtMultimedia` (live-wallpaper playback).

---

## Singletons

The palette reaches the UI through per-surface `Scheme`/`Theme`/`Tokens`
singletons, all watching `$XDG_CACHE_HOME/ryoku/colors.json` (`~/.cache/ryoku/colors.json`)
with a `FileView { watchChanges: true }` [READ]:

| Singleton | `colors.json` read | Surface |
|---|---|---|
| `ryoku/ui/Singletons/Tokens.qml` | `:348-356` | shared design system (`Ryoku.Ui.Singletons`) |
| `shell/services/Scheme.qml` | `:99` | shell-global |
| `shell/modules/desktop/Singletons/Scheme.qml` | `:153` | desktop backdrop chrome |
| `shell/modules/launcher/shared/Singletons/Scheme.qml` | `:90` | launcher |
| `shell/modules/overview/Singletons/Scheme.qml` | `:74` | overview |
| `shell/modules/visualizer/Singletons/Scheme.qml` | `:124` | visualizer |
| `shell/quickshell/plugins/kit/Singletons/Scheme.qml` | `:100` | plugin kit |
| `shell/modules/bar/barstyles/qsbar/Theme.qml` | `:18` (`colorsPath`) | the bar (qsbar) |
| `hub/quickshell/Singletons/Scheme.qml` | `:51` | Settings app |
| `shell/ryogami/wall-ui/qml/Colors.qml` | `:15` | wallpaper picker |

These singletons also read `~/.config/ryoku/theme.json` (`followWallpaper`) and
`~/.config/ryoku/shell.json` (named theme), so a theme pass and a fixed palette
resolve through one chain (`Tokens.qml:330-356`). The `nudgePalette` IPC push
exists because the atomic-rename write can be missed by the file watch
(`matugen.go:1303-1309`).

---

## IPC verbs used

**Over `$XDG_RUNTIME_DIR/ryogami.sock`** (one socket, four grammars — `proto.go:9-12`)
[READ]:

- plain verbs: `subscribe wallpaper` (QML `Wallpaper.qml:74`; daemon
  `ipc/ryogami.go:209`); `wallpaper set|random|next|repaint|restore|ui|resource|live-reload`
  and `depth set|clear` (`ryogami/daemon/verbs.go:14-127`).
- JSON-RPC methods (`ryogami/daemon/rpc.go`): `wall.apply` (`:61`),
  `wall.list` (`:57`), `wall.random_start/stop/status` (`:220-241`),
  `wall.daynight_*` (`:242-265`), `wall.palette_frame` (`:284-297`),
  `wall.import/delete/metadata/favourite` (`:131-166`), `playlist.*` (`:298-365`),
  `upscale.*` (`:381-390`), `optimize.*` (`:99-124`), `effects.*` (`:75-93`),
  `state.get/set` (`:39-45`), `wm.focusedOutput` (`:29`).

**Over the shell's Quickshell IPC** — `qs -c <cfg> ipc call <target> <fn> [arg]`
(`ipc/actions.go:58-77`) [READ]:

- `shell theme reload` — fired by `nudgePalette` (`matugen.go:1311`); handler at
  `shell/modules/bar/barstyles/qsbar/core/IpcRouter.qml:104-109` (`theme.reload`).
- `shell theme apply|applyLauncher` — same handler (`IpcRouter.qml:106-107`).
- `shell picker wallpaper` — opens the picker (`IpcRouter.qml:111-117`).

**Over the Hub's localhost palette bridge** (optional): `ryoku-hub palette-bridge
status|enable|disable|restart` (`ryoku/hub/backend/palettebridge.go:176-185`; wall-ui
`settings/PaletteBridgeSettings.qml:30-40`).

The `depth` verbs are the shell daemon handing stage cutouts back to ryogami
(`ipc/ryogami.go:98-120`).

---

## Binaries shelled out

Measured with `stat`/`readlink -f` on `PATH` this session **[TESTED]**; versions from
`pacman -Q` **[TESTED]**:

| Binary | Bytes | Version | Called by |
|---|---|---|---|
| `matugen` | 11,945,640 | 4.2.0-1 | `ryoku-shell` daemon (`matugen.go:775,1253`) |
| `ffmpeg` | 428,296 | 2:9.0.2-2 | shell `liveFrame`/luma (`theming.go:92`; `matugen.go:307,377`); ryogami `livewall`/`scan`/`optimize`/`upscale` |
| `ffprobe` | 202,944 | (ffmpeg pkg) | ryogami `livewall.go:73`, `scan.go:443`, `upscale.go` |
| `quickshell` / `qs` | 6,002,104 | 0.3.2-1 | the QML runtime; `qs ipc call` (`ipc/actions.go:66`); ryogami spawns wall-ui (`process.go:74`) |
| `magick` / `convert` | 14,824 | imagemagick 7.1.2.34-1 | ryogami thumbnails/colour/grading (`effects.go:300`, `scan.go:245`, `grade.go:127`) |
| `curl` | 223,536 | — | wall-ui remote downloads (`WallhavenService.qml:149`); palette-bridge install paths |
| `inotifywait` | 435,640 | — | wall-ui folder watcher (`wall-ui/qml/services/WatcherService.qml:117`) |
| `kitty` | 100,600 | — | SIGUSR1 reload target (`matugen.go:1299,1631`) |
| `gsettings` | (glib) | — | GTK nudges (`matugen.go:1289,1361,1626-1628`) |
| `pkill` | (procps) | — | `pkill -USR1 -x kitty` (`matugen.go:1299,1631`) |
| `ryoku-cursor-material-recolor` | [UNVERIFIED] | — | cursor recolor (`matugen.go:583`; `config.toml:39`) |
| `ryoku-cmd-folders` | [UNVERIFIED] | — | folder-icon recolor (`config.toml:39`) |
| `papirus-folders` | [UNVERIFIED] | — | papirus post_hook (`apps.toml:63`) |
| `nice` | (coreutils) | — | ryogami `livewall.go:199,310` |

Not installed here: `ryogami`, `ryogami-live`, `ryoku-shell`, `ryoku-palette-bridge`
(all built from source in this repo) **[TESTED]**.

---

## Services / daemons

| Unit | ExecStart | Notes |
|---|---|---|
| `ryoku-shell.service` | `/usr/bin/ryoku-shell daemon` | `ryoku/shell/systemd/user/ryoku-shell.service`; owns the matugen pipeline; `Environment=QT_MEDIA_BACKEND=ffmpeg`, `RYOKU_POLKIT_AGENT=1` |
| `ryogami.service` | `/usr/bin/ryogami` | `ryoku/shell/systemd/user/ryogami.service`; `MALLOC_CONF=…` tuning for the Quickshell-based picker; `KillMode=process` |
| *(optional)* `ryoku-palette-bridge` | localhost HTTP | shipped as its own package; enabled via the Hub; **not** part of the wallpaper→matugen path |

Both are `PartOf=ryoku-session.target`, `After=ryoku-session.target`,
`ConditionEnvironment=WAYLAND_DISPLAY`, `Restart=always`, `Slice=session.slice`.
matugen is not a daemon: it is a short-lived child of `ryoku-shell` per palette pass.

`ryogami` runs two long-lived things: the daemon (catalog/thumbnails/apply/depth) and,
for live wallpapers, one `ryogami-live` process per output (`livewall.go:17-23`) built
from `ryoku/shell/livewall/livewall.c`.

---

## Qt modules

From the PKGBUILDs [READ] and the imports:

| Qt package | Why the path needs it |
|---|---|
| `qt6-base` | QtCore/QtGui under Quickshell |
| `qt6-declarative` | `QtQuick` in every bridge/`Scheme`/`Theme` |
| `qt6-multimedia` | `Backdrop.qml:4,447-461` (`MediaPlayer`/`VideoOutput`/`AudioOutput`) — live wallpapers; also `ryoku-desktop` hard-depends it |
| `qt6-svg` | SVG assets in the bar/picker |
| `qt6-imageformats` | WebP/AVIF/JPEG wallpaper decoding |
| `qt6-wayland` | Quickshell's Wayland QPA plugin |
| `qt6-shadertools` | **build-time only** — bakes `reveal.frag.qsb` and `skwd/*.qsb`; the `.qsb` files ship, so no runtime compile |
| `quickshell` | the QML runtime the daemon, picker and shell all run on |

`ryoku-shell/PKGBUILD` runtime `depends`: `quickshell ffmpeg wayland jq uv`
(`release/packages/ryoku-shell/PKGBUILD:18`). `ryogami/PKGBUILD`:
`imagemagick ffmpeg quickshell curl inotify-tools` (`:29`), `makedepends go wayland
wayland-protocols`. `ryoku-desktop` hard-depends `matugen`, `qt6-multimedia`,
`qt6-declarative`, `adw-gtk-theme`, `gnome-themes-extra`, and the toolkits the
templates target.

---

## Fonts

The pipeline writes fonts but does not ship the display faces [READ]:

- 11 bundled faces load at runtime via `FontLoader` in
  `ryoku/shell/quickshell/shell/modules/desktop/Singletons/Fonts.qml:20-30`
  (`reckoner`, `jf-flat`, `abberancy`, `daydream`, `sabana`, `unrealised`, `vip-rawy`,
  `xenophobia`, `vexa-light`, `overhead`, …) — 366,768 B total, on disk under
  `ryoku/shell/quickshell/shell/assets/fonts/`.
- `applyFont` (`matugen.go:1623-1632`) pushes the chosen system fonts to gsettings
  (`font-name`, `document-font-name`, `monospace-font-name`), rewrites
  `~/.config/qt6ct/qt6ct.conf` (`writeQt6ctFont`, `:1658-1678`) and
  `~/.config/kitty/current-font.conf` (`writeKittyFont`, `:1683-1690`), then SIGUSR1s
  kitty. This runs off the settings topic (`fontSig`, `:1608-1617`), not the matugen
  pass.
- Compiled defaults: family `Space Grotesk` / mono `SpaceMono Nerd Font`, size 11
  (`matugen.go:1643-1651`); `Tokens.qml` defaults to `Fraunces` / `Space Grotesk` /
  `SpaceMono Nerd Font` / `Noto Sans CJK JP`.

The families themselves are Phase-4 installs (see `06-fonts-qt-assets.md`); matugen
shells to `gsettings`/`qt6ct`/`kitty` regardless of whether the family exists.

---

## Assets (incl. off-disk ryoku/assets, with sizes)

**On-disk (inside the checkout, referenced by the path)** [READ]:

| Path | Bytes | Referenced by |
|---|---|---|
| `ryoku/shell/quickshell/shell/assets/fonts/` (11 files) | 366,768 | `modules/desktop/Singletons/Fonts.qml:20-30` |
| `ryoku/shell/quickshell/reload-cover/assets/logo.png` | 1,401 | `reload-cover/ReloadMedia.qml:64` |
| `ryoku/shell/quickshell/shell/modules/bar/barstyles/qsbar/assets/` (11 files) | 68,506 | `qsbar/modules/ClaudeWidget.qml:237-257`, `GpuWidget.qml:37`, `panels/AiUsagePanel.qml:449-474` |
| `ryoku/shell/ipc/assets/*.oga` (5 sounds, `go:embed`) | — | `ryoku/shell/ipc/sounds.go:21` |
| `ryoku/shell/quickshell/shell/modules/wallpaper/reveal.frag` + `.qsb`, `skwd/*.qsb` | — | `Backdrop.qml:302,316,431` |

**Off-disk `ryoku/assets` (not in the sparse checkout)** — sizes from
`git ls-tree -r -l HEAD ryoku/assets` [READ], 94 entries / **250,784,221 B** total:

| Path | Bytes | Referenced by | Needed here? |
|---|---|---|---|
| `ryoku/assets/brand/logo.svg` | 594 | `ryoku/shell/deploy.sh:617`; `ryoku-desktop/PKGBUILD` | launcher entry icon |
| `ryoku/assets/brand/logo-mark.svg` | 552 | `ryoku/shell/deploy.sh:609` | fallback app icon |
| `ryoku/assets/brand/logo-mark.png` | 43,143 | `hub/quickshell/pages/FastfetchPage.qml:282` | no (Fastfetch) |
| `ryoku/assets/brand/fastfetch-emblem.png` | 377,909 | `FastfetchPage.qml:281`; `ryoku-desktop/PKGBUILD` | no (Fastfetch) |
| `ryoku/assets/ryodecors/*` (23 files) | 4,165,851 | `ryoku/shell/deploy.sh:541` | no (Decor/Profile/Rashin) |
| `ryoku/assets/wallpapers/*` (59 files) | 245,026,989 | seeded into `~/Pictures/Wallpapers`; not path-hardcoded | seeded content, not a runtime dep |

`ryoku/assets/brand/` = 1,591,381 B. **No runtime QML on the wallpaper/theming path
reads an off-disk `ryoku/assets` file** — the palette path reads the *user's*
`~/Pictures/Wallpapers`, and the wallpapers under `ryoku/assets/wallpapers/` are
seeded content only. The scripts that copy assets (`deploy.sh:541,609,617`) run at
deploy/install time, not per palette pass.

---

## Network calls

[READ] The wallpaper→palette path makes **no** outbound calls of its own:

- `matugen` runs entirely offline on a local file. No template performs a fetch.
- `resolveMode("sun")` depends on the **weather poll** (`sun.go` / `weather.go`) only
  when the mode knob is `sun` (`matugen.go:236-245`); the default `smart` mode uses
  only the local image (`:209-228`).
- The `palette-bridge` is **localhost-only**: it binds `127.0.0.1:47616`
  (`palette-bridge/main.go:241`) and serves `/colors.json`, `/v1/palette`,
  `/v1/events`, `/healthz` (`:255-258`) for local SPA integrations; no network egress.
- Outbound traffic belongs to the **picker only**, not the palette path: the
  wall-ui's `WallhavenService` (`wallpaper/WallhavenService.qml:149,190` — `curl`
  against `https://wallhaven.cc/api/v1/`), Steam Workshop downloads
  (`services/SteamDownloadService.qml`), and MoeWalls/MotionBGs, all host-allowlisted.
  The bar/palette never call these.

---

## Q7 — Two wallpaper options, costed

Two ways to reach the same end state (image on screen, palette regenerated by
matugen). Sizes measured this session **[TESTED]**; the substitute daemons are **not
installed**, so their sizes are **[UNVERIFIED]**.

### Option A — keep `ryogami` (as shipped)

What you build/ship beyond matugen:

| Item | Bytes | Source |
|---|---|---|
| `ryogami` Go binary | [UNVERIFIED] (not built; stdlib-only module, 1.9 MB source) | built from `ryoku/shell/ryogami/daemon` (`ryogami/PKGBUILD` `go build -mod=vendor`) |
| `ryogami-live` C binary | [UNVERIFIED] (built from `ryoku/shell/livewall/livewall.c`, 18,909 B source) | `livewall/build.sh`, only needed for live video |
| runtime tools | `imagemagick` + `ffmpeg` + `quickshell` + `curl` + `inotify-tools` | `ryogami/PKGBUILD:29` |
| the picker (wall-ui) | QML tree, shipped to `/usr/share/ryogami` | `ryogami/PKGBUILD` `package()` |

Gives: the `wallpaper` topic → `Wallpaper.qml` bridge, the GPU reveal transitions
(`Backdrop.qml`, 16 kinds + `skwd/` shaders), depth cutout, playlists, day/night
rotation, and live video — **with zero edits** to the shell QML or the Go bridge.

### Option B — substitute `hyprpaper` / `swww` / `swaybg` + matugen only

| Candidate | Bytes | Installed? |
|---|---|---|
| `hyprpaper` | NOT FOUND | no |
| `swww` / `swww-daemon` | NOT FOUND | no |
| `swaybg` | NOT FOUND | no |
| `mpvpaper` | NOT FOUND | no |

Sizes cannot be measured here; all are **[UNVERIFIED]** (they would have to be
installed first, which is out of scope). matugen (11,945,640 B) stays in **both**
options and dominates every measured number.

### Cost comparison

| | Option A (ryogami) | Option B (swww/swaybg + matugen) |
|---|---|---|
| Extra binaries to build/ship | `ryogami` + `ryogami-live` (sizes [UNVERIFIED]) | `hyprpaper`/`swww`/`swaybg` (sizes [UNVERIFIED]) |
| Extra runtime deps | imagemagick, ffmpeg, quickshell, curl, inotify-tools | none beyond the compositor tool + matugen |
| Shell edits needed | **none** | **must cut the topic bridge** (below) |
| Transitions / reveal shader | yes (`Backdrop.qml:414-445`) | no (plain set) |
| Live video wallpapers | yes (QtMultimedia + `ryogami-live`) | no (swaybg/hyprpaper are still-only; mpvpaper is a separate, heavier player) |
| Depth cutout, playlists, day/night | yes | no |
| Palette (matugen) | unchanged | unchanged |

**What Option B actually costs in code** (files that reference the ryogami
contract and would need rework) [READ]: `shell/modules/wallpaper/Wallpaper.qml`
(the topic socket), `WallpaperFrame.qml` (frame parse), `Backdrop.qml` (reveal +
`live`/`videoUrl`), `shell/modules/desktop/Desktop.qml:431` (the backdrop host),
`shell/shell.qml:177-193` (wiring), `ryoku/shell/ipc/ryogami.go` (daemon bridge) with
its consumers in the `ryoku-shell` daemon, `bar/Frame.qml:72,406` and
`barstyles/qsbar/panels/ImageCarousel*.qml` (`applyBgProc` → `ryogami wallpaper set`),
and `ryoku/hyprland/modules/binds.lua:62-63`.

**Verdict (bytes + blast radius):** matugen is the only large measured binary
(11.9 MB) and is common to both. Option B saves no measured bytes on this box (none
of the substitutes are installed, so the comparison is code, not size) while
deleting the reveal shader, live video, the depth channel and the picker, and
requiring edits across ~9 shell/daemon files. **Keep `ryogami` unless live video and
the reveal motion are explicitly dropped from the keep list** — that decision is
Phase 4/5, not a size win.

---

## Necessity / exclusions

**Mandatory for "wallpaper + matugen theming" to work** [READ]/[UNVERIFIED]:

- `ryoku-shell` daemon (owns the entire matugen pipeline — `ryoku/shell/ipc/`).
- `ryogami` daemon **or** a replacement that supplies the applied-wallpaper signal.
  The `ryoku-shell` pipeline keys on the ryogami `wallpaper` topic
  (`ipc/ryogami.go`); dropping ryogami without a substitute leaves the palette with
  no trigger.
- `matugen` (the renderer).
- `quickshell` (the runtime the shell + picker run on).
- `ffmpeg` (video-still sampling `theming.go:92`; luma/chroma `matugen.go:307,377`).
- The QML wallpaper module (`Wallpaper/Frame/Backdrop`) and the palette singletons.

**Conditional** [READ]:

- `qt6-multimedia` — only for live video wallpapers (`Backdrop.qml:4`). A still-only
  Mei could drop it and the `Backdrop.qml` video blocks.
- `ryogami-live` (C) — only for video wallpapers; built by `ryogami/PKGBUILD`.
- `imagemagick` / `curl` / `inotify-tools` — picker-side (thumbnails, remote
  downloads, folder watch), not palette-side.
- `qt6-imageformats` — WebP/AVIF wallpapers only.
- `kde` / GTK / app-suite templates — optional; the shell palette does not need them
  (`apps.toml` is gated by `themeRyokuApps` + `themeAppsEnabled`, `matugen.go:1172`).

**Excluded / not on the path**:

- `palette-bridge` (`ryoku/palette-bridge/`) — optional SPA integration; not needed
  by wallpaper + matugen on an existing Hyprland box.
- `ryoku/assets/wallpapers/` (245 MB) + `ryodecors/` (4.17 MB) — seeded content, not a
  runtime dependency of the pipeline.
- ryogami's `upscale`/`optimize`/`effects`/`playlist`/`daynight` RPC surfaces — extras
  beyond "apply + palette"; safe to disable behind their config flags but they ship in
  the same binary.
- The `hub` matugen backend (`ryoku/hub/backend/matugen.go`) — it only *writes knobs*
  to `~/.config/ryoku/matugen.json` (`:170`), the file the daemon watches
  (`matugen.go:1730-1746`); it renders nothing. A Mei settings page may write that
  file without importing the Hub.

**Opt-back-in notes:** if `ryogami` is dropped for Option B, the palette trigger must
be re-sourced (e.g. a tiny watcher that calls the shell's `theme reload` handler
`IpcRouter.qml:104-109` after an `swww`/`swaybg` set), and `Backdrop.qml` reduced to a
plain `Image` — the reveal transition and live video are lost either way.
