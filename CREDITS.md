# Credits and attribution

Mei is a **modified derivative of Ryoku** (<https://github.com/Ryoku-dev/ryoku>),
pinned at commit `98a0368253d9628be72b853985878a5db90e1547`
(v0.75.5-beta.20, "Onogoro"). Ryoku and Mei are distributed under the
**GNU General Public License version 3 or later (GPL-3.0-or-later)**.
The upstream licence and notice are kept verbatim in `LICENSE` and `NOTICE`.

## Shell / bar

The bar is derived from **QS Bar (Quickshell Rise)**; the credit comment is kept
at `src/ryoku/shell/quickshell/shell/modules/bar/barstyles/qsbar/Scene.qml:1`.

## Fonts

- **Space Grotesk** and **Fraunces** — SIL Open Font License 1.1, fetched from
  the Google Fonts repository (`ofl/spacegrotesk`, `ofl/fraunces`). The OFL
  texts live next to the files in `.run/data/fonts/OFL-*.txt`; the fonts are
  fetched by setup rather than committed.
- **JetBrains Mono Nerd Font**, **Inter**, **Noto Sans**, **Noto Color Emoji**
  — installed as Arch packages and used under their own licences.

## The lock screen's clock

- **The "orbital" dial** — adapted from Ryoku's clockwork lockscreen theme
  (`ryoku/lockscreen/qylock/themes/clockwork/orbital/Main.qml` upstream; the
  theme is by Darkkal44). The theme is part of Ryoku and is under the same
  **GPL-3.0-or-later** licence as the rest of it; the adapted clock lives in
  `src/ryoku/shell/quickshell/shell/modules/lock/OrbitalClock.qml` and keeps
  the attribution in its header.
- **The Outfit font** that the theme bundles is **not** bundled here: the
  upstream tree ships it without a licence file, and an asset without a licence
  is not redistributed. The clock uses the system's own font instead, so the
  shapes differ slightly from the greeter's. (Outfit itself is published under
  the SIL Open Font License 1.1 by Google Fonts.)

## Upstream assets

Assets copied from Ryoku (icons, illustrations, sounds) remain under their
original licences; see `NOTICE` and the per-file headers. Mei does not claim
authorship of them.

## Changes

Every modification vs upstream is recorded in `CHANGES.md`.
