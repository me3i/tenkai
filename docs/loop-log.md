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

**Change set:** `CHANGES.md` → "Phase 6 — step 4". Harness `docs/tests/step4.sh` (versioned in docs/tests).
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

## Step 4 amendments (2026-10-20)

Owner decisions after approving step 4: neuter weather/music/calendar outbound in the daemon,
hide "CHANGE ON MAP", disable the launcher's weather widget (and say whether it called).

| Item | Result | Evidence |
|---|---|---|
| daemon has no HTTP transport | **TESTED** | `go list -deps` = no `net/http` (only `net`, unix sockets); no `http.Client` in source |
| no tcp/udp on daemon / shell / hub | **TESTED** | `ss -tunp` — 3 pids, no sockets (`step4b-022341.log`) |
| launcher weather made no calls | **TESTED** | `Weather.qml`: `online:false`, fetch/locate/replay guarded, timer off |
| launcher shows date only | **TESTED** | `.run/shots/step4b2-launcher-open.png` |
| General page has no CHANGE ON MAP / weather rows | **TESTED** | `.run/shots/step4b-hub-generic-general.png` |
| bar weather slot collapsed | **TESTED (source)** | `WeatherWidget.qml` `implicitWidth: 0`; screenshot of the collapsed bar not captured (grim crop failed) |
| verify-untouched before/after | **PASS** | both runs |
| clean shutdown, no strays | **TESTED** | both runs |

- Two harness runs: `step4b-022032.log` (General page still showed the inert Location field —
  fixed), `step4b-022341.log` (PASS), `step4b2-022600.log` (real-launcher shot, PASS).
- **Reported, not changed:** the dashboard popup and clock menu still carry data-less weather
  tiles (pre-existing; layout change deferred to the owner).
- Audio/mute re-check by the owner: volume 1.00, not muted; PipeWire symlink absent from `.run/rt`.

### Verdict

**PASS.** Loop exited at the boundary. Step 5 (wallpaper + matugen) starts next.

## Step 5 — wallpaper + matugen theming (nested)

Loop: 6 runs of `docs/tests/step5.sh` (three exposed real gaps, then clean passes; the final
run adds the wallpaper/launcher assertions). Final PASS log: `.run/logs/step5-0259*.log`
(the previous clean PASS is `.run/logs/step5-025738.log`).

| Acceptance item | Result | Evidence |
|---|---|---|
| ryogami runs, stills only | **TESTED** | `wallPrefs()` Enabled:false; `applyWallpaper` refuses non-static; `depthVerb` refuses |
| guard refuses the live display | **TESTED** | unset -> `MEI_HOST_WAYLAND_SOCKET is unset: refusing`; equal -> `resolves to the live session`; nested -> `display guard ok (/…/.r/wayland-1 != live /run/user/1000/wayland-1)` |
| nested signature != baseline | **TESTED** | harness check |
| still wallpaper sets | **TESTED** | wallpaper-area mean `0C1724` -> `BB7165` -> `8A89B0` |
| reveal transition runs | **TESTED (frames)** | 3 distinct frames at 0.15 s / 0.60 s / settled; **feel UNVERIFIED** |
| palette regenerates | **TESTED** | `$HOME/.cache/mei/{colors,tones}.json` written; primary `#904b40` |
| bar recolours | **INVALID — see the correction below** | the old `B07165` -> `9C7EC5` measured the sumi rail, not the bar |
| launcher recolours | **INVALID — see the correction below** | the old `E4D3CF` -> `DAD9E4` came from the same sumi run |
| second wallpaper recolours again | **TESTED** | colors.json hash changes; bar + accent change |
| matugen + right config path in log | **TESTED** | `matugen render: matugen -c /home/mei/projects/mei/.run/config/mei/matugen/config.toml json …` |
| no outbound | **TESTED** | `ss -tunp`: ryogami, daemon and shell own no tcp/udp; `go list -deps` has no `net/http` |
| no 47616 listener | **TESTED** | `ss -ltnp`; neither binary contains the port |
| no strays after `./mei stop` | **TESTED** | comm-based check: no ryogami/matugen/mei-shell/project quickshell |
| real configs/caches untouched | **TESTED** | sha256 of `~/.config/{kitty,qt6ct,gtk-3.0}` + absent `{btop,gtk-4.0}`, `~/.cache/{ryoku,matugen}` identical before/after |
| ryogami resource use | **TESTED** | VmRSS/VmHWM 10.9 MB, 10-11 threads, 0.0% CPU at idle |
| verify-untouched before/after | **PASS** | both ends |

