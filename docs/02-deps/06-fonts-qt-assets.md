# 06 — Fonts, assets, QML modules, Qt modules

Cross-cutting inventory for the kept surfaces: the bar (`qsbar`), the launcher,
the control sidebar (`qsbar/controlcenter`), and the Settings "appearance + shell"
pages (Hub `GlobalPage` / `DesktopPage` / `AnimationsPage`, rendered through
`Ryoku.Ui`). Scope is the sparse checkout on disk plus the off-disk trees reachable
with `git show HEAD:<path>`.

Labels: **[TESTED]** observed by running a build/test — none here (Ryoku source is
read-only, nothing built or run). **[READ]** read directly from committed source /
blob sizes. **[UNVERIFIED]** inferred or not confirmed by execution.

Citations are `path:line` for content and `path` + blob bytes for sizes.

---

## Fonts (families, files, packages, fallbacks)

### Family names the UI hardcodes [READ]

| Family | Declared in | Role |
|---|---|---|
| `Fraunces` | `ryoku/ui/Singletons/Tokens.qml:105`; `ryoku/hub/quickshell/Singletons/Theme.qml` (display); `ryoku/shell/quickshell/shell/services/Theme.qml:213`; launcher `shared/Singletons/Theme.qml:75` | display serif: page titles, hub heads |
| `Space Grotesk` | `Tokens.qml:106` (`ui`, default); hub `Theme.qml` (`font`); shell `Theme.qml:203` (`fontPrimary` default) | UI/body sans (brand) |
| `JetBrainsMono Nerd Font` | hub `Theme.qml` (`mono`); shell `Theme.qml:214`; qsbar `Theme.qml:121`; launcher `Config.qml:97` (`fontFamily` default) | labels, code, nerd glyphs |
| `SpaceMono Nerd Font` | `ryoku/ui/Singletons/Tokens.qml:107` (`mono`, compiled default) | default mono until shell.json overrides |
| `Noto Sans CJK JP` | `Tokens.qml:108` (`jp`); hub `Theme.qml` (`fontJp`); shell `Theme.qml:215` | the 力 seal and every kanji mark |
| `Material Symbols Rounded` | `ryoku/shell/quickshell/shell/components/MaterialIcon.qml:12` | every bar/pill/settings icon ligature |
| `Inter` / `Inter Display` | hub previews e.g. `ClockPreview.qml:124,227,306`; `AioPreview.qml:75` | hub preview widget bodies |
| `Archivo Black` | loaded from a file, `ryoku/hub/quickshell/pages/RashinPage.qml:50` | Rashin page face (Hub, not on the Mei keep list) |

Notes [READ]:
- `Tokens.refreshNamed()` (`Tokens.qml:303-315`) overwrites both `ui` and `mono`
  with `shell.json` `fontFamily` when the user sets a System font, so Space
  Grotesk / SpaceMono are *defaults*, not fixed.
- The seal is text, not an image: `Theme.mark = Config.markText || "\u529b"`
  (`shell/services/Theme.qml:219`, `shell/modules/desktop/Singletons/Theme.qml:84`)
  rendered `font.family: Theme.fontJp` (`shell/components/BrandMark.qml:36-38`).
  A custom image mark is optional (`markSource`, `BrandMark.qml:23-25`).

### Font FILES actually shipped [READ]

On-disk (inside the checkout, part of the kept modules):

| Path | Bytes |
|---|---|
| `ryoku/shell/quickshell/shell/assets/fonts/abberancy.ttf` | 29220 |
| `ryoku/shell/quickshell/shell/assets/fonts/daydream-demo.otf` | 20216 |
| `ryoku/shell/quickshell/shell/assets/fonts/jf-flat-regular.otf` | 43852 |
| `ryoku/shell/quickshell/shell/assets/fonts/overhead.ttf` | 16264 |
| `ryoku/shell/quickshell/shell/assets/fonts/reckoner-bold.ttf` | 28376 |
| `ryoku/shell/quickshell/shell/assets/fonts/reckoner.ttf` | 23592 |
| `ryoku/shell/quickshell/shell/assets/fonts/sabana-regular.ttf` | 32100 |
| `ryoku/shell/quickshell/shell/assets/fonts/unrealised.ttf` | 42500 |
| `ryoku/shell/quickshell/shell/assets/fonts/vexa-light.ttf` | 65360 |
| `ryoku/shell/quickshell/shell/assets/fonts/vip-rawy-regular.otf` | 37836 |
| `ryoku/shell/quickshell/shell/assets/fonts/xenophobia-nominal.ttf` | 27452 |
| **`ryoku/shell/quickshell/shell/assets/fonts/` total** | **366,768** |
| `ryoku/hub/quickshell/fonts/archivo-black.ttf` | 40544 |

