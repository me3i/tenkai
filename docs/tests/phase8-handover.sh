#!/usr/bin/env bash
# Phase 8 request 2: D-Bus name handover, nested, private bus only.
#
# The live-trial moment, rehearsed: an old owner holds
# org.freedesktop.Notifications and org.kde.StatusNotifierWatcher, it stops,
# then Mei starts and takes both names, then releases them on stop.
#
# One daemon lifetime: ./mei run is handed a private bus this script created
# (MEI_BUS_ADDRESS), so no Mei process is ever stopped or restarted by hand and
# nothing outlives the run. Only that bus is addressed; the live bus is read by
# `verify-untouched` and never contacted.
set -uo pipefail
MEI=/home/mei/projects/mei
RUN="$MEI/.run"; RT="$MEI/.r"
HOST_XDG="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
HOST_WL="${WAYLAND_DISPLAY:-wayland-1}"
STAMP="$(date +%H%M%S)"
LOG="$RUN/logs/phase8-handover-$STAMP.log"
NOTIF=org.freedesktop.Notifications
WATCH=org.kde.StatusNotifierWatcher
mkdir -p "$RUN/logs"
exec > >(tee -a "$LOG") 2>&1

fail=0
ok()  { echo "TESTED      $*"; }
bad() { echo "FAIL        $*"; fail=1; }
note(){ echo "NOTE        $*"; }
owner() { busctl --address="$BUS" list --no-legend 2>/dev/null | awk -v n="$1" '$1==n{print $2}' | grep -v '^-$'; }
wait_free() {
  local i
  for i in $(seq 1 48); do
    [ -z "$(owner $NOTIF)" ] && [ -z "$(owner $WATCH)" ] && return 0
    sleep 0.25
  done
  return 1
}
wait_owner() { # $1 name, $2 ticks
  local i o=""
  for i in $(seq 1 "${2:-80}"); do
    o="$(owner "$1")"; [ -n "$o" ] && { echo "$o"; return 0; }
    sleep 0.25
  done
  return 1
}

echo "=== private bus ==="
BUSOUT="$(dbus-daemon --session --fork --print-address=1 --print-pid=1 2>/dev/null)"
BUS="$(printf '%s\n' "$BUSOUT" | sed -n 1p)"
BUSPID="$(printf '%s\n' "$BUSOUT" | sed -n 2p)"
if [ -z "$BUS" ] || [ -z "$BUSPID" ] || ! busctl --address="$BUS" list >/dev/null 2>&1; then
  bad "could not create a private bus"
  echo; echo "RESULT: FAIL"; exit 1
fi
ok "private bus up (pid $BUSPID), address $BUS"
trap 'kill -TERM "$BUSPID" 2>/dev/null' EXIT

echo; echo "=== verify-untouched BEFORE ==="
( cd "$MEI" && env -u HYPRLAND_INSTANCE_SIGNATURE -u WAYLAND_DISPLAY \
    XDG_RUNTIME_DIR="$HOST_XDG" ./mei verify-untouched 2>&1 | tail -1 )

echo; echo "=== 1. stand-in owner takes both names ==="
HOME="$RUN/home" DBUS_SESSION_BUS_ADDRESS="$BUS" \
  python3 "$MEI/docs/tests/name-owner.py" > "$RUN/logs/name-owner-$STAMP.log" 2>&1 &
SPID=$!
ready=0
for _ in $(seq 1 60); do
  grep -q '^READY' "$RUN/logs/name-owner-$STAMP.log" 2>/dev/null && { ready=1; break; }
  sleep 0.25
done
[ "$ready" = 1 ] && ok "stand-in ready (pid $SPID)" || bad "stand-in never became ready"
n="$(owner $NOTIF)"; w="$(owner $WATCH)"
[ "$n" = "$SPID" ] && ok "stand-in owns notifications ($n)" || bad "notifications owner='$n' stand-in='$SPID'"
[ "$w" = "$SPID" ] && ok "stand-in owns the watcher ($w)" || bad "watcher owner='$w' stand-in='$SPID'"

