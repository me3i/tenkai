# audit-5 — binding the shell to Hyprland

## 0. How to read this file

This pass answers one report: *"integrate tenkai to hyprland and also tenkai
install is supposed to do that, hyprland settings is not being edited so bound
the shell to hyprland"*.

The work is three deliverables (A live apply, B install binds the seam, C the
`DECISIONS.md` §2 contract) and the evidence for each. Numbers in §1 are raw
output from this machine; §3–§5 name the files and commits; §6 lists the tests
and three consecutive suite runs; §7–§8 are what was found but not fixed; §9 is
every live-system change (all restored or inside the checkout).

Read §2 first if you want the one-line answer: the seam existed and worked for
two keys, every other compositor control was routed somewhere else, and two
code paths silently dropped multi-level options.

## 1. Preflight — the binding failure, reproduced

Raw output: `docs/audit-5/preflight.txt`. State at start: branch
`audit-4/settings-preview-fix`, clean tree apart from two untracked transcripts;
`tenkai-shell` (pid) + `tenkai-wm-hyprland watch outputs` + `tenkai-wm-hyprland
watch` all running; `.run/bin/tenkai-wm-hyprland` present (6.6 MB);
`command -v tenkai-wm-hyprland` empty (it lives in `.run/bin`, not on a login
PATH); suite **18 PASS / 1 UNVERIFIED / 1 FAIL** — the FAIL was
`static/no-personal-strings` tripping on the audit-4 preflight transcript I had
committed (`/home/<user>/…`), fixed in `docs/audit-4/preflight-4.txt` and
re-verified with the three clean runs in §6.

### 1a. Which controls claim to touch Hyprland

`grep -rn 'wm\.act|Wm\.' src/tenkai_core/hub/quickshell` → the Hub uses no wm
calls; it drives the compositor through the backend verbs
`tenkai-hub desktop preview|save|restore|set`, raised by
`WindowManagerPage.qml` (`onEdited → hub.hyprEdit`), `VisualsPage.qml`
(its own `hyprctl eval`), `DisplaysPage.qml` (monitor rules) and the shell's
`setSetting` IPC. The Window Manager schema has 56 rows
(`schema/WindowSettings.js`); 37 were mapped to a compositor option.

### 1b–1c. The three settings

Run against the live session (`HYPRLAND_INSTANCE_SIGNATURE` from the daemon's
`/proc/<pid>/environ`), values read with `hyprctl getoption`:

```
== shell setSetting('screenShader')          (dedicated setter, Wm.setScreenShader)
qs ipc --pid <shell> call shell setSetting screenShader '"vignette"'
  before: {"option":"decoration:screen_shader","str":"","set":true}
  after : {"option":"decoration:screen_shader",
           "str":"/home/<user>/.run/home/.config/hypr/shaders/vignette.glsl","set":true}
  => APPLIED. The wm seam itself is alive (Wm -> daemon -> tenkai-wm-hyprland -> hyprctl).

== shell setSetting('desktop.appearance.gapsIn')   (generic setting)
  before: css gap data: 12 12 12 12
  qs ipc ... setSetting desktop.appearance.gapsIn 13   ->  ok
  after : css gap data: 12 12 12 12                     => NOT APPLIED
  (the value was persisted: shell.json gained a "desktop" object)

== shell setSetting('desktop.appearance.blurEnabled')
  before: bool: true
  setSetting ... false -> ok
  after : bool: true                => NOT APPLIED
```

And the Hub's own backend path, called exactly as the page calls it:

```
tenkai-hub desktop preview '{"desktop":{"appearance":{"gapsIn":9}}}'
  -> {"applied":1,"errors":null,"ok":true}
hyprctl getoption general:gaps_in -> css gap data: 9 9 9 9     => APPLIED
```

So the failure is not the compositor, the provider, or eval: it is **routing**.
The Hub page's `desktop preview` reaches Hyprland; the shell's generic
`setSetting` does not, and 19 of the page's 56 rows have no mapping at all.

