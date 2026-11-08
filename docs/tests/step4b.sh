#!/usr/bin/env bash
# Step-4 amendments (owner decisions):
#  1. weather.go / music.go / calendar.go outbound compiled out  -> prove
#  2. CHANGE ON MAP hidden
#  3. launcher weather widget disabled (and its Settings rows)
# Test-only, git-ignored.
set -uo pipefail
TENKAI=$HOME/projects/tenkai
RUN="$TENKAI/.run"
RT="$TENKAI/.r"
HOST_XDG="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
HOST_WL="${WAYLAND_DISPLAY:-wayland-1}"
LOG="$RUN/logs/step4b-$(date +%H%M%S).log"
mkdir -p "$RUN/shots"
exec > >(tee -a "$LOG") 2>&1
fail=0
ok()  { echo "TESTED      $*"; }
bad() { echo "FAIL        $*"; fail=1; }
note(){ echo "NOTE        $*"; }

echo "=== STATIC PROOF (no session needed) ==="
if (cd "$TENKAI/src/tenkai_core/shell/ipc" && go list -deps . 2>/dev/null | grep -qx 'net/http'); then
  bad "net/http is still in the daemon dependency graph"
else
  ok "net/http is NOT in the daemon dependency graph (go list -deps)"
fi
if (cd "$TENKAI/src/tenkai_core/shell/ipc" && go list -deps . 2>/dev/null | grep -qx 'net'); then
  note "the 'net' package is linked (unix sockets only)"
fi
grep -rn 'net/http\|http\.Client' "$TENKAI/src/tenkai_core/shell/ipc"/*.go | grep -v '// ' | grep -q . \
  && bad "an http reference survives in the daemon source" \
  || ok "no net/http import or http.Client in the daemon source (comments only)"
for pair in "src/tenkai_core/hub/quickshell/SettingsSheet.qml:CHANGE ON MAP" \
            "src/tenkai_core/hub/quickshell/pages/LauncherPage.qml:Show weather" \
            "src/tenkai_core/shell/quickshell/shell/modules/launcher/variants/main/Preview.qml:readonly property bool showWeather: false" \
            "src/tenkai_core/shell/quickshell/shell/modules/launcher/variants/hero/Preview.qml:visible: false   // TENKAI"; do
  f="${pair%%:*}"; pat="${pair#*:}"
  grep -qF "$pat" "$TENKAI/$f" && ok "UI marker present: $(basename "$f") <- $pat" || bad "UI marker missing: $f <- $pat"
done

echo; echo "=== verify-untouched BEFORE ==="
XDG_RUNTIME_DIR="$HOST_XDG" WAYLAND_DISPLAY="$HOST_WL" "$TENKAI/tenkai" verify-untouched 2>&1 | tail -2

echo "=== starting ./tenkai run ==="
XDG_RUNTIME_DIR="$HOST_XDG" WAYLAND_DISPLAY="$HOST_WL" "$TENKAI/tenkai" run || { bad "tenkai run failed"; exit 1; }

SIG=""; QS=""
for _ in $(seq 1 90); do
  SIG="$(ls -d "$RT/hypr/"*/ 2>/dev/null | head -1 | xargs -r basename)"
  QS="$(pgrep -f "qs -p $TENKAI/src/tenkai_core/shell/quickshell/shell" | head -1)"
  [ -n "$SIG" ] && [ -n "$QS" ] && break
  sleep 0.5
