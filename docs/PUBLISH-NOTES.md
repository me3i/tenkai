# PUBLISH-NOTES — making this repository public

This repository is Mei: a shell built on Ryoku. It will be published, and the
public tree must not carry **anyone's** setup: no personal shell name, no
personal paths, no personal process ids, no personal config hashes.

## What is already done

- **Nothing personal is tracked.** `./mei scrub-check` greps the tracked tree
  for the built-in patterns (a personal home directory, the previous shell's
  name) plus the terms in `.local/scrub-terms.txt`, which is **not** tracked.
  It prints every hit and exits non-zero if there is one. The check has been
  proven able to fail: a deliberate hit was added, the check failed, and the
  hit was removed.
- **The owner's setup lives in one untracked file**, `.local/mei.local.env`:
  the previous shell's name and its start and stop commands. `./mei start
  --fallback`, `./mei live-stop`, the preflight messages and
  `docs/revert-to-previous-shell.sh` read it. If the file or a value is
  missing, they say so and do nothing; they never guess.
  `.local/mei.local.env.example` is tracked, with placeholders.
- **The private notes** (the detailed parity audit, the keybind mapping) are in
  `.local/private/`, which is not tracked. Back it up separately: it is the
  only place the personal mapping lives.
- **The baseline capture** (`docs/baseline/`) is not tracked either: it is a
  process list and the D-Bus names of a real session.

## Publishing, without rewriting history

**Do not rewrite the git history in this repository.** The history contains the
earlier commits, and those mention the previous shell, the personal paths and
the personal process ids. Rewriting history in the working repo is risky and
unnecessary.

Instead, export a clean tree and start the public repository with a single
fresh commit:

```bash
cd ~/projects/mei
./mei export-clean ../mei-public
```

`./mei export-clean <dir>` copies **only the tracked files** into the directory,
and it refuses to copy anything if the scrub check finds a hit. So the exported
tree is clean by construction.

Then, in the new directory:

```bash
cd ../mei-public
git init
git add -A
git commit -m "Mei: a Hyprland desktop shell built on Mei"
```

Before you push, check the export yourself:

```bash
grep -rIil -e serpantinum -e serpentinum ../mei-public   # must print nothing
```

and read the README and `docs/PUBLISH-NOTES.md` once more.

## What the public tree still says

Some documents describe the *previous* setup in general words (a previous
shell, a panel that needs a host, a power menu that was dead). That is
deliberate: they are the audit that says what Mei has to cover, and they name
no one. The private copies in `.local/private/` hold the specifics.

## Checklist before the first push

- [ ] `./mei scrub-check` → PASS
- [ ] `./mei export-clean ../mei-public` → succeeds
- [ ] `grep -rIil -e serpantinum -e serpentinum ../mei-public` → prints nothing
- [ ] `git status` in this repo is clean, and `.local/` is ignored
      (`git check-ignore -v .local/mei.local.env`)
- [ ] the README, the install instructions and `docs/PUBLISH-NOTES.md` name no
      personal setup
- [ ] you have a copy of `.local/` somewhere safe: it is not in git
