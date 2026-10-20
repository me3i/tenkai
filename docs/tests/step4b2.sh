#!/usr/bin/env bash
# Step-4 amendments, second shot: capture the REAL launcher (hub closed) and the
# bar's weather slot, to prove no weather block and no placeholder glyph.
set -uo pipefail
MEI=/home/mei/projects/mei
RUN="$MEI/.run"
RT="$MEI/.r"
HOST_XDG="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
HOST_WL="${WAYLAND_DISPLAY:-wayland-1}"
LOG="$RUN/logs/step4b2-$(date +%H%M%S).log"
mkdir -p "$RUN/shots"
exec > >(tee -a "$LOG") 2>&1
fail=0
ok()  { echo "TESTED      $*"; }
bad() { echo "FAIL        $*"; fail=1; }
note(){ echo "NOTE        $*"; }

XDG_RUNTIME_DIR="$HOST_XDG" WAYLAND_DISPLAY="$HOST_WL" "$MEI/mei" verify-untouched 2>&1 | tail -1
XDG_RUNTIME_DIR="$HOST_XDG" WAYLAND_DISPLAY="$HOST_WL" "$MEI/mei" run || { bad "mei run failed"; exit 1; }

SIG=""; QS=""
for _ in $(seq 1 90); do
  SIG="$(ls -d "$RT/hypr/"*/ 2>/dev/null | head -1 | xargs -r basename)"
  QS="$(pgrep -f "qs -p $MEI/src/ryoku/shell/quickshell/shell" | head -1)"
  [ -n "$SIG" ] && [ -n "$QS" ] && break
  sleep 0.5
done
[ -n "$SIG" ] && [ -n "$QS" ] || { bad "session did not come up"; "$MEI/mei" stop; exit 1; }
export XDG_RUNTIME_DIR="$RT" HYPRLAND_INSTANCE_SIGNATURE="$SIG"
WDISP="$(basename "$(ls "$RT"/wayland-* 2>/dev/null | head -1)")"
export WAYLAND_DISPLAY="$WDISP"
H() { hyprctl "$@" 2>/dev/null; }
shot() { grim -o "${WDISP^^}" "$RUN/shots/step4b2-$1.png" 2>/dev/null && echo "  shot: step4b2-$1.png"; }

MON="$(H -j monitors | jq -r '.[0].name' 2>/dev/null)"
[ -n "$MON" ] && H keyword monitor "$MON,1600x1000,auto,1" >/dev/null 2>&1
sleep 3

echo "=== real launcher, hub closed ==="
H dispatch global ryoku:launcher >/dev/null 2>&1; sleep 3
n="$(H clients -j | jq '[.[] | select(.class != "")] | length' 2>/dev/null)"
note "windows (launcher layers count via hyprctl clients): ${n:-?}"
shot launcher-open
H dispatch global ryoku:launcher >/dev/null 2>&1; sleep 1.5

echo "=== bar strip only (weather slot) ==="
H dispatch global ryoku:launcher >/dev/null 2>&1
sleep 2
grim -o "${WDISP^^}" -g "0,0 1600x40" "$RUN/shots/step4b2-bar-strip.png" 2>/dev/null && echo "  shot: step4b2-bar-strip.png"
H dispatch escape >/dev/null 2>&1; sleep 1

"$MEI/mei" stop || true
sleep 2
stray="$(pgrep -af "$RUN/bin/mei-shell|quickshell/shell|quickshell/hub|mei-wm-hyprland|mei-hub" | grep -v pgrep || true)"
[ -z "$stray" ] && ok "clean shutdown: no stray Mei processes" || { bad "stray:"; printf '%s\n' "$stray"; }

XDG_RUNTIME_DIR="$HOST_XDG" WAYLAND_DISPLAY="$HOST_WL" "$MEI/mei" verify-untouched 2>&1 | tail -1
echo "RESULT: $([ "$fail" = 0 ] && echo PASS || echo FAIL)"; echo "log: $LOG"
exit "$fail"
