# UPSTREAM.md — upstream source pin

- Repository: https://github.com/Ryoku-dev/ryoku
- Pinned commit: `98a0368253d9628be72b853985878a5db90e1547`
- Commit date: 2026-09-26
- Commit subject: `release: bump unstable to 0.75.5-beta.20`
- Branch at clone time: `main`
- Clone type: partial clone with `--filter=blob:none` (promisor); blobs are fetched on demand
  from GitHub. Working tree at the pinned commit.
- Working tree is a **sparse checkout** (`git sparse-checkout set docs ryoku/shell ryoku/hub
  ryoku/hyprland ryoku/wm ryoku/ui ryoku/palette-bridge`): 2 578 files / 38 MB. A full tree
  would be ~851 MB, mostly `ryoku/assets` (239 MB), `ryoku-shell-installer/` (35 MB) and
  `ryoku/i18n` (22 MB) — none needed. Anything outside the sparse set is read read-only with
  `git show HEAD:<path>` / `git ls-tree -r HEAD <dir>` (this fetches the blob, it does not
  materialise the tree).
- Local path: `~/projects/mei/upstream/` — **READ-ONLY. Never edited.** All Mei modifications
  happen in `src/` and are recorded in `CHANGES.md`.

Notes:
- The clone was pre-seeded on this machine on 2026-10-19 09:42 (this machine), before this session
  began; an interrupted transfer left `.git/objects/pack/tmp_pack_*` behind. It was verified
  (`git log`, refs, remotes) and the working tree was checked out at the pinned commit.
- If history is ever needed: `git -C upstream fetch --unshallow` (network required).
