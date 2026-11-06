#!/usr/bin/env bash
# revert-to-previous-shell.sh — the owner's rescue path.
#
# It stops Tenkai and brings the previous shell back. It does NOT edit the Hyprland
# config: that stays a manual step, so nothing here can silently rewrite the
# owner's configuration. The agent never runs this against the live session.
#
# The previous shell's own commands come from .local/tenkai.local.env, which is
# not tracked by git: the public repository must not name anyone's setup. If
# that file or its values are missing, the script says so and stops Tenkai only.
#
# Usage (from your own terminal):
#   bash ~/projects/tenkai/docs/revert-to-previous-shell.sh
set -uo pipefail

TENKAI="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CONF="$TENKAI/.local/tenkai.local.env"

conf() { # $1 = key -> the value, or nothing
  [ -f "$CONF" ] || return 1
  local line
  line="$(grep -E "^$1=" "$CONF" 2>/dev/null | tail -1 || true)"
  [ -n "$line" ] || return 1
  printf '%s' "${line#*=}" | sed 's/^"//; s/"$//'
}

echo "revert: stopping Tenkai"
if [ -d "$TENKAI" ]; then
  ( cd "$TENKAI" && XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}" ./tenkai live-stop ) 2>&1 | sed 's/^/  /'
fi

prev_name="$(conf TENKAI_PREV_SHELL_NAME || true)"
prev_start="$(conf TENKAI_PREV_SHELL_START || true)"

if [ -z "$prev_start" ]; then
  echo "revert: the previous shell's start command is not configured."
  echo "  Set TENKAI_PREV_SHELL_START in $CONF (see .local/tenkai.local.env.example)."
  echo "  Tenkai has been stopped; start your previous shell the way your autostart does,"
  echo "  e.g.: systemctl --user start ryoku-session.target"
  exit 1
fi

echo "revert: starting ${prev_name:-the previous shell}"
echo "  command: $prev_start"
eval "$prev_start" 2>&1 | sed 's/^/  /'

cat <<NOTE

revert: the autostart line is still Tenkai's, so the next login would start Tenkai
again. Uncomment your own line in your Hyprland config and comment Tenkai's out:

    # hl.exec_cmd("${prev_start}")
    hl.exec_cmd("${prev_start}")

then log out and back in (or restart the compositor).

If the screen is blank: Ctrl+Alt+F3 gives you a TTY. Log in, then:
    bash ~/projects/tenkai/docs/revert-to-previous-shell.sh

If the screen is blank because the lock is up and the shell died with it, the
compositor is still holding the lock. Clear it with the compositor's own
command:
    hyprctl dispatch 'hl.clear_crashed_lockscreen()'
(the answer is the line it prints; "session is locked with a client" means the
shell is still running and has to be stopped first.)
NOTE
