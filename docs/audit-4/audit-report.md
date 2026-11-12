# Audit-4 — boot-into-Tenkai, settings preview, cross-check

Date: 2026-11-12. Branch: `audit-4/boot-into-tenkai` (no push).

## 0. How to read this file

This is the authoritative record. Every finding (E1–E11), every audit-3 claim
status (C1–C56), every fix commit, every deferred item, every live file touched
and every command that produced the evidence below is in this file. Supporting
raw output is under `tests/evidence/<timestamp>/` and `/tmp/audit4-*.log`; no
other report file is needed to understand the pass. Sections with no findings
say "nothing found" explicitly.

## 1. Preflight — current boot chain, mechanism decision

Base: `0f72710`, branch renamed from `audit-4/crosscheck-settings-preview` to
`audit-4/boot-into-tenkai`; 10 commits before this report. Preflight suite:
18/18 PASS, exit 0 (before M1/boot work). Working tree also had two untracked
files, `tenkaifinal.txt` and `tenkairun.txt`; untouched.

Raw boot investigation:

```
B1 bootloader: bootctl status -> UEFI 2.80 (INSYDE), Secure Boot disabled.
   No /boot/limine, /boot/grub/grub.cfg or /boot/loader. Bootloader untouched.
B2 default target: graphical.target
   running: ly@tty1.service (TUI display manager), active since 00:57.
B3 display manager: ly 1.4.1-1, /usr/lib/systemd/system/ly@.service, enabled.
   sddm/gdm/lightdm/greetd: not-found. ly config: /etc/ly/config.ini.
B4 Hyprland start: /usr/share/wayland-sessions/hyprland.desktop ->
   /usr/bin/start-hyprland. ~/.config/hypr/hyprland.lua loads modules;
   autostart.lua had NO tenkai start hook before this pass.
B5 TTY1 autologin: no /etc/systemd/system/getty@tty1.service.d.
B6 login shell: /usr/bin/fish for mei. No TTY1 exec block in fish config.
B7 scripts/tenkai-autostart exists; prints the exact exec block and can append
   it with --apply --yes-hyprland.
B8 conflicting shell: no live Ryoku/Tenkai *autostart* line. Grep hits were
   comments and .bak files only.
B9 systemd user units: none for ryoku/tenkai (no ~/.config/systemd/user units).
B10 session env: no environment.d files; Hyprland env module carries the
   session variables.
```

Decision: **Mechanism B-variant — the already-installed Ly autologin, plus
Tenkai's Hyprland-start hook.** Ly is already enabled and running on tty1, so
its built-in `auto_login_user`/`auto_login_session` is one config change, no new
package and no bootloader edit. TTY1 getty+fish exec (A) was rejected because
Ly owns tty1 and conflicts with getty@tty1; SDDM (C) and greetd (B) were rejected
because neither is installed, so either adds a package and a service; systemd
user target (D) still needs a graphical session first and adds complexity.

Layer status: Ly itself exists; the Tenkai session hook existed only as an
installer action and was missing live; autologin is not configured. During this
pass the session hook was installed live. **Autologin needs root** (`/etc/ly/`
is root-owned and `sudo -n` is unavailable), so it remains the one manual step.

## 2. Boot-into-Tenkai — implementation

### 2.1 Chosen mechanism + why
Ly autologin → `hyprland.desktop` (`start-hyprland`) → Hyprland
`hyprland.start` → `/home/mei/tenkai/tenkai start`, which brings up the daemon
and bar. Ly is already the only DM; this is the smallest complete chain.

### 2.2 Rejected mechanisms
A: no getty on tty1 (Ly conflicts), and it would replace a working DM.
C: SDDM absent. B: greetd absent. D: no rootless way to get a graphical session.

### 2.3 Files created/modified (repo)
- `tests/run-all.sh`: new `runtime/boot-chain-configured` check (commit
  `44306c9`, hardened in `9a42f88`). No shipped Hyprland file hardcodes this
  machine's checkout path; the existing `scripts/tenkai-autostart` remains the
  installer mechanism.

