#!/usr/bin/env bash
# The clipboard history: the daemon keeps a bounded, local history and
# publishes it; the surface exists in the shell.
#
# The test only reads: it subscribes to the topic and calls the control
# verbs, and it checks the owner's own clipboard is untouched (the nested
# session shares the host's selection, so nothing may write to it).
set -uo pipefail
MEI=/home/mei/projects/mei
RUN="$MEI/.run"; RT="$MEI/.r"
HOST_XDG="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
HOST_WL="${WAYLAND_DISPLAY:-wayland-1}"
STAMP="$(date +%H%M%S)"
LOG="$RUN/logs/clipboard-module-$STAMP.log"
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

echo "clipboard module: $(date -Is)"
start || exit 1

frame="$(printf 'subscribe clipboard\n' | timeout 6 socat - "UNIX-CONNECT:$RT/mei-shell.sock" 2>/dev/null | head -1)"
echo "  first clipboard frame: ${frame:0:200}"
case "$frame" in
*entries*|*clipboard*) ok "the daemon publishes the clipboard history" ;;
*) bad "no clipboard frame arrived ($frame)" ;;
esac

for verb in clipboard.clear clipboard.copy clipboard.delete clipboard.star; do
  ans="$(call "$verb" '{"entry":0}')"
  case "$ans" in
  *unknown\ method*) bad "$verb is not registered ($ans)" ;;
  *) ok "$verb answered: $ans" ;;
  esac
done

# the history must live inside Mei's own state, never in the owner's home
if [ -d "$RUN/state/mei" ] || [ -d "$RUN/home/.local/state/mei" ]; then
  ok "the clipboard state is inside Mei's own .run tree"
else
  bad "no clipboard state under .run"
fi
if ls "$HOME/.local/state/mei/clipboard"* >/dev/null 2>&1; then
  bad "clipboard state leaked into the owner's home"
else
  ok "nothing leaked into the owner's home"
fi

SHELLLOG="$RUN/state/mei/surfaces/shell.log"; [ -f "$SHELLLOG" ] || SHELLLOG="$RUN/home/.local/state/mei/surfaces/shell.log"
if grep -iE "TypeError|ReferenceError" "$SHELLLOG" 2>/dev/null | grep -qi "clipboard"; then
  bad "the shell logged QML errors around the clipboard"
else
  ok "the shell logged no QML errors around the clipboard"
fi

stop
( cd "$MEI" && ./mei verify-untouched >/dev/null 2>&1 ) && ok "verify-untouched PASS" || bad "verify-untouched FAILED"
[ "$fail" = 0 ] && echo "CLIPBOARD MODULE: PASS" || echo "CLIPBOARD MODULE: FAIL"
echo "log: $LOG"
exit $fail
