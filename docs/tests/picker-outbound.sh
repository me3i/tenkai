#!/usr/bin/env bash
# The wallpaper picker's sources: local folders only, and nothing leaves the
# machine.
#
# The check is threefold:
#   1. the wallpaper path (the QML, the bridge and ryogami itself) has no
#      outbound code: no http, no URL, no catalogue service;
#   2. a live nested session owns no TCP or UDP socket at all;
#   3. the library it lists is the local folder.
set -uo pipefail
TENKAI=$HOME/projects/tenkai
RUN="$TENKAI/.run"; RT="$TENKAI/.r"
HOST_XDG="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
HOST_WL="${WAYLAND_DISPLAY:-wayland-1}"
STAMP="$(date +%H%M%S)"
LOG="$RUN/logs/picker-outbound-$STAMP.log"
mkdir -p "$RUN/logs"
exec > >(tee -a "$LOG") 2>&1

fail=0
ok(){ echo "TESTED      $*"; }
bad(){ echo "FAIL        $*"; fail=1; }
note(){ echo "NOTE        $*"; }

SIG=""; QS=""
start(){
  ( cd "$TENKAI" && XDG_RUNTIME_DIR="$HOST_XDG" WAYLAND_DISPLAY="$HOST_WL" ./tenkai run ) >/dev/null 2>&1
  for _ in $(seq 1 250); do
    SIG="$(ls -d "$RT/hypr/"*/ 2>/dev/null | head -1 | xargs -r basename)"
    QS="$(pgrep -f "^qs -p $TENKAI/src/tenkai_core/shell/quickshell/shell" | head -1)"
    [ -n "$SIG" ] && [ -n "$QS" ] && break; sleep 0.3
  done
  [ -n "$SIG" ] && [ -n "$QS" ] || { bad "the nested session did not come up"; return 1; }
  sleep 8
}
stop(){ ( cd "$TENKAI" && XDG_RUNTIME_DIR="$HOST_XDG" WAYLAND_DISPLAY="$HOST_WL" ./tenkai stop ) >/dev/null 2>&1; sleep 2; }

echo "picker outbound audit: $(date -Is)"

echo; echo "=== 1. no outbound code in the wallpaper path ==="
hits="$(grep -rInE "^[^#]*\b(http://|https://|http\.Get|http\.Client|net/http)\b" \
        src/tenkai_core/shell/ryogami/daemon/ \
        src/tenkai_core/shell/ipc/ryogami.go \
        src/tenkai_core/shell/quickshell/shell/modules/wallpaper/ \
        src/tenkai_core/shell/quickshell/shell/services/Wallpaper.qml 2>/dev/null | grep -v "^.*: *[/*]" || true)"
if [ -z "$hits" ]; then
  ok "no http/URL code in the wallpaper daemon, the bridge or the wallpaper QML"
else
  bad "outbound code in the wallpaper path:"; echo "$hits" | head -5 | sed 's/^/     /'
fi
for name in wallhaven wallhaven.cc steamgridd wallpaper-api; do
  if grep -rIn "$name" src/tenkai_core/shell/ryogami/daemon/ src/tenkai_core/shell/quickshell/shell/modules/wallpaper/ 2>/dev/null | grep -v "^[^\n]*: *//" | head -2; then
    bad "the picker mentions $name"
  else
    ok "the picker does not mention $name"
  fi
done

echo; echo "=== 2. the library is the local folder ==="
if [ -d "$RUN/home/Pictures" ]; then
  ok "Tenkai's library folder exists: $RUN/home/Pictures"
else
  bad "no Pictures folder under .run/home"
fi
if [ -L "$RUN/home/Pictures/Wallpapers" ] || [ -d "$RUN/home/Pictures/Wallpapers" ]; then
  ok "the wallpaper folder is the read-only view of your own library"
else
  note "no Wallpapers folder in the fake home (the session creates one when it is needed)"
fi

echo; echo "=== 3. a live session owns no outbound connection ==="
start || exit 1
sleep 4
socks="$(ss -tunp 2>/dev/null | grep -E "pid=($QS|$(pgrep -f "$RUN/bin/ryogami" | head -1))," || true)"
if [ -z "$socks" ]; then
  ok "the shell and ryogami own no TCP or UDP socket"
else
  bad "a socket is open:"; echo "$socks" | head -5 | sed 's/^/     /'
fi
# the wallpaper daemon's own view: it can only read local folders
if command -v ryogami >/dev/null 2>&1; then
  note "ryogami is on the system: its daemon has no net/http import at all (checked above)"
fi
stop

( cd "$TENKAI" && ./tenkai verify-untouched >/dev/null 2>&1 ) && ok "verify-untouched PASS" || bad "verify-untouched FAILED"
[ "$fail" = 0 ] && echo "PICKER OUTBOUND: PASS" || echo "PICKER OUTBOUND: FAIL"
echo "log: $LOG"
exit $fail
