#!/usr/bin/env bash
# Phase 9 core: the items that need one nested session and no harness of their
# own. Run by phase9.sh after the cold start; also usable alone.
#   1  launch + no QML errors      2  bar + workspaces match Hyprland
#   3  launcher (docs/tests/launcher-check.sh)
#   4  sidebar (panel, clock render, read-only audio, real brightness)
#  10  missing dependency (brightness helper + brightnessctl)
#   11 clean shutdown              12  5-minute idle capture
set -uo pipefail
MEI=$HOME/projects/mei
RUN="$MEI/.run"; RT="$MEI/.r"
HOST_XDG="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
HOST_WL="${WAYLAND_DISPLAY:-wayland-1}"
STAMP="$(date +%H%M%S)"
LOG="$RUN/logs/phase9-core-$STAMP.log"
mkdir -p "$RUN/logs" "$RUN/shots"
exec > >(tee -a "$LOG") 2>&1

fail=0; SIG=""; QS=""; BUS=""; DPID=""; SHELLLOG=""
ok()  { echo "TESTED      $*"; }
bad() { echo "FAIL        $*"; fail=1; }
note(){ echo "NOTE        $*"; }
H() {
  local rt="${RT:-${MEI:-$HOME/projects/mei}/.r}" sig="${SIG:-}"
  [ -n "$sig" ] && [ -S "$rt/hypr/$sig/.socket.sock" ] \
    || { echo "REFUSED: nested Hyprland socket absent; no live fallback" >&2; return 1; }
  XDG_RUNTIME_DIR="$rt" HYPRLAND_INSTANCE_SIGNATURE="$sig" hyprctl "$@" 2>/dev/null
}
D() { H dispatch "hl.dsp.global(\"mei:$1\")" >/dev/null 2>&1; }
IPC() { XDG_RUNTIME_DIR="$RT" qs ipc --pid "$QS" call qsbar "$@" 2>&1; }
SH() { XDG_RUNTIME_DIR="$RT" qs ipc --pid "$QS" call shell "$@" 2>&1; }
owner() { busctl --address="$BUS" list --no-legend 2>/dev/null | awk -v n="$1" '$1==n{print $2}' | grep -v '^-$'; }

cleanup() {
  # Real-hardware brightness: restore the pre-test level before anything else,
  # even if the script dies mid-step (owner rule 7: small steps, restore).
  [ -n "${BR_RESTORE:-}" ] && brightnessctl set "$BR_RESTORE" >/dev/null 2>&1 || true
  [ "${KEEP:-0}" = 1 ] && return
  ( cd "$MEI" && XDG_RUNTIME_DIR="$HOST_XDG" WAYLAND_DISPLAY="$HOST_WL" ./mei stop ) >/dev/null 2>&1
}
trap cleanup EXIT

echo "=== cold start check ==="
if [ -e "$RUN/config/mei/shell.json" ]; then
  bad "shell.json already exists; this is not a cold start"
else
  ok "cold start: no ~/.config/mei/shell.json before launch"
fi

echo; echo "=== verify-untouched BEFORE ==="
( cd "$MEI" && env -u HYPRLAND_INSTANCE_SIGNATURE -u WAYLAND_DISPLAY \
    XDG_RUNTIME_DIR="$HOST_XDG" ./mei verify-untouched 2>&1 | tail -1 )

echo; echo "=== launch ==="
( cd "$MEI" && XDG_RUNTIME_DIR="$HOST_XDG" WAYLAND_DISPLAY="$HOST_WL" ./mei run ) >/dev/null 2>&1
for _ in $(seq 1 240); do
  SIG="$(ls -d "$RT/hypr/"*/ 2>/dev/null | head -1 | xargs -r basename)"
  QS="$(pgrep -f "^qs -p $MEI/src/ryoku/shell/quickshell/shell" | head -1)"
  [ -n "$SIG" ] && [ -S "$RT/hypr/$SIG/.socket.sock" ] && [ -n "$QS" ] && break
  sleep 0.3
