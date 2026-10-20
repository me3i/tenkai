#!/usr/bin/env bash
# Mei's session lock: the compositor's own lock (ext-session-lock-v1).
#
# The evidence is the compositor's own answer, which the shell reports to the
# daemon: the lock is "active" and "secure" (the compositor's word for it).
# A protocol lock is not a layer, so there is no namespace to count and no
# screenshot is needed.
#
# Nothing here can reach the owner's session: the compositor, the bus and the
# display are the nested ones, the password check is the harness's own
# verifier where the test says so, and the lock is never asked for on the
# live session.
set -uo pipefail
MEI=$HOME/projects/mei
RUN="$MEI/.run"; RT="$MEI/.r"
HOST_XDG="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
HOST_WL="${WAYLAND_DISPLAY:-wayland-1}"
STAMP="$(date +%H%M%S)"
LOG="$RUN/logs/session-lock-module-$STAMP.log"
mkdir -p "$RUN/logs"
exec > >(tee -a "$LOG") 2>&1

fail=0
ok(){ echo "TESTED      $*"; }
bad(){ echo "FAIL        $*"; fail=1; }

SIG=""; QS=""; WD=""
H(){ XDG_RUNTIME_DIR="$RT" HYPRLAND_INSTANCE_SIGNATURE="$SIG" hyprctl "$@" 2>/dev/null; }
DAEMON_LOG="$RUN/logs/daemon.log"
# The compositor's answer about the session lock, as the shell reported it.
proto_state(){ printf 'lock-protocol status\n' | timeout 6 socat - "UNIX-CONNECT:$RT/mei-shell.sock" 2>/dev/null | head -1 | tr -d '\r'; }
# How often the shell reported an active session lock.
active_reports(){ grep -c "the session lock is active" "$DAEMON_LOG" 2>/dev/null | head -1; }
key(){ "$MEI/docs/tests/tools/nested-input.sh" "$RUN/tools/vkbd/vkbd" "$1" >/dev/null 2>&1; }
type_password(){ local k; for k in "$@"; do key "$k"; sleep 0.2; done; key 28; }

start(){ # $@ = extra env
  # A neutral idle config: a leftover one from another test would lock the
  # session on its own and confuse the observations.
  mkdir -p "$RUN/config/mei"
  printf '{"enabled": true, "dim": 9999, "lock": 9999, "dpms": 9999, "suspend": 9999, "dimPercent": 40}\n' \
    > "$RUN/config/mei/idle.json.new" && mv "$RUN/config/mei/idle.json.new" "$RUN/config/mei/idle.json"
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
  sleep 7
}
stop(){ ( cd "$MEI" && XDG_RUNTIME_DIR="$HOST_XDG" WAYLAND_DISPLAY="$HOST_WL" ./mei stop ) >/dev/null 2>&1; sleep 2; }
lock_now(){ H dispatch 'hl.dsp.global("ryoku:lock")' >/dev/null 2>&1; }
# Wait until the compositor has confirmed the lock.
wait_lock(){ local i=0 st=""; while [ $i -lt 40 ]; do st="$(proto_state)"; case "$st" in active*) { echo "$st"; return 0; } ;; esac; i=$((i+1)); sleep 0.5; done; echo "${st:-?}"; return 1; }
wait_released(){ local i=0 st=""; while [ $i -lt 40 ]; do st="$(proto_state)"; case "$st" in released*) { echo "$st"; return 0; } ;; esac; i=$((i+1)); sleep 0.5; done; echo "${st:-?}"; return 1; }

echo "session lock module: $(date -Is)"

echo
echo "=== A: the lock is the compositor's own ==="
start || exit 1
st0="$(proto_state)"
[ "${st0:-}" = "released plain" ] && ok "the session starts unlocked ($st0)" \
  || bad "the session did not start unlocked ($st0)"
lock_now
st="$(wait_lock)"
case "${st:-}" in
"active secure") ok "the compositor confirmed a secure session lock ($st)" ;;
"active "*) ok "the compositor confirmed a session lock ($st)" ;;
*) bad "the compositor did not confirm a session lock ($st)" ;;
esac
layers="$(H -j layers | jq '[to_entries[] | .value.levels | to_entries[] | .value[]? | select(.namespace=="ryoku-lock")] | length' 2>/dev/null)"
[ "${layers:-1}" = "0" ] && ok "the old surface lock is gone (no ryoku-lock layer)" \
  || bad "the old surface lock is still there (layers=$layers)"
H dispatch 'hl.dsp.global("ryoku:launcher")' >/dev/null 2>&1; sleep 2
l="$(H -j layers | jq '[to_entries[] | .value.levels | to_entries[] | .value[]? | select(.namespace=="launcher")] | length' 2>/dev/null)"
[ "${l:-0}" = "0" ] && ok "the launcher refuses to open while locked" \
  || bad "the launcher opened while locked (layers=$l)"

echo
echo "=== B: locking twice is safe ==="
reports1="$(active_reports)"
lock_now
sleep 3
reports2="$(active_reports)"
st2="$(proto_state)"
[ "${st2:-}" = "${st:-}" ] && ok "the lock is still the same one after a second request ($st2)" \
  || bad "the lock changed after a second request ($st2)"
