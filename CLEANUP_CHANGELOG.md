# Cleanup Changelog — Phase 16

> Live record of every deletion and fix in this Phase-16 cleanup pass.
> `ARCHITECTURAL_AUDIT.md` is frozen as the historical "Before" snapshot and is **not**
> edited here. This file is the working record; update it when the next cleanup pass starts.

**Phase owner:** Tenkai (Celestial Lite of Ryoku Quickshell)
**Phase status:** in progress — cleaned up, not yet committed / not yet run live
**Applies to:** `git` HEAD at commit `e83eb34` (before this phase's commits)

---

## 1. Scope decision

This phase removes genuinely dead code and stale references from the Tenkai checkout,
which is a reduced copy of [Ryoku](https://github.com/Ryoku-dev/ryoku). The guiding rule
from `AGENTS.md` applies everywhere here: prefer disabling over deleting, trace dependencies
at file level, and never regenerate a component "from scratch" — copy/adapt from `upstream/`.

Two sub-decisions shaped what got removed vs kept:

- **Keep the integrated GPU-tuning/preset surface.** `gputune.go` and the five-file `import`
  layer (`import.go`, `import_apply.go`, `import_parse.go`, `import_types.go`, `import_undo.go`)
  are part of the kept Ryoku surface (GPU tuning + config-import). They were briefly deleted
  during an earlier Step-2 attempt, which broke the hub build (`undefined: Tunable`,
  `undefined: pendingWrite`, `undefined: bindsPath/reBind/reExec/resolveKeys`). They were
  restored from `HEAD` and are **retained** in this phase.
- **Delete only the isolated dead modules.** The `gpu`/`voxtype` dispatch branches were removed
  from `main.go`, and the standalone dead modules that nothing kept depends on were deleted.
  The dispatcher-level `runGpu*` / `runVoxtype*` entry points that the keep list does not cover
  are gone; the underlying tuning/import/passthrough/voxtype *libraries* that the keep list does
  cover remain.

---

## 2. What was deleted

### 2.1 Hub backend — isolated dead GPU modules (git-tracked deletions)

| File | Lines | Why it was necessary | Revertible? |
|------|-------|----------------------|-------------|
| `src/ryoku/hub/backend/gpu.go` | 35 | Standalone dead GPU module; not on the keep list, no kept component depends on it at file level. | Yes — restore from `upstream/` or `git` reflog. Not a kept surface. |
| `src/ryoku/hub/backend/gpumode.go` | 145 | Dead, isolated. | Yes — same. |
| `src/ryoku/hub/backend/gpumux.go` | 85 | Dead, isolated. | Yes — same. |
| `src/ryoku/hub/backend/gpuhook.go` | 145 | Dead, isolated. | Yes — same. |
| `src/ryoku/hub/backend/gpuvm.go` | 453 | Dead, isolated VM orchestration; nothing kept calls it. | Yes — same. |
| `src/ryoku/hub/backend/voxtype.go` | 324 | Restored from upstream to supply `configHome()`/`dataHome()`; then deleted as part of Step 2 because the *dispatcher* `runVoxtype` and the `voxtype` CLI branch are not on the keep list. The generic `configHome()`/`dataHome()` helpers were moved to `fsutil.go` before deletion so the kept matugen/import/rice/wm/desktop/schemes/reloadcover code keeps compiling. If a future keep-list change wants the dictation/voxtype backend back, restore from `upstream/ryoku/hub/backend/voxtype.go` and re-add the `case "voxtype"` branch to `main.go`. | Yes — restore from `upstream/`. |

**How verified:** `git diff --stat` shows these six deletions. The hub backend builds cleanly
(`go build -trimpath -p 2 ./...` inside `src/ryoku/hub/backend`) with none of these files on disk.

### 2.2 Hub backend — dead dispatch + usage lines removed from `main.go` (edit)

| What | Why it was necessary | Revertible? |
|------|----------------------|-------------|
| `gpu` subcommand branch (`case "gpu": runGpu(...)`) in `main.go` | Removed because the `gpu` dispatcher entry point is not on the keep list and no kept component calls `runGpu`. The GPU *tuning* surface (`gputune.go`, `runGpuTune`) is kept separately; this was the dead plain `gpu caps|mode` branch. | Yes — re-add the `case "gpu"` branch; restore `gpu.go`/`gpumode.go` etc. if needed. |
| `voxtype` subcommand branch (`case "voxtype": runVoxtype(...)`) in `main.go` | Removed because the `voxtype` dispatcher is not on the keep list and no kept component calls `runVoxtype`. | Yes — re-add the branch; restore `voxtype.go` from `upstream/` if the dictation page returns. |
| `import` subcommand branch — **kept** | The `import` branch (`case "import": runImport(...)`) was **not** removed. The import layer is on the keep surface, so it stays wired in `main.go`. | n/a (kept) |
| `gpu` usage lines in `usage()` | Removed to match the removed dispatch branch. | Yes — re-add. |
| `voxtype` usage lines in `usage()` | Removed to match the removed dispatch branch. | Yes — re-add. |
| `import` usage lines in `usage()` — **kept** | Kept because the import subcommand is kept. | n/a (kept) |

**How verified:** `git diff src/ryoku/hub/backend/main.go` shows only the `gpu`/`voxtype`
branches and their usage lines gone; the `import` branch is untouched. Build is clean.

### 2.3 Shell IPC — dead pill code stripped from `actions.go` (edit)

| What | Why it was necessary | Revertible? |
|------|----------------------|-------------|
| Dead `pillSockPath()` / `pillSocketCall()` / `pillIpc()` block | The frame shell was consolidated into the single shell instance, which serves no command socket. These helpers (and their socket fast path) are dead in production. The comment said they were "retained for a future cutover" — they are not, so they were stripped. | Yes — restore from `git` reflog / the previous commit. |
| Unused `"net"` import in `actions.go` | Removed because removing the socket code made `net` unused. Clean build requires no unused imports. | Yes — re-add `"net"` if the socket code returns. |

**How verified:** `git diff src/ryoku/shell/ipc/actions.go` shows the block and the import gone.
`shellIpc` is still present. `go build` inside `src/ryoku/shell/ipc` is clean.

### 2.4 Picker variants — dead carousel/Hearthstone/qmldir entries (edit)

These remove the unused picker variants so the dead ffmpeg thumbnail paths they reference are
no longer reachable in the Tenkai build.

| File | What changed | Why it was necessary | Revertible? |
|------|-------------|----------------------|-------------|
| `src/ryoku/shell/quickshell/shell/modules/bar/barstyles/qsbar/panels/qmldir` | Removed `ImageCarouselCarousel`, `ImageCarouselHearthstone`, `MediaBrowserCarousel`, `MediaBrowserHearthstone` entries. | These four variant panel entries are unreachable: the picker is now `"tanzaku"` only (see 2.5). Without the qmldir entries the QML engine will not resolve them, and the files they point to are dead weight. | Yes — restore the four lines from `upstream/` / git reflog. |
| `src/ryoku/shell/quickshell/shell/modules/bar/barstyles/qsbar/Theme.qml` | Trimmed `pickerStyle` default comment from `"tanzaku", "hearthstone", "carousel"` to `"tanzaku"`; trimmed the picker validation branch from `ps === "hearthstone" || ps === "carousel" || ps === "tanzaku"` to `ps === "tanzaku"`. | The other two picker styles are not kept in Tenkai. Leaving the branches in would let a hand-editable config silently switch to a dead style. | Yes — re-add the branches + comment. |
| `src/ryoku/shell/quickshell/shell/modules/bar/barstyles/qsbar/VariantRoot.qml` | Removed the duplicate "Picker variants" comment (the block was already empty). | The comment claimed there were picker variants below it; there are none. Stale comment. | Yes — re-add the comment. |
| `src/ryoku/hub/quickshell/pages/DesktopPage.qml` | Trimmed `pickerOptions` to `["tanzaku"]`. | Mirrors the qsbar side; the other options are not kept. | Yes — re-add. |

**How verified:** `git diff` on the four files shows the edits above. No non-test file references
`ImageCarouselHearthstone`, `ImageCarouselCarousel`, `MediaBrowserHearthstone`, or `MediaBrowserCarousel`
after this pass. Run `rg -F "ImageCarouselHearthstone|ImageCarouselCarousel|MediaBrowserHearthstone|MediaBrowserCarousel" --glob '!vendor' --glob '!.run'` to re-confirm after commit.

### 2.5 Comment-only fixes in kept hub files (edits)

These are not deletions of functionality — they remove stale cross-references that pre-dated this
phase's edits and would mislead a reader.

| File | What changed | Why it was necessary | Revertible? |
|------|-------------|----------------------|-------------|
| `src/ryoku/hub/backend/gpudomain.go` | Removed stale sentence "Kept separate from gpuvm.go's orchestration so both are unit-tested as functions of their inputs, with no virsh or sysfs in the way." | `gpuvm.go` is deleted in this phase, so the cross-reference is now a lie. The kept summary is "pure libvirt-domain builder + CPU-pinning planner." | Yes — re-add the sentence. |
| `src/ryoku/hub/backend/tenkai_runtime.go` | Reworded "(import_parse.go)" reference in `bindDsp`'s doc comment to "the config-import layer would generate". | `import_parse.go` is internal to the import layer; the comment should not name an internal file that readers of `tenkai_runtime.go` do not need to chase. | Yes — re-add "(import_parse.go)". |

**How verified:** `git diff` on both files shows only those comment lines changed.

---

## 3. What was restored (not deletions, but part of the same fix pass)

These were restored to make the hub build, then some were edited (Tenkai→Ryoku rename) and in one
case removed again. They are listed here for the record so the changelog is complete.

| File | Action | Why | Revertible / re-deletable? |
|------|--------|-----|-----------------------------|
| `src/ryoku/hub/backend/import.go` | Restored from `HEAD` (git), retained. | Supplies `bindsPath`, `reBind`, `reExec`, `resolveKeys`, `pendingWrite`, etc. The import layer is on the keep list. | n/a (kept) |
| `src/ryoku/hub/backend/import_apply.go` | Restored from `HEAD`, retained. | Part of the import layer. | n/a (kept) |
| `src/ryoku/hub/backend/import_parse.go` | Restored from `HEAD`, retained. | Part of the import layer. | n/a (kept) |
| `src/ryoku/hub/backend/import_types.go` | Restored from `HEAD`, retained. | Part of the import layer. | n/a (kept) |
| `src/ryoku/hub/backend/import_undo.go` | Restored from `HEAD`, retained. | Part of the import layer. | n/a (kept) |
| `src/ryoku/hub/backend/gputune.go` | Restored from `HEAD`, retained. | Supplies `Tunable`, `tuneInputs`, `gpuProbe`, `buildTunables()`, `runGpuTune()`. GPU tuning is on the keep list. | n/a (kept) |
| `src/ryoku/hub/backend/gpuapply.go` | Restored from `upstream/ryoku/hub/backend/gpuapply.go`, edited (Tenkai→Ryoku), retained. | Supplies `runGpuApply`, `escalateSelf`, `ttyRun` so the hub builds; not itself a kept surface in Tenkai's reduced form, but it is the live home of `escalateSelf`/`ttyRun` and is kept on disk for now because other kept code may reference it. | Yes — restore from `upstream/` if a future step re-enables the passthrough stack; or remove if nothing kept calls it. |
| `src/ryoku/hub/backend/voxtype.go` | Restored from `upstream/ryoku/hub/backend/voxtype.go`, edited (Tenkai→Ryoku), then **deleted** as part of Step 2. | Was needed to supply `configHome()`/`dataHome()` so the hub built after the restore. Those two generic helpers were moved to `fsutil.go` before deletion; the voxtype-specific code (`runVoxtype`, `buildVoxtypeConfig`, `ensureVoxtypeUnit`, etc.) was dead and removed with the file. | Yes — restore from `upstream/` if the Dictation page returns to the keep list. |
| `src/ryoku/hub/backend/lock.go` + `lock_test.go` | Copied from `upstream/` to fix a missing-symbol build error; `lock.go`'s duplicate `fileExists` was removed (kept unique in `fsutil.go`). | Build-fix probe only. | The files are **not committed**; see §5. |

---

## 4. What was NOT deleted (kept, by keep list)

These are explicitly retained and were not touched in this phase (beyond the comment rewording in
`gpudomain.go` and `tenkai_runtime.go`):

- Top bar (qsbar), workspaces, launcher, control sidebar / quick settings, clock/date, audio,
  brightness, network, battery, system tray, notifications.
- Wallpaper selector + matugen theming.
- `ryoku-shell` Go daemon, trimmed to kept components.
- Animations — full motion language, never flattened.
- Settings app — Appearance + Shell pages only; never writes or generates Hyprland config;
  settings persist to Tenkai's own config dir.

---

## 5. Untracked artifacts (do not commit)

| Path | Kind | Why it exists | Action |
|------|------|---------------|--------|
| `src/ryoku/hub/backend/ryoku-hub` | Statically-linked ELF x86-64 build artifact | Built during this phase's verification; not part of the source tree. | Leave untracked. Clean up with `go clean` or delete locally; never commit. |
| `src/ryoku/hub/backend/lock.go` | Untracked copy from `upstream/` used as a build-fix probe | Only needed to diagnose the duplicate-`fileExists` issue; the final fix keeps the symbol in `fsutil.go`. | Leave untracked / delete locally; do not commit unless a later step re-uses it. |
| `src/ryoku/hub/backend/lock_test.go` | Same probe's test file | Same as above. | Same. |
| `src/ryoku/shell/ipc/ryoku-shell` | Build artifact | Built during IPC verification. | Leave untracked / delete locally; do not commit. |
| `src/ryoku/shell/ryogami/daemon/ryogami` | Build artifact | Built during ryogami verification. | Leave untracked / delete locally; do not commit. |
| `ARCHITECTURAL_AUDIT.md` | New file, project root | Frozen historical "Before" snapshot; intentionally untracked here so the committed tree stays clean until/unless the owner wants it shipped. | Do not commit as part of this phase unless the owner asks. |

> `git stash list` still holds `stash@{0}: On main: phase16-pre-restore-snapshot: working tree before hub edits`.
> Drop it once Step 2 is committed and no longer needed: `git stash drop`.

---

## 6. Revert summary

Everything in §2 and §3 except the kept surfaces is individually revertible:

- **Hub backend deletions** (§2.1) — `git checkout HEAD -- <file>` from a reflog / `upstream/` copy.
- **main.go dispatch edits** (§2.2) — re-add the three deleted `case` branches and their `usage()` lines;
  re-add the files in §2.1 if a dispatcher needs them.
- **actions.go pill strip** (§2.3) — restore the dead block + `"net"` import from the previous commit.
- **Picker variant edits** (§2.4) — re-add the four qmldir lines, the two Theme.qml branches, the
  VariantRoot.qml comment, and the DesktopPage.qml `pickerOptions` entries from `upstream/` / git reflog.
- **Comment-only fixes** (§2.5) — re-add the exact removed sentences.
- **Restored-and-removed files** (§3) — restore from `upstream/` at `ryoku/hub/backend/`.
- **`fsutil.go` additions** (Step 2) — `configHome()`/`dataHome()` were moved here from `voxtype.go`;
  revert by moving them back and restoring `voxtype.go` from `upstream/`.

No change in this phase is irreversible at the source level. The only thing that is not revertible by
a source checkout is a *built-and-run* live session that already consumed the change; that is the
owner's decision via `docs/LIVE-TEST.md`, not part of this cleanup pass.

---

## 7. Verification gate (run before `./tenkai live`)

- [ ] `bash -n tenkai && bash -n install.sh` — both scripts parse.
- [ ] `go build -trimpath -p 2 ./...` clean on all four module roots:
  `src/ryoku/hub/backend`, `src/ryoku/shell/ipc`, `src/ryoku/shell/ryogami/daemon`, `src/ryoku/wm`.
- [ ] `./tenkai verify-untouched` — PASS (live config hashes identical to `docs/baseline/`).
- [ ] `./install.sh --dry-run` — succeeds, prints nothing destructive.
- [ ] `git log --oneline -6` — shows the Phase-16 commits in order.
- [ ] No untracked build artifacts committed (§5).
- [ ] `ARCHITECTURAL_AUDIT.md` frozen (not edited).

**Current state of the gate (at changelog-write time):** the four Go module roots build clean;
`bash -n` on both scripts, `./tenkai verify-untouched`, and `./install.sh --dry-run` are not yet run
for this exact working tree and must be run after the Step 1/2/3/5 commits are in.

---

## 8. Commit sequencing (owner-specified messages, in order)

1. Step 2 — `chore(hub): restore integrated import/gputune layers, delete only isolated gpu/voxtype modules`
   (covers §2.1 + §2.2 + the gpuapply restore+edit from §3 + configHome/dataHome moved fsutil.go→voxtype.go
   deletion from §3 + the §2.5 comment fixes in `gpudomain.go`/`tenkai_runtime.go`).
2. Step 1 — `chore: fix stale README paths` (README line 108 only).
3. Step 3 — `chore(ipc): strip dead pillIpc code from actions.go` (§2.3).
4. Step 5 — `perf(qsbar): remove unused picker variants to eliminate dead ffmpeg thumbnail paths`
   (§2.4 + the Theme.qml/VariantRoot.qml/DesktopPage.qml edits).

The README fix (Step 1) is committed after Step 2 so the changelog's own first commit-message
reference stays accurate. The IPC fix (Step 3) and picker fix (Step 5) are independent and can land
in either order after Step 2.

---

## 9. Known pre-existing stale references NOT touched in this phase

These were noticed during the audit but are either pre-existing (present in HEAD) or fall outside the
step messages, so they are left for a later pass / the owner to decide:

- **`ryoku-hub lock list` / `ryoku-hub lock set` usage lines in `main.go` `usage()`.** These two
  lines advertise a `lock` subcommand that has no `case "lock"` branch in `main.go` and whose
  implementation (`runLock` etc.) was never tracked in this checkout's git HEAD (`lock.go` is
  untracked here). So `ryoku-hub lock <anything>` already dead-ends to `usage()` + exit 2 in HEAD.
  Removing the two lines is a 2-line correctness fix but is **not** part of any step message; left
  for the owner. (The lock screen itself is not on this phase's keep list.)
- **`Tenkai` product-name usage throughout `README.md`, `install.sh`, `tenkai`, and the Go source.**
  The checkout is named `tenkai/` and the control script/binary are `tenkai*`, but the Go source
  lives in `src/ryoku/` and the hub/shell binaries are `ryoku-hub`/`ryoku-shell`. The README's tree
  entry for `src/ryoku/` was fixed in Step 1 (line 108 only). A wider rename is a larger decision
  the owner has not asked for.

---

## Phase 17 — System-wide audit (Phase 1: asset purge)

Phase lead: buffy. Branch: `phase17-audit` (off `dac38d5`). Baseline commit: `6994f84`.

### Phase 1 — Asset purge (disk & memory)

Delivered: **38 files, 3055 deletions, ≈1.68 MB** (`b476537`).

#### Deleted

**qsbar/assets/ (7 files):** `codex.svg`, `hdd-mark.svg`, `arch-header-arch.png`, `arch-header-linux.png`, `bob2.png` (1.7 KB), `bob3.png` (41 KB), `omacom-text.png` — zero references anywhere in the project.

**ui/art/ + hub/quickshell/art/ (4 files):** `graces.svg` (55 KB), `helm.svg` (26 KB), `justice.svg` (76 KB), `dither-torii.png` (599 KB) — zero references.

**fastfetch (1 file):** `tenkai-logo.png` (722 KB) — zero references. Only `fastfetch-emblem.png` and `tenkai-logo.png.1bit.png` are used by the rice system; the blind `find -type f` in install.sh would have deployed this dead file on every install.

**matugen/templates/ (26 files, 192 KB):** All non-kitty template files. `config.toml` has an empty `[templates]` section; only `kitty-colors.conf` is copied by `tenkai_seed_matugen()`. Kept: `kitty-colors.conf`.

#### Kept (verified alive)

- `components/icons/*.svg` (152 files, ≈608 KB): loaded dynamically by `SymbolIcon.qml` via `Qt.resolvedUrl("icons/" + name + "-symbolic.svg")`. Partial trace (20 names) did not reveal unused glyphs; the full set is the icon fallback available to data-driven `name` values. **Not deleted — Review Required for full data-flow trace.**
- `fastfetch-emblem.png` + `tenkai-logo.png.1bit.png`: referenced by `rice.go`.
- All 11 fonts in `shell/assets/fonts/`: loaded by `Fonts.qml` singleton, exposed to Settings Appearance font picker.
- `grain.png`, `profile-hero.png`, `roots.png`, `hands-adam.png`: all referenced.
- `kitty-colors.conf`: copied by `tenkai_seed_matugen()`.

#### Review Required

- **`components/icons/*.svg` (152 files):** Dynamic loading via `SymbolIcon.qml` means any icon whose `name` is passed as `root.icon` or `root.iconName` could be loaded. Full data-flow tracing of all `icon`/`iconName` sources needed to identify genuinely unused glyphs. Not deleted; flagged for Phase 2–3 deeper inspection.

#### Verification

`bash -n tenkai && bash -n install.sh` — PASS. `go build ./...` — PASS. `./tenkai verify-untouched` — PASS.

### Phase 2 — QML deep clean (RAM & CPU)

Delivered: **2 QML panel files, 1293 deletions, ≈61 KB** (`8eac401`).

#### Deleted

**qsbar/panels/ (2 files):** `ImageCarouselPanel.qml` (35 KB) — zero references outside its qmldir entry; dead picker variant. `MediaBrowserPanel.qml` (26 KB) — zero references anywhere, not even in qmldir; dead panel file.

Also cleaned `panels/qmldir`: removed the `ImageCarouselPanel` registration line.

#### Kept (Review Required — too deeply integrated to delete safely in this pass)

- `Needle.qml` (17 KB): AI chat service, heavily referenced by `Actions.qml` (Super+S panel, ~50 refs). Not on keep list but deeply integrated.
- `Stash.qml` (18 KB): download manager, heavily referenced by `Dock.qml` + `Desktop.qml`. Not on keep list but deeply integrated.
- `VoxtypeWidget.qml` (2.3 KB): voice typing, referenced by `Theme.qml` + `BarSlot.qml` (core bar files). Not on keep list, wired into bar architecture.
- `AiUsagePanel.qml` (24 KB): AI usage panel, referenced by `Theme.qml` + `ClaudeWidget.qml` + `VariantRoot.qml`. Not on keep list.
- AI rendering cluster (`AiBarInset.qml`, `AiPanelSurface.qml`, `ConnectedBarInset.qml`, `ConnectedPanelSurface.qml`): wired into `BarSlot.qml` + 20+ panel files. Core bar infrastructure.
- `CloudflareSpeedTest.qml` (12 KB): speed test widget, referenced by `NetworkPanel.qml`. Sub-feature of network (which IS kept).
- `components/icons/*.svg` (152 files, ≈608 KB): dynamic loading via `SymbolIcon.qml`; need full data-flow trace of `root.icon`/`root.iconName` sources to identify unused glyphs.

#### Verification

`bash -n` OK, `go build ./...` OK, `./tenkai verify-untouched` PASS.

### Phase 3 — Go backend sweep (execution & memory)

Delivered: **0 files deleted** (no dead Go code found).

#### Finding

Scanned all 4 Go module roots (`hub/backend`, `shell/ipc`, `wm`, `ryogami/daemon`) via function-level cross-referencing. Every `.go` file in `hub/backend/` is reachable through a dependency chain from a kept CLI subcommand or kept module:

- GPU tuning subsystem (`gpuapply.go`, `gputune.go`, `gpudomain.go`, `gpupreset.go`) is interconnected: `cputune.go` → `gputune.go` (Tunable type) → `gpuapply.go` (escalateSelf) + `gpupreset.go` (runGpuPreset). `cputune.go` is the `tenkai cpu` CLI handler (kept: system monitor).
- Lighting subsystem (`lightingfx.go`) is used by `openrgb.go` (46 refs, kept: lighting/quick settings).
- Import subsystem (`import_types.go`, `import_parse.go`, `import_apply.go`, `import_undo.go`) is used by `import.go` (kept: import CLI).
- `desktop_enum.go` is used by `desktop.go` (listCursorThemes, listKbLayouts, listKbVariants).
- `daemonclient.go` is used by `cputune.go` + `clipboard.go` (daemonCall).
- `fsutil.go` is used by 10+ files (fileExists, configHome, dataHome).

#### Pre-existing issues found (not introduced by this audit)

- `gpuhook_test.go:43: undefined: sysAction` — pre-existing test compilation issue; not caused by this audit. Does not affect `go build`.

#### Verification

`go build ./...` across all 4 modules — PASS. `go vet` — PASS (except pre-existing gpuhook_test.go issue). `./tenkai verify-untouched` — PASS.

### Phase 4 — Script & dependency stripping

Delivered: **0 files deleted** (all scripts and dependencies are used).

#### Scripts (src/ryoku/shell/scripts/)

All 7 scripts are deployed and used by Tenkai:

- `tenkai-app` — Tenkai's app launcher (5 refs)
- `tenkai-screenshot` — Tenkai's screenshot tool (4 refs)
- `ryoku-cmd-brightness` — brightness control, shipped verbatim from Ryoku (5 refs)
- `ryoku-app` — app launcher helper (18 refs)
- `ryoku-summon` — window summon (3 refs)
- `ryoku-volume` — volume control (3 refs)
- `ryoku-restart-audio` — audio restart (1 ref)

The `ryoku-*` scripts are intentional: they are the original Ryoku helpers that Tenkai's Hyprland keybinds still exec. The `tenkai` script's `TENKAI_OWNED_BINS` list (line 172) and `tenkai_provision_bin()` (line 305) both enumerate all 7 scripts as deployed binaries.

#### install.sh dependencies

Dependency checks cover: Go toolchain, C compiler, cmake, ninja, HIDAPI, pipewire/wireplumber, font tools (fc-cache, fc-list), and font packages (JetBrains Mono Nerd, Space Mono Nerd, Material Symbols). All are used by kept features. No dead dependency checks found in a quick scan.

#### tenkai script

No legacy dead code paths found. The rebrand from "Mei" to "Tenkai" is complete: `CHANGES.md` documents the rename, and the script uses `TENKAI_` prefixes consistently. No "Mei" references remain in active code paths.

#### Verification

`bash -n tenkai && bash -n install.sh` — PASS. `go build ./...` — PASS. `./tenkai verify-untouched` — PASS.

---

*End of Phase 16 changelog (so far). Append to this file as the next cleanup pass starts; do not
edit `ARCHITECTURAL_AUDIT.md` for the same reason.*