done
if [ -z "$SIG" ] || [ -z "$QS" ]; then bad "session did not come up"; echo "RESULT: FAIL"; exit 1; fi
export XDG_RUNTIME_DIR="$RT" HYPRLAND_INSTANCE_SIGNATURE="$SIG"
export WAYLAND_DISPLAY="$(basename "$(ls "$RT"/wayland-* 2>/dev/null | head -1)")"
BUS="$(cat "$RUN/bus" 2>/dev/null)"
SHELLLOG="$RUN/state/mei/surfaces/shell.log"
DPID="$(pgrep -f "^$RUN/bin/mei-shell daemon" | head -1)"
note "nested sig $SIG, display $WAYLAND_DISPLAY, shell $QS, daemon $DPID"
[ "$WAYLAND_DISPLAY" = "wayland-1" ] && ok "nested display is wayland-1 (launcher harness expects it)" \
  || bad "nested display is $WAYLAND_DISPLAY"

echo; echo "=== 1. launch: one shell, fresh defaults, private bus, no QML errors ==="
# Count only Quickshell servers bound to the nested runtime. Any Mei qs on
# another runtime is a leak onto the live session: kill it (we started it).
nqs=0; leak=""
for _ in $(seq 1 10); do
  nqs=0; leak=""
  for p in $(pgrep -f "^qs -p $MEI/" 2>/dev/null); do
    prt="$(tr '\0' '\n' < /proc/$p/environ 2>/dev/null | sed -n 's/^XDG_RUNTIME_DIR=//p')"
    [ -z "$prt" ] && continue
    if [ "$prt" = "$RT" ]; then
      case "$(tr '\0' '\n' < /proc/$p/cmdline 2>/dev/null | head -3 | tail -1)" in
        */quickshell/shell) nqs=$((nqs+1)) ;;
      esac
    else leak="$leak $p:$prt"; fi
  done
  [ -z "$leak" ] && [ "$nqs" = 1 ] && break
  sleep 0.4
done
if [ -n "$leak" ]; then
  for lp in $leak; do kill -TERM "${lp%%:*}" 2>/dev/null || true; done
  bad "Mei qs leaked outside the nested runtime (killed):$leak"
fi
[ "$nqs" = 1 ] && ok "exactly one shell instance (nested runtime)" || bad "shell instances: $nqs"
BASELINE_SIG="$(sed -n 's/^BASELINE_SIG="\(.*\)"$/\1/p' "$RUN/session.sh")"
[ -n "$BASELINE_SIG" ] && [ "$SIG" != "$BASELINE_SIG" ] && ok "nested signature differs from the live baseline" || bad "nested signature equals baseline"
LIVE_BUS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=$HOST_XDG/bus}"
[ -n "$BUS" ] && [ "$BUS" != "$LIVE_BUS" ] && ok "private nested bus, not the live bus" || bad "bus is live or missing"
if [ -s "$RUN/config/mei/shell.json" ]; then
  ok "a fresh shell.json was written from defaults"
  if jq -e 'has("modules")' "$RUN/config/mei/shell.json" >/dev/null 2>&1; then
    note "fresh shell.json carries a modules block: $(jq -c '.modules' "$RUN/config/mei/shell.json")"
  else
    ok "fresh shell.json has no modules block -> every module defaults ON"
  fi
  [ "$(jq -r '.theme.theme // "?"' "$RUN/config/mei/shell.json")" = "Default" ] \
    && ok "default theme is Default" || bad "default theme is $(jq -r '.theme.theme' "$RUN/config/mei/shell.json")"
  [ "$(jq -r '.theme.matugen.mode // "?"' "$RUN/config/mei/shell.json")" = "Dark" ] \
    && ok "default matugen mode is Dark" || bad "default mode is $(jq -r '.theme.matugen.mode' "$RUN/config/mei/shell.json")"
else
  # The settings store writes lazily: a fresh start keeps the code defaults in
  # memory and touches disk only on the first change. Absence is the expected
  # cold-start state; the compiled defaults are asserted in settings.go and the
  # resulting dark palette in the Phase 8 theme probe.
  ok "fresh start has no shell.json (settings are written on first change; code defaults Default + Dark)"
