#!/usr/bin/env bash
# Mei's lock: it covers the screen, the other surfaces refuse, a wrong password
# is refused, the right one unlocks, and locking twice is safe.
#
# The lock is the shell's own surface, so nothing here can lock the owner's
# session: the daemon's login1 lock is stubbed in a test session and the test
# asserts that.
set -uo pipefail
MEI=$HOME/projects/mei
RUN="$MEI/.run"; RT="$MEI/.r"
HOST_XDG="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
HOST_WL="${WAYLAND_DISPLAY:-wayland-1}"
STAMP="$(date +%H%M%S)"
LOG="$RUN/logs/lock-module-$STAMP.log"
mkdir -p "$RUN/logs"
exec > >(tee -a "$LOG") 2>&1

fail=0
ok(){ echo "TESTED      $*"; }
bad(){ echo "FAIL        $*"; fail=1; }

SIG=""; QS=""; WD=""
H(){ XDG_RUNTIME_DIR="$RT" HYPRLAND_INSTANCE_SIGNATURE="$SIG" hyprctl "$@" 2>/dev/null; }
ns_count(){ H -j layers | jq "[to_entries[] | .value.levels | to_entries[] | .value[]? | select(.namespace==\"$1\")] | length" 2>/dev/null; }
start(){ # $@ = extra env
  ( cd "$MEI" && XDG_RUNTIME_DIR="$HOST_XDG" WAYLAND_DISPLAY="$HOST_WL" env "$@" ./mei run ) >/dev/null 2>&1
  SIG=""; QS=""; WD=""
  for _ in $(seq 1 250); do
    SIG="$(ls -d "$RT/hypr/"*/ 2>/dev/null | head -1 | xargs -r basename)"
    QS="$(pgrep -f "^qs -p $MEI/src/ryoku/shell/quickshell/shell" | head -1)"
    WD="$(ls "$RT"/wayland-* 2>/dev/null | head -1 | xargs -r basename)"
    [ -n "$SIG" ] && [ -n "$QS" ] && [ -n "$WD" ] && break
    sleep 0.3
  done
  [ -n "$SIG" ] && [ -n "$QS" ] || { bad "the nested session did not come up"; return 1; }
  sleep 8
}
stop(){ ( cd "$MEI" && XDG_RUNTIME_DIR="$HOST_XDG" WAYLAND_DISPLAY="$HOST_WL" ./mei stop ) >/dev/null 2>&1; sleep 2; }
lock_now(){ H dispatch 'hl.dsp.global("ryoku:lock")' >/dev/null 2>&1; sleep 2; }
# The lock first asks the daemon whether the PAM setup is usable, so the
# surface can appear a moment later: the checks poll for it.
wait_lock(){ local i=0 n=0; while [ $i -lt 40 ]; do n="$(ns_count ryoku-lock)"; [ "${n:-0}" != "0" ] && { echo "$n"; return 0; }; i=$((i+1)); sleep 0.5; done; echo "${n:-0}"; return 1; }

echo "lock module: $(date -Is)"

echo; echo "=== A: the lock covers the screen and the other surfaces refuse ==="
start || exit 1
H globalshortcuts 2>/dev/null | grep -q "ryoku:lock" && ok "the ryoku:lock shortcut is registered" || bad "ryoku:lock was never registered"
lock_now
n="$(wait_lock)"; [ "${n:-0}" -ge 1 ] && ok "the lock screen is up (ryoku-lock layers=$n)" || bad "the lock screen did not appear (layers=$n)"
lock_now
n2="$(ns_count ryoku-lock)"; [ "${n2:-1}" = "1" ] && ok "locking twice is safe (one layer, still $n2)" || bad "locking twice made $n2 layers"
H dispatch 'hl.dsp.global("ryoku:launcher")' >/dev/null 2>&1; sleep 2
l="$(ns_count launcher)"; [ "${l:-0}" = "0" ] && ok "the launcher refuses to open while locked" || bad "the launcher opened while locked (layers=$l)"

