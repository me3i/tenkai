#!/usr/bin/env bash
# Proof that the whole-run leak monitor really fails a live-runtime launch.
#
# Deliberately broken launches are harmless `sleep` processes with the live
# runtime/display in their environment; nothing connects to the live
# compositor and no live process is signalled. The monitor is pointed at a
# temporary pidfile, never at the real session.
set -uo pipefail
MEI=/home/mei/projects/mei
RUN="$MEI/.run"; RT="$MEI/.r"
LIVE_RT="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
LIVE_WL="${WAYLAND_DISPLAY:-wayland-1}"
STAMP="$(date +%H%M%S)"
TMP="$RUN/tmp-leak-$STAMP"
LOG="$RUN/logs/leak-check-$STAMP.log"
MON="$MEI/docs/tests/leak-monitor.sh"
mkdir -p "$TMP" "$RUN/logs"
exec > >(tee -a "$LOG") 2>&1

fail=0
ok()  { echo "TESTED      $*"; }
bad() { echo "FAIL        $*"; fail=1; }
cleanup() {
  for p in ${BROKEN_PID:-} ${GOOD_PID:-} ${PARENT_PID:-}; do
    [ -n "$p" ] && kill -TERM "$p" 2>/dev/null || true
  done
  rm -rf "$TMP"
}
trap cleanup EXIT

run_monitor() { # $1 pidfile, $2 stopfile, $3 log; extra env comes from caller
  NESTED_RT="$RT" LIVE_RT="$LIVE_RT" LIVE_WL="$LIVE_WL" \
    bash "$MON" "$1" "$2" "$3" >/dev/null 2>&1
}

echo "leak guard self-test: live=$LIVE_RT display=$LIVE_WL nested=$RT"

# 1. The old b915e0a failure mode: a Mei-shaped process with the live runtime.
env XDG_RUNTIME_DIR="$LIVE_RT" WAYLAND_DISPLAY="$LIVE_WL" sleep 6 &
BROKEN_PID=$!
printf '%s\t%s\tbroken-live-runtime\n' "$BROKEN_PID" "$BROKEN_PID" > "$TMP/broken.pids"
run_monitor "$TMP/broken.pids" "$TMP/broken.stop" "$TMP/broken.log" &
MONPID=$!
sleep 1
touch "$TMP/broken.stop"
wait "$MONPID"; BRC=$?
if [ "$BRC" != 0 ] && grep -q 'uses the live XDG_RUNTIME_DIR' "$TMP/broken.log"; then
  ok "deliberate live-runtime process fails the guard (rc=$BRC)"
else
  bad "guard did not fail the deliberate live-runtime process (rc=$BRC)"
  sed 's/^/  | /' "$TMP/broken.log"
fi
kill -TERM "$BROKEN_PID" 2>/dev/null; wait "$BROKEN_PID" 2>/dev/null; BROKEN_PID=""

# 2. No false positive: the same shape on the nested runtime.
env -u WAYLAND_DISPLAY XDG_RUNTIME_DIR="$RT" sleep 6 &
GOOD_PID=$!
printf '%s\t%s\tnested-ok\n' "$GOOD_PID" "$GOOD_PID" > "$TMP/good.pids"
run_monitor "$TMP/good.pids" "$TMP/good.stop" "$TMP/good.log" &
MONPID=$!
sleep 1
touch "$TMP/good.stop"
wait "$MONPID"; GRC=$?
if [ "$GRC" = 0 ]; then
  ok "nested-runtime process passes the guard (no false positive)"
else
  bad "guard flagged a nested-runtime process (rc=$GRC)"
  sed 's/^/  | /' "$TMP/good.log"
fi
kill -TERM "$GOOD_PID" 2>/dev/null; wait "$GOOD_PID" 2>/dev/null; GOOD_PID=""

# 3. Parent check: a recorded process whose direct parent is a "live" PID.
env -u WAYLAND_DISPLAY XDG_RUNTIME_DIR="$RT" sleep 6 &
PARENT_PID=$!
printf '%s\t%s\tlive-parent\n' "$PARENT_PID" "$PARENT_PID" > "$TMP/parent.pids"
NESTED_RT="$RT" LIVE_RT="$LIVE_RT" LIVE_WL="$LIVE_WL" LEAK_LIVE_PIDS="$$" \
  bash "$MON" "$TMP/parent.pids" "$TMP/parent.stop" "$TMP/parent.log" >/dev/null 2>&1 &
MONPID=$!
sleep 1
touch "$TMP/parent.stop"
wait "$MONPID"; PRC=$?
if [ "$PRC" != 0 ] && grep -q 'is a child of live PID' "$TMP/parent.log"; then
  ok "direct child of a live PID fails the guard (rc=$PRC)"
else
  bad "guard did not fail a child of a live PID (rc=$PRC)"
  sed 's/^/  | /' "$TMP/parent.log"
fi
kill -TERM "$PARENT_PID" 2>/dev/null; wait "$PARENT_PID" 2>/dev/null; PARENT_PID=""

echo "leak self-test log: $LOG"
exit "$fail"