### 1d. Caps / binary / mode

```
tenkai-wm-hyprland caps
  {"name":"hyprland","version":"v0.57.2", …,
   "supports":[… "screenShader","monitors","tiledLayout" …],
   "settingDomains":["desktop","wm.hyprland"], …}
```
Binary present, caps true, provider already running. `hyprctl keyword` on this
compositor answers `unknown request` (Lua config manager, documented in
`docs/audit-3/gestures.md`); every working path already uses `hyprctl eval`.
Layer that fails: the **shell/backend setting path** (and the install that never
proved the binding).

## 2. Diagnosis — the layer that broke

| Layer | State | Proof |
|---|---|---|
| Hyprland + Lua eval | works | gaps/shader changed live from `hyprctl eval` and from `tenkai-hub desktop preview` |
| `tenkai-wm-hyprland` provider | installed, running, caps true | `caps` output in §1d; `watch` processes in preflight |
| `Wm.setScreenShader` (shell) | works | shader path visible in `hyprctl getoption` (§1b) |
| `Config.patch` / `setSetting` for `desktop.*` | **broken** | value persisted, compositor unchanged (§1c) |
| hub backend `advancedLua` | **broken for nested sections** | it emitted `blur = { size = 4 }, blur = { passes = 1 }`; Lua keeps the last duplicate key, so all blur/shadow/snap siblings but one were dropped. Found while wiring the new keys, reproduced in the generated drop-in, fixed in §3 |
| hub backend mapping table | **incomplete** | 19/56 Window Manager rows had no `advancedOptions` entry: layout, blur special/popups/vibrancy_darkness, shadow colour/scale/sharp, border colours, plus rows Hyprland has no option for (wobbly windows, window style, glow, tame-maximize) |
| install.sh | **never binds** | no step verifies the provider or dispatches through it; `hyprland.lua` had no `tenkai_settings` drop-in; a fresh install could deploy a read-only view |
| contract | **stale** | `DECISIONS.md` §2 said "Settings never writes Hyprland config", which is what produced the routing above |

## 3. Deliverable A — live apply

Files:

- `src/tenkai_core/hub/backend/tenkai_runtime.go`
  - `advancedOptions` gains the real Hyprland options the page already exposes:
    `layout` (`general:layout`), `blurSpecial`, `blurPopups`,
    `blurVibrancyDarkness`, `shadowColor`, `shadowScale`, `shadowSharp`,
    `activeBorder`, `inactiveBorder`. Keys Hyprland has no option for stay out
    and are reported through the existing `unhonored` verb.
  - `advancedColors` + `luaRGB`: stored `#rrggbb` becomes `rgb(rrggbb)`; border
    colours are skipped while `borderFollowsPalette` is true (the palette owns
    them, matching the provider's own rule).
  - `advancedLua` renders one nested table per section through a small `luaTree`
    instead of repeating `blur = {…}` per key — the bug that silently dropped
    every neighbouring option in a nested section.
  - `writeTenkaiSettingsDropIn`: on Save, the same scripts are written to
    `~/.config/hypr/tenkai_settings.lua` (atomic, previous content kept as
    `.bak`). Live apply still happens through `hyprctl eval` only.
  - `applyTenkaiDesktopKey`: merge one dotted leaf into the saved map and
    re-apply the whole map — the one-key entry point.
- `src/tenkai_core/hub/backend/desktop.go`: new verb
  `tenkai-hub desktop set <dotted.key> <json>`.
- `src/tenkai_core/shell/quickshell/shell/shell.qml`: `setSetting(path, value)`
  routes any `desktop.*` path to `tenkai-hub desktop set`, so the IPC method and
  the Hub control are the same action.
- `src/tenkai_core/hub/quickshell/Hub.qml`: `srcOf` now also reads the Window
  Manager schema, and `preview()` routes `desktop.json` keys through
  `hyprEdit` (the ledger that already throttles `desktop preview`), so a page
  edit applies live like the brand keys did in `c454590`.

The provider (`src/tenkai_core/wm/hyprland/`) needed no change: it already
dispatches with `hyprctl eval` (`session.go: evalLua`, `act.go`) and never uses
`hyprctl keyword`; `caps` reports the session. Its `keyword`-mode fallback is
the shipped `config_settings.go` path for a hyprlang session.

Behaviour now, for a control on the Window Manager page: edit → draft →
`hyprDraft` → throttled `tenkai-hub desktop preview` → `hyprctl eval` →
compositor. Save → same apply **plus** `~/.config/tenkai/hypr-advanced.json`
and `~/.config/hypr/tenkai_settings.lua`. Revert/quit → `desktop restore`
re-applies the saved map. Boot → the daemon's `overrides apply` re-applies the
store (unchanged), and Hyprland itself now loads the drop-in.

Proven end-to-end through the Hub's own edit path (IPC drives `hub.preview`,
which is what a click calls):

