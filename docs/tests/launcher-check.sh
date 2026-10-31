#!/usr/bin/env bash
# Test-only launcher acceptance for the nested session. Lives in docs/tests (versioned).
# Assumes ./mei run already started the session.
set -uo pipefail
MEI=$HOME/projects/mei
RUN="$MEI/.run"
export XDG_RUNTIME_DIR="$MEI/.r"
export WAYLAND_DISPLAY=wayland-1
SIG=""
H() {
  local rt="${RT:-${MEI:-$HOME/projects/mei}/.r}" sig="${SIG:-}"
  [ -n "$sig" ] && [ -S "$rt/hypr/$sig/.socket.sock" ] \
    || { echo "REFUSED: nested Hyprland socket absent; no live fallback" >&2; return 1; }
  XDG_RUNTIME_DIR="$rt" HYPRLAND_INSTANCE_SIGNATURE="$sig" hyprctl "$@" 2>/dev/null
}
VK="$MEI/docs/tests/tools/nested-input.sh $RUN/tools/vkbd/vkbd"
fail=0
ok()  { echo "TESTED      $*"; }
bad() { echo "FAIL        $*"; fail=1; }
layers_launcher() {
  H -j layers | jq '[to_entries[] | .value.levels | to_entries[] | .value[]? | select(.namespace=="launcher")] | length' 2>/dev/null
}

for _ in $(seq 1 60); do
  pgrep -f "qs -p $MEI/src/ryoku/shell/quickshell/shell" >/dev/null && break
  sleep 0.4
done
QS=$(pgrep -f "qs -p $MEI/src/ryoku/shell/quickshell/shell" | head -1)
[ -n "$QS" ] && ok "shell process present (pid $QS)" || { bad "no shell process"; exit 1; }

# The nested signature only exists after the compositor starts; resolve it now,
# not before ./mei run returned.
for _ in $(seq 1 60); do
  SIG=$(basename "$(ls -d "$RUN/rt/hypr/"*/ 2>/dev/null | tail -1)")
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
  H globalshortcuts 2>/dev/null | grep -q 'mei:launcher' && break
  sleep 0.5
done
H globalshortcuts 2>/dev/null | grep -q 'mei:launcher' \
  && ok "global shortcut mei:launcher registered" \
  || { bad "mei:launcher shortcut never registered"; exit 1; }
sleep 1

# prove the launcher writes usage state from scratch in this run
rm -f "$RUN/state/mei/launcher-usage.json"

# start from closed
if [ "$(layers_launcher)" != "0" ]; then
  H dispatch 'hl.dsp.global("mei:launcher")' >/dev/null
  for _ in $(seq 1 20); do [ "$(layers_launcher)" = "0" ] && break; sleep 0.25; done
fi

# open through the compositor global shortcut (same path as SUPER+SPACE).
# The first open after a cold start compiles the launcher QML, which took ~5 s
# on this box; poll instead of assuming a fixed delay.
H dispatch 'hl.dsp.global("mei:launcher")' >/dev/null
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
"$VK" 53
sleep 1
grim -o WAYLAND-1 "$RUN/shots/launcher-$(date +%H%M%S)-slash.png" 2>/dev/null
"$VK" 14
sleep 0.6

# search "kitty" and press Enter
"$VK" 37 23 20 20 21
sleep 1.5
grim -o WAYLAND-1 "$RUN/shots/launcher-$(date +%H%M%S)-search.png" 2>/dev/null
"$VK" 28
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
  echo "$ENVS" | grep -qx "XDG_RUNTIME_DIR=$MEI/.r" && ok "app runtime dir = nested .r" || bad "app runtime dir wrong"
  echo "$ENVS" | grep -qx "WAYLAND_DISPLAY=wayland-1" && ok "app on nested Wayland display" || bad "app display wrong"
  kill -TERM "$KPID" 2>/dev/null || true
  for _ in $(seq 1 20); do [ -z "$(H -j clients | jq -r '.[]|select(.class=="kitty")|.pid' 2>/dev/null)" ] && break; sleep 0.25; done
else
  bad "kitty did not launch"
fi
grim -o WAYLAND-1 "$RUN/shots/launcher-$(date +%H%M%S)-launched.png" 2>/dev/null

grep -q '"kitty"' "$RUN/state/mei/launcher-usage.json" 2>/dev/null \
  && ok "frecency written under fake XDG_STATE_HOME ($RUN/state/mei/launcher-usage.json)" \
  || bad "frecency missing under fake state home"

# reopen and close with Esc
H dispatch 'hl.dsp.global("mei:launcher")' >/dev/null
for _ in $(seq 1 40); do [ "$(layers_launcher)" = "1" ] && break; sleep 0.25; done
sleep 2
"$VK" 1
n=1
for _ in $(seq 1 30); do
  n=$(layers_launcher)
  [ "$n" = "0" ] && break
  sleep 0.25
done
[ "$n" = "0" ] && ok "Esc closes the launcher (0 layers)" || bad "launcher layers after Esc: $n"

c=$(pgrep -fc "qs -p $MEI/src/ryoku/shell/quickshell/shell")
[ "$c" = "1" ] && ok "exactly one shell/launcher instance" || bad "qs instance count: $c"

if ss -tunp 2>/dev/null | grep -q "pid=$QS,"; then
  bad "shell owns tcp/udp sockets"
else
  ok "shell has no tcp/udp sockets"
fi

if grep -q 'ryoku-cmd-radio' "$RUN/state/mei/surfaces/shell.log" 2>/dev/null; then
  echo "NOTE        radio probe line present (local unbuilt helper; inspect)"
else
  ok "no radio probe spawned"
fi

if grep -qiE 'is not a type|Cannot assign|Unable to assign|TypeError|SyntaxError|is not defined|Failed to load' "$RUN/state/mei/surfaces/shell.log" 2>/dev/null; then
  bad "QML error lines in shell log"
else
  ok "no launcher QML load/type errors"
fi

grim -o WAYLAND-1 "$RUN/shots/launcher-$(date +%H%M%S)-bar.png" 2>/dev/null
echo "RESULT: $([ "$fail" = 0 ] && echo PASS || echo FAIL)"
exit "$fail"
