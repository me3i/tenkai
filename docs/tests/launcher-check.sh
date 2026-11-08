#!/usr/bin/env bash
# Test-only launcher acceptance for the nested session. Lives in docs/tests (versioned).
# Starts its own nested session: accept stops the previous gate's session before
# this one runs, so there is never one waiting to be borrowed.
set -uo pipefail
TENKAI=$HOME/projects/tenkai
RUN="$TENKAI/.run"
RT="$TENKAI/.r"
# The host runtime and display, read before the nested ones replace them: ./tenkai
# run is launched from the host session and builds the nested one itself.
HOST_XDG="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
HOST_WL="${WAYLAND_DISPLAY:-wayland-1}"
export XDG_RUNTIME_DIR="$RT"
export WAYLAND_DISPLAY=wayland-1
SIG=""
H() {
  local rt="${RT:-${TENKAI:-$HOME/projects/tenkai}/.r}" sig="${SIG:-}"
  [ -n "$sig" ] && [ -S "$rt/hypr/$sig/.socket.sock" ] \
    || { echo "REFUSED: nested Hyprland socket absent; no live fallback" >&2; return 1; }
  XDG_RUNTIME_DIR="$rt" HYPRLAND_INSTANCE_SIGNATURE="$sig" hyprctl "$@" 2>/dev/null
}
# A two-word command in a variable does not survive "$VK": quoting keeps it one
# word, so the call was a command named ".../nested-input.sh .../vkbd". A
# function keeps both words on the command line. VK 53 sends one key;
# VK 37 23 20 20 21 types "kitty". The guard pins the display to .r.
VK() { "$TENKAI/docs/tests/tools/nested-input.sh" "$RUN/tools/vkbd/vkbd" "$@"; }
fail=0
ok()  { echo "TESTED      $*"; }
bad() { echo "FAIL        $*"; fail=1; }
layers_launcher() {
  H -j layers | jq '[to_entries[] | .value.levels | to_entries[] | .value[]? | select(.namespace=="launcher")] | length' 2>/dev/null
}

echo; echo "=== launch nested session ==="
if [ -f "$RUN/pids" ]; then bad "a Tenkai session is already running; refusing to start another"; exit 1; fi
( cd "$TENKAI" && XDG_RUNTIME_DIR="$HOST_XDG" WAYLAND_DISPLAY="$HOST_WL" ./tenkai run ) >/dev/null 2>&1

# Bounded wait, 120 s: the shell compiles its QML on a cold start, so the
# process appears well after ./tenkai run returns. If it is still absent after two
# minutes that is a startup failure, not a race, and the diagnostics say why.
QS=""
for _ in $(seq 1 400); do
  QS=$(pgrep -f "^qs -p $TENKAI/src/tenkai_core/shell/quickshell/shell" | head -1)
  [ -n "$QS" ] && break
  sleep 0.3
done
if [ -z "$QS" ]; then
  bad "no shell process after 120 s"
  echo "--- diagnostics ---"
  ps -eo pid,args | grep -F "$TENKAI/src/tenkai_core" | grep -v grep || echo "(no process mentions the project)"
  for f in "$RUN"/logs/shell*.log "$RUN"/state/tenkai/surfaces/shell.log; do
    [ -f "$f" ] && { echo "--- $f (last 20) ---"; tail -n 20 "$f"; }
  done
  exit 1
fi
ok "shell process present (pid $QS)"

# The nested signature only exists after the compositor starts; resolve it now,
# not before ./tenkai run returned.
for _ in $(seq 1 60); do
  SIG=$(basename "$(ls -d "$RUN/r/hypr/"*/ 2>/dev/null | tail -1)")
  if [ -n "$SIG" ] && HYPRLAND_INSTANCE_SIGNATURE="$SIG" hyprctl -j layers >/dev/null 2>&1; then
    break
  fi
  SIG=""
  sleep 0.4
done
[ -n "$SIG" ] || { bad "nested Hyprland instance unreachable"; exit 1; }
ok "nested instance reachable ($SIG)"

# Wait for Quickshell to register the shortcut; the qs process exists before
# the QML (and its CustomShortcut) has finished loading.
for _ in $(seq 1 60); do
  H globalshortcuts 2>/dev/null | grep -q 'tenkai:launcher' && break
  sleep 0.5
done
H globalshortcuts 2>/dev/null | grep -q 'tenkai:launcher' \
  && ok "global shortcut tenkai:launcher registered" \
  || { bad "tenkai:launcher shortcut never registered"; exit 1; }
sleep 1

# prove the launcher writes usage state from scratch in this run
rm -f "$RUN/state/tenkai/launcher-usage.json"

# start from closed
if [ "$(layers_launcher)" != "0" ]; then
  H dispatch 'hl.dsp.global("tenkai:launcher")' >/dev/null
  for _ in $(seq 1 20); do [ "$(layers_launcher)" = "0" ] && break; sleep 0.25; done