These 11 shell faces are loaded at runtime by `FontLoader` in
`ryoku/shell/quickshell/shell/modules/desktop/Singletons/Fonts.qml` and exposed as
`Fonts.families` to the Hub's widget-font picker; they are bundled so a widget can
name one without a system install. `ryoku/ui/art/` holds no fonts.

### Packages that provide the system families [READ]

`release/packages/ryoku-desktop/PKGBUILD:168-173` (hard `depends`, official repo):
`ttf-jetbrains-mono-nerd`, `inter-font`, `noto-fonts`, `noto-fonts-cjk`,
`noto-fonts-emoji`, `ttf-material-symbols-variable`.

`system/packages/base.packages:304-323` (ISO pacstrap set): the six above plus
`otf-space-grotesk` and `ttf-maple-mono-nf`, both shipped from `[ryoku]`
(`release/packages/otf-space-grotesk/PKGBUILD`, `release/packages/ttf-maple-mono-nf/PKGBUILD`,
fixed-version prebuilt releases).

`system/packages/aur.packages:52`: `ttf-fraunces-variable` (Fraunces, AUR).

`ryoku-desktop-hyprland/PKGBUILD` carries **no** font packages — it inherits
`ryoku-desktop`.

### Mandatory vs decorative [READ] + [UNVERIFIED]

- **Mandatory for the kept surfaces**: `Noto Sans CJK JP` (the 力 seal + kanji);
  `Material Symbols Rounded` (every icon — without it `MaterialIcon.qml` renders
  the ligature *name* as text, e.g. "wifi", per the PKGBUILD comment at
  `ryoku-desktop/PKGBUILD:164-167`); `JetBrainsMono Nerd Font` (mono text + nerd
  glyphs); `Space Grotesk` (default UI sans); `Inter` (hub preview bodies).
- **Decorative / page-local**: `Fraunces` (titles — falls back to the default sans,
  titles still read); the 11 bundled `FontLoader` faces and `archivo-black.ttf`
  (widget font picker / Rashin page only).
- **Not referenced by any kept QML**: `ttf-maple-mono-nf` (terminal/code offer
  only), `noto-fonts` / `noto-fonts-emoji` (generic + emoji fallback).
- **Fallback when missing** [UNVERIFIED]: Qt font substitution falls through to
  the platform default sans; a missing CJK face leaves 力 as a tofu box; a missing
  `Material Symbols Rounded` leaves icon slots showing the glyph name. No Ryoku
  code installs a substitute — degradation is Qt's.

---

## Assets needed by the kept surfaces (with sizes)

### On-disk art shipped inside the kept modules [READ]

Bar / control sidebar:
- `ryoku/shell/quickshell/shell/modules/bar/barstyles/qsbar/assets/` — 11 files,
  **68,506 B** total: `arch-header-arch.png` 10300, `arch-header-linux.png` 8596,
  `bob2.png` 1688, `bob3.png` 41408, `claude.svg` 2000, `codex-cli.svg` 1355,
  `codex.svg` 1306, `gpu-card.svg` 439, `hdd-mark.svg` 287, `omacom-text.png` 932,
  `opencode-mark.svg` 195. Referenced from `qsbar/modules/ClaudeWidget.qml:237-257`,
  `GpuWidget.qml:37`, `panels/AiUsagePanel.qml:449-474`.
- `ryoku/shell/quickshell/shell/modules/bar/barstyles/qsbar/shaders/` —
  `logo-tint.frag.qsb` 1404, `stream.frag` 16277, `stream.frag.qsb` 50516 (**68,197 B**).
- `ryoku/shell/quickshell/shell/components/icons/` — 152 symbolic SVGs, **65,090 B**
  (glyph fallback set, `SymbolIcon.qml:23`).

