#!/usr/bin/env bash
# Tenkai's idle: dim, DPMS off and suspend on the user's own thresholds, with the
# compositor's inhibitors honoured (IdleMonitor's respectInhibitors). The
# D-Bus ScreenSaver inhibitor service and the lock were removed 2026-11-01.
#
# Nothing here can reach the owner's session: the nested session has its own
# bus and its own display, the brightness goes into a file (the harness seam
# TENKAI_BRIGHTNESS_FAKE), the suspend is stubbed (TENKAI_STUB_POWER), and the DPMS
# reaches only the nested compositor.
set -uo pipefail
TENKAI=$HOME/projects/tenkai
RUN="$TENKAI/.run"; RT="$TENKAI/.r"
HOST_XDG="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
HOST_WL="${WAYLAND_DISPLAY:-wayland-1}"
STAMP="$(date +%H%M%S)"
LOG="$RUN/logs/idle-module-$STAMP.log"
mkdir -p "$RUN/logs"
exec > >(tee -a "$LOG") 2>&1

fail=0
ok(){ echo "TESTED      $*"; }
bad(){ echo "FAIL        $*"; fail=1; }

SIG=""; QS=""; WD=""
H(){ XDG_RUNTIME_DIR="$RT" HYPRLAND_INSTANCE_SIGNATURE="$SIG" hyprctl "$@" 2>/dev/null; }
ns_count(){ H -j layers | jq "[to_entries[] | .value.levels | to_entries[] | .value[]? | select(.namespace==\"$1\")] | length" 2>/dev/null; }
DAEMON_LOG="$RUN/logs/daemon.log"

FAKE="$RUN/state/idle-fake-brightness"
CFG="$RUN/config/tenkai/idle.json"
# The thresholds are the user's own (Tenkai's config), so the test only shortens
# them. Everything else is the real code path.
cfg_with(){ # $1=dim $2=dpms $3=suspend
  printf '{"enabled": true, "dim": %s, "dpms": %s, "suspend": %s, "dimPercent": 40}\n' \
    "$1" "$2" "$3" > "$CFG.new" && mv "$CFG.new" "$CFG"
}
fake_val(){ tr -d '[:space:]' < "$FAKE" 2>/dev/null; }
# The virtual keyboard must reach the nested session. Without the nested
# runtime and display it would type into the owner's live session.
key(){ "$TENKAI/docs/tests/tools/nested-input.sh" "$RUN/tools/vkbd/vkbd" "$1" >/dev/null 2>&1; }

start(){
  mkdir -p "$RUN/config/tenkai" "$RUN/state"
  echo 80 > "$FAKE"
  cfg_with 9999 9999 9999
  ( cd "$TENKAI" && XDG_RUNTIME_DIR="$HOST_XDG" WAYLAND_DISPLAY="$HOST_WL" \
      env TENKAI_BRIGHTNESS_FAKE="$FAKE" ./tenkai run ) >/dev/null 2>&1
  SIG=""; QS=""; WD=""
  for _ in $(seq 1 250); do
    SIG="$(ls -d "$RT/hypr/"*/ 2>/dev/null | head -1 | xargs -r basename)"
    QS="$(pgrep -f "^qs -p $TENKAI/src/ryoku/shell/quickshell/shell" | head -1)"
    WD="$(ls "$RT"/wayland-* 2>/dev/null | head -1 | xargs -r basename)"
    [ -n "$SIG" ] && [ -n "$QS" ] && [ -n "$WD" ] && break
    sleep 0.3
  done
  [ -n "$SIG" ] && [ -n "$QS" ] || { bad "the nested session did not come up"; return 1; }
  # The config is re-read when it changes, so it is written again once the
  # shell is up: the file may not have existed when the shell started.
  cfg_with 9999 9999 9999
  sleep 6
}
# stop also puts the thresholds back. They are the shell's config, not the
# test's: leaving dpms at 1 s behind blacked out the next gate's screenshots.
stop(){
  ( cd "$TENKAI" && XDG_RUNTIME_DIR="$HOST_XDG" WAYLAND_DISPLAY="$HOST_WL" ./tenkai stop ) >/dev/null 2>&1
  sleep 2
  printf '{"enabled": true, "dim": 9999, "dpms": 9999, "suspend": 9999, "dimPercent": 40}\n' \
    > "$CFG.new" && mv "$CFG.new" "$CFG"
}

echo "idle module: $(date -Is)"
panel_before="$(brightnessctl g 2>/dev/null)"
start || exit 1

echo
echo "=== A: the idle dims, and activity restores the brightness exactly ==="
cfg_with 4 9999 9999
sleep 14
v="$(fake_val)"
[ "$v" = "40" ] && ok "the idle dimmed the panel to 40 (the panel value is $v)" \
  || bad "the idle did not dim the panel (it reads $v)"
key 30
sleep 4
after="$(fake_val)"
[ -n "$after" ] && [ "$after" = "80" ] && ok "the brightness came back to exactly 80" \
  || bad "the brightness did not come back to 80 (it reads $after)"

echo
echo "=== B: the suspend is stubbed ==="
cfg_with 9999 9999 1
sleep 8
if grep -q "suppressed session suspend" "$DAEMON_LOG" 2>/dev/null; then
  ok "the daemon stubbed the suspend (the machine did not suspend)"
else
  bad "the daemon did not stub the suspend"
fi

echo
echo "=== C: the display goes to sleep on idle and wakes on activity ==="
cfg_with 9999 1 9999
sleep 8
if grep -q "wm.act output.power off" "$DAEMON_LOG" 2>/dev/null; then
  ok "the idle turned the nested display off (the provider accepted the dispatch)"
else
  bad "the idle did not turn the display off"
fi
key 30
sleep 5
grep -q "wm.act output.power on" "$DAEMON_LOG" 2>/dev/null \
  && ok "activity woke the display again" \
  || bad "the display was not woken"

stop
echo
echo "=== D: the owner's session was not touched ==="
panel_after="$(brightnessctl g 2>/dev/null)"
[ "$panel_before" = "$panel_after" ] && ok "the panel brightness was not written ($panel_after)" \
  || bad "the panel brightness changed: $panel_before -> $panel_after"
( cd "$TENKAI" && ./tenkai verify-untouched >/dev/null 2>&1 ) && ok "verify-untouched PASS" \
  || bad "verify-untouched FAILED"
[ "$fail" = 0 ] && echo "IDLE MODULE: PASS" || echo "IDLE MODULE: FAIL"
echo "log: $LOG"
exit $fail