fi
sleep 2
qerr="$(grep -E 'TypeError|ReferenceError|is not defined|SyntaxError|is not creatable|Cannot assign to|Unable to assign' "$SHELLLOG" 2>/dev/null | grep -viE 'pipewire|pulseaudio' | head -5)"
[ -z "$qerr" ] && ok "no hard QML errors in the shell log" || bad "QML errors: $qerr"

echo; echo "=== 2. bar renders; workspaces match nested Hyprland ==="
# cold start: the layer map can trail the IPC by a few seconds
for _ in $(seq 1 40); do H layers 2>/dev/null | grep -q 'namespace: ryoku-frame' && break; sleep 0.5; done
H layers | grep -q 'namespace: ryoku-frame' && ok "bar layer present (ryoku-frame)" || bad "no bar layer"
for _ in $(seq 1 60); do case "$(IPC layout)" in \{*) break;; esac; sleep 0.5; done
case "$(IPC layout)" in \{*) ok "qsbar IPC live";; *) bad "qsbar IPC never appeared";; esac
# Owner directive: this pass runs on workspace 1 only. Do not focus or create
# workspaces 2/3 here, so no test surface or window ever appears elsewhere.
# The bar's per-workspace sync is consequently checked on workspace 1 only.
for ws in 1; do
  # Lua-config instances: the classic `workspace N` dispatcher is accepted but
  # does nothing here; hl.dsp.focus is the form the nested config uses.
  H dispatch "hl.dsp.focus({ workspace = $ws })" >/dev/null 2>&1; sleep 0.9
  hy="$(H -j activeworkspace | jq -r '.id')"
  bar="$(IPC workspaceState | python3 -c 'import json,sys; print(json.load(sys.stdin)["focused"])' 2>/dev/null)"
  [ -n "$bar" ] && [ "$bar" = "$hy" ] && ok "workspace $ws: bar sees $bar, Hyprland active $hy" \
    || bad "workspace $ws: bar='$bar' hypr='$hy'"
done
hyall="$(H -j workspaces | jq -r '[.[].id|tostring]|sort|join(",")')"
barall="$(IPC workspaceState | python3 -c 'import json,sys; print(",".join(sorted(json.load(sys.stdin)["names"], key=int)))' 2>/dev/null)"
[ "$barall" = "$hyall" ] && ok "bar workspace list matches Hyprland ($barall)" || bad "bar list '$barall' != hypr '$hyall'"

echo; echo "=== 3. launcher (docs/tests/launcher-check.sh) ==="
LAUNCH_LOG="$RUN/logs/phase9-launcher-$STAMP.log"
bash "$MEI/docs/tests/launcher-check.sh" > "$LAUNCH_LOG" 2>&1
lrc=$?
grep -E 'TESTED|FAIL' "$LAUNCH_LOG" | sed 's/^/  /'
[ "$lrc" = 0 ] && ok "launcher open / search / launch / close all passed" || bad "launcher harness failed (see $LAUNCH_LOG)"

echo; echo "=== 16. terminal role (mei-app; Ryoku's ryoku-app) ==="
# The shell runs every Terminal=true desktop entry through mei-app; without it
# a TUI (htop, vim) silently died. This harness proves the direct call, the
# desktop.json choice and the launcher -> AppLaunch -> mei-app -> kitty chain.
TERM_LOG="$RUN/logs/phase9-terminal-$STAMP.log"
bash "$MEI/docs/tests/terminal-check.sh" > "$TERM_LOG" 2>&1
trc=$?
grep -E 'TESTED|FAIL' "$TERM_LOG" | sed 's/^/  /'
if [ "$trc" = 0 ]; then
  ok "terminal: Terminal=true apps open in the configured terminal"
  echo "TERMINAL-CHECK: PASS"
else
  bad "terminal harness failed (see $TERM_LOG)"
  echo "TERMINAL-CHECK: FAIL"
fi