### 2.4 Files created/modified (live, with backup paths)
- `~/.config/hypr/modules/autostart.lua`: appended Tenkai's start block.
  Backup: `autostart.lua.pre-audit4.bak` (plus the script's own
  `autostart.lua.tenkai-autostart.bak`).
- `~/.config/hypr/modules/decoration.lua`: omit empty `screen_shader` (E7).
  Backup: `decoration.lua.pre-audit4.bak`.
- `~/.config/hypr/modules/misc.lua` and `binds.lua`: audit-3 state retained;
  backups `misc.lua.pre-audit4.bak`, `binds.lua.pre-audit4.bak`.
- `~/.config/hypr/hyprland.lua`: backup `hyprland.lua.pre-audit4.bak` (gesture
  module require from audit-3).
- `.run/live-pids`: stale after the lost session; moved to
  `.run/live-pids.pre-audit4.bak`, then session restored manually from the
  same binaries.
- `/etc/ly/config.ini`: **not touched** (no root).

### 2.5 Conflicting auto-starts disabled
None found; nothing disabled. The boot test fails if a real Ryoku/other-shell
`exec` line appears in live Hyprland or fish config.

### 2.6 Test added
`runtime/boot-chain-configured` asserts: live autostart hook calls
`tenkai start`; repo installer is executable; no conflicting shell autostart;
`hyprland.desktop` session entry exists; reports Ly `auto_login_user`. It
records UNVERIFIED (not PASS) while autologin is unset, because the chain is not
complete without root.

### 2.7 Verification performed
`bash tests/run-all.sh` → 19 PASS, 1 UNVERIFIED, 0 FAIL, exit 0
(evidence `tests/evidence/20261112-064753/`). The live hook text was read back:

```
-- tenkai-autostart: start the Tenkai shell at session start
hl.on("hyprland.start", function()
    hl.exec_cmd("/home/mei/tenkai/tenkai start")
end)
```

The session was also restarted manually with the same binary/env after the
daemon was rebuilt; the bar returned (screenshot `/tmp/restored4.png`).

### 2.8 Reboot required to fully prove — YES
The user must reboot to prove power-on → Ly → Hyprland → Tenkai. This pass did
not reboot. `runtime/boot-chain-configured` is UNVERIFIED until autologin is
set and a reboot is observed.

### 2.9 Rollback — exact commands
```bash
cp ~/.config/hypr/modules/autostart.lua.pre-audit4.bak \
   ~/.config/hypr/modules/autostart.lua
sudo cp /etc/ly/config.ini.pre-audit4.bak /etc/ly/config.ini   # if step 14 was run
```

## 3. Settings preview (user-reported) — fixed

### 3.1 Repro
Started the Hub; edited a schema page row. The draft changed and the footer
showed "1 CHANGE · PREVIEWING · NOT SAVED", but the running shell kept its old
value: only Bar Studio staged its fixed key list live, shared schema pages
(`DesktopPage`, `GlobalPage`) wrote the draft alone. IPC:
`draft set frameThickness 4` left `shell getSetting frameThickness` at 2.

### 3.2 Root cause
P3/P4 class: preview read the draft (correct) but the draft was never sent to
the running shell for any page except Bar Studio. The live-preview seam existed
but was hard-coded to Bar Studio's `liveKeys`.

### 3.3 Fix
- `Hub.qml`: `liveKeys` derived from every shell-source `defs` entry; new
  `preview(k, v)` applies through the existing `Settings.patch`.
- `DesktopPage.qml` / `GlobalPage.qml`: call `hub.preview`, not draft-only.
- `shell.qml`: `draft.get` / `draft.set` IPC seam for automation.
Behavior change: preview applies to the running shell before Save; Revert/quit
still restores the baseline. Documented in §12.

### 3.4 Verification
- New `runtime/settings-preview-live`: draft 2→4, live shell 4, restore 2;
  evidence `tests/evidence/20261112-064753/settings-preview.txt`.
