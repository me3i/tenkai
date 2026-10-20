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
  for p in ${BROKEN_PID:-} ${GOOD_PID:-} ${PARENT_PID:-} ${DESC_QS:-} ${DESC_ROOT:-} ${GOOD_DESC_QS:-} ${GOOD_DESC_ROOT:-} ${COMP_CHILD:-} ${COMP_ROOT:-} ${QS_COMP_CHILD:-} ${QS_COMP_ROOT:-}; do
    [ -n "$p" ] && kill -TERM "$p" 2>/dev/null || true
  done
  for f in broken good parent desc good-desc comp-probe qs-comp; do
    [ -f "$TMP/$f.log" ] && cp "$TMP/$f.log" "$RUN/logs/leak-check-$STAMP-$f.log"
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

# 4. Descendant coverage: qs is not in the pidfile, but it is a child of the
#    recorded nested-launcher. A live-runtime qs must fail the guard.
cp /bin/sleep "$TMP/qs"
env -u WAYLAND_DISPLAY XDG_RUNTIME_DIR="$RT" \
  bash -c "XDG_RUNTIME_DIR='$LIVE_RT' WAYLAND_DISPLAY='$LIVE_WL' '$TMP/qs' 6 & wait" &
DESC_ROOT=$!
sleep 0.3
DESC_QS="$(pgrep -P "$DESC_ROOT" 2>/dev/null | head -1)"
printf '%s\t%s\tnested-launcher\n' "$DESC_ROOT" "$DESC_ROOT" > "$TMP/desc.pids"
run_monitor "$TMP/desc.pids" "$TMP/desc.stop" "$TMP/desc.log" &
MONPID=$!
sleep 1
touch "$TMP/desc.stop"
wait "$MONPID"; DRC=$?
if [ "$DRC" != 0 ] && grep -q 'name=qs .*uses the live XDG_RUNTIME_DIR' "$TMP/desc.log"; then
  ok "descendant qs with the live runtime fails the guard (pid ${DESC_QS:-?}, rc=$DRC)"
else
  bad "guard did not fail a descendant qs with the live runtime (rc=$DRC)"
  sed 's/^/  | /' "$TMP/desc.log"
fi
kill -TERM "$DESC_QS" "$DESC_ROOT" 2>/dev/null; wait "$DESC_ROOT" 2>/dev/null; DESC_QS=""; DESC_ROOT=""

# 5. Descendant false-positive guard: the same qs shape on the nested runtime
#    must pass, proving the guard actually walks descendants instead of
#    ignoring them.
env -u WAYLAND_DISPLAY XDG_RUNTIME_DIR="$RT" \
  bash -c "XDG_RUNTIME_DIR='$RT' '$TMP/qs' 6 & wait" &
GOOD_DESC_ROOT=$!
sleep 0.3
GOOD_DESC_QS="$(pgrep -P "$GOOD_DESC_ROOT" 2>/dev/null | head -1)"
printf '%s\t%s\tnested-launcher\n' "$GOOD_DESC_ROOT" "$GOOD_DESC_ROOT" > "$TMP/good-desc.pids"
run_monitor "$TMP/good-desc.pids" "$TMP/good-desc.stop" "$TMP/good-desc.log" &
MONPID=$!
sleep 1
touch "$TMP/good-desc.stop"
wait "$MONPID"; GDRC=$?
if [ "$GDRC" = 0 ] && grep -q 'name=qs' "$TMP/good-desc.log"; then
  ok "descendant nested-runtime qs passes (pid ${GOOD_DESC_QS:-?}, no false positive)"
else
  bad "guard flagged or missed a descendant nested-runtime qs (rc=$GDRC)"
  sed 's/^/  | /' "$TMP/good-desc.log"
fi
kill -TERM "$GOOD_DESC_QS" "$GOOD_DESC_ROOT" 2>/dev/null; wait "$GOOD_DESC_ROOT" 2>/dev/null; GOOD_DESC_QS=""; GOOD_DESC_ROOT=""

# 6. A non-Mei compositor startup probe (Hyprland runs `sh -c lspci ...`)
#    inherits the host display before the nested display is set. It must not
#    be a false positive.
cp /bin/sleep "$TMP/lspci"
env XDG_RUNTIME_DIR="$RT" WAYLAND_DISPLAY="$LIVE_RT/$LIVE_WL" \
  bash -c "XDG_RUNTIME_DIR='$RT' WAYLAND_DISPLAY='$LIVE_RT/$LIVE_WL' '$TMP/lspci' 6 & wait" &
COMP_ROOT=$!
sleep 0.3
COMP_CHILD="$(pgrep -P "$COMP_ROOT" 2>/dev/null | head -1)"
printf '%s\t%s\thyprland-nested\n' "$COMP_ROOT" "$COMP_ROOT" > "$TMP/comp-probe.pids"
run_monitor "$TMP/comp-probe.pids" "$TMP/comp-probe.stop" "$TMP/comp-probe.log" &
MONPID=$!
sleep 1
touch "$TMP/comp-probe.stop"
wait "$MONPID"; CPRC=$?
if [ "$CPRC" = 0 ] && grep -q 'COMPOSITOR-HOSTDISPLAY.*name=lspci' "$TMP/comp-probe.log"; then
  ok "compositor startup probe with host display passes (pid ${COMP_CHILD:-?}, no false positive)"
else
  bad "guard flagged or missed a compositor startup probe (rc=$CPRC)"
  sed 's/^/  | /' "$TMP/comp-probe.log"
fi
kill -TERM "$COMP_CHILD" "$COMP_ROOT" 2>/dev/null; wait "$COMP_ROOT" 2>/dev/null; COMP_CHILD=""; COMP_ROOT=""

# 7. The compositor allowance must not hide a Mei component: qs below the
#    compositor with the host display still fails.
env XDG_RUNTIME_DIR="$RT" WAYLAND_DISPLAY="$LIVE_RT/$LIVE_WL" \
  bash -c "XDG_RUNTIME_DIR='$RT' WAYLAND_DISPLAY='$LIVE_RT/$LIVE_WL' '$TMP/qs' 6 & wait" &
QS_COMP_ROOT=$!
sleep 0.3
QS_COMP_CHILD="$(pgrep -P "$QS_COMP_ROOT" 2>/dev/null | head -1)"
printf '%s\t%s\thyprland-nested\n' "$QS_COMP_ROOT" "$QS_COMP_ROOT" > "$TMP/qs-comp.pids"
run_monitor "$TMP/qs-comp.pids" "$TMP/qs-comp.stop" "$TMP/qs-comp.log" &
MONPID=$!
sleep 1
touch "$TMP/qs-comp.stop"
wait "$MONPID"; QCRC=$?
if [ "$QCRC" != 0 ] && grep -q 'name=qs .*WAYLAND_DISPLAY points into the live runtime' "$TMP/qs-comp.log"; then
  ok "Mei qs below the compositor with the host display still fails (pid ${QS_COMP_CHILD:-?}, rc=$QCRC)"
else
  bad "compositor allowance hid a Mei qs with the host display (rc=$QCRC)"
  sed 's/^/  | /' "$TMP/qs-comp.log"
fi
kill -TERM "$QS_COMP_CHILD" "$QS_COMP_ROOT" 2>/dev/null; wait "$QS_COMP_ROOT" 2>/dev/null; QS_COMP_CHILD=""; QS_COMP_ROOT=""

echo "leak self-test log: $LOG"
exit "$fail"
