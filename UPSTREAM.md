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
- Local path: `~/projects/tenkai/upstream/` — **READ-ONLY. Never edited.** All Tenkai
  modifications happen in `src/` and are recorded in `CHANGES.md`.
- **The upstream folder is not present in a fresh clone.** It was deleted in Phase 17 to
  reclaim disk space, and it is not tracked here. Re-create it exactly like this (network
  required, ~38 MB of blobs for the sparse set):

  ```bash
  cd ~/projects/tenkai
  git clone --filter=blob:none --sparse https://github.com/Ryoku-dev/ryoku upstream
  cd upstream
  git sparse-checkout set docs ryoku/shell ryoku/hub ryoku/hyprland ryoku/wm ryoku/ui \
      ryoku/palette-bridge
  git checkout 98a0368253d9628be72b853985878a5db90e1547
  ```

  Read it read-only; never edit it. Any blob outside the sparse set is still reachable with
  `git show 98a0368:<path>` without materialising the tree.

Notes:
- The clone was pre-seeded on this machine on 2026-10-19 09:42 (this machine), before this session
  began; an interrupted transfer left `.git/objects/pack/tmp_pack_*` behind. It was verified
  (`git log`, refs, remotes) and the working tree was checked out at the pinned commit.
- If history is ever needed: `git -C upstream fetch --unshallow` (network required).

## Pre-republish archive tag

The repository was republished to `https://github.com/me3i/tenkai` on
2026-11-08. The previous `main` tip there was commit `c0d98bf` (a 5-commit
repack of this tree, made before the `src/ryoku` → `src/tenkai_core` rename,
and unrelated to this repo's history). It is preserved locally on branch
`archive/github-before-republish` and tagged `pre-republish-archive`, so it can
be recovered if the working clone is ever lost.

## Licence provenance

`LICENSE` (GPL-3.0) and `NOTICE` are byte-identical to upstream at the pinned commit:

```
3972dc9744f6499f0f9b2dbf76696f2ae7ad8af9b23dde66d6af86c9dfb36986  LICENSE
062137be76c0d594a089130445ad82495e745b67cdf677aa71be065d40635732  NOTICE lines 1-34
```

`NOTICE` is 34 lines upstream at the pin (1497 bytes). Everything after the ruled
delimiter in this repo's `NOTICE` is Tenkai's addendum and is not upstream text. Note that
upstream HEAD today has a much longer NOTICE (152 lines); the extra paragraphs credit
components added after the pin, and this NOTICE quotes the ones Tenkai still ships.
