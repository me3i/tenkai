# Credits and attribution

Tenkai is an **opinionated, lightweight fork of Ryoku**
(<https://github.com/Ryoku-dev/ryoku>), pinned at commit
`98a0368253d9628be72b853985878a5db90e1547` (v0.75.5-beta.20, "Onogoro").
It is a **modified derivative work**: the upstream tree is kept and reduced,
never re-implemented from scratch. Ryoku and Tenkai are distributed under the
**GNU General Public License version 3 or later (GPL-3.0-or-later)**.
The upstream licence and notice are kept verbatim in `LICENSE` and `NOTICE`.

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

- **Space Grotesk** and **Fraunces** — SIL Open Font License 1.1, fetched from
  the Google Fonts repository (`ofl/spacegrotesk`, `ofl/fraunces`). The OFL
  texts live next to the files in `.run/data/fonts/OFL-*.txt`; the fonts are
  fetched by setup rather than committed.
- **JetBrains Mono Nerd Font**, **Inter**, **Noto Sans**, **Noto Color Emoji**
  — installed as Arch packages and used under their own licences.

## Upstream assets

Assets copied from Ryoku (icons, illustrations, sounds) remain under their
original licences; see `NOTICE` and the per-file headers. Tenkai does not claim
authorship of them.

## Changes

Every modification vs upstream is recorded in `CHANGES.md`.