echo; echo "=== 2. stand-in stops; both names free ==="
kill -TERM "$SPID" 2>/dev/null
for _ in $(seq 1 60); do [ -d "/proc/$SPID" ] || break; sleep 0.25; done
[ -d "/proc/$SPID" ] && bad "stand-in still alive" || ok "stand-in exited"
wait_free && ok "both names free between owners" || bad "names stuck: $(owner $NOTIF) / $(owner $WATCH)"

echo; echo "=== 3. Mei starts on the same bus and takes both names ==="
( cd "$MEI" && env -u HYPRLAND_INSTANCE_SIGNATURE -u WAYLAND_DISPLAY \
    XDG_RUNTIME_DIR="$HOST_XDG" WAYLAND_DISPLAY="$HOST_WL" \
    MEI_BUS_ADDRESS="$BUS" ./mei run ) >/dev/null 2>&1
SIG=""; QS=""
for _ in $(seq 1 200); do
  SIG="$(ls -d "$RT/hypr/"*/ 2>/dev/null | head -1 | xargs -r basename)"
  QS="$(pgrep -f "^qs -p $MEI/src/ryoku/shell/quickshell/shell" | head -1)"
  [ -n "$SIG" ] && [ -S "$RT/hypr/$SIG/.socket.sock" ] && [ -n "$QS" ] && break
  sleep 0.3
done
if [ -z "$SIG" ] || [ -z "$QS" ]; then
  bad "session did not come up"
  echo; echo "RESULT: FAIL"; exit 1
fi
export HYPRLAND_INSTANCE_SIGNATURE="$SIG"
WAYLAND_DISPLAY="$(basename "$(ls "$RT"/wayland-* 2>/dev/null | head -1)")"
export WAYLAND_DISPLAY
session_bus="$(cat "$RUN/bus" 2>/dev/null)"
[ "$session_bus" = "$BUS" ] && ok "the session used this private bus" || bad "session bus '$session_bus' != '$BUS'"
sleep 4
DPID="$(pgrep -f "^$RUN/bin/mei-shell daemon" | head -1)"
[ -n "$DPID" ] || { bad "daemon not running"; echo; echo "RESULT: FAIL"; exit 1; }
n="$(wait_owner $NOTIF 80)" && ok "notifications claimed by Mei's shell ($n)" || bad "notifications not claimed"
w="$(wait_owner $WATCH 80)" && ok "watcher claimed by Mei's daemon ($w)" || bad "watcher not claimed"
[ "$n" = "$QS" ] && ok "notifications owner is the shell process ($QS)" || bad "notifications owner '$n' != shell '$QS'"
[ "$w" = "$DPID" ] && ok "watcher owner is the daemon ($DPID)" || bad "watcher owner '$w' != daemon '$DPID'"

echo; echo "=== 4. stopping Mei releases both names ==="
( cd "$MEI" && env -u HYPRLAND_INSTANCE_SIGNATURE -u WAYLAND_DISPLAY \
    XDG_RUNTIME_DIR="$HOST_XDG" WAYLAND_DISPLAY="$HOST_WL" ./mei stop ) >/dev/null 2>&1
pgrep -f "^$RUN/bin/mei-shell daemon" >/dev/null && bad "a daemon survived" || ok "no daemon left"
pgrep -f "^qs -p $MEI/src/ryoku/shell/quickshell/shell" >/dev/null && bad "a shell survived" || ok "no shell left"
wait_free && ok "both names released after Mei stopped" || bad "names still owned: $(owner $NOTIF) / $(owner $WATCH)"

echo; echo "=== 5. close the private bus ==="
kill -TERM "$BUSPID" 2>/dev/null
for _ in $(seq 1 40); do [ -d "/proc/$BUSPID" ] || break; sleep 0.25; done
[ -d "/proc/$BUSPID" ] && bad "private bus still alive" || ok "private bus gone"
trap - EXIT

echo; echo "=== verify-untouched AFTER ==="
( cd "$MEI" && env -u HYPRLAND_INSTANCE_SIGNATURE -u WAYLAND_DISPLAY \
    XDG_RUNTIME_DIR="$HOST_XDG" ./mei verify-untouched 2>&1 | tail -1 )

echo
[ "$fail" = 0 ] && echo "RESULT: PASS" || echo "RESULT: FAIL"
exit "$fail"