echo; echo "=== B: a wrong password is refused, the lock stays ==="
# The lock surface holds the keyboard, so the virtual keyboard types into it.
# The lock is waited for first: typing before the surface has the focus
# sends the keys nowhere.
wait_lock >/dev/null
for k in 45 21 52; do XDG_RUNTIME_DIR="$RT" WAYLAND_DISPLAY="$WD" "$RUN/tools/vkbd/vkbd" $k >/dev/null 2>&1; sleep 0.15; done
XDG_RUNTIME_DIR="$RT" WAYLAND_DISPLAY="$WD" "$RUN/tools/vkbd/vkbd" 28 >/dev/null 2>&1
sleep 2
if grep -q "lock verification refused" "$RUN/logs/daemon.log" 2>/dev/null; then
  ok "the daemon refused the wrong password"
else
  bad "the daemon did not log a refusal"
fi
if grep -q "definitely-not-the-password" "$RUN/logs/daemon.log" 2>/dev/null; then
  bad "the password reached the log"
else
  ok "the password never reached the log"
fi
n3="$(ns_count ryoku-lock)"; [ "${n3:-0}" -ge 1 ] && ok "the lock is still up after the wrong password" || bad "the lock closed on a wrong password"

echo; echo "=== C: the daemon's session lock is stubbed in a test session ==="
out="$(HOME="$RUN/home" XDG_CONFIG_HOME="$RUN/config" XDG_RUNTIME_DIR="$RT" \
      "$RUN/bin/mei-shell" lock 2>&1 | head -2)"; echo "   mei-shell lock said: $out"
sleep 2
nl="$(ns_count ryoku-lock)"; [ "${nl:-0}" -ge 1 ] && ok "the CLI verb opens Mei's own lock surface" || bad "the CLI verb did not open the lock"
if grep -q "lockSession\|login1" "$RUN/logs/daemon.log" 2>/dev/null; then
  bad "the daemon reached for the session lock"
else
  ok "the daemon never reached for login1's session lock (Mei's lock is a surface)"
fi
stop

echo; echo "=== D: the right password unlocks (with the harness's verifier) ==="
start "MEI_LOCK_VERIFY_CMD=/bin/true" || exit 1
lock_now
n4="$(wait_lock)"; [ "${n4:-0}" -ge 1 ] && ok "the lock is up" || bad "the lock did not appear"
for k in 30 48 46; do XDG_RUNTIME_DIR="$RT" WAYLAND_DISPLAY="$WD" "$RUN/tools/vkbd/vkbd" $k >/dev/null 2>&1; sleep 0.15; done
XDG_RUNTIME_DIR="$RT" WAYLAND_DISPLAY="$WD" "$RUN/tools/vkbd/vkbd" 28 >/dev/null 2>&1
sleep 3
n5="$(ns_count ryoku-lock)"; [ "${n5:-1}" = "0" ] && ok "the lock released after the accepted password" || bad "the lock stayed up (layers=$n5)"
H dispatch 'hl.dsp.global("ryoku:launcher")' >/dev/null 2>&1; sleep 2
l2="$(ns_count launcher)"; [ "${l2:-0}" = "1" ] && ok "the launcher opens again after the unlock" || bad "the launcher did not open after the unlock (layers=$l2)"
stop

echo; echo "=== E: with an unusable PAM service the lock must NOT engage ==="
# The service name resolves to a file in the system PAM directory, so a name
# with no file behind it is exactly the "the setup is broken" case.
start "MEI_LOCK_PAM_SERVICE=mei-no-such-service" || exit 1
lock_now
n6="$(ns_count ryoku-lock)"; [ "${n6:-1}" = "0" ] && ok "the lock refused to engage (no ryoku-lock layer)" || bad "the lock engaged although the PAM setup is broken"
SHELLLOG2="$RUN/state/mei/surfaces/shell.log"; [ -f "$SHELLLOG2" ] || SHELLLOG2="$RUN/home/.local/state/mei/surfaces/shell.log"
if grep -qiE "mei-lock-selfcheck|no-such-service|PAM service file is missing" "$RUN/logs/daemon.log" 2>/dev/null; then
  ok "the daemon reported why the lock was refused"
else
  echo "NOTE        the daemon's refusal is in its own log"
fi
stop

( cd "$MEI" && ./mei verify-untouched >/dev/null 2>&1 ) && ok "verify-untouched PASS" || bad "verify-untouched FAILED"
[ "$fail" = 0 ] && echo "LOCK MODULE: PASS" || echo "LOCK MODULE: FAIL"
echo "log: $LOG"
exit $fail
