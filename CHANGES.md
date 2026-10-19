# CHANGES.md — modifications vs upstream Ryoku

Pinned upstream: see `UPSTREAM.md`. Mei is built by copying and adapting upstream files into
`src/`; every modification is recorded here, newest first.

## Phase 6 — rebrand (RYOKU → MEI, user-visible only)

Scope: visible branding in kept surfaces; QML module URIs (`Ryoku.*`), D-Bus
names, env prefixes, and `ryogami` stay as-is. Attribution kept/added.

### Wordmark (bar left module)

- `src/ryoku/shell/quickshell/shell/modules/bar/barstyles/qsbar/Theme.qml`
  - `launcherLogoText` default `"ryoku"` → `"mei"`; `launcherLogoIcon` default
    `"ryoku"` → `"mei"`.
  - text options: `"ryoku"` removed, `"mei"` added first.
  - icon options: `"mei"` added; `"ryoku"` kept as a backward-compatible id.
  - icon glyph map: `"ryoku": 0x529B` (CJK 力) → `"mei"/"ryoku": 0xEE99`
    (Nerd Font "mark" seal). `launcherLogoIconFont()` now always returns the
    mono font, so **no surface needs `noto-fonts-cjk`**.
  - font/size/weight/spacing of the wordmark unchanged: `mono` (JetBrains Mono
    Nerd Font), 12 px, Bold, letter-spacing 2. `MEI` is simply the uppercase of
    the id, via the existing `launcherLogoTextLabel()`.
- `.../qsbar/modules/LauncherWidget.qml`: comment only (Mei brand mark).

### The 力 seal → plain `M`

- `.../overview/Singletons/Config.qml`, `.../desktop/Singletons/Config.qml`,
  `.../services/Config.qml`: `markText` default `"力"` → `"M"`; `name`
  `"Ryoku"` → `"Mei"`.
- `.../overview/Singletons/Theme.qml`, `.../desktop/Singletons/Theme.qml`,
  `.../services/Theme.qml`: mark fallback `"\u529b"` → `"M"`; brand-name
  fallback `"Ryoku"` → `"Mei"`.
- `.../overview/BrandMark.qml`, `.../desktop/BrandMark.qml`,
  `.../components/BrandMark.qml`: glyph font `Theme.fontJp` → `Theme.mono`.
- `.../launcher/variants/main/BrandMark.qml`, `.../launcher/variants/main/Preview.qml`:
  hard-coded `"力"` → `"M"`.
- `.../qsbar/controlcenter/CcRail.qml`: masthead `"\u529b"` → `"M"`,
  font `Tokens.jp` → `Tokens.mono`; wordmark and barcode `"RYOKU"` → `"MEI"`.
  (Route *glosses* in the same file still use CJK kanji; that is step-3 scope,
  not the wordmark/seal.)

### Other visible strings in kept surfaces

- `shell.qml`: keybind description "Toggle the Ryoku frame bar…" → "Mei".
- `.../framebars/menus/QsTabRail.qml`: tooltip "Ryoku Hub" → "Mei Settings".
- `.../qsbar/modules/UpdateWidget.qml`: "Ryoku is up to date" / "Ryoku update"
  → "Mei …" (widget is off-list but visible if enabled).
- `.../qsbar/modules/ParticleStream.qml`: update particle "RYOKU" → "MEI".
- `.../controlcenter/routes/IdentityRoute.qml`: wordmark preview `"RYOKU"` →
  `"MEI"`; icon preview `"\u529b"` → `"M"`.
- `.../controlcenter/ControlCenter.qml`: "outside Ryoku" → "outside Mei".
- `.../controlcenter/routes/CommunityRoute.qml`: "Ryoku does not review" →
  "Mei does not review".
- `.../launcher/catalog.json`: description → "Mei's live palette".
- `.../launcher/shared/providers/actions/catalog.js`: "Ryoku Settings" →
  "Mei Settings".
- `.../bar/panel/PanelChat.qml`: "the Ryoku source" → "the Mei source".

Runtime brand file `.run/config/mei/brand.json` (git-ignored) patched to
`{"markText":"M","name":"Mei"}` so the fake-home run agrees with the new
defaults; it regenerates from source anyway.

### Attribution (added, not removed)

- Copied `upstream/LICENSE` → `LICENSE` and `upstream/NOTICE` → `NOTICE`
  (verbatim; the clone itself is git-ignored, so these were not previously in
  the repository).
- Added `CREDITS.md`: Mei is a modified derivative of Ryoku under
  GPL-3.0-or-later; QS Bar (Quickshell Rise) credit; font licences.
- `UPSTREAM.md` retained; the QS Bar credit comment in
  `qsbar/Scene.qml:1` retained.

## Phase 6 step 1 — bar + workspaces (code + build + nested test)

Deliverable: `docs/06-step1.md`. Stop point: launcher/sidebar/notifications/Settings not started.

### Copied into `src/` (upstream = `98a0368`, v0.75.5-beta.20)

- `ryoku/shell/quickshell/{shell,plugins}` → `src/ryoku/shell/quickshell/{shell,plugins}`
- `ryoku/ui` → `src/ryoku/ui`; `ryoku/shell/framebars` → `src/ryoku/shell/framebars`
- `ryoku/wm` → `src/ryoku/wm`; `ryoku/shell/{ipc,plugin,matugen}` → `src/ryoku/shell/…`
- Upstream `tests/`, `qa/`, CI files stripped. Vendored Go deps kept so builds are offline.

