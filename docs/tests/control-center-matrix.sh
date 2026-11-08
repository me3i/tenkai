#!/usr/bin/env bash
# The control centre must not depend on the bar module.
#
# Three scenarios, each with its own nested session, each rewriting only the
# nested fake config (.run/config/tenkai/shell.json):
#   A  bar off, control_center on  -> the panel opens and closes
#   B  bar on,  control_center off -> the bar renders, the panel stays shut
#   C  bar on,  control_center on  -> both, unchanged (the bar hosts the panel)
#
# The owner's real config is never opened, and verify-untouched runs after
# every scenario.
set -uo pipefail
TENKAI=$HOME/projects/tenkai
RUN="$TENKAI/.run"; RT="$TENKAI/.r"
CFG="$RUN/config/tenkai/shell.json"
HOST_XDG="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
HOST_WL="${WAYLAND_DISPLAY:-wayland-1}"
STAMP="$(date +%H%M%S)"
LOG="$RUN/logs/control-center-matrix-$STAMP.log"
mkdir -p "$RUN/logs"
exec > >(tee -a "$LOG") 2>&1

fail=0
ok(){ echo "TESTED      $*"; }
bad(){ echo "FAIL        $*"; fail=1; }
note(){ echo "NOTE        $*"; }

BK="$(mktemp -d)"; trap 'rm -rf "$BK"' EXIT
[ -f "$CFG" ] && cp "$CFG" "$BK/shell.json" || printf '{}\n' > "$BK/shell.json"

SIG=""; QS=""
H(){ XDG_RUNTIME_DIR="$RT" HYPRLAND_INSTANCE_SIGNATURE="$SIG" hyprctl "$@" 2>/dev/null; }
D(){ H dispatch "hl.dsp.global(\"tenkai:$1\")" >/dev/null 2>&1; }
bar_up(){ H layers | grep -q 'namespace: ryoku-frame'; }
cc_layers(){ H -j layers | jq '[to_entries[] | .value.levels | to_entries[] | .value[]? | select(.namespace=="ryoku-control")] | length' 2>/dev/null; }
# The panel's first build takes a moment (the QML is compiled when the host is
# built), so the check polls for the surface instead of assuming a fixed wait.
wait_cc(){ local i=0 n=0; while [ $i -lt 40 ]; do n="$(cc_layers)"; [ "${n:-0}" != "0" ] && { echo "$n"; return 0; }; i=$((i+1)); sleep 0.5; done; echo "${n:-0}"; return 1; }

set_mods(){ # $1 = overrides
  jq --argjson m "$1" \
    '.modules = ({"bar":true,"launcher":true,"control_center":true,"notifications":true,"tray":true,"wallpaper":true,"settings":true} + $m)' \
    "$BK/shell.json" > "$CFG.tmp" && mv "$CFG.tmp" "$CFG"
}

start(){ # starts a nested session and waits for it
  local old_sig="$SIG"
  ( cd "$TENKAI" && XDG_RUNTIME_DIR="$HOST_XDG" WAYLAND_DISPLAY="$HOST_WL" ./tenkai run ) >/dev/null 2>&1
  SIG=""; QS=""
  for _ in $(seq 1 250); do
    SIG="$(ls -d "$RT/hypr/"*/ 2>/dev/null | head -1 | xargs -r basename)"
    QS="$(pgrep -f "^qs -p $TENKAI/src/tenkai_core/shell/quickshell/shell" | head -1)"
    [ -n "$SIG" ] && [ "$SIG" != "$old_sig" ] && [ -n "$QS" ] && break
    sleep 0.3
  done
  [ -n "$SIG" ] && [ -n "$QS" ] || { bad "the nested session did not come up"; return 1; }
  sleep 7
}
stop(){ ( cd "$TENKAI" && XDG_RUNTIME_DIR="$HOST_XDG" WAYLAND_DISPLAY="$HOST_WL" ./tenkai stop ) >/dev/null 2>&1; sleep 2; }

echo "control centre vs the bar module: $(date -Is)"

echo; echo "=== A: bar OFF, control_center ON ==="
set_mods '{"bar":false}'
start || exit 1
bar_up && bad "A: a bar layer exists with the bar module off" || ok "A: no bar layer (the bar module is off)"
D quicksettings
n="$(wait_cc)"; [ "${n:-0}" -ge 1 ] && ok "A: the control centre opened without the bar (ryoku-control layers=$n)" || bad "A: the control centre did not open (layers=$n)"
SL="$RUN/state/tenkai/surfaces/shell.log"; [ -f "$SL" ] || SL="$RUN/home/.local/state/tenkai/surfaces/shell.log"
if grep -E "TypeError|ReferenceError" "$SL" 2>/dev/null | grep -q "controlcenter"; then
  bad "A: the panel logged QML type errors without the bar"
else
  ok "A: the panel logged no QML type errors without the bar"
fi
D quicksettings; sleep 2
n2="$(cc_layers)"; [ "${n2:-1}" = "0" ] && ok "A: it closes again (layers=0)" || bad "A: it stayed open (layers=$n2)"
stop
( cd "$TENKAI" && ./tenkai verify-untouched >/dev/null 2>&1 ) && ok "A: verify-untouched PASS" || bad "A: verify-untouched FAILED"

echo; echo "=== B: bar ON, control_center OFF ==="
set_mods '{"control_center":false}'
start || exit 1
bar_up && ok "B: the bar still renders (ryoku-frame)" || bad "B: the bar is missing"
D quicksettings; sleep 2.5
n="$(cc_layers)"; [ "${n:-1}" = "0" ] && ok "B: the control centre stayed shut with its flag off (layers=0)" || bad "B: the control centre opened although its flag is off (layers=$n)"
bar_up && ok "B: the bar survived the attempt" || bad "B: the bar broke"
stop
( cd "$TENKAI" && ./tenkai verify-untouched >/dev/null 2>&1 ) && ok "B: verify-untouched PASS" || bad "B: verify-untouched FAILED"

echo; echo "=== C: bar ON, control_center ON (unchanged) ==="
set_mods '{}'
start || exit 1
bar_up && ok "C: the bar renders" || bad "C: the bar is missing"
D quicksettings; sleep 2.5
# With the bar on, the bar keeps hosting the panel exactly as before: the
# request reaches ShellState (the same assertion the Phase 8 module matrix
# makes) and the bar's own control-centre button is what opens the panel.
trace="$(XDG_RUNTIME_DIR="$RT" qs ipc --pid "$QS" call shell lastSurface 2>/dev/null | head -1)"
[ "$trace" = "quick-settings" ] && ok "C: the control centre request reaches ShellState ($trace)" || bad "C: the trace is '$trace'"
n="$(cc_layers)"; [ "${n:-1}" = "0" ] && ok "C: the bar-hosted path is unchanged (no second panel: layers=0)" || bad "C: a second panel opened (layers=$n)"
bar_up && ok "C: the bar is intact" || bad "C: the bar broke"
stop
( cd "$TENKAI" && ./tenkai verify-untouched >/dev/null 2>&1 ) && ok "C: verify-untouched PASS" || bad "C: verify-untouched FAILED"

cp -f "$BK/shell.json" "$CFG"
echo
[ "$fail" = 0 ] && echo "CONTROL-CENTRE MATRIX: PASS" || echo "CONTROL-CENTRE MATRIX: FAIL"
echo "log: $LOG"
exit $fail
