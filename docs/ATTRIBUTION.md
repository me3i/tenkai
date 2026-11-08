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
| `NOTICE` | upstream notice at the **pinned commit** (34 lines), followed by a delimited Tenkai addendum | `head -34 NOTICE \| sha256sum` = `062137be76c0d594a089130445ad82495e745b67cdf677aa71be065d40635732`, which equals upstream `NOTICE` at `98a0368` (TESTED 2026-11-08; `cmp` reports the 34 lines byte-identical) |

An earlier revision of this file quoted upstream HEAD's 152-line notice instead
(`head -152 NOTICE` = `fa40700e…`). That was the wrong reference: the pin's notice
is 34 lines, and a fork must reproduce the notice of the commit it forked from.
Upstream HEAD's longer notice credits components added after the pin; the ones
Tenkai still ships are quoted inside the addendum, and the ones the reduction
removed are named there and listed at the end of this file.

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

## Font audit (2026-11-08) — blocking for a public repository

Every bundled font file was opened with fontTools and its `name` table read
(IDs 0/1/13/14), plus the OS/2 `fsType` embedding bit. Hashes are of the file as
committed. `fsType` legal values: 0 installable, 2 restricted, 4 preview & print,
8 editable.

| File | Face | sha256 (first 16) | fsType | Embedded licence text | Verdict |
| --- | --- | --- | --- | --- | --- |
| `src/tenkai-assets/fonts/space-grotesk/SpaceGrotesk[wght].ttf` | Space Grotesk | `acad6de1fc93436f` | 0 | SIL OFL 1.1 + `OFL.txt` beside it | **REDISTRIBUTABLE** (OFL-1.1) |
| `src/tenkai-assets/fonts/fraunces/Fraunces[SOFT,WONK,opsz,wght].ttf` | Fraunces | `177ff6c0f14e5550` | 0 | SIL OFL 1.1 + `OFL.txt` beside it | **REDISTRIBUTABLE** (OFL-1.1) |
| `src/tenkai-assets/fonts/fraunces/Fraunces-Italic[SOFT,WONK,opsz,wght].ttf` | Fraunces Italic | `b24448c43702fac4` | 0 | SIL OFL 1.1 + `OFL.txt` beside it | **REDISTRIBUTABLE** (OFL-1.1) |
| `src/tenkai_core/hub/quickshell/fonts/archivo-black.ttf` | Archivo Black | `9b1ac3e5da896e88` | 0 | "Copyright 2017 The Archivo Black Project Authors", licence URL `scripts.sil.org/OFL` | **REDISTRIBUTABLE** (OFL-1.1, per `Omnibus-Type/ArchivoBlack`) |
| `src/tenkai_core/shell/quickshell/shell/assets/fonts/unrealised.ttf` | Unrealised | `c74b41cd9581d745` | 0 | "Free for personal, non-profit use. Commercial use requires a license." | **PERSONAL-USE-ONLY** — PUBLIC-REPO-LEGAL-RISK |
| `src/tenkai_core/shell/quickshell/shell/assets/fonts/daydream-demo.otf` | Daydream (demo) | `7394a7524cade9f5` | 0 | "(c) 2020 by DoubleGum." File name says *demo* | **PERSONAL-USE-ONLY (demo cut)** — PUBLIC-REPO-LEGAL-RISK |
| `src/tenkai_core/shell/quickshell/shell/assets/fonts/vip-rawy-regular.otf` | VIP Rawy | `76b2ddd7c0753356` | 8 | "Typeface © (ar.photoshop.3abber.com). 2014. All Rights Reserved" | **PROPRIETARY** — PUBLIC-REPO-LEGAL-RISK |
| `src/tenkai_core/shell/quickshell/shell/assets/fonts/jf-flat-regular.otf` | JF Flat | `e59d6beae4aa7072` | 8 | "Copyright © 2014 ( Jozoor Fonts ) All Rights Reserved" | **PROPRIETARY** — PUBLIC-REPO-LEGAL-RISK |
| `src/tenkai_core/shell/quickshell/shell/assets/fonts/overhead.ttf` | Overhead BRK | `1a445fcc8937b516` | 2 | "∆NIGMA FONTS [e-mail] kentpw@norwich.net" — freeware, no terms shipped | **UNKNOWN (freeware, restricted embedding)** — risk |
| `src/tenkai_core/shell/quickshell/shell/assets/fonts/abberancy.ttf` | Abberancy | `6710865ce96c16e6` | 0 | "© 1998 Ray Larabie. This font is freeware. Read attached text file for details." — **no text file is attached** | **UNKNOWN (Larabie freeware, terms file missing)** — risk |
| `src/tenkai_core/shell/quickshell/shell/assets/fonts/xenophobia-nominal.ttf` | Xenophobia | `623e9896aa0d531e` | 2 | "©2001 Joiro Hatgaya | Freeware, but look at readme file." — **no readme shipped** | **UNKNOWN (freeware, terms file missing)** — risk |
| `src/tenkai_core/shell/quickshell/shell/assets/fonts/reckoner.ttf` | Reckoner | `4d5f5a1be2de030b` | 4 | none — no copyright, no licence | **UNKNOWN** — risk |
| `src/tenkai_core/shell/quickshell/shell/assets/fonts/reckoner-bold.ttf` | Reckoner Bold | `fdce2218319deda6` | 4 | none | **UNKNOWN** — risk |
| `src/tenkai_core/shell/quickshell/shell/assets/fonts/sabana-regular.ttf` | sabana | `2b50edc787292acd` | 4 | none | **UNKNOWN** — risk |
| `src/tenkai_core/shell/quickshell/shell/assets/fonts/vexa-light.ttf` | VEXA light R | `09eebd5d877b1cd7` | 0 | "Typeface © (your company). 2021. All Rights Reserved" — a *placeholder* copyright line, i.e. the designer never filled it in | **UNKNOWN/PROPRIETARY** — PUBLIC-REPO-LEGAL-RISK |

None of the eleven flagged files has a readme, licence or purchase receipt beside
it: `git ls-files` under `shell/assets/fonts/` returns only the font binaries.
All eleven arrive from upstream Ryoku, so this is inherited, not introduced here.

**STOPPED for the owner.** Removing or replacing these fonts is a copyright
decision, not an engineering one, so nothing was deleted. Each is referenced by
one or two QML files (a font picker list); removing them means editing that list
too. Options: (a) delete the flagged files and their list entries, (b) keep the
repository private, (c) replace them with OFL faces and keep the names as
aliases.

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