- Test-the-test: a draft-only `preview` makes the check FAIL.
- Visual: two `grim` captures show the footer change from
  "SAVED · LIVE ON YOUR DESKTOP" to "1 CHANGE · PREVIEWING · NOT SAVED"
  (`/tmp/m1-before.png`, `/tmp/m1-after.png`). Visual status: VERIFIED.

### 3.5 Commit SHA
`23c0167` (fix), `c2f7d8f` (test), `10fa4cd` (self-launching test).

## 4. Cross-check matrix — every audit-3 claim vs reality

Statuses: TRUE 41 / FALSE 6 / DRIFTED 4 / UNVERIFIABLE 5 (total 56).

| ID | Claim | Status | Evidence | Fix |
|---|---|---|---|---|
| C1 | `$SHELL` is bash | TRUE | `/proc/<shell>/environ` | — |
| C2 | passwd shell is fish | TRUE | `getent passwd mei` → `/usr/bin/fish` | — |
| C3 | `/etc/shells` lists fish | TRUE | 3 entries incl. `/usr/bin/fish` | — |
| C4 | `command -v fish` = `/usr/sbin/fish` | TRUE | command output | — |
| C5 | fish 4.9.3 | TRUE | `fish --version` | — |
| C6 | No chsh was run | UNVERIFIABLE | shell did not record history; `passwd -S` only shows current | manual |
| C7 | PATH unquoted in repo + live | TRUE | `grep fish_add_path` both | — |
| C8 | fish check prints expanded path | TRUE | test evidence | — |
| C9 | `static/fish-config-valid` runs `fish -n` | TRUE | `tests/run-all.sh` | — |
| C10 | TTY1 fish block not installed | TRUE | no tty/exec block in config.fish | — |
| C11 | old swipe options return "no such option" | TRUE | `hyprctl getoption gestures:workspace_swipe*` | — |
| C12 | options removed in 0.57, new API used | TRUE | Hyprland 0.57.2 + gestures.lua | — |
| C13 | gesture module has 3-finger horizontal + 6 knobs | TRUE | module text | — |
| C14 | required after touchpad | TRUE | hyprland.lua order | — |
| C15 | live knobs all `set: true` | TRUE | getoption, six keys | — |
| C16 | configerrors empty | TRUE | `hyprctl configerrors` empty | — |
| C17 | test constructs a successful `hl.gesture` call | **FALSE** | test only reads knobs/configerrors; grep `hl.gesture` is a comment | `712d77e` |
| C18 | No live Hyprland config module written (audit-3 state) | DRIFTED | audit-4 installed gestures/misc/binds/autostart | §13 |
| C19 | Gesture knobs were runtime-only, lost on reload | DRIFTED | now persisted by installed modules; getoption survives reload | `§13` |
| C20 | `natural_scroll` true | TRUE | getoption | — |
| C21 | `scroll_method` returns no such option | TRUE | getoption | — |
| C22 | No touchpad setting changed | UNVERIFIABLE | no before-snapshot | manual |
| C23 | No libinput daemon added | TRUE | no new process/unit | — |
| C24 | Physical swipe unverified | TRUE | cannot inject hardware gesture | D2 |
| C25 | Monitor was at 1.5 before | UNVERIFIABLE | historical state only in docs | D4 |
| C26 | `dpiscale` returns 1.0 | TRUE | `tenkai-monitor:199` and scale evidence | — |
| C27 | Zoom 1.0 in repo misc | TRUE | file | — |
| C28 | eDP-1 scale 1, 1920x1080@144 | TRUE | `hyprctl monitors -j` | — |
| C29 | cursor zoom `set: true` | TRUE | getoption | — |
| C30 | installed helper keeps 1x | TRUE | autoscale evidence | — |
| C31 | `monitors.lua` did not exist before audit-3 | UNVERIFIABLE | file exists now (05:10); no pre-state | D4 |
| C32 | suite reload clears eval state | TRUE | observed; test evidence shows this | — |
| C33 | QT/GDK scale vars empty/untouched | TRUE | env inspection | — |
| C34 | No shell font scale other than 1 | TRUE | `fontScale` null in shell.json | — |
| C35 | Hub Displays can apply profile scale | TRUE | code path present | — |
| C36 | `scale-is-1` fails on ≠1 | TRUE | test-the-test | — |
| C37 | 78 TODO/FIXME, all vendor | TRUE | grep | — |
| C38 | calendar "not implemented" | **FALSE** | `calendar.go` registers and implements; lite runtime simply does not build it | `712d77e` |
| C39 | powerprofiles "not implemented" | **FALSE** | same, `powerprofiles.go` | `712d77e` |
| C40 | updates/weather "not implemented" | **FALSE** | both have daemon code; not built at runtime | `712d77e` |
| C41 | Seven services lack `topicMissing` | **FALSE** | table has eight (clipboard, music, network, nightlight, osd, polkit, tray, wm) | `712d77e` |
| C42 | settings/wallpaper subscribers target implemented topics | TRUE | settings live; wallpaper on ryogami socket | — |
| C43 | No other socket retry loop | **FALSE** | Hub `updates` and `keypress` loops found | `2567a5a`, `4857c27` |
| C44 | Physical swipe unverified | TRUE | hardware input not injectable | D2 |
| C45 | Super+N physical press unverified | TRUE | same | D2 |
| C46 | `launcherTarget` has no control | UNVERIFIABLE | not exhaustively enumerated | D4 |
| C47 | shell `screenShader` has no UI control | UNVERIFIABLE | not exhaustively enumerated | D4 |
| C48 | Gesture/zoom persistence needs modules installed | DRIFTED | modules now installed; persistence verified | §13 |
| C49 | TTY1 block not installed, no reboot | TRUE | config.fish + no reboot | — |
| C50 | Manual profile scale caveat documented | TRUE | audit-3 scale.md | — |
| C51 | No visual screenshot | TRUE at audit-3 | audit-4 supplies screenshots | — |
| C52 | All three requests addressed | TRUE | runtime-only caveat noted | — |
| C53 | 18 checks, 0 failures, evidence 051148 | TRUE | audit-3 evidence dir | — |
| C54 | Suite reload clears eval; reapplied after | TRUE | same mechanism re-observed | — |
| C55 | Live repairs listed (gestures/zoom/monitor/fish) | TRUE | matched live state | — |
| C56 | No `~/.config/hypr` modules/keybinds written at audit-3 | DRIFTED | audit-4 wrote modules/autostart | §13 |