Launcher:
- `ryoku/shell/quickshell/shell/modules/launcher/shared/art/hands-adam.png`
  **681,800 B** (`HeroShutter.qml:89`, `Preview.qml:64,136`, `RestDashboard.qml:96`).
- launcher dir total (`ryoku/shell/quickshell/shell/modules/launcher/`) = 1,422,832 B
  (includes its own `shared/art/bt/*.png`, `qa/` etc.).

Ryoku.Ui (design system):
- `ryoku/ui/grain.png` **66,409 B** (`Grain.qml:7`, tiled film-tooth).
- `ryoku/ui/art/graces.svg` 54526, `helm.svg` 25541, `justice.svg` 35727.
- `ryoku/ui/shaders/dither.frag` 1281 + `dither.frag.qsb` 4219
  (`DitherImage.qml`), `spectrum.frag` 19414 + `spectrum.frag.qsb` 37499.

Misc (referenced by module code):
- `ryoku/shell/quickshell/reload-cover/assets/logo.png` **1,401 B**
  (`ReloadMedia.qml:64`).
- `ryoku/shell/quickshell/welcome/art/welcome-bg.png` **1,204,630 B**
  (`welcome/Backdrop.qml:19`, welcome screen).
- Hub art (`ryoku/hub/quickshell/art/`): `dither-torii.png` 599229,
  `profile-hero.png` 48737, `roots.png` 765424 (`CreditsPage.qml:94`),
  `tiling-dwindle.gif` 101955 + `tiling-master.gif` 96800 +
  `tiling-scrolling.gif` 133209 (`SettingsSheet.qml:534`).

### Off-disk `ryoku/assets` referenced [READ]

Sizes from `git ls-tree -r -l HEAD ryoku/assets`:

| Path | Bytes | Referenced by | Needed by kept surfaces? |
|---|---|---|---|
| `ryoku/assets/brand/logo.svg` | 594 | `ryoku-desktop/PKGBUILD:427`, `ryoku/shell/deploy.sh:617` | launcher entry icon (`ryoku-hub.svg`) |
| `ryoku/assets/brand/logo-mark.svg` | 552 | `ryoku-desktop/PKGBUILD:317`, `deploy.sh:609` | fallback app icon |
| `ryoku/assets/brand/logo-mark.png` | 43143 | `hub/pages/FastfetchPage.qml:282` | no (Fastfetch, not kept) |
| `ryoku/assets/brand/fastfetch-emblem.png` | 377909 | `FastfetchPage.qml:281`; `ryoku-desktop/PKGBUILD:93` | no (Fastfetch, not kept) |
| `ryoku/assets/brand/icon.png` | 17969 | installer/branding | no (runtime) |

- Referenced brand set total = **440,167 B**; whole `ryoku/assets/brand/` = 1,591,381 B.
- `ryoku/assets/wallpapers/` **245,026,989 B** (~233.7 MiB) — seeded into
  `~/Pictures/Wallpapers` by the installer (`installation/backend/lib/deploy.sh:303`,
  `ryoku-shell-installer/engine.go:1288`). No QML path hardcodes one; the bar wall
  index reads the user's folder, so this is *content*, not a runtime dependency.
- `ryoku/assets/ryodecors/` **4,165,851 B** (~3.97 MiB) — seeded into
  `~/Pictures/ryodecors` (`deploy.sh:541`), resolved via
  `ryoku/ui/Singletons/Ryodecors.qml`. Consumed by `ProfilePage.qml` / `RashinPage.qml`
  only (**not** on the keep list).
- `ryoku/assets` grand total = **250,784,221 B**.

**Bottom line for the kept surfaces** [READ]: the bar needs the 力 seal (a *font*
glyph, not an asset) plus the on-disk `qsbar/assets`/`icons` SVGs; the launcher
needs `hands-adam.png` + `bt/`; Ryoku.Ui needs `grain.png` + its shaders. **No
runtime QML in the kept surfaces reads an off-disk `ryoku/assets` file.** The only
off-disk brand files that matter are the two SVG icons used for the `ryoku-hub`
desktop entry.

---

## QML modules and qmldir inventory

Every committed `qmldir` and the module it declares (`module` line, or the
directory it is imported as) [READ]:

| qmldir | Module | Notes |
|---|---|---|
| `ryoku/ui/qmldir` | `Ryoku.Ui` | 50 QML + 4 JS types |
| `ryoku/ui/Singletons/qmldir` | `Ryoku.Ui.Singletons` | 12 singletons (Tokens, Ink, Paths, I18n, Spans, Silhouette, VizStyles, Ryodecors, ProfileStore, Spawn, Version, Wm) |
| `ryoku/shell/framebars/qmldir` | `Ryoku.FrameBars` | FrameBars/BarCatalog/MenuCatalog/NacreConfig |
| `ryoku/shell/quickshell/plugins/kit/qmldir` | `Ryoku.PluginKit` | 8 types |
| `ryoku/shell/quickshell/plugins/kit/Singletons/qmldir` | `Ryoku.PluginKit.Singletons` | Theme/Config/Motion/Scheme |
| `ryoku/wm/hyprland/qml/qmldir` | `Ryoku.Wm.Hyprland` | GlobalShortcutBridge, FocusGrabBridge |
| `ryoku/shell/quickshell/shell/services/qmldir` | `shell.services` | ~46 singletons (Theme, Config, Media, Audio, Notifs, Tray, Dock, Capture, …) |
| `ryoku/shell/quickshell/shell/barkit/qmldir` | `shell.barkit` | re-exports of stable bar products/components |
| `ryoku/hub/quickshell/Singletons/qmldir` | (hub singletons dir) | Theme/Updates/SysInfo/LiveStats/Scheme/Settings/UserSchemes/ProviderSchema |
| `ryoku/hub/quickshell/barstudio/qmldir` | `barstudio` | CatalogLabels, ZoneEditor, Nacre* |
| `…/qsbar/qmldir` | (qsbar dir) | BarPlugins/BarSlot/Theme/VariantRoot |
| `…/qsbar/core/qmldir`, `modules/`, `panels/`, `components/`, `controlcenter/{,kit,routes}/qmldir` | (relative dirs) | qsbar internal types |
| `ryoku/shell/quickshell/shell/modules/{desktop,launcher/shared,overview,stage,visualizer,wallpaper}/Singletons/qmldir` | (relative dirs) | per-surface singletons |
| `ryoku/shell/quickshell/{welcome,ryopin,ryoshot}/Singletons/qmldir` | (relative dirs) | aux surfaces |
| `ryoku/shell/ryogami/wall-ui/qml/**/qmldir` | (relative dirs) | Ryogami wall browser |
| `Ryoku.Blobs` | C++ module | **no committed qmldir** — generated by `qt_add_qml_module` (see below) |

Non-kept (lockscreen): `ryoku/lockscreen/qylock/.../imports/{QtGraphicalEffects,QtMultimedia,SddmComponents}/qmldir`.

### QML imports used by the kept surfaces [READ] (occurrence counts)

`Ryoku.Ui.Singletons` ×345 · `Ryoku.Ui` ×77 · `Ryoku.FrameBars` ×10 ·
`Ryoku.PluginKit` ×5 · `Ryoku.PluginKit.Singletons` ×1 · **`Ryoku.Blobs` ×3**
(`shell/modules/bar/Frame.qml:6`, `shell/modules/bar/popouts/Popout.qml:4`,
`shell/modules/capture/CameraOverlay.qml:7`).

`Quickshell` ×300 · `Quickshell.Io` ×187 · `Quickshell.Wayland` ×69 ·
`Quickshell.Widgets` ×23 · `Quickshell.Services.Mpris` ×14 ·
`Quickshell.Bluetooth` ×14 · `Quickshell.Services.Pipewire` ×5 ·
`Quickshell.Services.UPower` ×4 · `Quickshell.Services.Notifications` ×2 ·
`Quickshell.Networking` ×2 · `Quickshell.WindowManager` ×1.

`QtQuick` ×667 · `QtQuick.Controls` ×40 · `QtQuick.Effects` ×37 ·
`QtQuick.Shapes` ×33 · `QtQuick.Layouts` ×11 · `QtQuick.Dialogs` ×2 ·
`QtQuick.Window` ×1. Also `Qt5Compat.GraphicalEffects` (BrandMark, SymbolIcon,
WidgetSlot, EffectLayer) and `org.kde.syntaxhighlighting`
(`shell/components/CodeHighlight.qml:2`, optional `Loader`).