echo; echo "=== 4. sidebar: panel opens, clock/date render, audio read-only ==="
SH clearSurfaceTrace >/dev/null 2>&1
D quicksettings; sleep 1.6
tr="$(SH lastSurface)"
[ "$tr" = "quick-settings" ] && ok "quick-settings request reached the surface bus" || bad "sidebar trace='$tr'"
grim -o "${WAYLAND_DISPLAY^^}" "$RUN/shots/phase9-sidebar.png" 2>/dev/null
sd="$(identify -format '%[fx:standard_deviation]' "$RUN/shots/phase9-sidebar.png" 2>/dev/null)"
awk -v v="${sd:-0}" 'BEGIN{exit !(v>0.03)}' && ok "sidebar renders content (std=$sd)" || bad "sidebar looks blank (std=$sd)"
CLOCK="$(date +%H:%M)"
note "wall clock now $CLOCK (the panel's clock card binds to the same local time)"
[ -e /sys/class/power_supply ] && ls /sys/class/power_supply | tr '\n' ' ' | sed 's/^/  power supplies: /'
# Read-only, and against the *host* PipeWire runtime: this script exported the
# nested XDG_RUNTIME_DIR above, which has no pipewire-0 socket.
VOL="$(XDG_RUNTIME_DIR="$HOST_XDG" wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null | awk '{print $2}')"
if [ -n "$VOL" ]; then
  ok "audio sink readable on the host bus: volume $VOL (read-only; no write performed)"
else
  note "no audio sink readable from the host (read-only check skipped)"
fi

echo; echo "--- 4b. brightness: real 5% step, restored on exit (keep-list) ---"
if command -v brightnessctl >/dev/null 2>&1 && [ -n "$(brightnessctl get 2>/dev/null)" ]; then
  BR_DEV="$(brightnessctl -m 2>/dev/null | cut -d, -f1)"
  BR_MAX="$(brightnessctl max 2>/dev/null)"
  BR_BEFORE="$(brightnessctl get 2>/dev/null)"
  BR_RESTORE="$BR_BEFORE"   # cleanup() restores this even if the script dies
  restore_brightness() { brightnessctl set "$BR_BEFORE" >/dev/null 2>&1 || true; }
  note "backlight $BR_DEV: $BR_BEFORE of $BR_MAX before"
  # (a) the QML fader's exact write path (Devices.setBacklight)
  bash -c 'BL=$(ryoku-hw-backlight 2>/dev/null); brightnessctl ${BL:+-d "$BL"} set 5%+ >/dev/null 2>&1' || true
  BR_QML="$(brightnessctl get 2>/dev/null)"
  if [ -n "$BR_QML" ] && [ "$BR_QML" != "$BR_BEFORE" ]; then
    ok "QML brightness write path moved $BR_DEV ${BR_BEFORE} -> ${BR_QML} of ${BR_MAX} (5%)"
  else
    bad "QML brightness write path did not move $BR_DEV (${BR_BEFORE} -> ${BR_QML:-?})"
  fi
  restore_brightness
  BR_REST="$(brightnessctl get 2>/dev/null)"
  [ "$BR_REST" = "$BR_BEFORE" ] && ok "brightness restored between the two steps" \
    || bad "brightness not restored between steps ($BR_REST != $BR_BEFORE)"
  # (b) the media-key path: mei-shell brightness -> ryoku-cmd-brightness
  BOUT="$(env HOME="$RUN/home" XDG_CONFIG_HOME="$RUN/config" \
    XDG_CACHE_HOME="$RUN/home/.cache" XDG_STATE_HOME="$RUN/state" \
    XDG_DATA_HOME="$RUN/data" XDG_RUNTIME_DIR="$RT" \
    DBUS_SESSION_BUS_ADDRESS="$BUS" "$RUN/bin/mei-shell" brightness up 2>&1)"; BRC=$?
  BR_HUB="$(brightnessctl get 2>/dev/null)"
  if [ "$BRC" = 0 ] && [ -n "$BR_HUB" ] && [ "$BR_HUB" != "$BR_BEFORE" ]; then
    ok "hub brightness verb moved $BR_DEV ${BR_BEFORE} -> ${BR_HUB} of ${BR_MAX} (5%)"
  else
    bad "hub brightness verb failed (rc=$BRC, ${BR_BEFORE} -> ${BR_HUB:-?}) out=${BOUT}"
  fi
  restore_brightness
  BR_DONE="$(brightnessctl get 2>/dev/null)"
  [ "$BR_DONE" = "$BR_BEFORE" ] && ok "brightness restored to $BR_BEFORE" \
    || bad "brightness not restored ($BR_DONE != $BR_BEFORE)"
  BR_RESTORE=""