fi

# open through the compositor global shortcut (same path as SUPER+SPACE).
# The first open after a cold start compiles the launcher QML, which took ~5 s
# on this box; poll instead of assuming a fixed delay.
H dispatch 'hl.dsp.global("tenkai:launcher")' >/dev/null
n=0
for _ in $(seq 1 40); do
  n=$(layers_launcher)
  [ "$n" = "1" ] && break
  sleep 0.3
done
[ "$n" = "1" ] && ok "launcher opens on the bound shortcut (1 layer)" || bad "launcher layers after open: $n"
# The layer exists before it owns keyboard input; keys sent in the first frames
# go to the window underneath.
sleep 2
grim -o WAYLAND-1 "$RUN/shots/launcher-$(date +%H%M%S)-open.png" 2>/dev/null

# "/" must no longer enter a command mode (Actions provider disabled)
VK 53
sleep 1
grim -o WAYLAND-1 "$RUN/shots/launcher-$(date +%H%M%S)-slash.png" 2>/dev/null
VK 14
sleep 0.6

# search "kitty" and press Enter
VK 37 23 20 20 21
sleep 1.5
grim -o WAYLAND-1 "$RUN/shots/launcher-$(date +%H%M%S)-search.png" 2>/dev/null
VK 28
KPID=""
for _ in $(seq 1 40); do
  KPID=$(H -j clients | jq -r '.[] | select(.class=="kitty") | .pid' 2>/dev/null | head -1)
  [ -n "$KPID" ] && break
  sleep 0.25
done
if [ -n "${KPID:-}" ]; then
  ok "launcher launched kitty inside the nested session (pid $KPID)"
  ENVS=$(tr '\0' '\n' < "/proc/$KPID/environ" 2>/dev/null)
  echo "$ENVS" | grep -qx "HOME=$RUN/home" && ok "app HOME = fake home" || bad "app HOME wrong"
  echo "$ENVS" | grep -qx "XDG_RUNTIME_DIR=$TENKAI/.r" && ok "app runtime dir = nested .r" || bad "app runtime dir wrong"
  echo "$ENVS" | grep -qx "WAYLAND_DISPLAY=wayland-1" && ok "app on nested Wayland display" || bad "app display wrong"
  kill -TERM "$KPID" 2>/dev/null || true
  for _ in $(seq 1 20); do [ -z "$(H -j clients | jq -r '.[]|select(.class=="kitty")|.pid' 2>/dev/null)" ] && break; sleep 0.25; done
else
  bad "kitty did not launch"
fi
grim -o WAYLAND-1 "$RUN/shots/launcher-$(date +%H%M%S)-launched.png" 2>/dev/null

grep -q '"kitty"' "$RUN/state/tenkai/launcher-usage.json" 2>/dev/null \
  && ok "frecency written under fake XDG_STATE_HOME ($RUN/state/tenkai/launcher-usage.json)" \
  || bad "frecency missing under fake state home"

# reopen and close with Esc
H dispatch 'hl.dsp.global("tenkai:launcher")' >/dev/null
for _ in $(seq 1 40); do [ "$(layers_launcher)" = "1" ] && break; sleep 0.25; done
sleep 2
VK 1
n=1
for _ in $(seq 1 30); do
  n=$(layers_launcher)
  [ "$n" = "0" ] && break
  sleep 0.25
done
[ "$n" = "0" ] && ok "Esc closes the launcher (0 layers)" || bad "launcher layers after Esc: $n"

c=$(pgrep -fc "qs -p $TENKAI/src/tenkai_core/shell/quickshell/shell")
[ "$c" = "1" ] && ok "exactly one shell/launcher instance" || bad "qs instance count: $c"

if ss -tunp 2>/dev/null | grep -q "pid=$QS,"; then
  bad "shell owns tcp/udp sockets"
else
  ok "shell has no tcp/udp sockets"
fi

if grep -q 'ryoku-cmd-radio' "$RUN/state/tenkai/surfaces/shell.log" 2>/dev/null; then
  echo "NOTE        radio probe line present (local unbuilt helper; inspect)"
else
  ok "no radio probe spawned"
fi

if grep -qiE 'is not a type|Cannot assign|Unable to assign|TypeError|SyntaxError|is not defined|Failed to load' "$RUN/state/tenkai/surfaces/shell.log" 2>/dev/null; then
  bad "QML error lines in shell log"
else
  ok "no launcher QML load/type errors"
fi

grim -o WAYLAND-1 "$RUN/shots/launcher-$(date +%H%M%S)-bar.png" 2>/dev/null
echo "RESULT: $([ "$fail" = 0 ] && echo PASS || echo FAIL)"
exit "$fail"
