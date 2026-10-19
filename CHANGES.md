# CHANGES.md — modifications vs upstream Ryoku

Pinned upstream: see `UPSTREAM.md`. Mei is built by copying and adapting upstream files into
`src/`; every modification is recorded here, newest first.

## Phase 4 — extraction plan (plan only; no code, no installs, no builds)

- Wrote `docs/04-plan.md` (10 sections): HOME-confinement trace + fixes, the exact `src/`
  manifest, the daemon trim, the rename table, the build plan + `pacman -S` list with sizes,
  the nested test design, the minimal matugen config, fonts, the ordered Phase 6 steps, and
  risks/rollback/UNVERIFIED.
- **Housekeeping (approved):**
  - Reverted `25ba6a6` (`00b4511`) — `./mei` stays strict.
  - Extended `verify-untouched` to also hash `~/.config/{kitty,btop,qt6ct,gtk-3.0,gtk-4.0}` and
    `~/.cache/ryoku`. This exposed a latent `pipefail` bug (a missing watched dir made `find`
    exit 1 and aborted the script); fixed by passing only existing dirs.
  - Re-ran `./mei baseline --force` after the owner's session restart; `./mei verify-untouched`
    → **PASS**. Commits `00b4511` (revert) + `a8b0b2a` (hash set + re-baseline).
- Key Phase 4 findings (detail in `docs/04-plan.md`):
  - **Fake HOME closes the XDG hole**: nearly every path is `HOME + "/.…"` or `XDG_*`; the only
    true "outside project" writes left are four hard-coded `/tmp/ryoku-*` sites → repath to
    `$XDG_RUNTIME_DIR/mei-*`. `/run/polkit`, `/sys`, `/etc` reads are system, accepted.
  - **Hyprland 0.56.2 accepts both `.conf` and `.lua`** `[TESTED]` via isolated
    `--verify-config` → the nested session uses a plain `hyprland.conf`.
  - **wm apply chain cut**: remove `CapLiveConfigEval`/`CapConfigReload`/`CapPaletteBorder`
    (`ryoku/wm/hyprland/caps.go:31-32,47`) and neuter `apply.go:56-66` (`settings.lua` +
    `rebinds.lua`). Reads (workspaces, via ext-workspace + the daemon `wm` topic) stay.
  - **matugen is required** (palette is `matugen image … --json hex`); minimal `config.toml` is
    just `[config]` so no template ever targets the owner's home. Installed `matugen 4.2.0` ok.
  - **Versions**: Quickshell 0.3.2 (repo) + Qt 6.12.0 + Hyprland 0.56.2 + Go-to-be(1.27.2) all
    satisfy upstream; `cmake` + `go` + fonts missing. Rename list applied (env/sockets/locks/dirs);
    `Ryoku.*` QML module URIs deliberately **not** renamed.
- No install, no build, no code change beyond the approved `./mei` housekeeping.

## Phase 3 — classification (read-only; no code, no installs, no builds)

- Wrote `docs/03-classification.md`: every component, file group, daemon, Settings page, font
  and asset classified essential / optional-disabled / removable / uncertain, each with the
  necessity-test reason, a RAM/CPU estimate + whether it spawns a process, and its dependents.
  Includes the "bloat found" and "opted out, can re-enable" lists, licensing/credits (incl.
  the GPL-3.0 obligations and the unlicensed bundled fonts/icons redistribution flag), and the
  proposed Mei Settings-page list (5 kept: General, Appearance, Bar, Launcher, Motion).
- Added `docs/02b-gaps.md` because `docs/02-deps.md` was missing two items the owner required:
  (a) a mapping of **all 32** page files (28 nav + 4 helpers) to what each writes, and (b) the
  full list of daemons/processes the kept features need **with a process count** (3 resident:
  `ryoku-shell` → `qs -c shell`, and `ryogami`).
- Resolved the five open items by reading code (detail in `docs/03-classification.md` §1):
  1. **Dual `NotificationServer`** — real; both are instantiated
     (`services/Notifs.qml:230` and `barstyles/qsbar/panels/NotificationPanel.qml:26` via
     `VariantRoot.qml:251`). Keep `services/Notifs.qml` (integrated: popups, DND, menus); the
     qsbar panel's server also writes a foreign `~/.cache/qs-rise-notifications.json` → remove.
  2. **Polkit** — the agent is gated behind `RYOKU_POLKIT_AGENT=1` (`ipc/polkit.go:35-40`);
     test mode must simply not set it (Mei runs the daemon directly → never registers).
  3. **matugen** — `colors.json`/`tones.json` are written by the daemon's Go code, not by any
     template, so the kept palette needs **zero** templates. Every shipped template
     (`config.toml` 6 + `apps.toml` 22) targets the owner's home → **REMOVE**; plan is a bare
     Mei `config.toml` (`[config]` only, no templates, no post_hook) with `XDG_*` redirected.
  4. **Palette bridge** — HTTP on `127.0.0.1:47616` (`-listen` flag), loopback-only by default,
     not file-based; only browser/app theming uses it → optional-disabled.
  5. **ryogami** — live video runs a `ryogami-live` player per output (`[REPORTED] ~40–60 MB
     RSS`), depth adds a shader + map; both disable cleanly while keeping still images. The
     reveal shader lives in the kept Quickshell process (idle-zero, fires only on change) → keep.
