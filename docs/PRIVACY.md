# PRIVACY — what the public history contains

Tenkai is public at <https://github.com/me3i/tenkai>. This file records, plainly,
what personal data is in that repository and why it is still there.

## What is exposed

The working history (213 commits at the time of writing) contains commit
`0ba3273`, "phase0: scaffold", which added these files:

```
docs/baseline.txt
docs/baseline/config-hashes.sha256
docs/baseline/config-symlinks.txt
docs/baseline/dbus-names.txt
docs/baseline/env.txt
docs/baseline/ps-full.txt
docs/baseline/quickshell-instances.txt
docs/baseline/session-processes.txt
```

They are a read-only snapshot of one live desktop session, taken on 2026-10-19 to
give `./tenkai verify-untouched` something to compare against. They contain:

- the username `mei` and `HOME=/home/mei`, plus other absolute paths under it;
- `XDG_RUNTIME_DIR=/run/user/1000` and the UID;
- the Hyprland instance signature;
- the full process list of that session (program names and PIDs);
- the session's D-Bus name table;
- paths belonging to the shell that was running before Tenkai.

They were deleted from the tree by commit `b76cc00`, so `HEAD` is clean
(`git grep -n '/home/mei'` prints nothing), but the commits before it are public
and `git log -p` still shows them.

## What is not exposed

No credentials, keys or tokens were found in a full-history scan: no private-key
blocks, no SSH public keys, no AWS keys, no `ghp_`/`sk-`-style tokens, and no
literal `password=`/`token=`/`api_key=` assignments. No `.env`, `.pem`, `.key` or
credential file is tracked, at `HEAD` or anywhere in history.

## Decision: history is not rewritten

Rewriting 213 public commits was considered and **declined**:

- The exposure is a process list, a D-Bus name table, a username and a home path.
  None of it is a secret; it is the sort of thing any screenshot or `htop` paste
  reveals.
- Rewriting a published history invalidates every commit hash, every link, every
  clone and every fork. That is a larger, harder-to-reverse action than the
  exposure it would remove.
- The specific files can be removed from `HEAD` (already done) without touching
  the past.

If the owner decides otherwise, the operation is a `git filter-repo` against
`docs/baseline*` followed by a force-push, and it needs explicit approval because
it rewrites public history.

## What this means for clones

A fresh clone of this repository does **not** get `docs/baseline/`, so
`./tenkai verify-untouched` has nothing to compare against until you run
`./tenkai baseline` yourself. That is the tradeoff this decision accepts; it is
also documented in `docs/ROLLBACK.md`.
