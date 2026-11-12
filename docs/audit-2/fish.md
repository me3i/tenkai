# Fish and the TTY1 boot policy

## What the docs claim

`docs/ROLLBACK.md` ("Boot policy") says Tenkai becomes the login default by
masking `ryoku-session.target` and adding this to the **end** of
`~/.config/fish/config.fish`:

```fish
# Automatically launch Hyprland on TTY1
if test -z "$DISPLAY"; and test -z "$WAYLAND_DISPLAY"; and test "$XDG_VTNR" = 1
    exec start-hyprland
end
```

## What is actually installed

The live `~/.config/fish/config.fish` and the shipped
`src/tenkai-configs/terminal/fish/config.fish` are identical, and **neither
contains that block**. `grep` for `XDG_VTNR`/`start-hyprland` in both files and
in the shipped tree finds only the ROLLBACK documentation.

So the TTY1 auto-exec is currently *documented, not active*. Nothing in this
audit added it: doing so changes what happens at every login, and the task
explicitly rules out changing the launcher target or running `chsh`.

## Safety checks performed

```
fish -n ~/.config/fish/config.fish          -> 0
fish -n src/tenkai-configs/terminal/fish/config.fish -> 0
```

`launcherTarget` does not appear in either fish file (0 matches), so the safe
fish edits from the previous pass did not alter the launcher setting.

## Findings, not changed

The last PATH block in both files is:

```fish
set -gx PATH '~/.local/bin' $PATH
```

In fish, single quotes suppress tilde expansion; `echo "~/.local/bin"` prints the
literal string. That PATH entry therefore does not point at the home directory.
It is harmless to the workspace/settings/icons fixes and was left untouched
(the task limits fish work to interpretation); it is recorded here as a
follow-up candidate.

## Conclusion

The boot policy in ROLLBACK is coherent and safe to follow manually, but it is
not installed. Enabling it must be an explicit user action; it is out of scope
for a silent fix and is listed in `unverified.md`.