### Source modifications

- `src/ryoku/wm/hyprland/caps.go`: removed `CapLiveConfigEval`, `CapConfigReload`,
  `CapPaletteBorder` (Mei never writes Hyprland config).
- `src/ryoku/shell/ipc/daemon.go`: `bootstrap()` reduced to `startSettings`, `startTray`,
  `startMusic`, `startNetwork`, `startNightlight`, `paintWorker`, `watchMatugenKnobs`, `startWM`,
  `startComponents`. Removed weather/updates/calendar, keypress, clipboard, polkit, session,
  power sounds, sleep/wake, auto power saver, leds/hub, ryogami, stage.
- `src/ryoku/shell/ipc/control.go`: hub lock moved from `/tmp/ryoku-hub.lock` to
  `$XDG_RUNTIME_DIR/mei-hub.lock`.
- `src/ryoku/wm/hyprland/watch.go`: if `.socket2.sock` is missing, poll `hyprctl` every 500 ms
  (`socketExists`, `pollOnce`). Only reachable in the nested test (see below); the live session
  keeps the event-driven path.
- `src/ryoku/shell/quickshell/shell/shell.qml`: `Desktop` → `active: false`,
  `widgetsEnabled: false` (desktop clock/calendar is off-list).
- `src/ryoku/shell/matugen/config.toml`: reduced to `[config]` — no templates, no post-hook, so
  matugen cannot write into the owner's home.
- Renames (source-wide): `RYOKU_*` → `MEI_*` (SHELL_DIR/PATH/POLKIT_AGENT/STATE_PATH/
  SCREENRECORD_DIR/SCREENSHOT_DIR/PLUGINS_DIR/WM), `ryoku-shell.sock` → `mei-shell.sock`,
  `ryoku-pill.sock` → `mei-pill.sock`, `ryoku-reload-cover` → `mei-reload-cover`,
  `ryoku-hub.lock` → `mei-hub.lock`, `local/share/ryoku` → `local/share/mei`,
  `ryoku-wallpaper` → `mei-wallpaper`, `ryoku-plugins-place` → `mei-plugins-place`,
  Go package `ryoku` → `mei`, provider `ryoku-wm-<name>` → `mei-wm-<name>`.
  Deliberately **not** renamed: `Ryoku.*` QML module URIs, D-Bus names, polkit paths, font
  names, `ryogami`.

### `./mei` (control script)

- New `run` / `test` / `stop`-integration: fake `HOME=.run/home`, `XDG_*=.run/{config,cache,
  state,data,rt}`, private `dbus-run-session`, nested `Hyprland -c .run/hypr/nested.conf`.
- New `stop`: signals only recorded PIDs whose `/proc/<pid>/cmdline` contains `$MEI_DIR`;
  `run` refuses to clobber a session that is still alive.
- Resource cap: `systemd-run --user --scope -p MemoryMax=3G -p CPUQuota=200%` when available
  (fallback: process group only).
- Stale runtime cleaning (`rt/hypr`, `rt/quickshell`, sockets) before each launch.
- Short symlink `.r → .run/rt` exported as `XDG_RUNTIME_DIR` for the child. Hyprland names its
  event socket `$XDG_RUNTIME_DIR/hypr/<61-char signature>/.socket2.sock`; the 107-byte UNIX
  limit was exceeded (111 bytes) and Hyprland silently disabled Socket2. `.r` makes it 106.
  All bytes still land under `.run/rt`. `.r` added to `.gitignore`.

### Build (offline, `nice -n 10`, `-p 2` / `-j2`)

- `.run/bin/mei-shell` (~15.6 MB), `.run/bin/mei-wm-hyprland` (~6.7 MB).
- Blobs plugin via cmake/ninja → `.run/build/blobs/qml/Ryoku/Blobs`.
- QML modules assembled at `.run/qml/Ryoku/{Ui,FrameBars,PluginKit,Blobs,Wm/Hyprland}`.
- Fake-home fontconfig at `.run/home/.config/fontconfig/fonts.conf` (system config + Google
  Fonts `SpaceGrotesk[wght].ttf`, `Fraunces[…].ttf` fetched from the OFL repo).

### Verification

- `./mei test` exit 0 twice; `./mei verify-untouched` **PASS** before and after.
- Bar layer surfaces mapped (`ryoku-frame`, `ryoku-frame-edge`, `quickshell`); QML log has no
  load/type errors; workspaces nested 3 / daemon topic 3 (match); pixel capture 950×1024;
  zero outbound TCP from Mei PIDs; clean shutdown, no stray processes.
- Manual multi-workspace check: 5 cells, active pill moved from cell 5 to cell 2 on a nested
  `workspace 2` dispatch.
- **UNVERIFIED**: animation smoothness/visibility (still capture only), real GPU/144 Hz,
  audio (no PipeWire socket in the fake runtime dir), tray/network content (private bus).

### Baseline

- Host rebooted at 16:29 (kernel 7.2.9 → 7.2.11). Config hashes were unchanged; the baseline
  was re-captured (`./mei baseline --force`). Hyprland 0.56.2-4 / Quickshell 0.3.2-1 / Qt 6.12.0
  unchanged, so the `.conf` verification still holds.

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
