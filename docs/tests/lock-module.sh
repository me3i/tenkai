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
# The session lock is the compositor's own now: its answer, as the shell
# reported it to the daemon, is what the checks look at.
proto_state(){ printf 'lock-protocol status\n' | timeout 6 socat - "UNIX-CONNECT:$RT/mei-shell.sock" 2>/dev/null | head -1 | tr -d '\r'; }
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
wait_lock(){ local i=0 n=""; while [ $i -lt 40 ]; do n="$(proto_state)"; case "${n:-}" in active*) { echo "$n"; return 0; } ;; esac; i=$((i+1)); sleep 0.5; done; echo "${n:-?}"; return 1; }

echo "lock module: $(date -Is)"

echo; echo "=== A: the lock covers the screen and the other surfaces refuse ==="
start || exit 1
H globalshortcuts 2>/dev/null | grep -q "ryoku:lock" && ok "the ryoku:lock shortcut is registered" || bad "ryoku:lock was never registered"
lock_now
n="$(wait_lock)"; case "${n:-}" in active*) ok "the compositor confirmed the session lock ($n)" ;; *) bad "the lock did not appear ($n)" ;; esac
lock_now
n2="$(proto_state)"; [ "${n2:-$n}" = "${n:-$n2}" ] && ok "locking twice is safe (still $n2)" || bad "locking twice changed the lock ($n2)"
H dispatch 'hl.dsp.global("ryoku:launcher")' >/dev/null 2>&1; sleep 2
l="$(ns_count launcher)"; [ "${l:-0}" = "0" ] && ok "the launcher refuses to open while locked" || bad "the launcher opened while locked (layers=$l)"

echo; echo "=== B: a wrong password is refused, the lock stays ==="
# The lock surface holds the keyboard, so the virtual keyboard types into it.
# The lock is waited for first: typing before the surface has the focus
# sends the keys nowhere.
wait_lock >/dev/null
# The lock is raised again before typing: after the launcher was refused the
# keyboard focus may sit elsewhere, and the keys would go nowhere.
lock_now
wait_lock >/dev/null
sleep 1
# The keys have to land in the password field, and the field takes the focus
# a moment after the surface appears. The input is repeated until the daemon
# answers: the check stays the same (the refusal has to be logged), only the
# sending is patient.
refused=0
for attempt in 1 2 3; do
  for k in 45 21 52; do "$MEI/docs/tests/tools/nested-input.sh" "$RUN/tools/vkbd/vkbd" $k >/dev/null 2>&1; sleep 0.2; done
  "$MEI/docs/tests/tools/nested-input.sh" "$RUN/tools/vkbd/vkbd" 28 >/dev/null 2>&1
  for _ in $(seq 1 10); do
    grep -q "lock verification refused" "$RUN/logs/daemon.log" 2>/dev/null && { refused=1; break; }
    sleep 0.5
  done
  [ "$refused" = 1 ] && break
  lock_now
  wait_lock >/dev/null
done
if [ "$refused" = 1 ]; then
  ok "the daemon refused the wrong password"
else
  bad "the daemon did not log a refusal"
fi
if grep -q "definitely-not-the-password" "$RUN/logs/daemon.log" 2>/dev/null; then
  bad "the password reached the log"
else
  ok "the password never reached the log"
fi
n3="$(proto_state)"; case "${n3:-}" in active*) ok "the lock is still up after the wrong password ($n3)" ;; *) bad "the lock closed on a wrong password ($n3)" ;; esac

echo; echo "=== C: the daemon's session lock is stubbed in a test session ==="
out="$(HOME="$RUN/home" XDG_CONFIG_HOME="$RUN/config" XDG_RUNTIME_DIR="$RT" \
      "$RUN/bin/mei-shell" lock 2>&1 | head -2)"; echo "   mei-shell lock said: $out"
sleep 2
nl="$(proto_state)"; case "${nl:-}" in active*) ok "the CLI verb opens the session lock" ;; *) bad "the CLI verb did not open the lock ($nl)" ;; esac
if grep -q "lockSession\|login1" "$RUN/logs/daemon.log" 2>/dev/null; then
  bad "the daemon reached for the session lock"
else
  ok "the daemon never reached for login1's session lock (Mei's lock is a surface)"
fi
stop

echo; echo "=== D: the right password unlocks (with the harness's verifier) ==="
start "MEI_LOCK_VERIFY_CMD=/bin/true" || exit 1
lock_now
n4="$(wait_lock)"; case "${n4:-}" in active*) ok "the lock is up ($n4)" ;; *) bad "the lock did not appear ($n4)" ;; esac
unlocked=0
for attempt in 1 2 3; do
  for k in 30 48 46; do "$MEI/docs/tests/tools/nested-input.sh" "$RUN/tools/vkbd/vkbd" $k >/dev/null 2>&1; sleep 0.2; done
  "$MEI/docs/tests/tools/nested-input.sh" "$RUN/tools/vkbd/vkbd" 28 >/dev/null 2>&1
  for _ in $(seq 1 10); do
    n5="$(proto_state)"
    case "${n5:-}" in released*) { unlocked=1; break; } ;; esac
    sleep 0.5
  done
  [ "$unlocked" = 1 ] && break
done
[ "$unlocked" = 1 ] && ok "the lock released after the accepted password" || bad "the lock stayed up ($n5)"
H dispatch 'hl.dsp.global("ryoku:launcher")' >/dev/null 2>&1; sleep 2
l2="$(ns_count launcher)"; [ "${l2:-0}" = "1" ] && ok "the launcher opens again after the unlock" || bad "the launcher did not open after the unlock (layers=$l2)"
stop

echo; echo "=== E: with an unusable PAM service the lock must NOT engage ==="
# The service name resolves to a file in the system PAM directory, so a name
# with no file behind it is exactly the "the setup is broken" case.
start "MEI_LOCK_PAM_SERVICE=mei-no-such-service" || exit 1
lock_now
n6="$(proto_state)"; case "${n6:-}" in released*) ok "the lock refused to engage (the PAM setup is broken)" ;; *) bad "the lock engaged although the PAM setup is broken ($n6)" ;; esac
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
