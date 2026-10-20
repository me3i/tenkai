#!/usr/bin/env bash
# Test-only acceptance for Phase 6 step 4 (Settings app / mei-hub) plus the
# owner-approved audio reachability probe. Lives in docs/tests (versioned).
#   step4.sh          -> run, checks, stop, verify-untouched
#   KEEP=1 step4.sh   -> run, checks, leave the session up
set -uo pipefail
MEI=/home/mei/projects/mei
RUN="$MEI/.run"
RT="$MEI/.r"                 # short symlink to .run/rt (108-byte socket limit)
RTP=/run/user/1000/pipewire-0
SHELLJSON="$RUN/config/mei/shell.json"
HOST_XDG="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"   # host session (for ./mei run)
HOST_WL="${WAYLAND_DISPLAY:-wayland-1}"
LOG="$RUN/logs/step4-$(date +%H%M%S).log"
mkdir -p "$RUN/shots"
exec > >(tee -a "$LOG") 2>&1
fail=0
ok()  { echo "TESTED      $*"; }
bad() { echo "FAIL        $*"; fail=1; }
note(){ echo "NOTE        $*"; }

# ---- real audio: record, restore + unlink in a trap (even on failure) --------
VOL_BEFORE="$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null | awk '{print $2}')"
if wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null | grep -q MUTED; then MUTE_BEFORE=1; else MUTE_BEFORE=0; fi
restore_audio() {
  if [ -n "${VOL_BEFORE:-}" ]; then
    wpctl set-mute @DEFAULT_AUDIO_SINK@ "$MUTE_BEFORE" >/dev/null 2>&1 || true
    wpctl set-volume @DEFAULT_AUDIO_SINK@ "$VOL_BEFORE" >/dev/null 2>&1 || true
    echo "restored audio: $(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null) (was vol=$VOL_BEFORE mute=$MUTE_BEFORE)"
  fi
  rm -f "$RUN/rt/pipewire-0"
  if [ -e "$RUN/rt/pipewire-0" ]; then echo "FAIL  pipewire symlink still present"; else echo "TESTED      pipewire symlink removed from the nested runtime"; fi
}
trap restore_audio EXIT
note "audio before: vol=${VOL_BEFORE:-?} mute=${MUTE_BEFORE:-?}"

hypr_hash() { find "$HOME/.config/hypr" -type f 2>/dev/null | sort | xargs -r sha256sum 2>/dev/null | sha256sum | awk '{print $1}'; }
HYPR_BEFORE="$(hypr_hash)"
note "real ~/.config/hypr hash before: $HYPR_BEFORE"

echo "=== verify-untouched BEFORE ==="
"$MEI/mei" verify-untouched 2>&1 | tail -2

if [ -S "$RTP" ]; then
  ln -sfn "$RTP" "$RUN/rt/pipewire-0"
  ok "linked $RTP -> .run/rt/pipewire-0 (real PipeWire reachable in the nested runtime)"
else
  bad "real pipewire-0 socket not found at $RTP"
fi

echo "=== starting ./mei run ==="
XDG_RUNTIME_DIR="$HOST_XDG" WAYLAND_DISPLAY="$HOST_WL" "$MEI/mei" run || { bad "mei run failed"; exit 1; }

SIG=""; QS=""
for _ in $(seq 1 90); do
  SIG="$(ls -d "$RT/hypr/"*/ 2>/dev/null | head -1 | xargs -r basename)"
  QS="$(pgrep -f "qs -p $MEI/src/ryoku/shell/quickshell/shell" | head -1)"
  [ -n "$SIG" ] && [ -n "$QS" ] && break
  sleep 0.5
