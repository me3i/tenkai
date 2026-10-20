#!/usr/bin/env bash
# Mei's idle: dim, lock, DPMS off and suspend on the user's own thresholds,
# with the inhibitors honoured, plus the ScreenSaver service the apps that
# play video talk to.
#
# Nothing here can reach the owner's session: the nested session has its own
# bus and its own display, the brightness goes into a file (the harness seam
# MEI_BRIGHTNESS_FAKE), the suspend is stubbed (MEI_STUB_POWER), and the DPMS
# reaches only the nested compositor.
set -uo pipefail
MEI=$HOME/projects/mei
RUN="$MEI/.run"; RT="$MEI/.r"
HOST_XDG="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
HOST_WL="${WAYLAND_DISPLAY:-wayland-1}"
STAMP="$(date +%H%M%S)"
LOG="$RUN/logs/idle-module-$STAMP.log"
mkdir -p "$RUN/logs"
exec > >(tee -a "$LOG") 2>&1

fail=0
ok(){ echo "TESTED      $*"; }
bad(){ echo "FAIL        $*"; fail=1; }

SIG=""; QS=""; WD=""
H(){ XDG_RUNTIME_DIR="$RT" HYPRLAND_INSTANCE_SIGNATURE="$SIG" hyprctl "$@" 2>/dev/null; }
ns_count(){ H -j layers | jq "[to_entries[] | .value.levels | to_entries[] | .value[]? | select(.namespace==\"$1\")] | length" 2>/dev/null; }
NADDR(){ cat "$RUN/bus" 2>/dev/null; }
B(){ busctl --address="$(NADDR)" "$@" 2>&1; }
GDBUS(){ gdbus call --address "$(NADDR)" --dest org.freedesktop.ScreenSaver \
  --object-path /org/freedesktop/ScreenSaver --method "$@" 2>&1; }
DAEMON_LOG="$RUN/logs/daemon.log"

FAKE="$RUN/state/idle-fake-brightness"
CFG="$RUN/config/mei/idle.json"
# The thresholds are the user's own (Mei's config), so the test only shortens
# them. Everything else is the real code path.
cfg_with(){ # $1=dim $2=lock $3=dpms $4=suspend
  printf '{"enabled": true, "dim": %s, "lock": %s, "dpms": %s, "suspend": %s, "dimPercent": 40}\n' \
    "$1" "$2" "$3" "$4" > "$CFG.new" && mv "$CFG.new" "$CFG"
}
fake_val(){ tr -d '[:space:]' < "$FAKE" 2>/dev/null; }
# The virtual keyboard must reach the nested session. Without the nested
# runtime and display it would type into the owner's live session.
key(){ "$MEI/docs/tests/tools/nested-input.sh" "$RUN/tools/vkbd/vkbd" "$1" >/dev/null 2>&1; }

start(){
  mkdir -p "$RUN/config/mei" "$RUN/state"
  echo 80 > "$FAKE"
  cfg_with 9999 9999 9999 9999
  ( cd "$MEI" && XDG_RUNTIME_DIR="$HOST_XDG" WAYLAND_DISPLAY="$HOST_WL" \
      env MEI_BRIGHTNESS_FAKE="$FAKE" MEI_SCREENSAVER_NAME=1 ./mei run ) >/dev/null 2>&1
  SIG=""; QS=""; WD=""
  for _ in $(seq 1 250); do
    SIG="$(ls -d "$RT/hypr/"*/ 2>/dev/null | head -1 | xargs -r basename)"
    QS="$(pgrep -f "^qs -p $MEI/src/ryoku/shell/quickshell/shell" | head -1)"
    WD="$(ls "$RT"/wayland-* 2>/dev/null | head -1 | xargs -r basename)"
    [ -n "$SIG" ] && [ -n "$QS" ] && [ -n "$WD" ] && break
    sleep 0.3
  done
  [ -n "$SIG" ] && [ -n "$QS" ] || { bad "the nested session did not come up"; return 1; }
  # The config is re-read when it changes, so it is written again once the
  # shell is up: the file may not have existed when the shell started.
  cfg_with 9999 9999 9999 9999
  sleep 6
}
stop(){ ( cd "$MEI" && XDG_RUNTIME_DIR="$HOST_XDG" WAYLAND_DISPLAY="$HOST_WL" ./mei stop ) >/dev/null 2>&1; sleep 2; }

echo "idle module: $(date -Is)"
panel_before="$(brightnessctl g 2>/dev/null)"
start || exit 1

echo
echo "=== A: the ScreenSaver service is offered on the nested bus ==="
B list --no-legend 2>/dev/null | grep -q "org.freedesktop.ScreenSaver" \
  && ok "the nested session offers org.freedesktop.ScreenSaver" \
  || bad "the name is not offered on the nested bus"
