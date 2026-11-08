# Credits and attribution

Tenkai is an **opinionated, lightweight fork of Ryoku**
(<https://github.com/Ryoku-dev/ryoku>), pinned at commit
`98a0368253d9628be72b853985878a5db90e1547` (v0.75.5-beta.20, "Onogoro").
It is a **modified derivative work**: the upstream tree is kept and reduced,
never re-implemented from scratch. Ryoku and Tenkai are distributed under the
**GNU General Public License version 3 or later (GPL-3.0-or-later)**.
The upstream licence is kept verbatim in `LICENSE`, and `NOTICE` reproduces the
notice of the pinned commit byte for byte (34 lines, sha256 `062137be…`) followed
by a clearly delimited Tenkai addendum. Verify it with
`head -34 NOTICE | sha256sum`.

Tenkai is not affiliated with, endorsed by, or connected to the Ryoku project.

## Shell / bar

The bar is derived from **QS Bar (Quickshell Rise)** by HANCORE-linux
(<https://github.com/HANCORE-linux/quickshell-dots>); the credit comment is kept
at `src/tenkai_core/shell/quickshell/shell/modules/bar/barstyles/qsbar/Scene.qml:1`.

## Frame-blob renderer

The frame-blob rendering and parts of the motion curves come from the
**Caelestia** shell (<https://github.com/caelestia-dots/shell>, GPL-3.0),
adapted by Ryoku and carried through into Tenkai. See `NOTICE`.

## Fonts

- **Space Grotesk** and **Fraunces** (roman + italic) — SIL Open Font License
  1.1, from the Google Fonts repository (`ofl/spacegrotesk`, `ofl/fraunces`).
  The fonts are committed, not fetched: `src/tenkai-assets/fonts/`, with
  `OFL.txt` beside each family. `install.sh` step 9 copies them to
  `~/.local/share/fonts/tenkai/` (user-local, no sudo).
- **Archivo Black** — OFL 1.1, at `src/tenkai_core/hub/quickshell/fonts/`.
  The licence is recorded in the font's own name table; the upstream project is
  `Omnibus-Type/ArchivoBlack`.
- **JetBrains Mono Nerd Font**, **Inter**, **Noto Sans**, **Noto Color Emoji**
  — installed as Arch packages and used under their own licences.

Eleven bundled display faces that upstream ships in the shell's asset directory
(Abberancy, Daydream, JF Flat, Overhead, Reckoner + Bold, sabana, Unrealised,
VEXA Light, VIP Rawy, Xenophobia) were **removed on 2026-11-08**: their licences
are personal-use, proprietary, or unstated, and this repository is public. Their
per-file audit — hashes, embedded licence text, verdict — is kept in
[`docs/ATTRIBUTION.md`](docs/ATTRIBUTION.md).

## Upstream assets

Assets copied from Ryoku (icons, illustrations, sounds) remain under their
original licences; see `NOTICE` and the per-file headers. Tenkai does not claim
authorship of them.

## Asset licences

Per-file licences for every font, icon set, cursor theme, sound and ported
component are listed in [`docs/ATTRIBUTION.md`](docs/ATTRIBUTION.md).

## Changes

Every modification vs upstream is recorded in `CHANGES.md`.