No `Ryoku.Wm` import appears in the copied kept-surface trees; the bridge module is
installed but the surfaces on disk do not import it (compositor seam lives in the
shell root).

---

## C++ plugin (Ryoku.Blobs) build requirements

`ryoku/shell/plugin/` — total **73,797 B** [READ].

`CMakeLists.txt`:
- `cmake_minimum_required(VERSION 3.28)`; `CMAKE_CXX_STANDARD 20`, `AUTOMOC ON`.
- `find_package(Qt6 6.5 REQUIRED COMPONENTS Quick ShaderTools Multimedia)`
  (`CMakeLists.txt:19`) → **Qt Quick (Qt6::Quick), ShaderTools, Multimedia**.
- `qt_add_qml_module(ryoku-blobs URI Ryoku.Blobs VERSION 1.0 …)`; sources
  `blobgroup`, `blobshape`, `blobrect`, `blobinvertedrect`, `blobmaterial`,
  `camerafeed` (`.cpp/.hpp`).
- `target_link_libraries(ryoku-blobs PRIVATE Qt6::Quick Qt6::Multimedia)`
  (`CMakeLists.txt:42`).
- `qt_add_shaders(ryoku-blobs … GLSL "300es,330" PREFIX "/" FILES shaders/blob.vert shaders/blob.frag)`.
- `$ORIGIN` rpath so the plugin `.so` finds its backing lib in the same dir.

`build.sh` (run on dev/ISO only, never the installed target): requires `cmake`,
`ninja`, and (comment) `qt6-shadertools` + a C++20 compiler + Qt6 dev files;
emits `<dest>/Ryoku/Blobs/{libryoku-blobs.so, qmldir, *.qsb}`.

Committed sources/shaders: `shaders/blob.vert` 617 B, `shaders/blob.frag` 13,394 B;
largest C++ is `blobshape.cpp` 16,821 B.

The `ryoku-blobs` package (`release/packages/ryoku-blobs/PKGBUILD`) has
`depends=('qt6-base' 'qt6-declarative' 'qt6-multimedia')` and
`makedepends=('cmake' 'ninja' 'qt6-shadertools' 'qt6-declarative' 'qt6-multimedia')`,
installs to `/usr/lib/qt6/qml/Ryoku/Blobs`. **[READ]**

`CameraFeed` (plugin) links `Qt6Multimedia`; the three kept consumers are the bar
`Frame` (screen frame) and `Popout`.

---

## Qt modules required

From the three PKGBUILDs [READ]:

- `ryoku-blobs`: `qt6-base`, `qt6-declarative`, `qt6-multimedia`
  (+ build: `cmake`, `ninja`, `qt6-shadertools`).
- `ryoku-desktop`: `qt6-wayland`, `qt5-wayland`, `qt6-5compat`, `qt6-svg`,
  `qt6-imageformats`, `qt6-multimedia`, `qt6-declarative`
  (+ build: `go`, `cmake`, `ninja`, `qt6-base`, `qt6-declarative`). Also pulls
  `quickshell` (the QML runtime) and `syntax-highlighting`.
- `ryoku-desktop-hyprland`: **no** `qt6-*` packages (Hyprland/portal/plugin deps).

Which the **kept surfaces** actually require:

| Qt package | Why the kept surfaces need it |
|---|---|
| `qt6-base` | QtCore/QtGui under everything |
| `qt6-declarative` | `QtQuick`, `QtQuick.Controls`, `.Effects`, `.Shapes`, `.Layouts`, `.Dialogs`, `.Window` |
| `qt6-5compat` | `Qt5Compat.GraphicalEffects` — `BrandMark.qml`/`SymbolIcon.qml` (the 力 seal, symbolic icons) |
| `qt6-svg` | every `.svg` asset: `qsbar/assets/*.svg`, `components/icons/*.svg`, `ui/art/*.svg` |
| `qt6-imageformats` | WebP/AVIF decoders (bar/launcher previews, Hub art) |
| `qt6-multimedia` | video wallpaper previews + Ryoku.Blobs `CameraFeed` |
| `qt6-wayland` | Quickshell's Wayland QPA plugin |
| `qt6-shadertools` | build-time only — bakes `.qsb` (blobs + `ui/shaders`, `qsbar/shaders`) |
| `quickshell` | the QML runtime the whole UI runs on |