owner="$(B list --no-legend 2>/dev/null | awk '$1=="org.freedesktop.ScreenSaver"{print $3; exit}')"
echo "  the owner is ${owner:-?}"
[ -n "$owner" ] && ok "the name has an owner in this session" || bad "the name has no owner"
if busctl --address="unix:path=$HOST_XDG/bus" list --no-legend 2>/dev/null \
   | awk '$1=="org.freedesktop.ScreenSaver"{print $3}' | grep -qx "$owner" 2>/dev/null; then
  bad "the nested session also owns the name on the live bus"
else
  ok "the live bus is untouched by the nested session"
fi

echo
echo "=== B: an inhibitor holds the idle off, and releasing it resumes ==="
# The inhibitor is armed BEFORE the dim threshold comes down, so the
# inhibitor really has something to hold off.
out="$(GDBUS org.freedesktop.ScreenSaver.Inhibit "the idle test" "playing a video")"
echo "  Inhibit said: $out"
cookie="$(printf '%s' "$out" | sed -nE 's/.*uint32 ([0-9]+).*/\1/p' | head -1)"
case "$cookie" in
''|*[!0-9]*) bad "Inhibit returned no cookie ($out)" ;;
*) ok "the fake client got the cookie $cookie" ;;
esac
cfg_with 4 9999 9999 9999
sleep 14
v="$(fake_val)"
[ "$v" = "80" ] && ok "no dim while the inhibitor was held (the panel value is still $v)" \
  || bad "the dim happened despite the inhibitor (the panel value is $v)"
GDBUS org.freedesktop.ScreenSaver.UnInhibit "$cookie" >/dev/null 2>&1
sleep 14
v="$(fake_val)"
if [ -n "$v" ] && [ "$v" != "80" ]; then
  ok "the idle dim ran after the inhibitor was released (the panel value is $v)"
else
  bad "the dim did not run after the release (the panel value is $v)"
fi

echo
echo "=== C: activity restores the brightness exactly ==="
before="$(fake_val)"
key 30
sleep 4
after="$(fake_val)"
[ "$before" = "40" ] && ok "the panel was dimmed to $before before the activity" \
  || bad "the panel was not dimmed before the activity (it reads $before)"
[ -n "$after" ] && [ "$after" = "80" ] && ok "the brightness came back to exactly 80" \
  || bad "the brightness did not come back to 80 (it reads $after)"

echo
echo "=== D: the suspend is stubbed ==="
cfg_with 9999 9999 9999 1
sleep 8
if grep -q "suppressed session suspend" "$DAEMON_LOG" 2>/dev/null; then
  ok "the daemon stubbed the suspend (the machine did not suspend)"
else
  bad "the daemon did not stub the suspend"
fi

echo
echo "=== E: the display goes to sleep on idle and wakes on activity ==="
cfg_with 9999 9999 1 9999
sleep 8
if grep -q "wm.act output.power off" "$DAEMON_LOG" 2>/dev/null; then
  ok "the idle turned the nested display off (the provider accepted the dispatch)"
else
  bad "the idle did not turn the display off"
fi
key 30
sleep 5
grep -q "wm.act output.power on" "$DAEMON_LOG" 2>/dev/null \
  && ok "activity woke the display again" \
  || bad "the display was not woken"

echo
echo "=== F: the idle locks the screen, and a wrong password is refused ==="
cfg_with 9999 1 9999 9999
n=0
for _ in $(seq 1 40); do n="$(ns_count ryoku-lock)"; [ "${n:-0}" != "0" ] && break; sleep 0.5; done
[ "${n:-0}" -ge 1 ] && ok "the idle locked the screen (ryoku-lock layers=$n)" \
  || bad "the idle did not lock the screen (layers=$n)"
for k in 45 21 52; do key "$k"; sleep 0.15; done
key 28
sleep 3
grep -q "lock verification refused" "$DAEMON_LOG" 2>/dev/null \
  && ok "the daemon refused the wrong password" \
  || bad "the daemon did not log a refusal"
n2="$(ns_count ryoku-lock)"
[ "${n2:-0}" -ge 1 ] && ok "the lock is still up after the wrong password" \
  || bad "the lock closed on a wrong password"

stop
echo
echo "=== G: the owner's session was not touched ==="
panel_after="$(brightnessctl g 2>/dev/null)"
[ "$panel_before" = "$panel_after" ] && ok "the panel brightness was not written ($panel_after)" \
  || bad "the panel brightness changed: $panel_before -> $panel_after"
( cd "$MEI" && ./mei verify-untouched >/dev/null 2>&1 ) && ok "verify-untouched PASS" \
  || bad "verify-untouched FAILED"
[ "$fail" = 0 ] && echo "IDLE MODULE: PASS" || echo "IDLE MODULE: FAIL"
echo "log: $LOG"
exit $fail