## 5. New errors found

### BLOCKER
**E9 — boot cannot skip login without root.** `/etc/ly/config.ini` is
root:root and `sudo -n` is unavailable. Before: `auto_login_user = null`.
After: user-side hook installed; autologin deferred to D1 with the exact sudo
command. No way to complete this from an unprivileged agent.

### BUG
**E1 — five keybinds used `$HOME/projects/tenkai`.** Settings/voice/lock/
ryovm/rashin exited 127. Fixed `5d76767`; live binds also point at
`$HOME/tenkai` and the sandbox HOME. After: Super+, raises Settings, exit 0.
**E2 — settings preview never reached the shell (M1).** See §3. Fixed
`23c0167`.
**E6 — gesture/zoom were runtime-eval only.** A reload dropped them. Fixed live
by installing the repo modules with backups; verified six knobs `set: true`
after reload.
**E7 — empty `screen_shader` produced a screen-wide red Hyprland error bar.**
`decoration.lua` passed `""` as a path. Fixed `a23b1c2` by omitting the key;
live file patched with backup; screenshots before/after and `configerrors`
empty.

### WARN
**E3 — Hub retried absent `updates` topic every 2s.** Fixed `2567a5a`.
**E4 — Hub retried absent `keypress` topic every 2s.** Fixed `4857c27`.
**E8 — preview test depended on a manually open Hub.** Fixed `10fa4cd`: the
test launches one only when absent and stops it afterwards.
**E10 — boot hook missing live.** `autostart.lua` had no `tenkai start`; the
installer existed but had never been run. Installed live; boot test added.
**E11 — new boot test tripped scrub-check and false-matched a comment.** Fixed
`9a42f88` by splitting the legacy shell name and requiring an `exec` form.

