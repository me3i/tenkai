#!/usr/bin/env bash
# Short separate test: switch the nested compositor through all five
# workspaces and assert the bar's `workspaceState.focused` follows each one.
#
# This deliberately focuses workspaces 2-5 (owner follow-up); it creates no
# windows and no test surface there. The main phase9.sh pass stays on
# workspace 1 for speed.
set -uo pipefail
TENKAI=$HOME/projects/tenkai
RUN="$TENKAI/.run"; RT="$TENKAI/.r"
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
# Clean stale state from prior gates (same fix as F2 isolation bug)
rm -rf "$RUN/r/quickshell/by-id"/* 2>/dev/null || true
# Ensure clean exit: stop any leftover Tenkai session
 trap 'cd /home/tenkai/projects/tenkai 2>/dev/null; ./tenkai stop >/dev/null 2>&1' EXIT
# Resolve nested session signature from the actual session directory
# (same pattern as launcher-check.sh: discover after ./tenkai run)
SIG=""
H() {
  local rt="${RT:-$TENKAI/.r}" sig="${SIG:-}"
  [ -n "$sig" ] && [ -S "$rt/hypr/$sig/.socket.sock" ] \
    || { echo "REFUSED: nested Hyprland socket absent; no live fallback" >&2; return 1; }
  XDG_RUNTIME_DIR="$rt" HYPRLAND_INSTANCE_SIGNATURE="$sig" hyprctl "$@" 2>/dev/null
}
IPC() { XDG_RUNTIME_DIR="$RT" qs ipc --pid "$QS" call qsbar "$@" 2>&1; }

cleanup() {
  ( cd "$TENKAI" && XDG_RUNTIME_DIR="$HOST_XDG" WAYLAND_DISPLAY="$HOST_WL" ./tenkai stop ) >/dev/null 2>&1
}
trap cleanup EXIT

echo; echo "=== verify-untouched BEFORE ==="
VB="$( cd "$TENKAI" && env -u HYPRLAND_INSTANCE_SIGNATURE -u WAYLAND_DISPLAY \
      XDG_RUNTIME_DIR="$HOST_XDG" ./tenkai verify-untouched 2>&1 | tail -1 )"
echo "  $VB"
case "$VB" in *PASS*) ok "verify-untouched before" ;; *) bad "verify-untouched before did not PASS" ;; esac

if [ -f "$RUN/pids" ] || pgrep -f "^$RUN/bin/tenkai-shell daemon" >/dev/null 2>&1; then
  bad "a Tenkai session is already running; refusing to start another"
  echo "RESULT: FAIL"; exit 1
fi

echo; echo "=== launch nested session ==="
( cd "$TENKAI" && XDG_RUNTIME_DIR="$HOST_XDG" WAYLAND_DISPLAY="$HOST_WL" ./tenkai run ) >/dev/null 2>&1

# Discover the nested Hyprland instance signature — only accept the
# session F1 itself started, never a leftover from a prior gate.
# Compare the hypr directory before and after ./tenkai run.
BEFORE=$(ls -d "$RUN/r/hypr/"*/ 2>/dev/null | sort)
./tenkai run > /dev/null 2>&1 &
for _ in $(seq 1 120); do
  AFTER=$(ls -d "$RUN/r/hypr/"*/ 2>/dev/null | sort)
  NEW=$(comm -13 <(echo "$BEFORE") <(echo "$AFTER") | head -1)
  if [ -n "$NEW" ]; then
    SIG=$(basename "$NEW")
    [ -S "$RUN/r/hypr/$SIG/.socket.sock" ] && break
  fi
  sleep 0.5
done
[ -n "$SIG" ] || { bad "nested Hyprland instance unreachable; no new session sig found"; exit 1; }
ok "nested instance reachable ($SIG)"

# Bounded wait, 120 s: the bar compiles its QML on a cold start, so the shell
# (and the bar's first IPC to Hyprland, which fills its workspace list) appears
# well after ./tenkai run returns. If the bar's workspace list is still empty after
# 120 s that is a startup failure, not a race, and the diagnostics say why.
QS=""
for _ in $(seq 1 400); do
  QS=$(pgrep -f "^qs -p $TENKAI/src/ryoku/shell/quickshell/shell" | head -1)
  [ -n "$QS" ] && break
  sleep 0.3
done
if [ -z "$QS" ]; then
  bad "bar shell process not seen after 120 s"
  echo "--- diagnostics ---"
  ps -eo pid,args | grep -F "$TENKAI/src/ryoku" | grep -v grep || echo "(no process mentions the project)"
  echo "--- shell log tail ---"
  tail -30 "$RUN/state/tenkai/surfaces/shell.log" 2>/dev/null || echo "(no shell log)"
  echo "RESULT: FAIL"; exit 1
fi
# Bounded wait, 120 s: the bar compiles its QML on a cold start, so the shell
# (and the bar's first IPC to Hyprland, which fills its workspace list) appears
# well after ./tenkai run returns. If the bar's workspace list is still empty after
# 120 s that is a startup failure, not a race, and the diagnostics say why.
QS=""
for _ in $(seq 1 400); do
  QS=$(pgrep -f "^qs -p $TENKAI/src/ryoku/shell/quickshell/shell" | head -1)
  [ -n "$QS" ] && break
  sleep 0.3