```
qs ipc --pid <hub> call nav open windowmanager
qs ipc --pid <hub> call draft set desktop.appearance.gapsIn 6
  before=css gap data: 12 12 12 12   after=css gap data: 6 6 6 6
  (set back to 12: css gap data: 12 12 12 12)
```

## 4. Deliverable B — install.sh binds the shell

New **step 8 "Hyprland binding (shell → compositor)"** (steps 9/10 are wallpapers
and fonts; `STEP_TOTAL=10`), after the config deploy and the autostart step:

- verifies `$SYS_GO_BIN/tenkai-wm-hyprland` exists and is executable, and says
  which step builds it if not;
- requires `hyprctl` and `HYPRLAND_INSTANCE_SIGNATURE` (reports "not a live
  Hyprland session" instead of pretending);
- reads `general:gaps_in`, probes `hyprctl keyword general:gaps_in <same>`, and
  prints the mode it detected (`keyword` or `eval`) — on this compositor it
  prints *"hyprctl keyword is unavailable here (Lua config manager) — using
  hyprctl eval"* with keyword's own message;
- dispatches that unchanged value through the shell's real path,
  `tenkai-hub desktop set desktop.appearance.gapsIn <same>`, and reports
  `ok`/failure with the backend's message. Nothing changes on screen;
- `--dry-run` prints the plan and runs no hyprctl; `--yes-wm-bind` answers the
  prompt; the default prompts, and a refusal prints the exact command to close
  it later.

Step 6 also seeds `~/.config/hypr/tenkai_settings.lua` from the new shipped
template (`src/tenkai-configs/hypr-dropins/tenkai_settings.lua`) **only when it
does not exist**, and the shipped `src/tenkai-configs/hypr/hyprland.lua` now
`optional("tenkai_settings")`s it next to `optional("settings")`.

Upgrade path for an existing install:

```bash
cd ~/tenkai && ./install.sh --skip-build --yes-wm-bind
```

## 5. Deliverable C — DECISIONS.md §2 rewrite

Old (verbatim):

> ## 2. Settings never writes Hyprland config
>
> Disabled in the hub backend: the Settings app persists to Tenkai's own config
> dir and reads Hyprland state only. …

New: **"§2 Settings apply to Hyprland live, and persist only to Tenkai-owned
drop-ins"** — live apply through the wm seam (`hyprctl eval` under the Lua config
manager, `keyword` otherwise, mode probed and cached), persist only to
`tenkai_settings.lua` + `tenkai_autostart.lua`, never to hand-edited modules
(`binds.lua`, `decoration.lua`, `modules/*.lua`, `monitors.lua`, `keyboard.lua`,
`user.lua`), read always through `hyprctl`. It records why it was rewritten (the
read-only contract made the controls inert). `docs/ROLLBACK.md` gained step 8 and
the runtime `tenkai_settings.lua` rows; `docs/audit-4/audit-report.md` §12 gained
**D5** pointing at this rewrite.