done
[ -n "$QS" ] && ok "shell process present (pid $QS)" || { bad "no shell process"; "$MEI/mei" stop; exit 1; }
[ -n "$SIG" ] && ok "nested Hyprland instance ($SIG)" || { bad "no nested instance"; "$MEI/mei" stop; exit 1; }
export XDG_RUNTIME_DIR="$RT" HYPRLAND_INSTANCE_SIGNATURE="$SIG"
H() { hyprctl "$@" 2>/dev/null; }
WDISP="$(basename "$(ls "$RT"/wayland-* 2>/dev/null | head -1)")"
export WAYLAND_DISPLAY="$WDISP"
note "nested WAYLAND_DISPLAY=$WDISP"
# The daemon refuses to run outside Mei's fake home; without HOME here every
# hub/settings request in this harness is rejected by the guard.
# BREAK_HUB=1 deliberately drops HOME so the "does the hub open" gate can be
# proven to fail (a harness that cannot fail is not a test).
if [ "${BREAK_HUB:-0}" = 1 ]; then
  mesh() { XDG_RUNTIME_DIR="$RT" "$RUN/bin/mei-shell" "$@"; }
else
  mesh() { HOME="$RUN/home" XDG_CONFIG_HOME="$RUN/config" XDG_RUNTIME_DIR="$RT" "$RUN/bin/mei-shell" "$@"; }
fi
hub_geom() { H -j clients 2>/dev/null | jq -r '.[] | select(.class=="org.quickshell") | "\(.at[0]),\(.at[1]) \(.size[0])x\(.size[1])"' | head -1; }
hub_focused() { H -j activewindow 2>/dev/null | jq -r '.class // ""'; }
shot() { grim -o "${WDISP^^}" "$RUN/shots/step4-$1.png" 2>/dev/null && echo "  shot: step4-$1.png"; }
vkbd() { "$RUN/tools/vkbd/vkbd" "$@" >/dev/null 2>&1; }
hubs() { for p in $(pgrep -f "hub/quickshell" 2>/dev/null); do [ "$(cat /proc/$p/comm 2>/dev/null)" = qs ] && { echo "$p"; return; }; done; }
# A fresh hub opens on its default page (global) and writes no section key
# until the user navigates; absence therefore means global, not "did not open".
sec() { local s; s="$(sed -n 's/^ *section = "\(.*\)"/\1/p' "$RUN/config/mei/hub.toml" 2>/dev/null)"; printf '%s' "${s:-global}"; }

MON="$(H -j monitors | jq -r '.[0].name' 2>/dev/null)"
[ -n "$MON" ] && H keyword monitor "$MON,1600x1000,auto,1" >/dev/null 2>&1 && ok "nested output enlarged (monitor $MON)" || bad "could not enlarge nested output"
sleep 2

# ============================ AUDIO =========================================
echo; echo "=== AUDIO (nested reaches real PipeWire via the symlink) ==="
[ -L "$RUN/rt/pipewire-0" ] && ok "pipewire-0 symlink present in the nested runtime" || bad "pipewire-0 symlink missing"
H dispatch global ryoku:quicksettings >/dev/null 2>&1; sleep 3
shot audio-qspanel-readonly
note "read-only: the bar/panel audio readout should show the real sink (vol=$VOL_BEFORE)"
H dispatch global ryoku:quicksettings >/dev/null 2>&1; sleep 1
if [ -n "${VOL_BEFORE:-}" ]; then
  wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%- >/dev/null 2>&1 || true
  NOW="$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null | awk '{print $2}')"
  if [ -n "$NOW" ] && [ "$NOW" != "$VOL_BEFORE" ]; then
    ok "volume changed via the nested runtime: $VOL_BEFORE -> $NOW (<=5%), real sink"
    H dispatch global ryoku:quicksettings >/dev/null 2>&1; sleep 3
    shot audio-qspanel-changed
    H dispatch global ryoku:quicksettings >/dev/null 2>&1; sleep 1
  else bad "volume did not change via the nested runtime"; fi
  restore_audio
fi