done
[ -n "$SIG" ] && [ -n "$QS" ] || { bad "session did not come up"; "$TENKAI/tenkai" stop; exit 1; }
export XDG_RUNTIME_DIR="$RT" HYPRLAND_INSTANCE_SIGNATURE="$SIG"
WDISP="$(basename "$(ls "$RT"/wayland-* 2>/dev/null | head -1)")"
export WAYLAND_DISPLAY="$WDISP"
H() {
  local rt="${RT:-${TENKAI:-$HOME/projects/tenkai}/.r}" sig="${SIG:-}"
  [ -n "$sig" ] && [ -S "$rt/hypr/$sig/.socket.sock" ] \
    || { echo "REFUSED: nested Hyprland socket absent; no live fallback" >&2; return 1; }
  XDG_RUNTIME_DIR="$rt" HYPRLAND_INSTANCE_SIGNATURE="$sig" hyprctl "$@" 2>/dev/null
}
shot() { grim -o "${WDISP^^}" "$RUN/shots/step4b-$1.png" 2>/dev/null && echo "  shot: step4b-$1.png"; }
mesh() { "$RUN/bin/tenkai-shell" "$@"; }
hubs() { for p in $(pgrep -f "hub/quickshell" 2>/dev/null); do [ "$(cat /proc/$p/comm 2>/dev/null)" = qs ] && { echo "$p"; return; }; done; }

MON="$(H -j monitors | jq -r '.[0].name' 2>/dev/null)"
[ -n "$MON" ] && H keyword monitor "$MON,1600x1000,auto,1" >/dev/null 2>&1
sleep 2

DPID="$(pgrep -f "$RUN/bin/tenkai-shell daemon" | head -1)"
note "daemon pid=$DPID shell pid=$QS"

echo; echo "=== OUTBOUND CHECK (daemon / shell / hub) ==="
mesh hub open >/dev/null 2>&1
HUB=""; for _ in $(seq 1 60); do HUB="$(hubs)"; [ -n "$HUB" ] && break; sleep 0.5; done
sleep 4
for p in "$DPID" "$QS" "$HUB"; do
  [ -n "$p" ] || continue
  if ss -tunp 2>/dev/null | grep -qE "pid=$p,"; then
    bad "pid $p owns a tcp/udp socket:"; ss -tunp 2>/dev/null | grep -E "pid=$p,"
  else
    ok "pid $p owns no tcp/udp socket"
  fi
done
allpids="$(printf '%s\n' "$DPID" "$QS" "$HUB" | grep -E '^[0-9]+$' | paste -sd'|')"
if [ -n "$allpids" ]; then
  any="$(ss -tunp 2>/dev/null | grep -E "pid=($allpids)," || true)"
  [ -z "$any" ] && ok "no tcp/udp on any Tenkai process (daemon + shell + hub)" || { bad "tcp/udp seen:"; printf '%s\n' "$any"; }
fi

echo; echo "=== UI: General page has no CHANGE ON MAP ==="
mesh hub open global >/dev/null 2>&1; sleep 3
shot hub-generic-general
note "check: the timezone row shows the zone only, no button"
echo "=== UI: Launcher page has no weather rows ==="
mesh hub open launcher >/dev/null 2>&1; sleep 3
shot hub-generic-launcher
note "check: HERO card has Show greeting + Solar line, no Show weather / Weather units"
echo "=== UI: real launcher has no weather block ==="
H dispatch global tenkai:launcher >/dev/null 2>&1; sleep 2.5
shot launcher-noweather
H dispatch global tenkai:launcher >/dev/null 2>&1; sleep 1

mesh hub close >/dev/null 2>&1; sleep 2

echo; echo "=== stopping ==="
"$TENKAI/tenkai" stop || true
sleep 2
stray="$(pgrep -af "$RUN/bin/tenkai-shell|quickshell/shell|quickshell/hub|tenkai-wm-hyprland|tenkai-hub" | grep -v pgrep || true)"
[ -z "$stray" ] && ok "clean shutdown: no stray Tenkai processes" || { bad "stray:"; printf '%s\n' "$stray"; }

echo; echo "=== verify-untouched AFTER ==="
XDG_RUNTIME_DIR="$HOST_XDG" WAYLAND_DISPLAY="$HOST_WL" "$TENKAI/tenkai" verify-untouched 2>&1 | tail -2

echo; echo "RESULT: $([ "$fail" = 0 ] && echo PASS || echo FAIL)"; echo "log: $LOG"
exit "$fail"