The choice is deliberate and bounded: the shell now *writes a file* in
`~/.config/hypr`, so the file is Tenkai-owned, regenerated, backed up, and
listed in ROLLBACK — while the user's own modules are still never edited.

## 6. Tests

| Check | What it proves |
|---|---|
| `runtime/hyprland-live-apply` (new) | reads `hyprctl getoption` for `general:gaps_in`, `decoration:blur:enabled`, `decoration:blur:special`; calls `shell setSetting` for each; waits 1 s; asserts the compositor reflects it; restores through the same path and asserts the restore |
| `runtime/install-probes-wm-bind` (new) | `./install.sh --dry-run` prints the binding step and its prompt (no writes, no hyprctl) |
| `static/decisions-md-says-live-apply` (new) | `docs/DECISIONS.md` §2 says "Live apply" and names the drop-in, and its heading is no longer the read-only one |
| `runtime/settings-preview-live` | unchanged, still passes (the brand fix from `c454590` is untouched) |

Three consecutive full runs, `bash tests/run-all.sh`:

| Run | Result | Evidence |
|---|---|---|
| 1 | 22 PASS, 1 UNVERIFIED, 0 FAIL | `tests/evidence/20261112-101805/` |
| 2 | 22 PASS, 1 UNVERIFIED, 0 FAIL | `tests/evidence/20261112-101844/` |
| 3 | 22 PASS, 1 UNVERIFIED, 0 FAIL | `tests/evidence/20261112-101923/` |

The UNVERIFIED is `runtime/boot-chain-configured` (ly autologin is root-owned,
unchanged from audit-4). `runtime/hyprland-live-apply` also refuses to report
success without a live session, rather than passing vacuously.

## 7. New findings

- **E1 — the page opens on provider defaults, not on the live compositor.**
  `tenkai-hub desktop get` returns the provider's `defaults` merged with
  Tenkai's store; it never reads `hyprctl getoption`. On this box the page said
  gaps 12 while the compositor was at 11 (and 9 during an earlier probe). A user
  who touches one slider and saves writes defaults for every other mapped key.
  Closing move: overlay live `getoption` values in `getDesktop()` (42 reads, or a
  lazily-read cache), then drop the overlay from the drop-in writer.
- **E2 — `desktop save` writes the whole advanced map.** Because of E1 the map
  starts from defaults, so the first Save persists 42 keys, not the one changed.
  Same fix as E1.
- **E3 — `hyprctl keyword` failure is silent in the provider's fallbacks.**
  `config_settings.go` still emits a `hyprctl setcursor` for cursor changes;
  it is harmless here (exec_cmd) but the same class of call is what audit-3
  found dead. Recorded, not needed for this pass.
- **E4 — the Window Manager page has no live readback**, so Revert puts the
  draft back on the compositor but the rows only refresh on reopen.

## 8. Deferred

- **D1 — visualiser surface** (from audit-4 §31 F3) is still cut; unchanged.
- **D2 — Bar editor button** (`OPEN QS BAR SETTINGS` no-ops): separate from this
  pass; the `qsbar.settings(route)` target exists but raises no window.
- **D3 — displays**: `desktop set` covers the appearance map; `hl.monitor` has
  its own writer (`applyDisplays`, `tenkai-monitor`). The Displays page was not
  re-verified here. Close with: `tenkai-hub displays apply --json '<layout>'`
  then `hyprctl monitors`.
- **D4 — modifiers with no Hyprland option** (wobbly windows, window style,
  glow, tame-maximize, animated border) stay stored-only and are reported by
  `tenkai-hub desktop unhonored`. Do not invent options for them.
- **D5 — reboot proof** of `optional("tenkai_settings")` needs a session start.
  Manual: `hyprctl reload` (or reboot) then
  `hyprctl getoption general:gaps_in` must show the saved value before
  `tenkai-shell` starts (that is what the drop-in is for).

