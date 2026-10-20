# STATUS — Mei

Updated 2026-10-20. One page. **TESTED** = a nested run with a log under `.run/logs/`;
**UNVERIFIED** = only the owner can judge it (live session, feel, real apps). Nothing here is
"working" without a test or a number.

| Component | Status | Commit(s) | Notes |
|---|---|---|---|
| Bar (qsbar), workspaces | TESTED nested | `35c94a3`, `daa53aa`, `93c216a` | `barStyle` pinned to `qsbar` in shipped default, fallback and nested config |
| Launcher | TESTED nested | `9b2fc22`, `35c94a3` | `/` command mode and Actions provider disabled, not deleted |
| Control centre / sidebar | TESTED nested | `67041b8` | kanji labels are English |
| Settings (5 pages) | TESTED nested | `c3e1403`, `daa53aa` | never writes Hyprland config; sumi/kairos unreachable |
| Wallpaper + matugen | TESTED nested | `3092464`, `3973514` | stills only, guarded |
| Notifications | TESTED nested | `a3d4886` | one `NotificationServer`, no cache file |
| System tray | TESTED nested | `93c216a` | one watcher host; auto-pin + right-click menu |
| Module toggles (Phase 8) | NOT IMPLEMENTED | — | next |
| Full acceptance pass (Phase 9) | NOT RUN | — | cold start x2 |
| Measurements (Phase 10) | NO NUMBERS | — | do not call Mei lightweight yet |
| Live trial | NOT RUN | — | owner-run, needs a terminal |

## Where things are

- Tests (versioned): `docs/tests/step*.sh`, `docs/tests/sni-test.py`; evidence in `.run/logs/`.
- Decisions and investigations: `docs/loop-log.md` (newest last), `CHANGES.md` (newest first).
- Safety: `./mei verify-untouched` must PASS before and after every run.

## Owner-only (UNVERIFIED)

144 Hz smoothness and animation feel; tray glyphs from real apps (ProtonVPN, Steam) and their
menus; real audio/brightness hardware; wallpaper reveal on the real display; notification look;
whether the bar fits the real 1080p screen.
