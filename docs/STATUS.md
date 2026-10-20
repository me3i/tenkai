# STATUS — Mei

Updated 2026-10-20. One page. **TESTED** = a nested run with a log under `.run/logs/`;
**UNVERIFIED** = only the owner can judge it (live session, feel, real apps). Nothing here is
"working" without a test or a number.

| Component | Status | Commit(s) | Notes |
|---|---|---|---|
| Bar (qsbar), workspaces | TESTED nested | `35c94a3`, `daa53aa`, `93c216a` | `barStyle` pinned to `qsbar` in shipped default, fallback and nested config |
| Launcher | TESTED nested | `9b2fc22`, `35c94a3` | `/` command mode and Actions provider disabled, not deleted |
| Control centre / sidebar | TESTED nested | `67041b8` | kanji labels are English; brightness 5% step via the QML path and the hub verb, restored (helper `ryoku-cmd-brightness` now shipped) |
| Settings (5 pages) | TESTED nested | `c3e1403`, `daa53aa` | never writes Hyprland config; sumi/kairos unreachable |
| Wallpaper + matugen | TESTED nested | `3092464`, `3973514` | stills only, guarded |
| Notifications | TESTED nested | `a3d4886` | one `NotificationServer`, no cache file |
| System tray | TESTED nested | `93c216a` | one watcher host; auto-pin + right-click menu |
| Module toggles (Phase 8) | TESTED nested | `ae65a66`..`d344260` | two clean runs: `.run/logs/phase8-final1.log`, `phase8-final2.log` (50 TESTED, 0 FAIL each); schema in `docs/MODULES.md` |
| Full acceptance pass (Phase 9) | **PRODUCT PASS; HEAD HARNESS FAIL** | `a646782`, `8703304` | `a646782`: two clean cold-start runs, **16/16, 0 FAIL** (item 4 PARTIAL), `.run/logs/phase9-20261020-105305.log`, `-110312.log`. Post-acceptance commits have **no product-file diff** (`src/`, `hub`, `configs/`, `docs/baseline`). Final test-only run on `8703304` **FAILed item 7** (second wallpaper did not repaint) and hung in `grim` (item 6's last check became vacuous); harness fix applied, **not re-run** — see `docs/loop-log.md`. |
| Measurements (Phase 10) | NO NUMBERS | — | do not call Mei lightweight yet |
| Live trial | NOT RUN | — | owner-run, needs a terminal |

**Phase 9 detail:** the certified product bytes are at `a646782`; `git diff a646782..HEAD -- src hub configs docs/baseline` is empty, so the two clean runs describe the product at HEAD as well. The HEAD **test harness** is not certified: the final run failed in the harness, not the product. `docs/tests/phase9.sh` now has a 20 s `grim` timeout, DPMS/cursor wake, screenshot retries and a wallpaper repaint retry, but those edits are **UNVERIFIED** until one clean run.

## Where things are

- Tests (versioned): `docs/tests/step*.sh`, `docs/tests/sni-test.py`; evidence in `.run/logs/`.
- Decisions and investigations: `docs/loop-log.md` (newest last), `CHANGES.md` (newest first).
- Safety: `./mei verify-untouched` must PASS before and after every run.

## Owner-only (UNVERIFIED)

144 Hz smoothness and animation feel; tray glyphs from real apps (ProtonVPN, Steam) and their
menus; real audio hardware (writes were not exercised); wallpaper reveal on the real display; notification look;
whether the bar fits the real 1080p screen.
