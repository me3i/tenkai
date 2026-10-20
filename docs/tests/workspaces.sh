#!/usr/bin/env bash
# Short separate test: switch the nested compositor through all five
# workspaces and assert the bar's `workspaceState.focused` follows each one.
#
# This deliberately focuses workspaces 2-5 (owner follow-up); it creates no
# windows and no test surface there. The main phase9.sh pass stays on
# workspace 1 for speed.
set -uo pipefail
MEI=/home/mei/projects/mei
RUN="$MEI/.run"; RT="$MEI/.r"
HOST_XDG="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
HOST_WL="${WAYLAND_DISPLAY:-wayland-1}"
STAMP="$(date +%H%M%S)"
LOG="$RUN/logs/workspaces-$STAMP.log"
mkdir -p "$RUN/logs"
exec > >(tee -a "$LOG") 2>&1

fail=0; SIG=""; QS=""; BUS=""
ok()  { echo "TESTED      $*"; }
bad() { echo "FAIL        $*"; fail=1; }
note(){ echo "NOTE        $*"; }
H() {
  local rt="${RT:-$MEI/.r}" sig="${SIG:-}"
  [ -n "$sig" ] && [ -S "$rt/hypr/$sig/.socket.sock" ] \
    || { echo "REFUSED: nested Hyprland socket absent; no live fallback" >&2; return 1; }
  XDG_RUNTIME_DIR="$rt" HYPRLAND_INSTANCE_SIGNATURE="$sig" hyprctl "$@" 2>/dev/null
}
IPC() { XDG_RUNTIME_DIR="$RT" qs ipc --pid "$QS" call qsbar "$@" 2>&1; }

cleanup() {
  ( cd "$MEI" && XDG_RUNTIME_DIR="$HOST_XDG" WAYLAND_DISPLAY="$HOST_WL" ./mei stop ) >/dev/null 2>&1
}
trap cleanup EXIT

echo; echo "=== verify-untouched BEFORE ==="
VB="$( cd "$MEI" && env -u HYPRLAND_INSTANCE_SIGNATURE -u WAYLAND_DISPLAY \
      XDG_RUNTIME_DIR="$HOST_XDG" ./mei verify-untouched 2>&1 | tail -1 )"
echo "  $VB"
case "$VB" in *PASS*) ok "verify-untouched before" ;; *) bad "verify-untouched before did not PASS" ;; esac

if [ -f "$RUN/pids" ] || pgrep -f "^$RUN/bin/mei-shell daemon" >/dev/null 2>&1; then
  bad "a Mei session is already running; refusing to start another"
  echo "RESULT: FAIL"; exit 1
fi

echo; echo "=== launch nested session ==="
( cd "$MEI" && XDG_RUNTIME_DIR="$HOST_XDG" WAYLAND_DISPLAY="$HOST_WL" ./mei run ) >/dev/null 2>&1
for _ in $(seq 1 240); do
  SIG="$(ls -d "$RT/hypr/"*/ 2>/dev/null | head -1 | xargs -r basename)"
  QS=""
  for p in $(pgrep -f "^qs -p $MEI/src/ryoku/shell/quickshell/shell" 2>/dev/null); do
    prt="$(tr '\0' '\n' < /proc/$p/environ 2>/dev/null | sed -n 's/^XDG_RUNTIME_DIR=//p')"
    [ "$prt" = "$RT" ] && QS="$p"
  done
  [ -n "$SIG" ] && [ -S "$RT/hypr/$SIG/.socket.sock" ] && [ -n "$QS" ] && break
  sleep 0.3
done
if [ -z "$SIG" ] || [ -z "$QS" ]; then bad "nested session did not come up"; echo "RESULT: FAIL"; exit 1; fi
export XDG_RUNTIME_DIR="$RT" HYPRLAND_INSTANCE_SIGNATURE="$SIG"
BUS="$(cat "$RUN/bus" 2>/dev/null)"
note "nested sig $SIG, shell $QS, bus ${BUS:-?}"
BASELINE_SIG="$(sed -n 's/^BASELINE_SIG="\(.*\)"$/\1/p' "$RUN/session.sh")"
[ -n "$BASELINE_SIG" ] && [ "$SIG" != "$BASELINE_SIG" ] && ok "nested signature differs from live baseline" \
  || bad "nested signature equals baseline (or baseline missing)"
for _ in $(seq 1 60); do case "$(IPC layout)" in \{*) break;; esac; sleep 0.5; done
case "$(IPC layout)" in \{*) ok "qsbar IPC live";; *) bad "qsbar IPC never appeared";; esac

echo; echo "=== switch through workspaces 1-5; bar must follow ==="
for ws in 1 2 3 4 5; do
  H dispatch "hl.dsp.focus({ workspace = $ws })" >/dev/null 2>&1
  sleep 0.8
  hy="$(H -j activeworkspace | jq -r '.id' 2>/dev/null)"
  bar="$(IPC workspaceState | python3 -c 'import json,sys; print(json.load(sys.stdin)["focused"])' 2>/dev/null)"
  names="$(IPC workspaceState | python3 -c 'import json,sys; print(",".join(sorted(json.load(sys.stdin)["names"], key=int)))' 2>/dev/null)"
  if [ "$hy" = "$ws" ] && [ "$bar" = "$ws" ]; then
    ok "workspace $ws: Hyprland active $hy, bar focused $bar"
  else
    bad "workspace $ws: Hyprland '$hy', bar '$bar'"
  fi
  case ",$names," in
    *",$ws,"*) ok "workspace $ws is in the bar's live list ($names)" ;;
    *) bad "workspace $ws missing from the bar's live list ($names)" ;;
  esac
done
# Leave the session on workspace 1 for a clean stop.
H dispatch "hl.dsp.focus({ workspace = 1 })" >/dev/null 2>&1
sleep 0.5
barall="$(IPC workspaceState | python3 -c 'import json,sys; print(",".join(sorted(json.load(sys.stdin)["names"], key=int)))' 2>/dev/null)"
note "bar workspace list after the sweep: ${barall:-?}"

echo; echo "=== stop and verify-untouched AFTER ==="
cleanup
trap - EXIT
VA="$( cd "$MEI" && env -u HYPRLAND_INSTANCE_SIGNATURE -u WAYLAND_DISPLAY \
      XDG_RUNTIME_DIR="$HOST_XDG" ./mei verify-untouched 2>&1 | tail -1 )"
echo "  $VA"
case "$VA" in *PASS*) ok "verify-untouched after" ;; *) bad "verify-untouched after did not PASS" ;; esac

echo
[ "$fail" = 0 ] && echo "RESULT: PASS" || echo "RESULT: FAIL"
echo "log: $LOG"
exit "$fail"