---

## Install prefixes / import paths

`ryoku/shell/environment.d/ryoku-session.conf` [READ]:
- `QML_IMPORT_PATH=$HOME/.local/lib/qt6/qml`
- `QML2_IMPORT_PATH=$HOME/.local/lib/qt6/qml`
- (comment: `/usr/lib/qt6/qml` on a package install, `~/.local/lib/qt6/qml` from a
  checkout; a keybind-launched `qs -c <name>` has no other way to reach the modules.)

Dev installers:
- `ryoku/ui/install.sh` — default prefix `~/.local/lib/qt6/qml`, copies to
  `$root/Ryoku/Ui` (arg override supported).
- `ryoku/shell/quickshell/plugins/kit/install.sh` → `Ryoku/PluginKit`;
  `ryoku/shell/framebars/install.sh` → `Ryoku/FrameBars`;
  `ryoku/shell/deploy.sh:556-565` → `Ryoku/Wm/Hyprland`.

Package prefixes [READ] (`/usr/lib/qt6/qml/Ryoku/…`):
- `Ryoku.Ui` ← `ryoku-desktop/PKGBUILD:331-337`
- `Ryoku.PluginKit` ← `ryoku-desktop/PKGBUILD:324-326`
- `Ryoku.FrameBars` ← `ryoku-desktop/PKGBUILD:347-349`
- `Ryoku.Blobs` ← `ryoku-blobs/PKGBUILD` (package())
- `Ryoku.Wm.Hyprland` ← `ryoku-desktop-hyprland/PKGBUILD` (package())

---

## Necessity / exclusions

**Sizes asked for** [READ]:

| Item | Bytes | ~ |
|---|---|---|
| (a) `ryoku/shell/plugin` | **73,797** | 72.1 KiB |
| (b) `ryoku/ui` | **542,810** | 530.1 KiB |
| (c) off-disk `ryoku/assets` **referenced above** — brand icon/emblem set | **440,167** | 429.9 KiB |
| ↳ whole `ryoku/assets/brand/` | 1,591,381 | 1.52 MiB |
| ↳ `ryoku/assets/wallpapers/` (seeded content) | 245,026,989 | 233.7 MiB |
| ↳ `ryoku/assets/ryodecors/` (seeded; not kept) | 4,165,851 | 3.97 MiB |

**Necessity verdicts for the kept surfaces** [READ]/[UNVERIFIED]:

- **Keep (mandatory)**: the four `Ryoku.*` QML modules (`Ui`, `Ui.Singletons`,
  `FrameBars`, `PluginKit`, `PluginKit.Singletons`) and `Ryoku.Blobs`; the system
  fonts `ttf-material-symbols-variable`, `ttf-jetbrains-mono-nerd`,
  `otf-space-grotesk` (or `inter-font`), `noto-fonts-cjk`; the Qt packages
  `qt6-base`, `qt6-declarative`, `qt6-5compat`, `qt6-svg` + `quickshell`.
- **Conditional**: `qt6-imageformats` (only WebP/AVIF previews), `qt6-multimedia`
  (only video wallpaper + Blobs `CameraFeed`), `ttf-fraunces-variable` (titles
  degrade gracefully), `inter-font`/`noto-fonts-emoji` (fallbacks).
- **Exclude / not needed by kept surfaces**: `ttf-maple-mono-nf` (terminal offer);
  the hub `art/` set and `archivo-black.ttf` (Credits/Fastfetch/Rashin pages, not
  kept); `ryoku/assets/ryodecors` (Profile/Rashin only); the 233 MiB wallpaper
  catalog (user content, opt in by seeding a smaller set); `Ryoku.Wm.Hyprland`
  (installed but not imported by the copied surfaces).
- **Blobs is load-bearing, not optional** [UNVERIFIED]: the bar `Frame.qml`
  (`import Ryoku.Blobs`) draws the screen frame with it; dropping `ryoku-blobs`
  breaks the frame. If Blobs were dropped, `Frame.qml`/`Popout.qml` imports and
  the `CameraOverlay` must be removed too.
- **`qt6-shadertools`** is build-time only; the committed `.qsb` files ship, so a
  package install needs no shader compilation. Building Blobs locally (§plugin)
  does require it.
