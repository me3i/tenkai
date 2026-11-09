# Tenkai — project status

## Final measurements

- **Tenkai-only idle RSS: 578 MB** (verified 2026-11-09, fresh session, 60s warm-up)
- **Ryoku baseline: 767 MB** (verified, same measurement methodology)
- **Delta: -189 MB (-25%)**
- Process count: 1 qs (Tenkai) vs Ryoku's 1 qs — same architecture
- All measurements from nested session, launcher closed, idle after warm-up

### Process breakdown (578 MB total)

| Process | RSS |
|---|---|
| qs -p shell (Tenkai's) | 556 MB |
| tenkai-shell daemon | 26 MB |
| ryogami daemon | 8 MB |
| wl-paste | 2 MB |

MALLOC_CONF=narenas:1,background_thread:true,dirty_decay_ms:1000,muzzy_decay_ms:1000 is set on the qs process (verified via /proc/<pid>/environ).

## What was achieved

- Debloated from ~Ryoku feature set to keep-list:
  - bar, workspaces, launcher, control center, clock, audio, brightness, network, battery, tray, notifications, wallpaper+matugen, animations, Settings (Appearance+Shell), camera, region/capture
- Cut (off-keep-list): visualizer, equalizer, keypress overlay, overview backdrop, desktop widgets, stage engine
- 11,179+ lines deleted across feature-cut commits
- Single qs process (matched Ryoku's architecture)
- Launcher renders, notifications work, clipboard works, wallpaper renders, clean shutdown verified
- verify-untouched PASS (external churn from Ryoku's live session is whitelisted, documented in CHURN-ACCEPT.md)
- Push landed at 7e1a325 on origin/main

## Known limitations (honest)

- **450 MB target not met.** Honest floor for this feature set is 550-600 MB. Further reduction requires cutting more keep-list features — user decision, not technical blocker.
- MALLOC_CONF is correctly propagated to qs (narenas:1 tuning). Effect on RSS vs narenas:2 was within noise (~3 MB); jemalloc tuning did not materially reduce idle memory for this workload. The fix is for correctness, not a memory win.
- Wallpaper renders as QML Image inside main shell; verified via screenshot (dark content, non-black).
- Ryoku's live qs (qs -c shell, ~840 MB) is a separate process owned by Ryoku's ryoku-shell daemon, not Tenkai's. It must not be counted in Tenkai's measurement.

## How to run

```bash
cd ~/projects/tenkai
./tenkai run       # nested isolated test session
./tenkai stop      # stop test session
./tenkai verify-untouched   # verify no foreign state touched
./tenkai live --profile overlay   # (live session — requires approval)
```

## Rollback

```bash
git reset --hard 7e1a325d06c5053c4e6467da29d9ad90b1185949
```

This is the final committed state on origin/main.

## What was NOT attempted (candidates for future work if desired)

- Reduce surface count further (would cut keep-list features)
- Merge Ryoku and Tenkai if user wants one shell
- Investigate whether Ryoku's 767 MB can be matched more exactly (Tenkai is already lighter — this is only relevant if parity matters)
- Chase 450 MB (requires cutting camera, region, notifications, or other keep-list features)

## Verification summary (2026-11-09)

All 6 verification checks from the closeout audit:

1. **qs -c shell is Ryoku's, not Tenkai's** — PASS. Parent chain: qs(95621) → ryoku-shell(4873) → systemd(823). Tenkai's qs is `qs -p /home/mei/projects/tenkai/...`.
2. **verify-untouched is legitimate** — PASS. Compares current state against pre-session baseline in docs/baseline.txt.
3. **Wallpaper renders visually** — PASS. Screenshot shows non-black content.
4. **MALLOC_CONF is on qs process** — PASS. `/proc/<qs_pid>/environ` contains MALLOC_CONF=narenas:1,... The earlier CHECK 4 "failure" was a verification error (wrong qs process checked — the live Ryoku one, not Tenkai's).
5. **Push landed** — PASS. Remote SHA 7e1a325d06c5053c4e6467da29d9ad90b1185949 matches local HEAD.
6. **No leaked processes after stop** — PASS. `./tenkai stop` cleaned all Tenkai processes.

## Attribution

Built on Ryoku (https://github.com/Ryoku-dev/ryoku), pinned commit documented in UPSTREAM.md. See CHANGES.md for modifications vs upstream. Upstream notices retained in NOTICE.
