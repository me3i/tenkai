# Icons and symbols

## What was broken

`MaterialIcon.qml` uses `font.family: "Material Symbols Rounded"` and renders
ligature names such as `bolt` and `battery_full`. The font is shipped by
`ttf-material-symbols-variable` and was not installed, so `fc-match` fell back
to FreeSans and every Material icon rendered as a blank box.

## Fix

1. Installed `MaterialSymbolsRounded.ttf` **user-locally** (no sudo) at
   `~/.local/share/fonts/MaterialSymbols/MaterialSymbolsRounded.ttf` and ran
   `fc-cache`. This is a user-level install, not a bundle; nothing was added to
   the repo, so `docs/ATTRIBUTION.md` needed no new entry.
2. The *nested* shell does not use the owner's fontconfig: `./tenkai` sets
   `HOME=$RUN/home`, `XDG_DATA_HOME=$RUN/data` and
   `FONTCONFIG_FILE=$RUN/home/.config/fontconfig/fonts.conf`. That file (and its
   `<dir>$RUN/data/fonts</dir>`) existed only in the `./tenkai run` provisioning
   path; the manual live session had neither, producing the Fontconfig errors
   and still resolving FreeSans.
3. `./tenkai` now creates `.run/data/fonts` and symlinks the font from
   `/usr/share/fonts` or `$HOME/.local/share/fonts` when present. The live
   session's fontconfig file was created and the font linked into
   `.run/data/fonts`.

## Verification

Inside the running shell's own environment:

```
HOME=.run/home XDG_DATA_HOME=.run/data FONTCONFIG_FILE=.run/home/.config/fontconfig/fonts.conf \
  fc-match "Material Symbols Rounded"
-> MaterialSymbolsRounded.ttf: "Material Symbols Rounded" "Regular"
```

`tests/run-all.sh` now reads HOME/XDG_DATA_HOME/FONTCONFIG_FILE from
`/proc/<shell-pid>/environ` and fails if the match is not Material Symbols — the
earlier version accidentally asked the caller's environment and passed while the
shell still had FreeSans.

Current shell starts: zero `Fontconfig error` lines.

## Referenced icon packs removed from the tree

A grep for the removed packs (`Unrealised`, `Daydream`, `VIP Rawy`, `JF Flat`,
`Abberance`, `Xenophobia`, `Reckoner`, `sabana`, `VEXA`) over QML/JS/Lua finds
no live reference (the suite enforces this). No missing glyph name remains from
those packs.

## Limitation

Glyph-level rendering is not screenshot-tested (no Chrome/browser and no
compositor screenshot in this pass). Resolution is verified by fontconfig inside
the shell's environment, which is the mechanism that was failing.
