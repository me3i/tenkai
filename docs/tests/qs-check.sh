#!/usr/bin/env bash
# Test-only control-sidebar / quick-settings acceptance for the nested session.
# Lives in docs/tests (versioned). Assumes ./mei run already started the session.
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
fail=0
ok()  { echo "TESTED      $*"; }
bad() { echo "FAIL        $*"; fail=1; }
note(){ echo "NOTE        $*"; }

# ---- real-hardware brightness: record first, restore in a trap ---------------
BL_GET=$(brightnessctl get 2>/dev/null || true)
BL_MAX=$(brightnessctl max 2>/dev/null || true)
restore_bl() {
  if [ -n "${BL_GET:-}" ]; then
    bash -c 'BL=$(ryoku-hw-backlight 2>/dev/null); brightnessctl ${BL:+-d "$BL"} set "'"$BL_GET"'" >/dev/null 2>&1' || true
    echo "restored brightness to $BL_GET (max $BL_MAX)"
  fi
}
trap restore_bl EXIT
note "brightness before: get=${BL_GET:-?} max=${BL_MAX:-?}"

for _ in $(seq 1 60); do
  pgrep -f "qs -p $MEI/src/ryoku/shell/quickshell/shell" >/dev/null && break
  sleep 0.4
done
QS=$(pgrep -f "qs -p $MEI/src/ryoku/shell/quickshell/shell" | head -1)
[ -n "$QS" ] && ok "shell process present (pid $QS)" || { bad "no shell process"; exit 1; }

for _ in $(seq 1 60); do
  SIG=$(basename "$(ls -d "$RUN/rt/hypr/"*/ 2>/dev/null | tail -1)")
  if [ -n "$SIG" ] && HYPRLAND_INSTANCE_SIGNATURE="$SIG" hyprctl -j layers >/dev/null 2>&1; then
    break
  fi
  SIG=""; sleep 0.4
done
[ -n "$SIG" ] || { bad "nested Hyprland instance unreachable"; exit 1; }
ok "nested instance reachable ($SIG)"

# The nested output is the window the host gives us (~950x508 here), too short
# for the whole quick-settings panel. Enlarge this instance's output at runtime
# (targets the nested compositor only) so grim captures the full sidebar.
MON=$(H -j monitors | jq -r '.[0].name' 2>/dev/null)
[ -n "${MON:-}" ] && H keyword monitor "$MON,1600x1000,auto,1" >/dev/null 2>&1 && \
  ok "nested output enlarged to 1600x1000 (monitor $MON)" || note "could not enlarge nested output"

for _ in $(seq 1 60); do
  H globalshortcuts 2>/dev/null | grep -q 'mei:quicksettings' && break
  sleep 0.5
done
H globalshortcuts 2>/dev/null | grep -q 'mei:quicksettings' \
  && ok "global shortcut mei:quicksettings registered" \
  || { bad "mei:quicksettings shortcut never registered"; exit 1; }
sleep 1

namespaces() { H -j layers | jq -r '[.[] | .levels[]? | .[]? | .namespace] | unique | join(",")' 2>/dev/null; }
before_ns=$(namespaces)

# open through the compositor global shortcut (same path as SUPER+ESCAPE)
H dispatch global mei:quicksettings >/dev/null
sleep 2
grim -o WAYLAND-1 "$RUN/shots/qs-$(date +%H%M%S)-open.png" 2>/dev/null
after_ns=$(namespaces)
note "layer namespaces before: $before_ns"
note "layer namespaces after:  $after_ns"

# close it again
H dispatch global mei:quicksettings >/dev/null
sleep 1.5
grim -o WAYLAND-1 "$RUN/shots/qs-$(date +%H%M%S)-closed.png" 2>/dev/null

# ---- audio: nested runtime has no PipeWire socket ----------------------------
if [ -S "$MEI/.r/pipewire-0" ] || [ -S "$MEI/.r/pulse/native" ]; then
  bad "a PipeWire/Pulse socket exists in the nested runtime"
else
  ok "audio UNVERIFIED: no PipeWire socket in the nested runtime (expected)"
fi
# and prove the shell itself holds no PipeWire/Pulse connection (no real audio)
if ss -xp 2>/dev/null | grep -E "pid=$QS," | grep -qiE 'pipewire|pulse'; then
  bad "shell has a PipeWire/Pulse socket (would reach real audio)"
else
  ok "shell holds no PipeWire/Pulse connection (real audio untouched)"
fi

# ---- brightness write path (same command the shell uses), tiny step ---------
if [ -n "${BL_GET:-}" ] && [ -n "${BL_MAX:-}" ] && [ "$BL_MAX" -gt 0 ]; then
  pct=$((100 * BL_GET / BL_MAX))
  step=$((pct + 5)); [ "$step" -gt 100 ] && step=$((pct - 5)); [ "$step" -lt 1 ] && step=1
  bash -c 'BL=$(ryoku-hw-backlight 2>/dev/null); brightnessctl ${BL:+-d "$BL"} set "'"$step"'"% >/dev/null 2>&1' || true
  sleep 0.4
  now=$(brightnessctl get 2>/dev/null || true)
  if [ -n "${now:-}" ] && [ "$now" != "$BL_GET" ]; then
    ok "brightness write path works via the shell's exact command (${pct}% -> ${step}% -> $now)"
  else
    bad "brightness did not change via the shell's command"
  fi
  restore_bl
else
  note "brightness device not readable; control path UNVERIFIED"
fi

# ---- control centre: kanji seals were replaced with English ------------------
if timeout 8 qs ipc --pid "$QS" call qsbar settings bars >/dev/null 2>&1; then
  sleep 2
  grim -o WAYLAND-1 "$RUN/shots/qs-$(date +%H%M%S)-controlcenter.png" 2>/dev/null
  ok "control centre (qsbar settings) opened via IPC"
  timeout 8 qs ipc --pid "$QS" call qsbar settings close >/dev/null 2>&1 || true
  sleep 1
else
  note "qs ipc call qsbar settings bars failed (control centre not screenshotted)"
fi

# ---- process / network hygiene -----------------------------------------------
c=$(pgrep -fc "qs -p $MEI/src/ryoku/shell/quickshell/shell")
[ "$c" = "1" ] && ok "exactly one shell instance" || bad "qs instance count: $c"

for helper in ryoku-cmd-google-lens ryoku-cmd-ocr ryoku-cmd-qr-scan ryoku-cmd-color-picker; do
  pgrep -f "$helper" >/dev/null && bad "dead helper spawned: $helper"
done
ok "no disabled rail helper spawned"

if ss -tunp 2>/dev/null | grep -q "pid=$QS,"; then
  bad "shell owns tcp/udp sockets"
else
  ok "shell has no tcp/udp sockets"
fi

if grep -qiE 'is not a type|Cannot assign|Unable to assign|TypeError|SyntaxError|is not defined|Failed to load' "$RUN/state/mei/surfaces/shell.log" 2>/dev/null; then
  bad "QML error lines in shell log"
else
  ok "no QML load/type errors"
fi

echo "RESULT: $([ "$fail" = 0 ] && echo PASS || echo FAIL)"
exit "$fail"
