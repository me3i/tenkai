# DECISIONS.md — deliberate behavioural choices, with the evidence

Each entry records what was turned off, when, by which commit, and how to get it
back. Nothing here is an accident or rebrand damage.

## 1. The matugen app-suite fan-out is OFF (kept off)

**Decision: off, deliberately.** Introducing commit `309246d` — "step 5:
wallpaper + matugen theming (stills only, guarded, no fan-out)", 2026-10-20 —
an ancestor of `main`. Its own body says plainly: "matugen: config is [config] +
empty [templates] … App fan-out off (apps.toml, blankGtk, cursor recolor,
gsettings/kitty/KDE)."

Where: `src/tenkai_core/shell/ipc/matugen.go`

| Block | Line | What upstream did | What Tenkai does |
| --- | --- | --- | --- |
| app suite | ~1167 `// TENKAI: the app-suite fan-out is OFF` | rendered `apps.toml` (22 templates: kitty, btop, qt6ct, gtk3/4, vesktop, obsidian, …) and blanked the GTK sheets when "Theme apps" was off | renders `config.toml` only; no app config outside the project is written; no `post_hook` |
| toolkit reload | ~1282 `// TENKAI: the toolkit fan-out is OFF` | `gsettings` color-scheme + GNOME accent, KDE colour files, `gtk-theme` flip | `nudgePalette()` only — the in-shell repaint |

Why it stays off: it is the same boundary the project states as a rule — Tenkai
never writes an app's or the session's config (`~/.config/kitty`, `gtk-3.0`,
`gtk-4.0`, `qt6ct`, `btop` are only *watched* by `verify-untouched`, never
written). Re-enabling would also write outside the project, which the safety
contract forbids.

**To opt back in:** uncomment the block at `matugen.go:1172-1177` and restore
`apps.toml` into the matugen config home — that template file is **not** in this
tree any more (`find src -name apps.toml` returns nothing), so it has to be
taken from upstream at the pinned commit, and `ThemeTenkaiApps` /
`themeAppsEnabled()` must be live again. Until then the settings for them are
inert, which is intended.

## 2. Settings never writes Hyprland config

Disabled in the hub backend: the Settings app persists to Tenkai's own config
dir and reads Hyprland state only. `docs/` and `CHANGES.md` record the same
choice; it is listed here because it is a boundary, not a bug.

## 3. The two standard D-Bus names are still claimed

Pending, not decided: see `docs/DBUS.md`. It is deliberately left out of this
file until you choose an option.
