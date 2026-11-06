# Tenkai wallpapers

No wallpapers are shipped in this repo. The owner's current wallpaper is a
wallhaven upload with no explicit redistribution license, and Tenkai's other
candidates are personal photos — redistributing any of them from a public
repository is not something this repo does.

## How to give a fresh install a Matugen fallback

Either drop image files into this directory (`src/tenkai-assets/wallpapers/`)
BEFORE running `./install.sh` — the installer copies them into
`~/Pictures/Wallpapers/` (the directory Tenkai's wallpaper daemon scans by
default) — or copy images there yourself after installing. To use a
different directory, set `Paths.Wallpaper` in `~/.config/tenkai/ryogami.json`.

Supported extensions: `.jpg`, `.jpeg`, `.png`, `.webp`, `.avif`.

## Or use a freely licensed default yourself

CC0 / public-domain wallpaper sources (any of these are safe to commit here):

- https://openverse.org — filter by CC0 or Public Domain Mark
- https://unsplash.com/license — free to use, though not CC0

If you add one, note its source and license in this file.
