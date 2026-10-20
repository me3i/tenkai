#!/usr/bin/env bash
# revert-to-previous-shell.sh — the owner's rescue path.
#
# It stops Mei and brings the previous shell back. It does NOT edit the Hyprland
# config: that stays a manual step, so nothing here can silently rewrite the
# owner's configuration. The agent never runs this against the live session.
#
# The previous shell's own commands come from .local/mei.local.env, which is
# not tracked by git: the public repository must not name anyone's setup. If
# that file or its values are missing, the script says so and stops Mei only.
#
# Usage (from your own terminal):
#   bash ~/projects/mei/docs/revert-to-previous-shell.sh
set -uo pipefail

MEI="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
CONF="$MEI/.local/mei.local.env"

conf() { # $1 = key -> the value, or nothing
  [ -f "$CONF" ] || return 1
  local line
  line="$(grep -E "^$1=" "$CONF" 2>/dev/null | tail -1 || true)"
  [ -n "$line" ] || return 1
  printf '%s' "${line#*=}" | sed 's/^"//; s/"$//'
}

echo "revert: stopping Mei"
if [ -d "$MEI" ]; then
  ( cd "$MEI" && XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}" ./mei live-stop ) 2>&1 | sed 's/^/  /'
fi

prev_name="$(conf MEI_PREV_SHELL_NAME || true)"
prev_start="$(conf MEI_PREV_SHELL_START || true)"

if [ -z "$prev_start" ]; then
  echo "revert: the previous shell's start command is not configured."
  echo "  Set MEI_PREV_SHELL_START in $CONF (see .local/mei.local.env.example)."
  echo "  Mei has been stopped; start your previous shell the way your autostart does."
  exit 1
fi

echo "revert: starting ${prev_name:-the previous shell}"
eval "$prev_start" 2>&1 | sed 's/^/  /'

cat <<'NOTE'

revert: the autostart line is still Mei's, so the next login would start Mei
again. Uncomment your own line in your Hyprland config and comment Mei's out:

    # hl.exec_cmd("<your previous shell's start command>")
    hl.exec_cmd("<your previous shell's start command>")

then log out and back in (or restart the compositor).

If the screen is blank: Ctrl+Alt+F3 gives you a TTY. Log in, then:
    bash ~/projects/mei/docs/revert-to-previous-shell.sh
NOTE
