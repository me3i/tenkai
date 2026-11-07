# Tenkai fonts

Bundled fonts (both SIL Open Font License 1.1 — see the `OFL.txt` in each
directory):

- `space-grotesk/` — Space Grotesk (variable weight), used by the bar, the
  launcher and the Settings app. Not in the official Arch repos (only in the
  third-party `tenkai` repo as `otf-space-grotesk`), so Tenkai ships it.
- `fraunces/` — Fraunces (variable, `SOFT,WONK,opsz,wght` axes, romans +
  italics), used for display/serif accents. Not packaged for Arch at all.

Upstream source: https://github.com/google/fonts (`ofl/spacegrotesk`,
`ofl/fraunces`), fetched 2026-11-05.

`./install.sh` installs these into `~/.local/share/fonts/tenkai/` (user-local,
no sudo) and refreshes the fontconfig cache.

Fonts Tenkai uses but does NOT bundle (available in the official Arch repos):

- `ttf-jetbrains-mono-nerd` — JetBrainsMono Nerd Font (mono/terminal glyphs)
- `ttf-space-mono-nerd` — SpaceMono Nerd Font
- `ttf-material-symbols-variable` — Material Symbols Rounded (icons)

install.sh prints the `pacman` line for those; it never runs sudo itself.
