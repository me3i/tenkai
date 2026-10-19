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
