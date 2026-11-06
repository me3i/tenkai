#!/usr/bin/env bash
# The OSD: the daemon publishes the feed and the shell's OSD surfaces exist.
#
# The test never changes the panel brightness (that would be a live side
# effect): it subscribes to the feed over the control socket and reads the
# frame, and it checks the backlight value is untouched afterwards. The
# visible OSD (the popups themselves) is on the live checklist, because
# flashing one needs a real brightness or volume change.
set -uo pipefail
TENKAI=$HOME/projects/tenkai
RUN="$TENKAI/.run"; RT="$TENKAI/.r"
HOST_XDG="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
HOST_WL="${WAYLAND_DISPLAY:-wayland-1}"
STAMP="$(date +%H%M%S)"
LOG="$RUN/logs/osd-module-$STAMP.log"
mkdir -p "$RUN/logs"
exec > >(tee -a "$LOG") 2>&1

fail=0
ok(){ echo "TESTED      $*"; }
bad(){ echo "FAIL        $*"; fail=1; }

SIG=""; QS=""
H(){ XDG_RUNTIME_DIR="$RT" HYPRLAND_INSTANCE_SIGNATURE="$SIG" hyprctl "$@" 2>/dev/null; }
start(){
  ( cd "$TENKAI" && XDG_RUNTIME_DIR="$HOST_XDG" WAYLAND_DISPLAY="$HOST_WL" ./tenkai run ) >/dev/null 2>&1
  SIG=""; QS=""
  for _ in $(seq 1 250); do
    SIG="$(ls -d "$RT/hypr/"*/ 2>/dev/null | head -1 | xargs -r basename)"
    QS="$(pgrep -f "^qs -p $TENKAI/src/ryoku/shell/quickshell/shell" | head -1)"
    [ -n "$SIG" ] && [ -n "$QS" ] && break
    sleep 0.3
  done
  [ -n "$SIG" ] && [ -n "$QS" ] || { bad "the nested session did not come up"; return 1; }
  sleep 7
}
stop(){ ( cd "$TENKAI" && XDG_RUNTIME_DIR="$HOST_XDG" WAYLAND_DISPLAY="$HOST_WL" ./tenkai stop ) >/dev/null 2>&1; sleep 2; }

echo "osd module: $(date -Is)"
before="$(brightnessctl g 2>/dev/null)"
start || exit 1

frame="$(printf 'subscribe osd\n' | timeout 6 socat - "UNIX-CONNECT:$RT/tenkai-shell.sock" 2>/dev/null | head -1)"
echo "  first osd frame: ${frame:0:160}"
case "$frame" in
*brightness*) ok "the daemon publishes the osd feed with a brightness value" ;;
*) bad "no osd frame arrived ($frame)" ;;
esac

val="$(printf '%s' "$frame" | python3 -c "
import json,sys
try: print(json.load(sys.stdin)['brightness']['value'])
except Exception: print('?')" 2>/dev/null)"
cur="$(brightnessctl g 2>/dev/null)"
echo "  the feed says ${val} (0..1), the panel reads ${cur}"
[ "$val" != "?" ] && ok "the feed carries a real brightness fraction ($val)" || bad "the frame carried no value"

SHELLLOG="$RUN/state/tenkai/surfaces/shell.log"; [ -f "$SHELLLOG" ] || SHELLLOG="$RUN/home/.local/state/tenkai/surfaces/shell.log"
if grep -iE "TypeError|ReferenceError" "$SHELLLOG" 2>/dev/null | grep -qi "osd"; then
  bad "the shell logged QML errors around the OSD"
else
  ok "the shell logged no QML errors around the OSD"
fi

after="$(brightnessctl g 2>/dev/null)"
[ "$before" = "$after" ] && ok "the panel brightness was not written ($after)" || bad "the panel brightness changed: $before -> $after"

stop
( cd "$TENKAI" && ./tenkai verify-untouched >/dev/null 2>&1 ) && ok "verify-untouched PASS" || bad "verify-untouched FAILED"
[ "$fail" = 0 ] && echo "OSD MODULE: PASS" || echo "OSD MODULE: FAIL"
echo "log: $LOG"
exit $fail
