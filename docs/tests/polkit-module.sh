#!/usr/bin/env bash
# The polkit prompt: the daemon publishes the topic and the control verbs, and
# the D-Bus agent stays OFF in a test session.
#
# The agent is never registered here: the nested session does not set
# MEI_POLKIT_AGENT, and the registration itself is the detection of another
# agent (the authority refuses a second one and the daemon fails closed).
set -uo pipefail
MEI=/home/mei/projects/mei
RUN="$MEI/.run"; RT="$MEI/.r"
HOST_XDG="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
HOST_WL="${WAYLAND_DISPLAY:-wayland-1}"
STAMP="$(date +%H%M%S)"
LOG="$RUN/logs/polkit-module-$STAMP.log"
mkdir -p "$RUN/logs"
exec > >(tee -a "$LOG") 2>&1

fail=0
ok(){ echo "TESTED      $*"; }
bad(){ echo "FAIL        $*"; fail=1; }

SIG=""; QS=""
call(){ printf 'call %s %s\n' "$1" "$2" | socat - "UNIX-CONNECT:$RT/mei-shell.sock" 2>/dev/null | head -1; }
start(){
  ( cd "$MEI" && XDG_RUNTIME_DIR="$HOST_XDG" WAYLAND_DISPLAY="$HOST_WL" ./mei run ) >/dev/null 2>&1
  SIG=""; QS=""
  for _ in $(seq 1 250); do
    SIG="$(ls -d "$RT/hypr/"*/ 2>/dev/null | head -1 | xargs -r basename)"
    QS="$(pgrep -f "^qs -p $MEI/src/ryoku/shell/quickshell/shell" | head -1)"
    [ -n "$SIG" ] && [ -n "$QS" ] && break
    sleep 0.3
  done
  [ -n "$SIG" ] && [ -n "$QS" ] || { bad "the nested session did not come up"; return 1; }
  sleep 7
}
stop(){ ( cd "$MEI" && XDG_RUNTIME_DIR="$HOST_XDG" WAYLAND_DISPLAY="$HOST_WL" ./mei stop ) >/dev/null 2>&1; sleep 2; }

echo "polkit module: $(date -Is)"
start || exit 1

frame="$(printf 'subscribe polkit\n' | timeout 6 socat - "UNIX-CONNECT:$RT/mei-shell.sock" 2>/dev/null | head -1)"
echo "  first polkit frame: ${frame:0:200}"
case "$frame" in
*active*|*polkit*) ok "the daemon publishes the polkit topic" ;;
*) bad "no polkit frame arrived ($frame)" ;;
esac

for verb in polkit.submit polkit.cancel; do
  ans="$(call "$verb" '{"password":"never-logged"}')"
  case "$ans" in
  *unknown\ method*) bad "$verb is not registered ($ans)" ;;
  *) ok "$verb answered: $ans" ;;
  esac
done

if grep -q "polkit agent not registered" "$RUN/logs/daemon.log" 2>/dev/null; then
  ok "the D-Bus agent was not registered (the gate holds)"
else
  bad "the daemon did not log that the agent stayed off"
fi
if grep -q "polkit agent registered" "$RUN/logs/daemon.log" 2>/dev/null; then
  bad "the agent registered itself in a test session"
else
  ok "no agent registered itself in the test session"
fi
if grep -q "never-logged" "$RUN/logs/daemon.log" 2>/dev/null; then
  bad "the submitted password appeared in the log"
else
  ok "the submitted password never reached the log"
fi

stop
( cd "$MEI" && ./mei verify-untouched >/dev/null 2>&1 ) && ok "verify-untouched PASS" || bad "verify-untouched FAILED"
[ "$fail" = 0 ] && echo "POLKIT MODULE: PASS" || echo "POLKIT MODULE: FAIL"
echo "log: $LOG"
exit $fail
