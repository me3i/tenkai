# Fish as the login shell

## Live state

| check | value |
|---|---|
| `$SHELL` (this process) | `/usr/bin/bash` (inherited; expected until next login) |
| passwd login shell | `/usr/bin/fish` |
| `/etc/shells` | contains `/usr/bin/fish` and `/bin/fish` |
| `command -v fish` | `/usr/sbin/fish` |
| `fish --version` | 4.9.3 |

Fish was **already** the passwd login shell before this pass. No `chsh` was run:
changing it to the `/usr/sbin/fish` path reported by `command -v` would have
replaced an equivalent valid entry for no benefit. Before/after are therefore
both `/usr/bin/fish`.

Rollback (not needed, documented for completeness):

```bash
chsh -s /bin/bash
```

A new login or reboot is required before new terminals inherit fish. The
running session's `$SHELL` stays bash; that is not a failure.

## Repo change: PATH tilde bug

The shipped `src/tenkai-configs/terminal/fish/config.fish` had:

```fish
set -gx PATH '~/.local/bin' $PATH
```

Single quotes suppress tilde expansion, so this prepended the literal string
`~/.local/bin` rather than the home path. Fixed to:

```fish
set -gx PATH ~/.local/bin $PATH
```

`fish -n` passes. The live `~/.config/fish/config.fish` had the same line; it
was fixed too, with `config.fish.pre-audit3.bak` as backup, and `fish -n`
passes there as well. A fish check now prints `expanded` for the fixed form.

`tests/run-all.sh::static/fish-config-valid` runs `fish -n` on the shipped
config.

## TTY1 boot block

`docs/ROLLBACK.md` documents an optional fish block that execs Hyprland on
TTY1. It is **not installed** in either the live or shipped fish config, and it
was not added: the user asked for fish as the default shell, not for
auto-launching Hyprland at TTY1. It remains a separate explicit opt-in and is
listed in `unverified.md`.