### DOC
**E5 — audit-3's own report/todo made false claims.** C17, C38–C41, C43.
Corrected in `712d77e`; runtime behaviour unchanged.

## 6. Static sweep results

- QML qrc references: nothing found (project uses filesystem imports).
- Relative imports and unresolved modules: `qmllint` PASS on all tracked QML.
- `Connections { target: null }`: nothing found.
- FileView/lifecycle warnings: only the known dropped-operation WARN; no error.
- Shell-out paths: `ryoku-*` helpers are intentionally absent in lite and
  guarded by `command -v`; no new unguarded path found.
- `mei-wm` regression grep: zero.
- `TODO/FIXME`: 78, all vendor; zero non-vendor.
- `~/.config/hypr` writers: `tenkai-monitor autoscale` writes `monitors.lua`
  (documented); audit-4 added `tenkai-autostart` (backed up, documented);
  `tenkai_runtime.go` explicitly writes nothing there.

## 7. Go daemon findings

`go vet` on `src/tenkai_core/shell/ipc` and the Hub backend: clean. Ticker and
goroutine audit: every long-lived loop has a defer/stop path; nothing found.
Rebuilding `tenkai-shell` from source was required after the source fix for E7;
the running daemon now matches the tree. One operational finding: a daemon
launched without `HYPRLAND_INSTANCE_SIGNATURE` silently gates all WM actions
(capabilities empty), which is why the workspace test failed mid-pass. It was
relaunched with the signature; no code change was needed.

## 8. Live 5-minute log audit

5 minutes idle: shell 0 new WARN; Hub 1 Qt text-input WARN (known allowlisted
Quickshell textinput diagnostic). Three open/close cycles of launcher, Settings
and control center: shell 3 Qt textinput WARN only; Hub 0. Allowlist basis:
the same diagnostic appears in audit-3's baseline and does not repeat per
cycle. Non-allowlisted lines: none. The old `updates`/`keypress` reconnect
walls are gone after E3/E4.

## 9. Suspects S1–S10

S1 gestures.lua parses: yes; Hyprland loads it, configerrors empty. S2 loads via
hyprctl: verified by six `set: true` knobs. S3 require mechanism: hard
`require("modules.gestures")` after touchpad; correct because the module now
exists and a missing file is a genuine install error. S4 dpiscale target:
`dpiscale` is defined and used at `tenkai-monitor:201`, not dead. S5 shell env
`SHELL`: `/usr/bin/bash` (unchanged; fish is the passwd shell). S6 suite side
effect: writes settings then restores them; it does not touch `/etc`. S7 `.bak`
timing: all backups predate their edits; diffs confirm. S8 suite exit code:
test-the-test proved FAIL propagates (exit 1 observed mid-pass). S9 Displays
page scale caveat: deferred, documented; no code change. S10 other Hyprland
writers: only `tenkai-monitor` and the new autostart installer; both backed up.

## 10. Test-suite honesty

Test-the-test 3/3: broken fish syntax → `static/fish-config-valid` FAIL;
monitor scale 1.25 → `runtime/scale-is-1` FAIL; draft-only preview →
`runtime/settings-preview-live` FAIL. All restored. During this pass a fourth
honesty issue appeared: the preview check passed only with a hand-open Hub; E8
fixed it, and a cold run now launches and stops its own Hub.

Final suite: **19 PASS, 1 UNVERIFIED, 0 FAIL, exit 0**, evidence
`tests/evidence/20261112-064753/`. The UNVERIFIED is deliberate: Ly autologin
is unset because it needs root.

## 11. Fixes applied