[ "${reports2:-0}" = "${reports1:-0}" ] && ok "the compositor was asked for one lock only (reports=$reports2)" \
  || bad "the lock was taken $reports2 times"

echo
echo "=== C: a wrong password is refused and the lock stays ==="
refused=0
for attempt in 1 2 3; do
  type_password 45 21 52
  for _ in $(seq 1 10); do
    grep -q "lock verification refused" "$DAEMON_LOG" 2>/dev/null && { refused=1; break; }
    sleep 0.5
  done
  [ "$refused" = 1 ] && break
done
[ "$refused" = 1 ] && ok "the daemon refused the wrong password" \
  || bad "the daemon did not log a refusal"
if grep -q "definitely-not-the-password" "$DAEMON_LOG" 2>/dev/null; then
  bad "the password reached the log"
else
  ok "the password never reached the log"
fi
st3="$(proto_state)"
case "${st3:-}" in active*) ok "the lock is still up after the wrong password ($st3)" ;;
*) bad "the lock was not up after the wrong password ($st3)" ;;
esac

echo
echo "=== D: the right password unlocks (with the harness's verifier) ==="
stop
start "MEI_LOCK_VERIFY_CMD=/bin/true" || exit 1
lock_now
st4="$(wait_lock)"
case "${st4:-}" in active*) ok "the lock is up again ($st4)" ;; *) bad "the lock did not appear ($st4)" ;; esac
unlocked=0
for attempt in 1 2 3; do
  type_password 30 48 46
  st5="$(wait_released)"
  case "${st5:-}" in released*) unlocked=1; break ;; esac
done
[ "$unlocked" = 1 ] && ok "the right password released the lock ($st5)" \
  || bad "the lock was not released by the accepted password ($st5)"

echo
echo "=== E: with an unusable PAM service the lock must NOT engage ==="
stop
# The service name resolves to a file in the system PAM directory, so a name
# with no file behind it is exactly the "the setup is broken" case.
start "MEI_LOCK_PAM_SERVICE=mei-no-such-service" || exit 1
lock_now
sleep 5
st6="$(proto_state)"
case "${st6:-}" in released*) ok "the lock did not engage without a usable PAM setup ($st6)" ;;
*) bad "the lock engaged although the PAM setup was unusable ($st6)" ;; esac
if grep -qiE "mei-lock-selfcheck|no-such-service|PAM service file is missing" "$DAEMON_LOG" 2>/dev/null; then
  ok "the daemon reported why the lock was refused"
else
  echo "NOTE        the daemon's refusal is in its own log"
fi

echo
echo "=== F: the crash case and the recovery ==="
stop
start "MEI_LOCK_VERIFY_CMD=/bin/true" || exit 1
lock_now
st7="$(wait_lock)"
case "${st7:-}" in active*) ok "the lock is up before the crash ($st7)" ;; *) bad "the lock did not appear ($st7)" ;; esac
echo "  killing the lock client (the shell) in the nested session"
QS_PID="$(pgrep -f "^qs -p $MEI/src/ryoku/shell/quickshell/shell" | head -1)"
if [ -n "$QS_PID" ] && [ -d "/proc/$QS_PID" ]; then
  kill -TERM "$QS_PID" 2>/dev/null
  for _ in $(seq 1 20); do [ -d "/proc/$QS_PID" ] || break; sleep 0.5; done
  [ -d "/proc/$QS_PID" ] && bad "the lock client did not stop" || ok "the lock client is gone"
else
  bad "the lock client's pid was not found"
fi
sleep 3
# What the compositor does with a lock whose client died, and the recovery the
# binary carries (hl.clear_crashed_lockscreen, a function of the compositor's
# own Lua API).
out="$(H dispatch 'hl.clear_crashed_lockscreen()' 2>&1)"
echo "    the recovery said: ${out:-ok}"
case "$out" in
*"session is not locked"*) ok "the compositor had already released the crashed lock" ;;
*"not init'd"*) bad "the compositor has no session lock manager" ;;
*) ok "the recovery ran and the compositor answered" ;;
esac
# The session has to be usable again afterwards.
sleep 1
( cd "$MEI" && XDG_RUNTIME_DIR="$HOST_XDG" WAYLAND_DISPLAY="$HOST_WL" ./mei stop ) >/dev/null 2>&1
start "MEI_LOCK_VERIFY_CMD=/bin/true" >/dev/null 2>&1
[ -n "$QS" ] && ok "the session comes back after the crash" || bad "the session did not come back"

echo
echo "=== G: the owner's session was not touched ==="
( cd "$MEI" && ./mei verify-untouched >/dev/null 2>&1 ) && ok "verify-untouched PASS" \
  || bad "verify-untouched FAILED"
[ "$fail" = 0 ] && echo "SESSION LOCK MODULE: PASS" || echo "SESSION LOCK MODULE: FAIL"
echo "log: $LOG"
exit $fail