### Correction — the bar numbers above measured the wrong bar

The runs behind `B07165 -> 9C7EC5` had `barStyle: sumi` in `.run/config/mei/shell.json`
(the hub's unreadable-id fallback wrote it), so the `1180x36+0+0` crop was the sumi left rail
over the wallpaper, not the qsbar top bar. Those two rows are **invalid for the bar**.

Valid measurement with `qsbar` pinned — both runs print `nested shell.json barStyle: qsbar`:

| Run | bar strip before | after set 1 (warm) | after set 2 (purple) | launcher accent |
|---|---|---|---|---|
| `.run/logs/step5-045946.log` | `E0D9EC` | `E6D7D3` | `E0D9EC` | `F2956A` -> `6873A7` |
| `.run/logs/step5-050041.log` | `E0D9EC` | `E6D7D3` | `E0D9EC` | `F2956A` -> `6873A7` |

Both runs agree pixel-for-pixel. The crop is the bar itself: `.run/shots/step5-bar-after1-crop.png`
shows the MEI wordmark, the workspace pill, audio, clock and the tray glyphs. The bar returns to
its starting colour on set 2 because set 2 is the default wallpaper, i.e. the original palette.

**Fixed at the source:** the hub no longer invents `sumi`. `Hub.qml` shipped defaults and
`BarStudioPage.qml`'s `activeStyle` fallback are both `qsbar` now, so an unreadable id can no
longer reseed the alternative rail.

### Gaps this step exposed (all fixed)

1. **The palette had no trigger**: `bootstrap()` never called `watchRyogami()`, so wallpaper
   changes never reached matugen. Added.
2. **The wallpaper never painted**: the reveal Backdrop lives inside the Desktop surface, which
   step 1 had set `active: false`. The surface is now visible with widgets still off.
3. **`[config]`-only is not a valid matugen config**: matugen 4.2.0 requires a `templates`
   field. The shipped file is `[config]` + empty `[templates]`.

### Incident (self-inflicted, reverted)

While testing the guard I ran `.run/bin/ryogami daemon` with only `XDG_RUNTIME_DIR` overridden —
i.e. with the **real** `HOME` and `XDG_CACHE_HOME`. It created `~/.cache/ryogami/` (20 files:
thumbnails of the real wallpaper folder, `outputs.json`, `state.json`, `wall-ui.log`) and
`~/.local/state/mei-wallpaper`. No host ryogami was running and every file in that tree carried
the run's timestamp, so nothing the owner had was overwritten. I removed exactly those two paths
and `./mei verify-untouched` PASSes. **Gap for the owner:** `verify-untouched` compares the
recorded baseline files; it does not notice *new* paths outside that set, so it could not have
caught this. All later runs set the full fake environment.

### Exclusions reported (opt-in paths)

- `ryogami/wall-ui` picker (114 files, Wallhaven/Steam outbound, pkill-by-name) — not copied;
  `wallpaper ui` refuses and the bar's wallpaper surface request is dropped.
- Live video and depth — forced off as above; restore the blocks in `config.go`/`apply.go`.
- App theming fan-out (`apps.toml`, GTK blanking, cursor recolor, gsettings/kitty) — commented
  in place in `matugen.go`.
- Palette bridge — refused in `hub/backend/palettebridge.go`.

### Verdict

**PASS** for everything the nested session can prove. **UNVERIFIED for the owner:** reveal
animation feel, palette colour correctness/taste, 144 Hz smoothness. Before/after screenshots:
`.run/shots/step5-01-before.png`, `step5-02-set1-reveal-015.png`,
`step5-03-set1-reveal-060.png`, `step5-04-set1-settled.png`, `step5-05-set2-settled.png`,
`step5-launcher-p1.png`, `step5-launcher-p2.png`.

## Step 5 fixes — owner review (2026-10-20)

Owner's four objections were all correct. Run count, honestly: the two clean runs on record were
made **before** the `Frame.qml` edit, so the committed step-5 tree had zero clean runs.

| # | Item | Result |
|---|------|--------|
| a | HOME guard, four binaries | TESTED: each refuses `HOME=/home/mei` with exit 1 before any file access; probe XDG dirs still empty afterwards; `HOME` unset also refuses |
| b | `./mei wallpaper` | TESTED: both harness wallpaper changes go through it (SPIKE: palette + pixels changed both times) |
| c | new-entry scan | TESTED: decoy `~/.cache/mei-probe-test` and `~/.cache/ryogami` -> FAIL listing the path; removal -> PASS |
| d | re-run after `Frame.qml` | TESTED: two consecutive runs, `step5-041051.log` + `step5-041136.log`, both `RESULT: PASS`, 0 FAIL lines |
| e | weather tiles | Hidden (`MenuWeather` root, `DashboardPopup` `weatherUi`) — lint-clean, look UNVERIFIED |

Two defects found while doing (c):

1. `capture_names` initially aborted the whole script: `grep` exits 1 on zero matches and
   `set -o pipefail` propagated it. Fixed with `{ grep ... || true; }` — the empty result is the
   healthy case.
2. A literal substring match for `mei|ryoku|ryogami` cannot work on this host. It flags
   `MEIPreload` (Chrome), `namei.fish`, `GameInviteNotification.res`, `mimeinfo.cache`. The check
   is anchored at the start of each path segment instead; both real incident paths still match.

Still OPEN (UNVERIFIED, owner-only): reveal feel, palette taste, 144 Hz. And with the weather
islands hidden the dashboard's lower-right quadrant is empty — acceptable or wants the clock
island to grow? Owner's call.

## Nested test compositor: hyprlang `.conf` -> Lua (owner request, 2026-10-20)

`write_nested_conf()` in `mei` now emits `.run/hypr/nested.lua`, and the session template launches
`Hyprland -c "$RUN/hypr/nested.lua"`. Reason: Hyprland 0.56.2 still parses `.conf` but warns that
0.57 removes the format, which would have stopped the nested test from launching after an upgrade.
The owner's live session already uses Lua and was not involved.

| Check | Result |
|---|---|
| `Hyprland --verify-config -c .run/hypr/nested.lua` | `config ok`; Hyprland logs `[cfg] Config is lua, loading lua mgr` |
| API used | only forms from `/usr/share/hypr/hyprland.lua` (`hl.config`, `hl.bind`, `hl.dsp.focus`, `hl.dsp.exec_cmd`, `hl.dsp.global`) and upstream `ryoku/hyprland/modules/*.lua` — nothing invented |
| `.conf` deprecation toast | TESTED gone. Before: `.run/shots/step6-03-normal-popup.png` (04:49, `.conf`) shows both toasts top-right. After: `.run/shots/step5-01-before.png` (05:00, Lua) shows neither. Same capture path (`grim -o` on the nested output). |
| "started without start-hyprland" toast | Silenced with `misc:disable_watchdog_warning`. The key exists in this binary (`strings /usr/bin/Hyprland`), and at runtime `hyprctl getoption misc:disable_watchdog_warning` -> `bool: true`, `set: true`. |
| startup *log* line | Still printed: `WARN ]: WARNING: Hyprland is being launched without start-hyprland.` It is emitted before the config is parsed, so no config key can remove it. Harmless in a log; the visible toast is what the option controls. |
| bar/launcher re-run after the change | TESTED twice, two consecutive clean runs: `.run/logs/step5-045946.log` and `step5-050041.log`, both `RESULT: PASS` with 0 `FAIL` lines, 33 `TESTED` each, verify-untouched PASS at both ends. |

`~/.config/hypr` was never read from or written to: `./mei verify-untouched` PASS before and after
every run in this change.

## Step 6 — notifications (2026-10-20)

Scope: notifications only. The tray was **not** started; that is step 7.

| Item | Result |
|---|---|
| one `NotificationServer` | TESTED: `grep -rn NotificationServer src/` -> `services/Notifs.qml:230` only |
| panel became a view | TESTED: `NotificationPanel.qml` reads `Services.Notifs.history`, `+17 / -139`, no cache |
| nested bus | TESTED: Mei's shell owns `org.freedesktop.Notifications` on the private bus |
| live bus | TESTED: owner still pid 949 before and after; the nested bus address differs |
| `notify-send` popup | TESTED |
| urgency x3 | TESTED arrival; upstream gives urgency no styling/timeout effect, so all three look identical (look UNVERIFIED) |
| long body | TESTED: accepted (history=4) |
| actions | TESTED: `notifInvoke` -> `ActionInvoked 'later'`, sender exit 0, output `8 later` |
| icon | TESTED sent (`icon-static`, 1523 B); rendering UNVERIFIED |
| DND on/off | TESTED: popups stay 0 while on, history still fills; popup returns when off |
| dismiss / clear all | TESTED: 4 -> 3; clear emptied history and closed popups |
| `-t 0` | TESTED: alive after 6 s and absent from history |
| state location | TESTED: `flags.json` under the fake HOME; no new mei/ryoku/ryogami name outside the project |
| outbound | TESTED: both shell pids own no tcp/udp socket |
| clean stop | TESTED |
| two clean runs | TESTED: `.run/logs/step6-050659.log`, `step6-050728.log`, `RESULT: PASS`, 39 TESTED, 0 FAIL each |

Corrections carried into this step:

| Correction | Detail |
|---|---|
| step-5 bar colour numbers | The runs after 02:00 had `barStyle: sumi` in `.run/config/mei/shell.json`, so the `1180x36+0+0` crop measured the sumi rail and wallpaper, not the qsbar bar. Only the qsbar-pinned runs (04:59/05:00) measure the real bar. Harnesses now pin `barStyle=qsbar` and print the previous value. |
| live notifications PID | 949 per `docs/baseline/dbus-watched.tsv`; the "935" I reported earlier was stale. |

UNVERIFIED (owner only): popup motion, card appearance, icon rendering inside the card, palette
taste, 144 Hz smoothness. Screenshots: `.run/shots/step6-03-normal-popup.png` ...
`step6-12-actions.png`.

## Step 7 — system tray (2026-10-20)

Scope: system tray only. Nested Hyprland, fake HOME, private bus; no real session, no network.
The bar draws the icons, the themed menu is `panels/TrayMenu.qml`, and `ipc/tray.go` is the only
`org.kde.StatusNotifierWatcher` host.

| Item | Result |
|---|---|
| one host | TESTED: no QML file names `org.kde.StatusNotifierWatcher`; `tray.go` declares it; the daemon exposes the `tray.*` verbs |
| live bus before / after | TESTED: owner pid 949 before and after; the nested bus address differs |
| nested owner | TESTED: the nested watcher is owned by Mei's daemon pid (e.g. 195313), which differs from 949 |
| item appears | TESTED: tray count 1; icon auto-pinned; theme icon resolved `dialog-information` |
| icon size | TESTED: the 24 px ARGB pixmap is drawn in a `14x14` box (`14x14+122+13`); the theme glyph's ink is `7x11`; widget `sourceSize` 14 |
| left click | TESTED: SNI `Activate` reached the item (`Activate 0 0`) |
| right click menu | TESTED: the themed `TrayMenu` opened (header + rows), dbusmenu `GetLayout` was read |
| menu entry | TESTED: `trayMenuEvent 1` -> item received `MenuEvent 1`; the disabled row stayed disabled |
| tray panel | TESTED: opens |
| second item | TESTED: count 2, ARGB pixmap converted and cached under the fake HOME |
| item removal | TESTED: 2 -> 1, then 1 -> 0; the emptied tray shows nothing |
| icon resolution | read-only: item themed path -> theme name -> nearest-24px ARGB->RGBA pixmap -> generic executable fallback; no theme writes |
| outbound | TESTED: daemon and shell pids own no tcp/udp socket |
| clean stop | TESTED: both test clients exited, no stray ryogami / matugen / mei-shell / project quickshell, no nested control socket |
| verify-untouched | TESTED: PASS before and after each run |
| two clean runs | TESTED: `.run/logs/step7-final1.log`, `step7-final2.log`, `RESULT: PASS`, 32 TESTED, 0 FAIL each |

Two upstream defects surfaced while making the tray visible, and were fixed rather than worked
around:

| Defect | Detail |
|---|---|
| menus never loaded | `refreshMenu()` used `Store(&revision, &layout)`, but `GetLayout` returns ONE body argument (the struct). Every call failed with `dbus.Store: length mismatch` and the item's menu stayed nil. Proven with a throwaway Go probe against the test client, now decodes the struct and logs failures. |
| status cluster stuck collapsed | `TrayWidget.visible` was `trayRow.implicitWidth > 0`. An empty bar collapses that slot (`width: 0`, `opacity: 0`), so the row measured 0 forever after the first item arrived. The widget now has no `visible` gate (0-wide while empty) and its Repeater is fed from `trayModel`, refreshed in `onItemsChanged`, because binding the model straight at the services singleton resolved empty in the bar instance. |

Harness note: the nested output came up at `devicePixelRatio 2` (980x508 physical = 490x254
logical). qsbar's narrow stage hides low-priority slots there, which collapsed the status
cluster and hid the tray before any icon could appear. The nested compositor now pins
`scale = 1` (`hl.monitor`, documented form), so the test bar is 980 logical px. This is test
scaffolding in `.run/hypr/nested.lua`; the owner's config is untouched.

Deviations from upstream, to review:

| Area | Upstream | Mei |
|---|---|---|
| default pinning | `trayPinned: []`; every icon sits behind the "more" toggle until pinned by hand | each service is auto-pinned once; an explicit unpin is remembered for the session |
| right click | toggles pin/unpin | opens the item's own dbusmenu when it publishes one; pin/unpin stays on the panel row |

UNVERIFIED (owner only): tray icon legibility on the real wallpaper — the Adwaita legacy
`dialog-information` glyph is a pale lightbulb on the light bar, and only the owner can judge it;
real apps with submenus; 144 Hz smoothness. Screenshots: `.run/shots/step7-01-tray-icon.png`,
`step7-02-tray-menu.png`, `step7-03-tray-panel.png`, `step7-04-two-icons.png`,
`step7-05-after-one-removed.png`, `step7-06-after-both-removed.png`.

## Stage 1 — harness versioned, status page (2026-10-20)

Owner approved step 7 (keep auto-pin and right-click menu; tinting deferred to the live trial)
and asked for the test harnesses to leave the git-ignored `.run/tools`.

| Item | Result |
|---|---|
| harness move | TESTED: `docs/tests/step*.sh`, `sni-test.py`, `launcher-check.sh`, `qs-check.sh` moved to `docs/tests/`; the three `sni-test.py` call sites in `step7.sh` now use `$MEI/docs/tests/sni-test.py` |
| harness still runs from there | TESTED: `bash docs/tests/step7.sh` -> `RESULT: PASS`, 32 TESTED, 0 FAIL (`.run/logs/step7-moved.log`) |
| barStyle | TESTED: shipped default `Hub.qml:548` `"barStyle": "qsbar"`; `services/Config.qml:193` `"qsbar"`; `BarStudioPage.qml:158` fallback `"qsbar"`; nested `.run/config/mei/shell.json` -> `qsbar`; zero `kairos` references under `src/ryoku/hub/` |
| sumi/kairos in Settings | TESTED: `BarStudioPage.qml:335` BAR STYLE card `visible: false`, its ryostore `Process` `running: false` at `:86` |
| status page | `docs/STATUS.md` (one screen) |
| verify-untouched | PASS before and after |