## 9. Live system changes

Nothing outside `/home/<user>/tenkai` was written, so no `.pre-audit5.bak`
backups were needed. Changes visible to the session:

| What | Where | State |
|---|---|---|
| rebuilt `tenkai-hub` (new verb, mapping, drop-in) | `.run/bin/tenkai-hub` | in place; the checkout builds it, no backup (regenerated by install.sh step 2) |
| `hyprctl eval` runs during reproduction and tests | running Hyprland | `general:gaps_in`, `decoration:blur:enabled`, `decoration:blur:special`, `decoration:blur:popups`, `decoration:shadow:sharp`, `general:layout`, `decoration:screen_shader` were changed and **all restored**; final state: gaps 11, blur on, blur special/popups off, shadow sharp off, layout dwindle, shader empty — the state found at the start |
| test-created store + drop-in | `.run/config/tenkai/hypr-advanced.json`, `.run/config/hypr/tenkai_settings.lua(+.bak)` | **removed** after the runs (§1–§6); a real Save recreates them |
| `docs/audit-4/preflight-4.txt` redaction | in-repo | replaced `/home/<user>` with `<home>`; this is what makes `static/no-personal-strings` pass again |

`hyprctl keyword general:gaps_in` was run once by the probe (step 8 asks it) —
it fails by design on this compositor and changes nothing.

## 10. Manual steps for the user

1. Bind an existing install:
   ```bash
   cd ~/tenkai && ./install.sh --skip-build --yes-wm-bind
   ```
   It should print `hyprctl keyword is unavailable here (Lua config manager)`,
   then `wm binding works: … general:gaps_in=<current>`.
2. Verify live apply by hand:
   ```bash
   hyprctl getoption general:gaps_in
   qs ipc --pid "$(pgrep -f '^qs -p .*/shell/quickshell/shell$' | head -1)" \
      call shell setSetting desktop.appearance.gapsIn 9
   hyprctl getoption general:gaps_in        # must say 9
   ```
3. In the Hub: Window Manager → change Inner gaps / Blur / Layout; the desktop
   changes while the Hub is open (only the bar is visible behind it), `SAVE`
   writes `~/.config/hypr/tenkai_settings.lua`, `REVERT` puts it back.
4. After a reboot (D5), `hyprctl getoption general:gaps_in` should already show
   the saved value before the shell starts; if not, the drop-in is not loaded —
   check `hyprland.lua` has `optional("tenkai_settings")` and
   `hyprctl configerrors`.
5. Displays (D3) were not re-verified in this pass.

## 11. Summary

| Item | Result |
|---|---|
| Binding reproduced | YES — `setSetting desktop.appearance.gapsIn/blurEnabled` persisted but never reached the compositor; 19/56 Window Manager rows had no mapping; `advancedLua` dropped all but one key per nested section |
| Root cause | routing: the shell's generic setting path patched shell.json only; install never proved (or set up) the binding; the contract forbade the apply |
| Deliverable A (live apply) | fixed — 13 more options mapped, nested tables fixed, `tenkai-hub desktop set`, `setSetting` on `desktop.*`, Hub preview routing |
| Deliverable B (install.sh binds) | fixed — step 8 probe + mode detection + real dispatch; drop-in seeded; `optional("tenkai_settings")` |
| Deliverable C (DECISIONS §2) | rewritten, with ROLLBACK and audit-4 D5 updated |
| Tests | 3 added (`runtime/hyprland-live-apply`, `runtime/install-probes-wm-bind`, `static/decisions-md-says-live-apply`) |
| Suite | 22 PASS, 1 UNVERIFIED, 0 FAIL — three consecutive runs |
| New errors | 4 (E1–E4) |
| Deferred | 5 (D1–D5) |
| Live state | restored; test artifacts removed; nothing written outside the checkout |
| Pushed | no |
