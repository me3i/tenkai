#!/usr/bin/env bash
# revert-to-serpantinum.sh — the owner's rescue path.
#
# It stops Mei and brings the old shell back. It does NOT edit the Hyprland
# config: that stays a manual step, so nothing here can silently rewrite the
# owner's configuration. The agent never runs this against the live session.
#
# Usage (from your own terminal):
#   bash ~/projects/mei/docs/revert-to-serpantinum.sh
set -uo pipefail

MEI=/home/mei/projects/mei

echo "revert: stopping Mei"
if [ -d "$MEI" ]; then
  ( cd "$MEI" && XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}" ./mei live-stop ) 2>&1 | sed 's/^/  /'
fi

echo "revert: starting serpantinumd"
if command -v serpantinumd >/dev/null 2>&1; then
  serpantinumd start 2>&1 | sed 's/^/  /'
else
  echo "  serpantinumd is not on PATH: start it the way your autostart does"
fi

cat <<'NOTE'

revert: the autostart line is still Mei's, so the next login would start Mei
again. Uncomment your line in ~/.config/hypr/config/autostart.lua:

    # hl.exec_cmd("serpantinumd start")
    hl.exec_cmd("serpantinumd start")

and comment Mei's line out:

    # hl.exec_cmd("~/projects/mei/mei start --fallback \"serpantinumd start\"")

then log out and back in (or restart Hyprland).

If the screen is blank: Ctrl+Alt+F3, log in, run this script again.
NOTE
