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
`hyprland.start` → `~/tenkai/tenkai start`, which brings up the daemon
and bar. Ly is already the only DM; this is the smallest complete chain.

### 2.2 Rejected mechanisms
A: no getty on tty1 (Ly conflicts), and it would replace a working DM.
C: SDDM absent. B: greetd absent. D: no rootless way to get a graphical session.

### 2.3 Files created/modified (repo)
- `tests/run-all.sh`: new `runtime/boot-chain-configured` check (commit
  `44306c9`, hardened in `9a42f88`). No shipped Hyprland file hardcodes this
  machine's checkout path; the existing `scripts/tenkai-autostart` remains the
  standalone helper. (`install.sh`'s own mechanism changed later in this pass,
  after the fresh-install transcript — see E12/§15.)

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
    hl.exec_cmd("~/tenkai/tenkai start")   -- expanded at session start
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
**E13 — a failed cmake configure wedged every later run.** `install.sh` run 2
configured without `-G Ninja` (ninja absent), leaving a Unix-Makefiles cache;
after installing ninja/gcc every later run died with "generator ... does not
match the generator used previously" and only a manual `rm -rf
.run/build/blobs` recovered. The error text blamed Qt6 alone, which sent the
user through four wrong `pacman` lines. Fixed: a failed configure now clears its
build dir before dying and names the real prerequisites. See §15.
**E12 — a fresh install did not boot into Tenkai.** The autostart step appended
the start hook to `~/.config/hypr/hyprland.lua`; the config-deploy step then
reinstalled that file from the checkout, so the hook survived only in a backup.
Fixed by a separate drop-in and by running the autostart step after the config
deploy (now steps 7 and 6; were 4 and 7). See §15.
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
| E7 | `a23b1c2`, `ccf188c` | omit empty screen_shader; reload on clear |
| E8 | `10fa4cd` | preview test launches its own Hub |
| E10/E11 | `44306c9`, `9a42f88` | boot-chain test + scrub fix |
| E12/E13 | this commit | fresh-install hook drop-in + cmake cache reset |

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

**D5 — the read-only compositor contract is superseded.** audit-5 changed
`docs/DECISIONS.md` §2: Hub controls now apply to Hyprland live (`hyprctl eval`)
and persist to `~/.config/hypr/tenkai_settings.lua`. The old wording
("Settings never writes Hyprland config", and the `errWMWriteDisabled` comment
in `src/tenkai_core/hub/backend/desktop.go`) is stale; see `docs/audit-5/report.md`
§5. Kept here so anything that cited the old contract lands on the new one.

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

## 15. Fresh-install transcript (`tenkaifinal.txt`, `tenkairun.txt`)

The user supplied a full fresh-Arch install transcript. Both files stay
untracked and were not modified; `tenkairun.txt` is the same session with lines
636–1270 pasted twice. The transcript exposed two defects the live machine
cannot show, because the live machine had been hand-patched.

**E12 — a fresh install does not boot into Tenkai.** The old autostart step
appended `hl.exec_cmd("<checkout>/tenkai start")` to
`~/.config/hypr/hyprland.lua`; the old config-deploy step then reinstalled that
file wholesale from `src/tenkai-configs/hypr/` (transcript: `overwrite
hyprland.lua (backup: hyprland.lua.tenkai-install.bak)`).
The hook survived only in the backup, so Hyprland started with no bar. The
"already exists" guard greps all of `~/.config/hypr`, so it happily matched that
backup and would never re-add the hook on a later run.

Fix: one drop-in, `~/.config/hypr/tenkai_autostart.lua`, loaded by
`optional("tenkai_autostart")` in the shipped `hyprland.lua`. The autostart step
now runs after the config deploy (step 7 after step 6; they were 4 and 7) and its
existence check reads live files only, never `*.bak`. An upgrade that overwrites
`modules/autostart.lua` therefore re-adds the drop-in instead of losing the
hook; the live machine's existing hook in `modules/autostart.lua` keeps working
unchanged. `runtime/boot-chain-configured` accepts either live location and now
fails if the shipped `hyprland.lua` stops loading the drop-in.

**E13 — a failed cmake configure wedges every later run.** Transcript: run 2
configured without `-G Ninja` (ninja not installed yet) and left a
Unix-Makefiles cache; after installing ninja/gcc, runs 3–4 died with
`generator : Ninja does not match the generator used previously: Unix
Makefiles`, and only `rm -rf .run/build/blobs` recovered. The die message blamed
Qt6 alone, which is why the user tried `gt6-shadertools`, `qt-t`, `qt-6multimedia`.
Fix: a failed configure removes its build dir first, and the message names the
real prerequisites (ninja, gcc, Qt6 Quick/ShaderTools/Multimedia).

Not a defect: `./tenkai start` printing `REFUSING: PID 863 still owns
org.freedesktop.Notifications` is the documented single-owner guard; the shell
had already been started by the new autostart hook, and the start completed once
that shell exited.

Test correction found on the way: `runtime/boot-chain-configured` read `$HOME`,
which this harness points at `.run/home` for the shell it starts, so on the last
run it reported the hook MISSING while the live hook sat in the login user's
home. It now
prefers the login user's passwd home when that has a `~/.config/hypr`.

Verification: `bash -n install.sh`, `bash -n tests/run-all.sh`, then
`bash tests/run-all.sh` → **15 PASS, 5 UNVERIFIED, 0 FAIL, exit 0**
(evidence `tests/evidence/20261112-083102/`). Four of the UNVERIFIED are the
live-shell checks: no shell was running for this run (the auditing session had
ended), so they say "no running shell" rather than PASS — this run does not
re-confirm the §3 preview result. The fifth is Ly autologin (D1).

`install.sh --dry-run --skip-build` against a throwaway `HOME` holding a
hook-less `hyprland.lua` confirmed the new order prints 1–9 in sequence and
step 7 offers to write `~/.config/hypr/tenkai_autostart.lua` with the absolute
checkout path. The fresh install itself was not replayed end to end: that needs
a throwaway machine, since a real run rewrites `~/.config/hypr` and
`~/.config/kitty`.

## 16. Summary table

| Item | Result |
|---|---|
| Boot mechanism | Ly autologin → Hyprland → `tenkai start` (hook installed; autologin needs root) |
| Boot chain status | needs manual step (D1) + reboot proof |
| Settings preview | shell keys fixed §3; brand keys fixed §29 (tested); visualizer has no consumer §31 F3 |
| Crosscheck | 41 TRUE / 6 FALSE / 4 DRIFTED / 5 UNVERIFIABLE (56) |
| New errors | 13: BLOCKER 2, BUG 5, WARN 5, DOC 1 |
| Fixes | 12 commits + this pass (§29) |
| Deferred | 4 (D1–D4) |
| Suite | 18 PASS, 1 UNVERIFIED, 0 FAIL (§30, three runs) |
| Single file | this report |

---

# Second pass — "i cant live edit the settings, the preview thing doesnt work"

## 27. Reproduction

Setup: Hub started from source with the daemon's own environment
(`HOME=.run/home`, `XDG_CONFIG_HOME=.run/config`, `QML2_IMPORT_PATH=.run/qml`,
`WAYLAND_DISPLAY=wayland-1`, the daemon's `HYPRLAND_INSTANCE_SIGNATURE`).

Method: IPC, because this box has no pointer injection (`wtype`, `wlrctl`,
`ydotool`, `xdotool` all absent). `draft set` is not a parallel mock: the Hub's
IPC handler calls the same `hub.preview(k, v)` a control's `onEdited` calls
(`shell.qml` target `draft`, `pages/DesktopPage.qml:173`,
`pages/GlobalPage.qml:116` → `SchemaPage.edited`). Clicking with a real pointer
is therefore *unverified*; the preview code path is verified.

| Case (IPC `draft set`) | draft | daemon / file | desktop | verdict |
|---|---|---|---|---|
| `frameThickness 2 → 8` (shell source) | 8 | `shell getSetting` = 8; `.run/config/tenkai/shell.json` = 8, <250 ms | bar frame repaints | preview works (§3) |
| `markText "M" → "Z"` (brand source) | "Z" | `brand.json` stays `"M"` | nothing changes | **preview dead** |
| any Visualizer row (`bars`, `style`, …) | changes | `visualizer.json` written only on Save | no consumer exists | **nothing can change** |

In all three the footer switches from "SAVED · LIVE ON YOUR DESKTOP" to
"1 CHANGE · PREVIEWING · NOT SAVED", i.e. the UI asserts a preview that did not
happen. Captures: `/tmp/hub-desktop.png` (footer), `/tmp/fix-before.png`,
`/tmp/fix-after.png`, `/tmp/overview-z.png`.

Prior claim checked: §3 is true for `shell`-source keys and was verified, but it
covered only `src === "shell"`. The Appearance page's BRAND card (Name, Text
mark, Logo image, Tint) and the whole Visualizer tab are *not* shell-source, so
the user's page still had no working preview. That is the gap here.

## 28. Diagnosis

| P | Hypothesis | Verdict | Evidence |
|---|---|---|---|
| P1 | edit mutates the shared draft object so the compare can't see it | NO | `edit()` rebuilds the map each call; `draft get` returns per-key values |
| P2 | page not wired to the hub | NO | `SchemaPage` → `edited` → `onEdited: hub.preview`; IPC reaches the same function |
| P3 | preview routes only some sources | **YES** | `preview()` had `src === "shell" ? stageLive : edit`; brand/viz fell to draft-only. Its comment claimed "the viz/brand files have no live consumer in the shell" — wrong for brand: `shell/services/Config.qml` `brandFile` watches `brand.json` (`watchChanges`, `atomicWrites`) and feeds `Config.markText/name/markTint` → `BrandMark` in launcher, overview, eyebrow |
| P4 | applied but unobservable | PARTLY | the Hub window covers the desktop except the bar, so compositor-level previews (Visuals page) can only be seen through the bar; the brand mark is drawn on launcher/overview, not the bar wordmark |
| P5 | exposed feature was cut | **YES (visualizer)** | `SpectrumField` appears nowhere under `shell/`; no reader of `visualizer.json`; viz rows can neither preview nor take effect on Save |

Root cause of the report: P3 for the brand keys (dead preview, live consumer
exists but was never written before Save), plus P5 for the Visualizer rows
(no consumer at all in this build) — with the footer claiming "PREVIEWING" in
both cases.

## 29. Fix

`src/tenkai_core/hub/quickshell/Hub.qml` only. The live ledger that already
served `shell.json` now also carries the brand keys that the shell really watches:

- `brandLiveKeys = ["name", "markText", "markImage", "markTint"]` (reloadCover
  excluded: the shell does not read it and Save owns the prune),
  `liveSrc(k)` helper, `liveKeys` = shell-source keys + those brand keys.
- `preview()` sends brand keys down `stageLive()` as well; `liveFlush` writes
  `brandA[k]` and issues one `brandFV.writeAdapter()` per coalesced batch — the
  same adapter/file Save uses, so the shell's watched `brandFile` repaints the
  mark before Save.
- `captureLiveBaseline()` reads `brandA` once the file is loaded (brand.json can
  arrive after the first daemon frame); `brandFV.onLoaded` re-anchors the ledger
  only when nothing is staged, so a preview write never moves the anchor.
- `restoreLiveUnsaved()` walks brand keys back through the adapter, which keeps
  Revert and close-on-quit restoring the saved state (the mechanism §3 relied on).
- No daemon change, no persistence change: Save still writes the same files
  through the same adapter; preview simply stops waiting for Save.
- Visualizer rows left untouched on purpose (P5): writing `visualizer.json`
  earlier would still change nothing, so the fix would be a lie; see §31 F3.

## 30. Verification

- `runtime/settings-preview-live` extended: it now also stages `markText`,
  reads the value out of `.run/config/tenkai/brand.json`, and asserts the file
  returns to the original when the draft does (Revert path).
- Test-the-test: with the old routing the same check logs
  `brand staged on disk=` / `M` and fails; with the fix it logs `Z` then `M`.
- Three consecutive full suites: **18 PASS, 1 UNVERIFIED (`runtime/boot-chain-configured`,
  ly autologin needs root), 0 FAIL** — evidence
  `tests/evidence/20261112-093922/`, `20261112-094020/`, `20261112-094051/`
  (`settings-preview.txt`: `before draft=2 target=4 … after draft=4 live=4 …
  brand before=M target=Z … brand staged on disk=Z … brand restored on disk=M`).
- Visual: `/tmp/overview-z.png` — overview eyebrow renders **Z TENKAI** while the
  Hub still shows "1 CHANGE · PREVIEWING · NOT SAVED"; setting the draft back to
  M restores the mark and the footer returns to SAVED.
- Limitation: no pointer injection on this machine, so the click path itself is
  UNVERIFIED; everything below the click (`hub.preview`) is what the test drives.

## 31. New findings (recorded, not fixed here)

- **F1 — Bar page has no editor.** "OPEN QS BAR SETTINGS" runs
  `tenkai-shell bar settings` → `qs ipc call qsbar settings ""`. The target
  exists (`qs ipc show` lists `qsbar.settings(route)`), the call returns ok, and
  no window appears; under the default `barStyle: "qsbar"` the Bar page shows
  only that dead button (the frame sliders are hidden for qsbar), so bar
  adjustments cannot be made at all. Separate fix.
- **F2 — Hub config root depends on the launcher's env.** `cfgDir` comes from
  `XDG_CONFIG_HOME`; started by the daemon it is `.run/config` (correct), started
  by hand without it the Hub reads/writes `$HOME/.config/tenkai` — a silent
  split brand/shell state. (This cost an hour of false repro during this audit.)
- **F3 — Visualizer rows are dead in this build** (P5). They neither preview nor
  apply on Save, because the desktop spectrum was cut. Left draft-only because
  the page has its own `VizPreview` card; decide label/disable/hide at owner level.
- **F4 — The preview is often invisible.** The Hub is full-screen (bar
  excepted), so compositor-level previews (gaps, blur, borders on the Visuals
  page) are hidden behind it. A preview strip or a pinned mini-canvas would make
  the promise visible.

## 32. Manual steps

1. `Super+,` → Appearance → change **Name / Text mark / Logo image / Tint**: the
   mark changes in the launcher, overview and eyebrows immediately, before Save.
   `REVERT` or closing the Hub puts the saved mark back.
2. The bar wordmark is "TENKAI", not the text mark — test the mark on the
   overview (`Super+Tab`/overview surface) rather than expecting the bar to change.
3. Appearance → Visualizer: the card is the only preview that exists for it; the
   desktop draws no spectrum in this build (F3).
4. Appearance → Bar: the settings button is still broken (F1).

## 33. Summary

| Item | Result |
|---|---|
| Preview reproduced | YES (IPC-driven; pointer UNVERIFIED — no injection tool) |
| Root cause | P3 for brand keys (`preview()` routed only `shell`), P5 for visualizer rows |
| Fix | one file, `Hub.qml`: brand keys join the live ledger (baseline, flush, restore) |
| Test | `runtime/settings-preview-live` extended to brand.json: 3 consecutive PASS |
| Suite | 18 PASS, 1 UNVERIFIED (root-owned ly autologin), 0 FAIL |
| Behaviour change | Appearance brand edits reach the running desktop before Save; Revert/quit still restore |
| Not done | visualizer live preview (no consumer), Bar editor button (F1), desktop preview pane (F4), push |
