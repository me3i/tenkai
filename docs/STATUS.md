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
| Full acceptance pass (Phase 9) | **PRODUCT PASS; HEAD HARNESS UNVERIFIED** | `a646782`, `8e75f18` | `a646782`: two clean cold-start runs, **16/16, 0 FAIL** (item 4 PARTIAL), `.run/logs/phase9-20261020-105305.log`, `-110312.log`. Follow-up fixes: brightness wired and TESTED (`.run/logs/phase9-core-141104.log`), hub tests **170 PASS / 11 SKIP / 0 FAIL** (`.run/logs/hub-test-20261020-142100.log`), five-workspace test **5/5** (`.run/logs/workspaces-134543.log`). Three HEAD harness runs (`.run/logs/phase9-20261020-134723.log`, `-140057.log`, `-141101.log`) all passed the 16 product items in the last two; all failed the **new** item 17 leak-monitor check on its own defects (S9a expectation, launcher/compositor exemptions, transient empty `/proc` environ), fixed after run 3. A full clean run at HEAD is **not** certified; item 17 was validated only by its self-test and three short real-session runs. |
| Measurements (Phase 10) | NO NUMBERS | — | do not call Mei lightweight yet |
| Live trial | NOT RUN | — | owner-run, needs a terminal |

**Phase 9 detail:** the certified product bytes at `a646782` had two clean cold-start runs. The only product change since is `src/ryoku/shell/scripts/ryoku-cmd-brightness` (owner follow-up item 1) plus the `mei` symlink that installs it; `git diff --stat a646782..HEAD -- src hub configs` shows that script and test files only, no QML/Go product behaviour. The HEAD **test harness** is not certified: the three runs above failed in the new item 17 monitor, not in the 16 product items. `docs/tests/phase9.sh` now has the 20 s `grim` timeout, DPMS/cursor wake, screenshot retries, wallpaper repaint retry, and the leak monitor; those edits are **UNVERIFIED** by a clean full run. Do not claim Phase 9 PASS or start Phase 10 measurements until one clean run exists.

## Where things are

- Tests (versioned): `docs/tests/step*.sh`, `docs/tests/sni-test.py`; evidence in `.run/logs/`.
- Decisions and investigations: `docs/loop-log.md` (newest last), `CHANGES.md` (newest first).
- Safety: `./mei verify-untouched` must PASS before and after every run.

## Owner-only (UNVERIFIED)

144 Hz smoothness and animation feel; tray glyphs from real apps (ProtonVPN, Steam) and their
menus; real audio hardware (writes were not exercised); wallpaper reveal on the real display; notification look;
whether the bar fits the real 1080p screen.
