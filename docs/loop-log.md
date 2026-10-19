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