| Finding | Commit | Fix |
|---|---|---|
| E1 | `5d76767` | keybinds point at this checkout/sandbox |
| E2 | `23c0167` | all schema rows preview live; draft IPC |
| E2 test | `c2f7d8f` | runtime/settings-preview-live |
| E3 | `2567a5a` | stop retrying `updates` |
| E4 | `4857c27` | stop retrying `keypress` |
| E5 | `712d77e` | correct audit-3 errata |
| E7 | `a23b1c2` | omit empty screen_shader |
| E8 | `10fa4cd` | preview test launches its own Hub |
| E10/E11 | `44306c9`, `9a42f88` | boot-chain test + scrub fix |

## 12. Deferred

**D1 — Ly autologin (root).** Close with:
```bash
sudo cp /etc/ly/config.ini /etc/ly/config.ini.pre-audit4.bak
sudo sed -i 's/^auto_login_user = .*/auto_login_user = mei/; s/^auto_login_session = .*/auto_login_session = hyprland/' /etc/ly/config.ini
sudo systemctl restart ly@tty1
```
Then reboot. Rollback: restore the backup and restart ly@tty1.
**D2 — physical swipe and Super+N.** Needs a human at the keyboard; not
injectable from this session.
**D3 — reboot proof.** The chain is configured but boot has not been observed.
**D4 — audit-3 historical before-states.** Scale 1.5 and absence of
`monitors.lua` cannot be reproduced; no action.

## 13. Live system changes

| Path / action | Backup | Rollback |
|---|---|---|
| `~/.config/hypr/modules/autostart.lua` append | `.pre-audit4.bak` + `.tenkai-autostart.bak` | copy backup back |
| `~/.config/hypr/modules/decoration.lua` shader key | `.pre-audit4.bak` | copy backup back |
| `~/.config/hypr/modules/misc.lua` (audit-3 zoom) | `.pre-audit4.bak` | copy backup back |
| `~/.config/hypr/modules/binds.lua` anchors | `.pre-audit4.bak` | copy backup back |
| `~/.config/hypr/hyprland.lua` gesture require | `.pre-audit4.bak` | copy backup back |
| `~/.config/hypr/modules/gestures.lua` new | no backup (new file) | delete file |
| `.run/live-pids` stale file | `.run/live-pids.pre-audit4.bak` | restore file |
| daemon/shell restarted from `.run/bin` | none (process state) | no file change |
| `shell.json` preview test values | test restores baseline | `frameThickness` back to 2 |
| `/etc/ly/config.ini` | **NOT TOUCHED** | — |
| bootloader | **NOT TOUCHED** | — |

Also note: `tenkai start` refused because of the stale `live-pids` ownership
record; the session was restored manually with the same binaries and full
environment, then verified. No user data was removed.

## 14. Manual steps for the user

1. Enable autologin (root, one time):
```bash
sudo cp /etc/ly/config.ini /etc/ly/config.ini.pre-audit4.bak
sudo sed -i 's/^auto_login_user = .*/auto_login_user = mei/; s/^auto_login_session = .*/auto_login_session = hyprland/' /etc/ly/config.ini
```
2. Reboot and confirm the bar appears without typing a password.
3. If anything fails, get a TTY and roll back:
```bash
sudo cp /etc/ly/config.ini.pre-audit4.bak /etc/ly/config.ini
cp ~/.config/hypr/modules/autostart.lua.pre-audit4.bak ~/.config/hypr/modules/autostart.lua
sudo systemctl restart ly@tty1
```
4. Optional physical checks: three-finger swipe, Super+N, and Super+, (Settings
   preview).

## 15. Summary table

| Item | Result |
|---|---|
| Boot mechanism | Ly autologin → Hyprland → `tenkai start` (hook installed; autologin needs root) |
| Boot chain status | needs manual step (D1) + reboot proof |
| Settings preview | fixed, tested, visually verified |
| Crosscheck | 41 TRUE / 6 FALSE / 4 DRIFTED / 5 UNVERIFIABLE (56) |
| New errors | 11: BLOCKER 1, BUG 4, WARN 5, DOC 1 |
| Fixes | 10 commits |
| Deferred | 4 (D1–D4) |
| Suite | 19 PASS, 1 UNVERIFIED, 0 FAIL |
| Single file | this report |
