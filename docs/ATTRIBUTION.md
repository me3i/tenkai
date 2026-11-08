# ATTRIBUTION.md — licences of everything Tenkai distributes

Tenkai is a modified, reduced derivative of **Ryoku**
(<https://github.com/Ryoku-dev/ryoku>), pinned at commit
`98a0368253d9628be72b853985878a5db90e1547` (v0.75.5-beta.20, "Onogoro").
Tenkai is distributed under the **GNU General Public License version 3 or
later (GPL-3.0-or-later)**.

## Verification of the two licence files at the repo root

| File | Claim | How to check |
| --- | --- | --- |
| `LICENSE` | GPL-3.0, **byte-identical to upstream** | `sha256sum LICENSE` = `3972dc9744f6499f0f9b2dbf76696f2ae7ad8af9b23dde66d6af86c9dfb36986`; upstream `LICENSE` at the pinned commit has the same hash (TESTED, 2026-11-08) |
| `NOTICE` | upstream notice **verbatim**, followed by a delimited Tenkai addendum | `head -152 NOTICE \| sha256sum` = `fa40700e93a3621ae793193a2f3ec16f21375afc85a319325ea4b95148878c24`; that is the sha256 of upstream `NOTICE` (TESTED, 2026-11-08) |

Upstream `NOTICE` is GPL-3 material; it is kept whole, including the notices for
components Tenkai later removed (Nomarchy, iNiR/Shima, Serpantinum, Stage, the
ii dock, Kit, Monkeytype assets, the Redux adapter, the Vesktop theme), so the
provenance of the upstream tree stays readable. The Tenkai addendum states which
of those components are shipped and which are not.

## Code components shipped in Tenkai

| Component | Upstream | Licence | Where in Tenkai |
| --- | --- | --- | --- |
| Frame-blob renderer (`Tenkai.Blobs`) | Caelestia shell | GPL-3.0 | `src/tenkai_core/shell/plugin/` (`blobshape.cpp`, `blobrect.cpp`, `blobgroup.cpp`, …) |
| Bar style | Quickshell Rise by HANCORE-linux | MIT | `src/tenkai_core/shell/quickshell/shell/modules/bar/barstyles/qsbar/` (122 files); credit comment kept at line 1 of `Scene.qml` |
| Wallpaper picker UI | wall-ui by liixini | MIT (Copyright (c) 2026 liixini) | `src/tenkai_core/shell/ryogami/wall-ui/`, `LICENSE` ships beside the code |
| Sound effects (5 `.oga`) | freedesktop.org sound theme | see below | `src/tenkai_core/shell/ipc/assets/` |

Sound files and their upstream credits (from `NOTICE`):
`battery-low.oga` (complete, Dr. Richard Boulanger et al, CC-BY-3.0),
`power-plug.oga` / `power-unplug.oga` (Ivica Bukvic, CC-BY-SA),
`shutter.oga` (freesound user horsthorstensen, CC-BY-SA),
`volume-change.oga` (Lucas McCallister, CC-BY-SA).

## Fonts

15 font files are distributed in the tree. Two families ship with their licence
text; the rest are inherited verbatim from upstream Ryoku's asset directory and
**their licences are not stated in either tree**.

| Font | File(s) | Licence | Status |
| --- | --- | --- | --- |
| Space Grotesk | `src/tenkai-assets/fonts/space-grotesk/SpaceGrotesk[wght].ttf` | SIL OFL 1.1 — `OFL.txt` ships beside it | TESTED (licence file present) |
| Fraunces (roman + italic) | `src/tenkai-assets/fonts/fraunces/Fraunces[SOFT,WONK,opsz,wght].ttf`, `Fraunces-Italic[…]` | SIL OFL 1.1 — `OFL.txt` ships beside it | TESTED (licence file present) |
| Archivo Black | `src/tenkai_core/hub/quickshell/fonts/archivo-black.ttf` | Published by Google Fonts as OFL 1.1, but no licence file ships in either tree | UNVERIFIED — owner decision |
| Abberancy, Daydream (demo), JF Flat, Overhead, Reckoner (+Bold), Sabana, Unrealised, Vexa Light, VIP Rawy, Xenophobia Nominal | `src/tenkai_core/shell/quickshell/shell/assets/fonts/*` (11 files, the widget display faces offered by the Hub's widget-font picker) | **Not stated anywhere in the repo or upstream** | UNVERIFIED — owner decision needed before this repo stays public |

Not distributed: JetBrains Mono Nerd Font, Inter, Noto Sans and Noto Color Emoji
are installed as Arch packages and used under their own licences.

## Icons

No icon set is bundled. The desktop is themed against **Papirus-Dark**, read
from the system (`src/tenkai-configs/hypr/modules/autostart.lua:15`,
`src/tenkai-configs/hypr/modules/env.lua:62`), and matugen tints an overlay under
`~/.local/share/icons`. Papirus is GPL-3.0 upstream; Tenkai does not
redistribute it.

## Cursor theme

`Bibata-Material-Ryoku` is referenced from
`src/tenkai-configs/hypr/modules/env.lua` and
`src/tenkai-configs/hypr/modules/autostart.lua` as an already-installed cursor
theme. It is **not** bundled: it comes from the system/packages. Bibata's
upstream project is GPL-3.0; the "Material-Ryoku" build is a recolour distributed
by Ryoku's tooling. Licence of the recolour: UNVERIFIED, not redistributed here.

## qylock

Upstream's tree used the name `qylock` for its lock-screen proof files; the
identifier survives in Tenkai at `src/tenkai_core/shell/ipc/actions.go`
(`qylock.<session>.<suffix>` proof paths, `qylockProcessMatches`). No qylock
credit text exists in upstream's README or in this tree, and no qylock code is
shipped: the identifier is only a file-name prefix. Attribution to qylock as a
design reference is UNVERIFIED — the owner should confirm the author/project URL
before this line is treated as a credit.

## Removed upstream components

Removed in Tenkai and therefore not shipped (their notices remain in `NOTICE`
for provenance): the Nomarchy bar style, the Shima/`inir` bar style and its
bundled AGPL §7 notices, the Python/Serpantinum bar style (AGPL-3.0-or-later),
the Stage Editor, the ii dock, Kit and the `keys/`+phone modules, the Monkeytype
word lists and key sounds, the Redux dictation adapter and parakeet.cpp, and the
Vesktop/Equibop `ryoku-discord` theme.

## Changes

Every substantive change is listed in `CHANGES.md`; authorship and the shorter
credit list are in `CREDITS.md`.