# ============================ HUB OPEN + PAGES ==============================
echo; echo "=== SETTINGS APP (mei-hub) ==="
mesh hub open >/dev/null 2>&1
HUB=""
for _ in $(seq 1 60); do HUB="$(hubs)"; [ -n "$HUB" ] && break; sleep 0.5; done
HUB_OK=0
if [ -n "$HUB" ]; then
  HUB_OK=1; ok "Mei Settings opened (hub pid $HUB) via 'mei-shell hub open' (the rail button's exact command)"
else
  bad "Mei Settings did not open -- every hub check below will fail, not pass silently"
fi
sleep 4
shot hub-open
[ -e "$RT/mei-hub.lock" ] && ok "hub lock is \$XDG_RUNTIME_DIR/mei-hub.lock" || note "mei-hub.lock not seen (flock -o may unlink on exit)"

note "rail sections in source (active block only):"
AKEYS="$(awk '/readonly property var groups/{f=1} f{print} f&&/^    ]$/{exit}' "$MEI/src/ryoku/hub/quickshell/Hub.qml" | grep -o 'key: "[^"]*"' | cut -d'"' -f2 | sort | tr '\n' ' ')"
echo "    $AKEYS"
[ "$AKEYS" = "animations bar-studio desktop global launcher " ] \
  && ok "rail carries exactly the 5 kept sections (global/desktop/bar-studio/launcher/animations)" \
  || bad "rail sections are not the expected 5: $AKEYS"
for s in global desktop bar-studio launcher animations; do
  if [ "$HUB_OK" = 1 ]; then
    mesh hub open "$s" >/dev/null 2>&1
    got=""
    for _ in $(seq 1 24); do got="$(sec)"; [ "$got" = "$s" ] && break; sleep 0.5; done
    [ "$got" = "$s" ] && ok "page '$s' opened (nav section=$got)" || bad "page '$s' did not open (section=$got)"
    shot "hub-page-$s"
  else
    bad "page '$s' not tested: hub never opened"
  fi
done
# each kept page must actually render content (a broken page would be blank)
for s in global desktop bar-studio launcher animations; do
  if [ "$HUB_OK" != 1 ]; then bad "page '$s' content not tested: hub never opened"; continue; fi
  f="$RUN/shots/step4-hub-page-$s.png"
  geom="$(hub_geom)"
  if [ -z "$geom" ]; then bad "page '$s': no hub window to measure"; continue; fi
  read -r off sz <<< "$geom"
  crop="$RUN/shots/step4-hub-crop-$s.png"
  convert "$f" -crop "${sz}+${off/,/+}" +repage "$crop" 2>/dev/null
  sd="$(identify -format '%[fx:standard_deviation]' "$crop" 2>/dev/null)"
  awk -v v="${sd:-0}" 'BEGIN{exit !(v>0.02)}' && ok "page '$s' rendered hub content (crop std=$sd)" || bad "page '$s' hub area looks blank (std=$sd)"
done

# a disabled section must be refused
for dead in displays windowmanager; do
  if [ "$HUB_OK" != 1 ]; then bad "disabled section '$dead' not tested: hub never opened"; continue; fi
  mesh hub open "$dead" >/dev/null 2>&1; sleep 2
  got="$(sec)"
  [ "$got" != "$dead" ] && ok "disabled section '$dead' refused (section stayed '$got')" || bad "disabled section '$dead' opened"
done

# ============================ MOTION (UI) ===================================
echo; echo "=== MOTION: change by UI, restart, confirm it stuck, reset by UI ==="
MOT_PROVEN=0
MOT_AFTER=""
if [ "$HUB_OK" = 1 ]; then
  mesh hub open animations >/dev/null 2>&1; sleep 3
  note "motion before: $(jq -c '.theme.motion' "$SHELLJSON" 2>/dev/null)"
  if [ "$(hub_focused)" = "org.quickshell" ]; then
    # focused window is the hub; keyboard drives real controls (Sw/Btn are activeFocusOnTab)
    vkbd 15; sleep 0.4; vkbd 15; sleep 0.4; vkbd 57   # Tab Tab Space -> Reduce motion switch
    sleep 1.2
    MOT_AFTER="$(jq -c '.theme.motion' "$SHELLJSON" 2>/dev/null)"
    note "motion after UI toggle: $MOT_AFTER"
    echo "$MOT_AFTER" | grep -q '"reduce":true' && { ok "UI toggle changed theme.motion.reduce (live, via the Motion page switch)"; MOT_PROVEN=1; } || bad "UI toggle did not change theme.motion.reduce"
    shot hub-motion-changed
  else
    bad "hub is not focused (active='$(hub_focused)'), cannot drive the Motion switch"
  fi
else
  bad "motion UI not tested: hub never opened"
fi

MOT_SET="$MOT_AFTER"
if [ "$MOT_PROVEN" = 1 ]; then
  echo; note "--- restarting Mei (stop + run) to prove persistence ---"
  "$MEI/mei" stop >/dev/null 2>&1; sleep 3
  XDG_RUNTIME_DIR="$HOST_XDG" WAYLAND_DISPLAY="$HOST_WL" "$MEI/mei" run >/dev/null 2>&1
  for _ in $(seq 1 60); do QS="$(pgrep -f "qs -p $MEI/src/ryoku/shell/quickshell/shell" | head -1)"; [ -n "$QS" ] && break; sleep 0.5; done
  SIG="$(ls -d "$RT/hypr/"*/ 2>/dev/null | head -1 | xargs -r basename)"
  export HYPRLAND_INSTANCE_SIGNATURE="$SIG"
  MON="$(H -j monitors | jq -r '.[0].name' 2>/dev/null)"; H keyword monitor "$MON,1600x1000,auto,1" >/dev/null 2>&1
  sleep 2
  mesh hub open animations >/dev/null 2>&1
  HUB=""; for _ in $(seq 1 60); do HUB="$(hubs)"; [ -n "$HUB" ] && break; sleep 0.5; done
  [ -n "$HUB" ] || bad "hub did not reopen after the restart"
  sleep 5
  MOT_RESTART="$(jq -c '.theme.motion' "$SHELLJSON" 2>/dev/null)"
  [ "$MOT_RESTART" = "$MOT_SET" ] && ok "motion value survived a full Mei restart: $MOT_RESTART" || bad "motion value did NOT survive (before=$MOT_SET after=$MOT_RESTART)"
  shot hub-motion-restart-stuck
else
  bad "motion persistence not tested: the UI toggle was never proven"
fi

echo; note "--- RESET TO DEFAULTS by UI ---"
if [ "$MOT_PROVEN" = 1 ] && [ -n "$HUB" ]; then
  if [ "$(hub_focused)" = "org.quickshell" ]; then
    vkbd 15; sleep 0.35; vkbd 15; sleep 0.35; vkbd 15; sleep 0.35; vkbd 57   # Tab x3 -> RESET, Space
    sleep 1.5
    MOT_RESET="$(jq -c '.theme.motion' "$SHELLJSON" 2>/dev/null)"
    echo "$MOT_RESET" | grep -q '"scale":1' && echo "$MOT_RESET" | grep -q '"reduce":false' \
      && ok "RESET restored theme.motion defaults: $MOT_RESET" || bad "RESET did not restore defaults: $MOT_RESET"
    shot hub-motion-after-reset
  else
    bad "RESET not tested: hub is not focused"
  fi
else
  bad "RESET not tested: the motion UI flow never ran"
fi

# ============================ HYPR SEVERANCE ================================
echo; echo "=== HYPR WRITER SEVERED ==="
for f in settings.lua rebinds.lua; do
  find "$RUN/home" "$RUN/config" -name "$f" 2>/dev/null | grep -q . && bad "$f was created" || ok "no $f anywhere in the fake home"
done
find "$RUN/home" "$RUN/config" -type d -name user_edits 2>/dev/null | grep -q . && bad "user_edits dir created" || ok "no user_edits dir anywhere in the fake home"
HYPR_AFTER="$(hypr_hash)"
[ "$HYPR_AFTER" = "$HYPR_BEFORE" ] && ok "real ~/.config/hypr unchanged ($HYPR_AFTER)" || bad "real ~/.config/hypr CHANGED: $HYPR_BEFORE -> $HYPR_AFTER"
note "what Settings wrote (must be under \$XDG_CONFIG_HOME/mei only):"; ls -1 "$RUN/config/mei" 2>/dev/null | sed 's/^/    /'

# ============================ HYGIENE =======================================
echo; echo "=== HYGIENE ==="
pgrep -af hyprctl 2>/dev/null | grep -v pgrep | grep -q . && bad "a hyprctl is running" || ok "no hyprctl spawned by Settings"
if [ -n "$HUB" ]; then
  ss -tunp 2>/dev/null | grep -qE "pid=$HUB," && bad "hub owns tcp/udp sockets" || ok "hub has no tcp/udp sockets (zero outbound)"
else
  bad "socket check not tested: hub never opened"
fi
bad_pat='is not a type|is not installed|Cannot assign|Unable to assign|TypeError|SyntaxError|is not defined|Failed to load|Cannot read property|Non-existent|Unable to determine'
NOISE='ryoku-cmd|ryostage|ryoku-eq|xdg-desktop-portal|RealtimeKit|pipewire|PulseAudio|pa_context|org.freedesktop.portal'
if grep -rhiE "$bad_pat" "$RUN/logs/session.log" "$RUN/logs/daemon.log" "$RT"/quickshell/by-id/*/log.log 2>/dev/null | grep -vE "$NOISE" | grep -q .; then
  bad "QML errors in logs"; grep -rhiE "$bad_pat" "$RUN/logs/session.log" "$RUN/logs/daemon.log" "$RT"/quickshell/by-id/*/log.log 2>/dev/null | grep -vE "$NOISE" | head -8
else ok "no QML errors in the hub/shell logs (portal/pipewire noise excluded)"; fi

# static syntax check on the edited hub QML (runtime output is discarded by the daemon)
if command -v qmllint >/dev/null 2>&1; then
  syn=0
  for f in Hub.qml pages/AnimationsPage.qml pages/GlobalPage.qml pages/DesktopPage.qml pages/BarStudioPage.qml pages/LauncherPage.qml; do
    if qmllint "$MEI/src/ryoku/hub/quickshell/$f" 2>&1 | grep -qi 'syntax error'; then bad "syntax error in $f"; syn=1; fi
  done
  [ "$syn" = 0 ] && ok "qmllint: no syntax errors in the six edited hub files"
else note "qmllint unavailable"; fi

if [ "${KEEP:-0}" = 1 ]; then
  echo; note "KEEP=1: session left up. QS=$QS HUB=$HUB SIG=$SIG WDISP=$WDISP RT=$RT"
  echo "RESULT(partial): $([ "$fail" = 0 ] && echo PASS || echo FAIL)"; echo "log: $LOG"; exit "$fail"
fi

mesh hub close >/dev/null 2>&1
sleep 3
[ -z "$(hubs)" ] && ok "hub closed cleanly (no stray processes)" || { bad "stray hub process after close"; pgrep -af "hub/quickshell"; }

echo; echo "=== stopping ==="
"$MEI/mei" stop || true
sleep 2
stray="$(pgrep -af "$RUN/bin/mei-shell|quickshell/shell|quickshell/hub|mei-wm-hyprland|mei-hub" | grep -v pgrep || true)"
[ -z "$stray" ] && ok "clean shutdown: no stray Mei processes" || { bad "stray processes:"; printf '%s\n' "$stray"; }

echo; echo "=== verify-untouched AFTER ==="
XDG_RUNTIME_DIR="$HOST_XDG" WAYLAND_DISPLAY="$HOST_WL" "$MEI/mei" verify-untouched 2>&1 | tail -2

echo; echo "RESULT: $([ "$fail" = 0 ] && echo PASS || echo FAIL)"; echo "log: $LOG"
exit "$fail"