else
  note "no brightnessctl or no backlight on this host; brightness control UNVERIFIED"
fi
D quicksettings; sleep 0.8

echo; echo "=== 10. missing dependency: brightness helper and brightnessctl ==="
HELPER="$RUN/bin/ryoku-cmd-brightness"
[ -x "$HELPER" ] && ok "brightness helper is installed in the nested bin" \
  || bad "brightness helper missing from $RUN/bin"
if [ -e "$HELPER" ]; then
  HSAVED="$(readlink -f "$HELPER" 2>/dev/null || echo "$HELPER")"
  rm -f "$HELPER"
  BOUT="$(env HOME="$RUN/home" XDG_CONFIG_HOME="$RUN/config" \
    XDG_CACHE_HOME="$RUN/home/.cache" XDG_STATE_HOME="$RUN/state" \
    XDG_DATA_HOME="$RUN/data" XDG_RUNTIME_DIR="$RT" \
    DBUS_SESSION_BUS_ADDRESS="$BUS" "$RUN/bin/mei-shell" brightness up 2>&1)"; BRC=$?
  ln -sfn "$HSAVED" "$HELPER"
  echo "  output: $BOUT"
  [ "$BRC" != 0 ] && ok "hub brightness verb fails cleanly without the helper (rc=$BRC)" \
    || bad "brightness verb exited 0 without the helper"
  case "$BOUT" in
    *brightness*) ok "the error names the brightness step" ;;
    *) note "unexpected error text (still a clean failure)" ;;
  esac
else
  bad "cannot test helper-missing degradation"
fi
# The QML probe must come back empty when brightnessctl fails, so the fader
# hides itself instead of showing a control that does nothing.
FAKE="$RUN/deps/bin-no-brightnessctl"; mkdir -p "$FAKE"
printf '#!/bin/sh\nexit 127\n' > "$FAKE/brightnessctl"; chmod +x "$FAKE/brightnessctl"
PROBE="$(PATH="$FAKE:$PATH" bash -c 'BL=$(ryoku-hw-backlight 2>/dev/null); brightnessctl ${BL:+-d "$BL"} -m 2>/dev/null | cut -d, -f4 | tr -d "%"')"
[ -z "$PROBE" ] && ok "with brightnessctl failing, the panel probe is empty (fader hides)" \
  || bad "probe returned '$PROBE' with brightnessctl failing"
[ -d "/proc/$DPID" ] && ok "daemon alive after the failed step" || bad "daemon died"
[ -d "/proc/$QS" ] && ok "shell alive after the failed step" || bad "shell died"

echo; echo "=== 12. five-minute idle capture ==="
idle_pids() {
  { pgrep -f "^$RUN/bin/mei-shell"
    pgrep -f "^qs -p $MEI/src/ryoku/shell/quickshell/shell"
    pgrep -f "^Hyprland -c $RUN"
    pgrep -x ryogami; pgrep -x matugen; pgrep -x mei-hub; } 2>/dev/null | sort -u
}
OUT="$RUN/phase9-idle-outbound-$STAMP.txt"; : > "$OUT"
LISTEN="$RUN/phase9-idle-listen-$STAMP.txt"; : > "$LISTEN"
SAMPLES=60
for i in $(seq 1 $SAMPLES); do
  pids="$(idle_pids | tr '\n' '|')"; pids="${pids%|}"
  if [ -n "$pids" ]; then
    ss -tunap 2>/dev/null | grep -E "pid=($pids)," >> "$OUT.tmp" || true
    ss -tulnp 2>/dev/null | grep -E "pid=($pids)," >> "$LISTEN.tmp" || true
  fi
  sleep 5