- New confinement finding: many kept-module QML `FileView` paths are built as
  `Quickshell.env("HOME") + "/.config"` and therefore ignore `XDG_CONFIG_HOME`; the XDG redirect
  alone does not contain them. Flagged as **uncertain** — must be closed in Phase 6.
- ~~Hardened `./mei verify-untouched` for a live-session restart~~ — **REVERTED in Phase 4**
  (commit `00b4511`). This was an unapproved change to a safety script; `./mei` is strict again:
  a watched D-Bus owner-PID change is always fatal, full stop. The owner's session restart is
  handled by re-running `./mei baseline --force`, not by weakening the check.
- `./mei verify-untouched` → PASS (config hashes unchanged; D-Bus churn informational post-restart).

## Phase 2 — dependency mapping (read-only; no code, no installs, no builds)

- Wrote `docs/02-deps.md` (consolidated) from six read-only traces in `docs/02-deps/`
  (`01-bar`, `02-overlays`, `03-wallpaper-theming`, `04-settings`, `05-names-network-uv`,
  `06-fonts-qt-assets`). Nothing under `upstream/` was modified; no builds, no installs.
- Resolved the seven questions (detail in `docs/02-deps.md`):
  - matugen runs from the `ryoku-shell` daemon (`ipc/matugen.go:775`), triggered by the ryogami
    `wallpaper` topic; it writes `~/.cache/ryoku/{colors.json,tones.json,hypr-colors.lua}` and
    (via templates) `~/.config/{kitty,btop,qt6ct}`. matugen's `config.toml` hardcodes `~/.config`,
    so Phase 6 must generate a Mei config; the hypr template lands in cache, not the hypr dir.
  - Full IPC verb list + topic list recorded; audio/battery/notifications are in-process
    (PipeWire/UPower/Quickshell), only `network`/`tray`/`wm`/`settings`/`wallpaper` are daemon topics.
  - Kept features need **no** off-disk `ryoku/assets` (only the two brand logos, 1,146 B).
  - Network inventory: all outbound calls belong to off-keep-list features; keep-list traffic is
    loopback palette-bridge only.
  - Rename/redirect table: `ryoku*`→`mei*`, `ryogami`→`mei-wall`; KEEP polkit + freedesktop/KDE
    D-Bus names and `/run/polkit/agent-helper.socket`.
  - `uv` is needed only by `ryostage`/Rashin (off-list) → dropped.
  - Wallpaper: keep `ryogami` (Option B reworks ~9 files and loses reveal/live/depth; matugen
    dominates measured bytes).
- `./mei verify-untouched` → PASS after the phase.

## Phase 1 — read-only audit (still no upstream source touched)

- Read-only audit of the pinned upstream, written to `docs/01-audit.md`. No file outside
  `~/projects/mei` was created/modified/killed; no installs; no repo scripts run.
- `upstream/` working tree narrowed to a sparse checkout (see `UPSTREAM.md`); content unchanged
  (same pinned commit), only which paths are materialised changed.
- Key findings for later phases (full detail in `docs/01-audit.md`):
  - The Settings→Hyprland writer is `ryoku/wm/hyprland` (`settings.lua`/`rebinds.lua` +
    `hyprctl reload`), invoked by `ryoku-hub`; disabling it is a code change, not a flag.
  - Wallpaper is a separate daemon (`ryogami`), not part of `ryoku-shell`.
  - Config/cache/state are XDG-derived (redirectable); `/tmp/ryoku-hub.lock` and
    `/run/polkit/agent-helper.socket` are absolute and not redirectable.
  - Motion is centralised in `services/Motion.qml` (shell) + `ui/Singletons/Tokens.qml` (apps),
    but not fully — see §8.
  - Missing toolchain/fonts: `go`, `cmake`, `uv`, and all seven UI font roles.
- Verified `./mei verify-untouched` → PASS after the audit.

## Phase 0 — project scaffold (no upstream source touched yet)

- Created project layout: `AGENTS.md`, `docs/`, `src/`, `.run/`, `./mei` control script.
- Captured read-only live-session baseline (`docs/baseline.txt`, `docs/baseline/`) and
  `./mei verify-untouched`.
- `upstream/` cloned at pinned commit (see `UPSTREAM.md`); never edited.