done
if [ -z "$QS" ]; then
  bad "bar shell process not seen after 120 s"
  echo "--- diagnostics ---"
  ps -eo pid,args | grep -F "$TENKAI/src/ryoku" | grep -v grep || echo "(no process mentions the project)"
  echo "--- shell log tail ---"
  tail -30 "$RUN/state/tenkai/surfaces/shell.log" 2>/dev/null || echo "(no shell log)"
  echo "RESULT: FAIL"; exit 1
fi
export XDG_RUNTIME_DIR="$RT" HYPRLAND_INSTANCE_SIGNATURE="$SIG"
BUS="$(cat "$RUN/bus" 2>/dev/null)"
note "nested sig $SIG, shell $QS, bus ${BUS:-?}"
BASELINE_SIG="$(sed -n 's/^BASELINE_SIG="\(.*\)"$/\1/p' "$RUN/session.sh")"
[ -n "$BASELINE_SIG" ] && [ "$SIG" != "$BASELINE_SIG" ] && ok "nested signature differs from live baseline" \
  || bad "nested signature equals baseline (or baseline missing)"
for _ in $(seq 1 60); do case "$(IPC layout)" in \{*) break;; esac; sleep 0.5; done
case "$(IPC layout)" in \{*) ok "qsbar IPC live";; *) bad "qsbar IPC never appeared";; esac

echo; echo "=== switch through workspaces 1-5; bar must follow ==="
# Wait until the bar's workspace list is populated AND the bar reports a
# focused workspace. A cold start leaves the bar's workspace widget with an
# empty list for a while; polling the exact command the sweep below uses
# (qs ipc call qsbar workspaceState) turns that wait into a bounded wait
# instead of a blind assumption. With NO wait, the very first workspace
# query hits an empty list, which is exactly the silent "bar ''" failure.
WS_LIST=""
WAITED=0
while [ "$WAITED" -lt 120 ]; do
  WS_LIST=$(
    XDG_RUNTIME_DIR="$RT" qs ipc --pid "$QS" call qsbar workspaceState 2>/dev/null       | python3 -c 'import json,sys; print(json.load(sys.stdin)["names"])' 2>/dev/null
  )
  if [ -n "$WS_LIST" ]; then
    break
  fi
  sleep 1
  WAITED=$((WAITED + 1))
done
  sig="${HYPRLAND_INSTANCE_SIGNATURE:-}"
if [ -z "$WS_LIST" ]; then
  echo "FAIL    bar's workspace list empty after 120 s"
  echo "---- ps (hyprland + qs + tenkai):"
  ps -eo pid,cmd | grep -E "hyprland|qs -c|tenkai-" | grep -v grep || echo "(no process matches)"
  echo "---- hyprctl workspaces (what Hyprland thinks):"
  hyprctl workspaces -j 2>/dev/null | head -c 500
  echo
  echo "---- shell log tail:"
  tail -30 "$RUN/state/tenkai/surfaces/shell.log" 2>/dev/null || echo "(no shell log)"
  echo "---- daemon log tail:"
  tail -30 "$RUN/state/tenkai/shell.log" 2>/dev/null || echo "(no daemon log)"
  echo "RESULT: FAIL"; exit 1
fi
echo "note    bar workspace list after wait: ${WS_LIST}"
BAR_FOCUSED=""
for ws in 1 2 3 4 5; do
  H dispatch "hl.dsp.focus({ workspace = $ws })" >/dev/null 2>&1
  sleep 0.8
  hy="$(H -j activeworkspace | jq -r '.id' 2>/dev/null)"
  bar="$(IPC workspaceState | python3 -c 'import json,sys; print(json.load(sys.stdin)["focused"])' 2>/dev/null || true)"
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
  if [ -z "$BAR_FOCUSED" ] && [ "$bar" = "$ws" ]; then
    BAR_FOCUSED="$ws"
  fi
done
# The last workspace the test switches to stays focused; the test stops on
# workspace 1, so assert that the bar ends on workspace 1.
# Leave the session on workspace 1 for a clean stop.
H dispatch "hl.dsp.focus({ workspace = 1 })" >/dev/null 2>&1
sleep 0.5
barall="$(IPC workspaceState | python3 -c 'import json,sys; print(",".join(sorted(json.load(sys.stdin)["names"], key=int)))' 2>/dev/null)"
note "bar workspace list after the sweep: ${barall:-?}"

echo; echo "=== stop and verify-untouched AFTER ==="
cleanup
trap - EXIT
VA="$( cd "$TENKAI" && env -u HYPRLAND_INSTANCE_SIGNATURE -u WAYLAND_DISPLAY \
      XDG_RUNTIME_DIR="$HOST_XDG" ./tenkai verify-untouched 2>&1 | tail -1 )"
echo "  $VA"
case "$VA" in *PASS*) ok "verify-untouched after" ;; *) bad "verify-untouched after did not PASS" ;; esac

echo
[ "$fail" = 0 ] && echo "RESULT: PASS" || echo "RESULT: FAIL"
echo "log: $LOG"
exit "$fail"