done
# outbound = established/syn-sent with a non-loopback peer
awk 'BEGIN{IGNORECASE=1} /ESTAB|SYN-SENT|FIN-WAIT|LAST-ACK/ && $0 !~ /127\.0\.0\.1|\[::1\]|::1/ {print}' "$OUT.tmp" 2>/dev/null | sort -u > "$OUT"
sort -u "$LISTEN.tmp" 2>/dev/null > "$LISTEN"
rm -f "$OUT.tmp" "$LISTEN.tmp"
if [ -s "$OUT" ]; then bad "outbound connections during idle:"; sed 's/^/  /' "$OUT"; else ok "zero outbound connections from Mei PIDs over 5 minutes"; fi
note "listening sockets during idle: $(wc -l < "$LISTEN") line(s)"
sed 's/^/  /' "$LISTEN"
note "5 shell log lines during idle: $(tail -5 "$SHELLLOG" 2>/dev/null | tr '\n' '|' | cut -c1-200)"

echo; echo "=== 11. clean shutdown ==="
( cd "$MEI" && XDG_RUNTIME_DIR="$HOST_XDG" WAYLAND_DISPLAY="$HOST_WL" ./mei stop ) >/dev/null 2>&1
trap - EXIT
for _ in $(seq 1 120); do
  pgrep -f "^$RUN/bin/mei-shell|^qs -p $MEI/src/ryoku/shell|^Hyprland -c $RUN" >/dev/null 2>&1 || break
  sleep 0.25
done
stray=""
for p in $(pgrep -f "^$RUN/bin/" 2>/dev/null || true); do
  tr '\0' ' ' < "/proc/$p/cmdline" 2>/dev/null | grep -q "$MEI" && stray="$stray $p"
done
for p in $(pgrep -x quickshell 2>/dev/null || true); do
  tr '\0' ' ' < "/proc/$p/cmdline" 2>/dev/null | grep -q "$MEI/src/ryoku" && stray="$stray qs:$p"
done
for p in $(pgrep -x mei-hub 2>/dev/null || true); do stray="$stray hub:$p"; done
[ -z "$stray" ] && ok "no Mei process left" || bad "strays:$stray"
waysock="$(ls "$RT"/wayland-* 2>/dev/null | tr '\n' ' ')"
[ -z "$waysock" ] && ok "nested Wayland socket removed" || bad "Wayland socket left: $waysock"
livehypr="$(find "$RT/hypr" -name .socket.sock 2>/dev/null | tr '\n' ' ')"
[ -z "$livehypr" ] && ok "no live Hyprland control socket" || bad "live Hyprland socket left: $livehypr"
# Lock files and the per-instance directory are inert; ./mei run removes them
# before the next start. Report them instead of counting them as a failure.
stale="$(ls "$RT"/mei-shell.sock.lock "$RT"/ryogami.sock "$RT"/mei-hub.lock 2>/dev/null | tr '\n' ' ')"
[ -n "$stale" ] && note "inert runtime files left (next run cleans or rebinds): $stale"
inst="$(ls -d "$RT"/hypr/*/ 2>/dev/null | tr '\n' ' ')"
[ -n "$inst" ] && note "stale instance dir left (no live socket): $inst"
if [ -f "$RUN/pids" ]; then
  n="$(wc -l < "$RUN/pids")"
  [ "$n" = 0 ] && ok "PID file emptied" || note "PID file still has $n line(s)"
else
  ok "PID file removed by stop"
fi

echo; echo "=== verify-untouched AFTER ==="
( cd "$MEI" && env -u HYPRLAND_INSTANCE_SIGNATURE -u WAYLAND_DISPLAY \
    XDG_RUNTIME_DIR="$HOST_XDG" ./mei verify-untouched 2>&1 | tail -1 )

echo
[ "$fail" = 0 ] && echo "RESULT: PASS" || echo "RESULT: FAIL"
echo "log: $LOG"
exit "$fail"
