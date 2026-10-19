# CHANGES.md — modifications vs upstream Ryoku

Pinned upstream: see `UPSTREAM.md`. Mei is built by copying and adapting upstream files into
`src/`; every modification is recorded here, newest first.

## Phase 0 — project scaffold (no upstream source touched yet)

- Created project layout: `AGENTS.md`, `docs/`, `src/`, `.run/`, `./mei` control script.
- Captured read-only live-session baseline (`docs/baseline.txt`, `docs/baseline/`) and
  `./mei verify-untouched`.
- `upstream/` cloned at pinned commit (see `UPSTREAM.md`); never edited.
