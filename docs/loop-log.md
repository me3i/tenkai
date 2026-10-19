# Phase 6 loop log

Bounded self-correcting loop. Each iteration: implement from upstream → `./mei verify-untouched` →
`./mei test` (nested only) → acceptance check → upstream diff → commit. A hard stop ends the loop
immediately (see `AGENTS.md` and the owner's loop rule).

Legend: **TESTED** = observed in this run with evidence; **FAIL** = observed failure;
**UNVERIFIED** = cannot be tested by the agent (motion feel, GPU/144 Hz, subjective look).

---

## Rebrand — iteration 1 (2026-10-19 16:55)

**Change set:** `CHANGES.md` → "Phase 6 — rebrand". Wordmark default `ryoku` → `mei` (renders
`MEI`); 力 seal → plain `M`; visible strings in kept surfaces → Mei; attribution added
(`LICENSE`, `NOTICE`, `CREDITS.md`).

### Acceptance

| Item | Result | Evidence |
|---|---|---|
| Bar wordmark shows **MEI** | **TESTED** | `.run/shots/rebrand-bar.png` (crop of `.run/shots/test-bar.png`), run log `.run/logs/rebrand-iter1.log` |
| Same font / size / weight / spacing as upstream | **TESTED** | `LauncherWidget.qml` diff vs upstream is a **comment only**; render props unchanged (`mono`, 12 px, Bold, letter-spacing 2) — `docs/loop-log.md` (this entry) |
| No stray visible "Ryoku"/"RYOKU" in kept surfaces | **TESTED** | grep for `I18n.tr/text/title/tipText/description/placeholderText/label` over `src/ryoku/shell/quickshell/shell` + `src/ryoku/ui` → **0 hits** |
| No CJK font required by the wordmark/seal | **TESTED** | hard-coded 力 / `\u529b` grep outside comments → **0**; icon fallback is Nerd Font `0xEE99`; `launcherLogoIconFont()` → `mono` |
| Attribution intact | **TESTED** | `LICENSE` (674 lines), `NOTICE` (34), `UPSTREAM.md`, `CREDITS.md` (GPL-3.0-or-later + QS Bar credit); `Scene.qml:1` credit comment present |
| Renders with no QML load errors | **TESTED** | run log: "shell QML log has no errors" |
| No stray processes after `./mei stop` | **TESTED** | run log: "clean shutdown: no stray Mei processes"; `pgrep` → none |
| Zero outbound connections | **TESTED** | run log: "zero outbound connections from Mei PIDs" |
| Real config hashes unchanged | **TESTED** | `verify-untouched: PASS` before edits and after the run |
| Every change logged in `CHANGES.md` | **TESTED** | rebrand section, file-by-file |
| Visuals diffed against upstream | **TESTED** | `diff -u upstream/…/LauncherWidget.qml src/…/LauncherWidget.qml` → one comment line; `Theme.qml` diff → only logo ids/options/glyph map/font, plus the pre-existing path renames |
| Animation feel | **UNVERIFIED** | still capture only; owner must run `./mei run` and watch the pill |
| 144 Hz / GPU behaviour | **UNVERIFIED** | nested test cannot prove it |

### Notes / scope boundaries

- The control-center route **glosses** (`CcRail.qml:98`) still use CJK kanji. They are decorative
  route labels, not the wordmark/seal; replacing them belongs to the control-sidebar step. The logo
  seal in the same file is now `M` + `Tokens.mono`.
- `"ryoku"` remains as a backward-compatible **icon id** (renders the same Nerd Font mark, no CJK).
  It is not a visible string.
- Non-qsbar bar styles (nacre/dock) are off-list; their defaults also read the shared `brand.json`
  (`name: "Mei"`, `markText: "M"`), so they inherit the rebrand if enabled.

### Verdict

Every testable item passed. Run once → **clean**. Second clean run required before exiting the loop.

---

## Rebrand — iteration 2 (2026-10-19 16:57)

No code change (confirmation run). Second consecutive clean pass.

| Item | Result | Evidence |
|---|---|---|
| `verify-untouched` before | **TESTED** | PASS |
| Bar renders, wordmark **MEI** | **TESTED** | `.run/shots/rebrand-bar-iter2.png` (crop of the new `.run/shots/test-bar.png`, 16:57) |
| QML load errors | **TESTED** | none (`rebrand-iter2.log`) |
| Workspaces vs nested compositor | **TESTED** | 1 / 1 (match) |
| Zero outbound connections | **TESTED** | run log |
| Clean shutdown / no stray processes | **TESTED** | run log + `pgrep` → none |
| `verify-untouched` after | **TESTED** | PASS |
| Animation feel / 144 Hz / GPU | **UNVERIFIED** | owner |

### Verdict

**Two consecutive clean runs.** Loop exited. Rebrand is done; stopping for owner review before
the launcher (step 2). The owner should run `./mei run`, press `SUPER+1/2/3`, watch the pill, and
confirm the wordmark/spacing reads right in person.

---

## Phase 6 step 2 — Launcher (2 clean runs, 2026-10-19 20:24–20:25)

**Change set:** `CHANGES.md` → "Phase 6 — step 2: launcher". Catalog → `main` only; providers →
`Apps` + local `Actions`; web/radio/weather/packages/script/snippets/find/calc/media/recent/
windows disabled; RASHIN panel disabled; real read-only `XDG_DATA_DIRS`; nested
`SUPER+SPACE → global ryoku:launcher`.

### Harness failures before the clean runs (launcher code unchanged)

| Attempt | Result | Cause | Log |
|---|---|---|---|
| 1 | **FAIL (harness)** | the check script resolved the nested instance signature before the compositor wrote it, so `hyprctl -j layers` fed non-JSON to `jq` | `launcher-iter1-harness-fail.log` |
| 2 | **FAIL (harness)** | it dispatched the shortcut before Quickshell registered `CustomShortcut` (the `qs` process exists earlier) | `launcher-iter1-harness-fail2.log` |
| 3 | **PASS** | — | `launcher-iter1.log` |
| 4 | **PASS** (confirmation) | — | `launcher-iter2.log` |

No launcher source changed between attempt 2 and the passes; both failures were marked **FAIL**
and recorded, never relabelled.

### Acceptance

| Item | Result | Evidence |
|---|---|---|
| Opens on the bound key | **TESTED** | nested `bind = SUPER, SPACE, global, ryoku:launcher`; `hyprctl dispatch global ryoku:launcher` → 1 `launcher` layer (the same `ShellState.launcherOpen` transition the shortcut drives) |
| Lists real installed apps | **TESTED** | query `kitty` → `kitty` (Terminal emulator, `/usr/share/applications/kitty.desktop`); `.run/shots/launcher-202511-search.png` |
| Lists owner-only apps | **TESTED** | query `sklauncher` → `SKLauncher` from `~/.local/share/applications` via the new read-only `XDG_DATA_DIRS`; `.run/shots/launcher-userdesktop.png` (searched only, not launched) |
| Launch works, nested only | **TESTED** | Enter → kitty in nested clients; `/proc/<pid>/environ`: `HOME=.run/home`, `XDG_RUNTIME_DIR=.r`, `WAYLAND_DISPLAY=wayland-1`; `.run/shots/launcher-202516-launched.png` |
| Frecency/state under fake HOME | **TESTED** | `.run/state/mei/launcher-usage.json` = `{"kitty":1}` after a from-scratch delete; `.run/config/mei/launcher.json` (`variant: main`, `showWeather: false`) |
| Esc closes | **TESTED** | `launcher` layers 1 → 0 |
| One launcher instance | **TESTED** | `pgrep -fc 'qs -p …/quickshell/shell'` = 1; one `launcher` layer |
| Bar unaffected | **TESTED** | `.run/shots/launcher-202519-bar.png`; `./mei test` bar-layer + QML-log checks |
| Zero network | **TESTED** | shell owns no tcp/udp sockets (`ss -tunp`); web/weather/radio providers never instantiated; no `ryoku-cmd-radio` probe in the log |
| Step-1 regression | **TESTED** | `./mei test`: bar renders, workspaces 1/1, zero outbound, clean shutdown (`launcher-regression-step1.log`) |
| `verify-untouched` | **TESTED** | PASS before and after both runs, and after `./mei test` |
| Animation feel / 144 Hz / GPU | **UNVERIFIED** | owner |

### Notes / scope boundaries

- `Actions` is kept only because `variants/main/Launcher.qml` binds `providerSet.actions`. Its
  catalog is local; the `ryoku-shell`/`ryoku-cmd-*` helpers it names are unbuilt, so those
  commands fail harmlessly if invoked. It is the `/` command mode.
- The media card reads MPRIS only; the nested private bus has no player, so remote `artUrl`
  artwork (a potential outbound fetch) is not exercised. Marked **UNVERIFIED** for the live case.
- Radio streaming, web search, weather and the RASHIN panel are disabled but still on disk
  (unreachable). Physical prune is a later pass.
- `docs/loop-log.md` review (owner request): the rebrand section has **no repeated reverts** and
  **no FAIL quietly reworded to UNVERIFIED**; the launcher harness failures above are kept as
  FAIL with their logs.

### Verdict

**Two consecutive clean runs.** Loop exited. Stopping for owner review before the control
sidebar (step 3). The owner should `./mei run`, press `SUPER+SPACE`, type a query, launch a
harmless app, press Esc, and judge the motion by feel.

---

## Launcher amendment — "/" command mode + Actions off (owner decision, 2 clean runs, 20:32–20:33)

**Change set:** `CHANGES.md` → step-2 section. `Providers.qml` is `Apps` only; `actionMode`
pinned false and its category `Binding` commented out in `variants/main/Launcher.qml`;
`SearchRow.qml` hint → "Search apps". Provider files stay on disk (disabled, not deleted).

| Item | Result | Evidence |
|---|---|---|
| App search still works after the change | **TESTED** | two clean runs `.run/logs/launcher-actions-off-iter{1,2}.log` (open, search, launch kitty, fake-HOME state, Esc) |
| `/` no longer enters a command mode | **TESTED** | typing `/` shows "No matches", no ACTIONS chip, no category tabs; `.run/shots/launcher-203307-slash.png` |
| No `providerSet.actions` QML error | **TESTED** | shell log clean in both runs |
| `verify-untouched` | **TESTED** | PASS before and after both runs |
| Animation feel | **UNVERIFIED** | owner |

### Verdict

**Two consecutive clean runs.** Amendment done; stopping for owner review before step 3.

---

## Phase 6 step 3 — Control sidebar / quick settings (2026-10-19 20:34–21:23)

**Change set:** `CHANGES.md` → "Phase 6 — step 3". Two empty states (`Audio.sink` null) and the
read-only network tile are the visible result of the owner rules (read-only network; audio held
UNVERIFIED).

| Acceptance item | Result | Evidence |
|---|---|---|
| Sidebar opens and closes on `ryoku:quicksettings` | **TESTED** | dispatched on the nested instance; `SUPER+ESCAPE` bound in the nested conf; `.run/shots/qs-212253-open.png`, `qs-212255-closed.png` |
| Keep-list sections only | **TESTED** | panel shows clock/date, battery 72%, audio out+in, brightness 23%, read-only Wi-Fi tile; no Connect grid, media, calendar, system, power, surface switch — `.run/shots/qs-bigmon.png` |
| Network is read-only | **TESTED** | Wi-Fi tile has no `onToggled`/`hasPage` (code); nothing toggles Wi-Fi/BT; `QuickSettingsHome.qml` |
| Power actions stubbed in test mode | **TESTED** | `SessionActions.testMode` (MEI_TEST) + `session.go testStubbed()`; every reachable power path routed through it (`QuickSettingsHome`, `MenuQuickActions`, `Frame.qml`); the confirmed-dialog path already used `SessionActions.run` |
| Audio | **UNVERIFIED (expected)** | no PipeWire socket in nested `.r`; shell holds no PipeWire/Pulse socket (`ss -xp`); `Audio.sink` null → sliders blank. Real alternative (`/run/user/1000/pipewire-0`) **not** linked |
| Brightness step + restore | **TESTED** (control path) | real backlight 23%→28%→restored to `22080` (max `96000`) via the shell's exact command, in an `EXIT` trap; live % shown in the panel. Slider drag not keyboard-driven |
| Kanji → English (route labels / seals) | **TESTED** | control centre shows BAR/SEAL/LAYOUT/PARTS/DOCK/PEERS and POSITION/MOTION/FORM seals, no tofu — `.run/shots/qs-212258-controlcenter.png` |
| Zero outbound | **TESTED** | `ss -tunp`: shell owns no tcp/udp sockets |
| Exactly one shell instance | **TESTED** | `pgrep` count 1 in every iteration |
| No dead rail helpers spawned | **TESTED** | `ryoku-cmd-google-lens|ocr|qr-scan|color-picker` never spawned |
| No QML errors | **TESTED** | shell log clean (`is not a type`, `Failed to load`, … absent) |
| `verify-untouched` | **TESTED** | PASS before and after every iteration |
| Animation feel / audio control | **UNVERIFIED** | owner |

### Notes / scope boundaries

- Iteration 1 passed functionally but the nested output (950×508 — the host's window size) was
  too short for the whole panel, so the audio/brightness section sat below the fold. The test
  harness now enlarges the nested output via `hyprctl keyword monitor` (targets the **nested**
  instance only); iter3/iter4 captured the full panel. An attempt to force the size at startup
  with a `monitor =` line was ignored by nested Hyprland and removed.
- The `[pipewire] connected` line in `session.log` is Quickshell's own log; `ss -xp` shows no
  PipeWire/Pulse socket on the shell and `.r` has none, so the nested shell cannot reach real
  audio.
- Disabled but on disk (opt back in by uncommenting): quick-settings modules notifications /
  weather / capture / media / stage; Connect tiles Bluetooth / Airplane / Night light / Keep
  awake / DND / Gaming; media hero, calendar, system monitor, power profiles; rail Lens / OCR /
  QR / colour-picker. The control centre's own `QS BAR SETTINGS | QUICK SETTINGS` switch is
  untouched (it is not the Super+Esc sidebar's control).
- `MenuQuickActions` is not reachable by default (no bar widget requests the `quick-actions`
  menu); its power actions were still routed through the stub.

### Verdict

**Two consecutive clean runs (iter3, iter4).** Loop exited. Stopping for owner review before the
Settings app (step 4). The owner should `./mei run`, press `SUPER+ESCAPE`, judge the motion and
the brightness fader by feel, and press the bar logo to see the control centre's English labels.

---

## Phase 6 step 4 — Settings app (`mei-hub`) (2026-10-20 01:47–02:00)

**Change set:** `CHANGES.md` → "Phase 6 — step 4". Harness `.run/tools/step4.sh` (git-ignored).
One clean run: `.run/logs/step4-015917.log`. Earlier runs in this step were harness failures
(.run/logs/step4-012437.log, step4-014714.log) and are kept as **FAIL** — see the loop notes.

| Acceptance item | Result | Evidence |
|---|---|---|
| Opens from the quick-settings rail | **TESTED** | rail button runs `mei-shell hub open` (`QsTabRail.qml`); same command opened pid 98096 — `.run/shots/step4-hub-open.png` |
| Exactly the 5 pages | **TESTED** | active `groups` = global/desktop/bar-studio/launcher/animations; all five opened (`nav section` = key) and rendered (std 0.094–0.113) — `.run/shots/step4-hub-page-*.png` |
| Disabled pages cannot open | **TESTED** | `hub open displays` / `windowmanager` refused; section stayed `animations` |
| English labels, no kanji | **TESTED** | rail General/Appearance/Bar/Launcher/Motion; `力`→`M`, `jpName` map emptied — screenshots above |
| Motion edits live animation values | **TESTED** (data path) | UI toggle set `theme.motion.reduce=true` in `shell.json`; `Tokens.qml` `dur()`/`reduceMotion` read it |
| Motion persists across restart | **TESTED** | `./mei stop` + `./mei run`, value still `{"reduce":true,"scale":1}` — `.run/shots/step4-hub-motion-restart-stuck.png` |
| Reset restores the default | **TESTED** | RESET TO DEFAULTS → `{"reduce":false,"scale":1}` — `.run/shots/step4-hub-motion-after-reset.png` |
| No Hyprland write | **TESTED** | no `settings.lua`/`rebinds.lua`/`user_edits` anywhere in the fake HOME; real `~/.config/hypr` hash `4a9daa50…68afe` unchanged before/after |
| Persists only to Mei config | **TESTED** | everything written sits in `$XDG_CONFIG_HOME/mei`: brand/hub/launcher/shell/theme/visualizer/stage/stash/widgets |
| No `hyprctl` from Settings | **TESTED** | no `hyprctl` process during the run |
| Zero outbound | **TESTED** (hub) | `ss -tunp`: hub owns no tcp/udp sockets. The two Settings-side network seams found in review (RyoStore catalogue, open-meteo geocode) are now disabled in code |
| Hub lock under `$XDG_RUNTIME_DIR` | **TESTED** | `$XDG_RUNTIME_DIR/mei-hub.lock` present |
| Clean exit | **TESTED** | `hub close` → no hub process; `./mei stop` → no stray Mei process |
| Audio reaches the real sink (owner-approved probe) | **TESTED** (value path) | symlink only `pipewire-0`; real sink 1.00 → 0.95 → restored 1.00; symlink unlinked — `.run/shots/step4-audio-qspanel-{readonly,changed}.png` |
| No QML errors | **TESTED** | shell log clean (portal/pipewire noise excluded); `qmllint` clean on the edited hub files |
| `verify-untouched` | **TESTED** | PASS before and after |
| Animation feel / slider drag gestures / 144 Hz / GPU | **UNVERIFIED** | owner — the Motion toggle and the audio *value* were driven, but a slider **drag** and the perceived timing are not keyboard-provable here |

### Exclusions (disabled, not deleted — opt back in at the marked block)

- Hub: Profile, Updates, Displays, Connections, Input, Graphics & Power, Lockscreen, Window
  Manager, Plugins, Layer Rules, Keybinds, App Overrides, Window Rules, Performance, Session,
  Recording, Dictation, Fastfetch, Import, Add-ons, Rashin, Credits, Widgets.
- Bar page: **BAR STYLE** card (RyoStore-fed). Desktop page: Clipboard tab, boot `reloadCover`
  row. Motion page: Hyprland window-animation editor, Focus Flash, animation presets.
- Settings-side network: RyoStore catalogue/install and the open-meteo city geocode.

### Notes / scope boundaries

- **Earlier FAILs in this step, kept as FAIL:** run 1 (`.run/logs/step4-012437.log`) opened the
  hub with the long `.run/rt` runtime path, which breaks Hyprland's `.socket.sock` and sent
  `mei-shell` to the host socket, so the hub never opened; run 2 (`.run/logs/step4-014714.log`)
  used `qs ipc --pid` for the page check (wrong instance handle) and a log filter that caught an
  `xdg-desktop-portal` line. Both were harness bugs, not product regressions; the harness now
  uses `.r`, reads the hub's own `hub.toml` section, and excludes portal/pipewire noise. No FAIL
  was reworded to UNVERIFIED.
- Step 3's `Audio = UNVERIFIED` is now **TESTED for the value path** with the owner-approved
  symlink; the slider gesture itself is still UNVERIFIED.
- **Still outbound-capable in the daemon (not exercised, reported for the owner):**
  `src/ryoku/shell/ipc/weather.go` (Open-Meteo forecast/geocode/air), `music.go` (remote artwork),
  `calendar.go` (ICS over HTTP). None was reached in this run and the hub made no socket; whether
  they should be neutered is a keep-list decision for the owner (weather/music/calendar are not on
  the keep list).
- Tray icons: `Icons.qml` was spawning a non-existent `ryoku-shell` path; fixed to `mei-shell`.
  Real tray content is still **UNVERIFIED**.

### Verdict

**One clean run after two harness-only FAILs.** Loop exited at the step boundary. Stopping for
owner review before wallpaper / notifications / tray (not started). The owner should `./mei run`,
open Settings from the quick-settings rail and from the bar, move the **Motion → Speed** slider
and watch the shell's panels, then RESET and confirm 100%.
