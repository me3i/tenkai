#!/usr/bin/env bash
# Phase 6 step 7 acceptance: system tray.
#  - the daemon is the only StatusNotifierWatcher host, and only on the nested
#    private bus; the live bus owner is printed before and after
#  - one harmless SNI item (icon-theme path) and one pixmap item register inside
#    the nested session; their icons appear in the bar
#  - left click activates, right click opens the item's dbusmenu, an entry fires
#  - removing an item drops its icon
#  - no outbound, clean stop, no strays, verify-untouched at both ends
set -uo pipefail
MEI=/home/mei/projects/mei
RUN="$MEI/.run"; RT="$MEI/.r"
HOST_XDG="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
HOST_WL="${WAYLAND_DISPLAY:-wayland-1}"
STAMP="$(date +%H%M%S)"
LOG="$RUN/logs/step7-$STAMP.log"
WATCH=org.kde.StatusNotifierWatcher
mkdir -p "$RUN/shots"
exec > >(tee -a "$LOG") 2>&1
fail=0
ok()  { echo "TESTED      $*"; }
bad() { echo "FAIL        $*"; fail=1; }
note(){ echo "NOTE        $*"; }

echo "=== STATIC: one host, daemon only ==="
QML_OWNERS="$(grep -rl "$WATCH" "$MEI/src" --include=*.qml 2>/dev/null | wc -l)"
if [ "$QML_OWNERS" = 0 ]; then ok "no QML file names the watcher: the daemon is the only host"
else bad "QML names the watcher: $(grep -rl "$WATCH" "$MEI/src" --include=*.qml)"; fi
if grep -q "watcherName      = \"$WATCH\"" "$MEI/src/ryoku/shell/ipc/tray.go"; then
  ok "tray.go declares the single watcher name"
else bad "tray.go does not declare $WATCH"; fi
if grep -q 'registerCall("tray.activate"' "$MEI/src/ryoku/shell/ipc/tray.go"; then
  ok "daemon exposes the tray control verbs"
else bad "no tray control verbs"; fi

echo; echo "=== LIVE BUS BEFORE ==="
LIVE_BEFORE="$(busctl --user list --no-legend 2>/dev/null | awk -v n="$WATCH" '$1==n{print $2}')"
note "live bus $WATCH owner BEFORE: ${LIVE_BEFORE:-none}"
[ -n "$LIVE_BEFORE" ] && ok "the live session owns the watcher before the test (pid $LIVE_BEFORE)" || note "live bus has no watcher owner"

echo; echo "=== verify-untouched BEFORE ==="
XDG_RUNTIME_DIR="$HOST_XDG" WAYLAND_DISPLAY="$HOST_WL" "$MEI/mei" verify-untouched 2>&1 | tail -2

echo; echo "=== starting ./mei run ==="
XDG_RUNTIME_DIR="$HOST_XDG" WAYLAND_DISPLAY="$HOST_WL" "$MEI/mei" run || { bad "mei run failed"; exit 1; }

SIG=""; QS=""
for _ in $(seq 1 150); do
  SIG="$(ls -d "$RT/hypr/"*/ 2>/dev/null | head -1 | xargs -r basename)"
  QS="$(pgrep -f "qs -p $MEI/src/ryoku/shell/quickshell/shell" | head -1)"
  [ -n "$SIG" ] && [ -S "$RT/hypr/$SIG/.socket.sock" ] && [ -n "$QS" ] && break
  sleep 0.3
done
[ -n "$SIG" ] && [ -n "$QS" ] || { bad "session did not come up"; "$MEI/mei" stop; exit 1; }
export XDG_RUNTIME_DIR="$RT" HYPRLAND_INSTANCE_SIGNATURE="$SIG"
WDISP="$(basename "$(ls "$RT"/wayland-* 2>/dev/null | head -1)")"
export WAYLAND_DISPLAY="$WDISP"
BSIG="$(sed -n 's/^HYPRLAND_INSTANCE_SIGNATURE=//p' "$MEI/docs/baseline/env.txt" | head -1)"
[ "$SIG" != "$BSIG" ] && ok "nested Hyprland signature differs from the live baseline" || { bad "nested signature equals the baseline"; "$MEI/mei" stop; exit 1; }
H() {
  local rt="${RT:-${MEI:-/home/mei/projects/mei}/.r}" sig="${SIG:-}"
  [ -n "$sig" ] && [ -S "$rt/hypr/$sig/.socket.sock" ] \
    || { echo "REFUSED: nested Hyprland socket absent; no live fallback" >&2; return 1; }
  XDG_RUNTIME_DIR="$rt" HYPRLAND_INSTANCE_SIGNATURE="$sig" hyprctl "$@" 2>/dev/null
}
SCREENW="$(hyprctl -j monitors 2>/dev/null | jq -r '.[0].width // empty' 2>/dev/null)"
IPC() { XDG_RUNTIME_DIR="$RT" qs ipc --pid "$QS" call qsbar "$@" 2>&1; }
wake() { H dispatch dpms on >/dev/null 2>&1; H dispatch movecursor 960 540 >/dev/null 2>&1; }
shot() {
  local f="$RUN/shots/step7-$1.png" i
  rm -f "$f"
  for i in 1 2 3; do
    wake
    timeout 20 grim -o "${WDISP^^}" "$f" 2>/dev/null && { echo "  shot: step7-$1.png"; return 0; }
    sleep 1
  done
  bad "screenshot step7-$1.png failed after 3 attempts"
  return 1
}
sleep 3

BUS="$(cat "$RUN/bus" 2>/dev/null)"
[ -n "$BUS" ] && ok "the session recorded its private bus address" || bad "no .run/bus"
LIVE_BUS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=$HOST_XDG/bus}"
[ "$BUS" != "$LIVE_BUS" ] && ok "nested bus differs from the live bus" || bad "nested bus is the live bus"

DPID="$(pgrep -f "$RUN/bin/mei-shell daemon" | head -1)"
[ -n "$DPID" ] && ok "mei-shell daemon running (pid $DPID)" || bad "daemon not running"
NESTED_OWNER="$(busctl --address="$BUS" list --no-legend 2>/dev/null | awk -v n="$WATCH" '$1==n{print $2}')"
if [ -n "$NESTED_OWNER" ] && [ "$NESTED_OWNER" = "$DPID" ]; then
  ok "nested $WATCH owner is Mei's daemon (pid $NESTED_OWNER)"
else bad "nested owner '${NESTED_OWNER:-none}' != daemon '${DPID:-none}'"; fi
[ "$NESTED_OWNER" != "$LIVE_BEFORE" ] && ok "nested owner ($NESTED_OWNER) differs from the live owner ($LIVE_BEFORE)" || bad "nested owner equals the live owner"

echo; echo "=== the live bus still shows its own owner (read-only) ==="
LIVE_NOW="$(busctl --user list --no-legend 2>/dev/null | awk -v n="$WATCH" '$1==n{print $2}')"
[ "$LIVE_NOW" = "$LIVE_BEFORE" ] && ok "live bus $WATCH owner unchanged while the nested session runs (pid $LIVE_NOW)" || bad "live owner changed: $LIVE_BEFORE -> $LIVE_NOW"
busctl --user status "$WATCH" 2>/dev/null | head -3 | sed 's/^/  /'

tray_state() { IPC trayState; }
tray_count() { tray_state | jq -r '.count // empty' 2>/dev/null; }
wait_count() {
  local want="$1" i=0
  while [ "$i" -lt 75 ]; do
    [ "$(tray_count)" = "$want" ] && return 0
    sleep 0.2; i=$((i+1))
  done
  return 1
}
wait_log() {
  local f="$1" pat="$2" i=0
  while [ "$i" -lt 50 ]; do
    grep -q "$pat" "$f" 2>/dev/null && return 0
    sleep 0.2; i=$((i+1))
  done
  return 1
}
kill_sni() {
  local p="$1"
  tr '\0' ' ' < "/proc/$p/cmdline" 2>/dev/null | grep -q "$MEI/docs/tests/sni-test.py" \
    && kill -TERM "$p" 2>/dev/null
}

echo; echo "=== item 1: icon-theme path ==="
SNI1_LOG="$RUN/logs/step7-sni1-$STAMP.log"; : > "$SNI1_LOG"
env DBUS_SESSION_BUS_ADDRESS="$BUS" HOME="$RUN/home" XDG_RUNTIME_DIR="$RT" \
  python3 "$MEI/docs/tests/sni-test.py" --icon-name dialog-information \
  --event-log "$SNI1_LOG" --title "Mei Tray Test" \
  > "$RUN/logs/step7-sni1-$STAMP.out" 2>&1 &
SNI1=$!
wait_count 1 && ok "the item registered with the nested watcher (tray count 1)" || bad "item did not appear (count $(tray_count))"
# the menu is fetched after a 100 ms debounce; wait for it before asserting
wait_menu() {
  local i=0
  while [ "$i" -lt 40 ]; do
    [ "$(tray_state | jq -r '.items[0].hasMenu // false' 2>/dev/null)" = "true" ] && return 0
    sleep 0.15; i=$((i+1))
  done
  return 1
}
S="$(tray_state)"
echo "$S" | jq -c '.items[0] | {service,iconPath,iconName,hasMenu,pinned}' 2>/dev/null | sed 's/^/  /'
echo "$S" | jq -e '.items[0].pinned == true' >/dev/null 2>&1 && ok "the icon is pinned in the bar by default (no manual pin)" || bad "the item is not pinned"
wait_menu && S="$(tray_state)" && ok "the item's dbusmenu was read by the daemon" || bad "no menu on the item"
echo "$S" | jq -e '.items[0].hasMenu == true' >/dev/null 2>&1 || bad "hasMenu still false"
IPATH="$(echo "$S" | jq -r '.items[0].iconPath // ""')"
INAME="$(echo "$S" | jq -r '.items[0].iconName // ""')"
if [ -n "$IPATH" ]; then ok "icon resolved to a file: $IPATH"; [ -f "$IPATH" ] && ok "that icon file exists on disk" || bad "iconPath missing on disk"
elif [ -n "$INAME" ]; then ok "icon resolved to a theme name: $INAME"
else bad "no icon resolved"; fi
BARX="$(echo "$S" | jq -r '.barX // 0' | cut -d. -f1)"
note "tray icon row centre on screen: x=$BARX"
sleep 1
shot 01-tray-icon
echo; echo "=== left click / right click ==="
IPC trayActivate 0 | sed 's/^/  /'
wait_log "$SNI1_LOG" '^Activate' && ok "left click delivered SNI Activate to the item" || bad "no Activate in the item's event log"
IPC trayMenu 0 | sed 's/^/  /'
sleep 0.8
MS="$(tray_state)"
[ "$(echo "$MS" | jq -r '.menuVisible')" = "true" ] && ok "right click opened the item's menu in the themed TrayMenu" || bad "the tray menu did not open"
shot 02-tray-menu
IPC trayMenuEvent 1 | sed 's/^/  /'
wait_log "$SNI1_LOG" '^MenuEvent 1' && ok "menu entry 1 fired back to the item (dbusmenu Event)" || bad "menu event did not reach the item"
IPC trayMenuClose >/dev/null

echo; echo "=== tray panel (the 'more' drawer) ==="
IPC trayPanel true >/dev/null; sleep 0.6
[ "$(tray_state | jq -r '.panelVisible')" = "true" ] && ok "the tray panel opens" || bad "the tray panel did not open"
shot 03-tray-panel
IPC trayPanel false >/dev/null

echo; echo "=== item 2: pixmap path ==="
SNI2_LOG="$RUN/logs/step7-sni2-$STAMP.log"; : > "$SNI2_LOG"
env DBUS_SESSION_BUS_ADDRESS="$BUS" HOME="$RUN/home" XDG_RUNTIME_DIR="$RT" \
  python3 "$MEI/docs/tests/sni-test.py" --pixmap --bus-name org.kde.StatusNotifierItem.meitest2 \
  --event-log "$SNI2_LOG" --title "Mei Pixmap" \
  > "$RUN/logs/step7-sni2-$STAMP.out" 2>&1 &
SNI2=$!
wait_count 2 && ok "a second item registered (tray count 2)" || bad "second item did not appear (count $(tray_count))"
S2="$(tray_state)"
echo "$S2" | jq -c '.items[1] | {service,iconPath,iconName}' 2>/dev/null | sed 's/^/  /'
P2="$(echo "$S2" | jq -r '.items[1].iconPath // ""')"
if [ -n "$P2" ] && [ -f "$P2" ]; then ok "the ARGB pixmap was converted and stored: $P2"; else bad "pixmap item produced no icon file"; fi
# the bar pins a new service and paints it a beat after the daemon sees it
for _ in $(seq 1 20); do
  [ "$(tray_state | jq -r '.items[1].pinned // false' 2>/dev/null)" = "true" ] && break
  sleep 0.2
done
sleep 1.2
shot 04-two-icons
# The second item ships a solid 24x24 #1F9E8F ARGB pixmap, so its on-screen
# extent is the drawn icon box itself (the theme glyph above only gives its ink).
S4="$RUN/shots/step7-04-two-icons.png"
PINFO="$(magick "$S4" -fuzz 8% -fill black +opaque '#1F9E8F' -fill white \
  -opaque '#1F9E8F' -trim -format '%wx%h%X%Y' info: 2>/dev/null)"
PBOX="${PINFO%%+*}"
# A failed -trim prints "1x1-1-1" (negative offsets); require the +X+Y form so
# that cannot pass as a real 14x14 box and poison the crop offsets below.
case "$PINFO" in
  [0-9]*x[0-9]*+[0-9]*+[0-9]*) : ;;
  *) bad "pixmap icon not visible on screen (bbox '${PINFO:-none}')"; PINFO=""; PBOX="" ;;
esac
if [ -n "$PBOX" ]; then
  [ "$PBOX" = "14x14" ] && ok "a 24px tray pixmap is drawn in the bar's 14x14 icon box ($PINFO)" \
    || bad "pixmap icon box unexpected: ${PINFO:-none}"
fi
# the theme icon is the cell immediately left of the pixmap icon; measure its
# ink there rather than from barX (the row anchor is the cluster centre).
if [ -n "$PINFO" ]; then
  PX="$(echo "$PINFO" | cut -d+ -f2)"; PX="${PX:-0}"
  CROP4="$RUN/shots/step7-04-theme-crop.png"
  magick "$S4" -crop "20x18+$((PX - 26))+6" +repage "$CROP4" 2>/dev/null
  BG4="$(magick "$CROP4" -format '%[hex:p{1,1}]' info: 2>/dev/null)"
  TBOX="$(magick "$CROP4" -fuzz 10% -transparent "#$BG4" -trim -format '%wx%h' info: 2>/dev/null)"
  TW="${TBOX%x*}"; TH="${TBOX#*x}"
  note "theme glyph ink left of the pixmap: ${TBOX:-none} on #$BG4 (Adwaita legacy 'dialog-information')"
  if [ -n "${TBOX:-}" ] && [ "${TW:-0}" -ge 3 ] && [ "${TH:-0}" -ge 3 ] && [ "${TH:-0}" -le 18 ]; then
    ok "the theme icon is drawn in the bar (ink ${TBOX})"
  else bad "theme icon not drawn / unexpected ink: ${TBOX:-none}"; fi
else
  note "theme icon crop skipped: the pixmap bbox gave no anchor (the pixmap check above already failed)"
fi

echo; echo "=== removal ==="
kill_sni "$SNI2"
wait_count 1 && ok "removing an item dropped its icon (2 -> 1)" || bad "item removal did not update the tray (count $(tray_count))"
shot 05-after-one-removed
kill_sni "$SNI1"
wait_count 0 && ok "removing the last item emptied the tray (1 -> 0)" || bad "tray not empty after removal (count $(tray_count))"
shot 06-after-both-removed

echo; echo "=== outbound ==="
for p in "$DPID" "$QS"; do
  [ -n "$p" ] || continue
  ss -tunp 2>/dev/null | grep -qE "pid=$p," && { bad "pid $p owns a tcp/udp socket:"; ss -tunp | grep -E "pid=$p,"; } || ok "pid $p owns no tcp/udp socket"
done
for p in "$SNI1" "$SNI2"; do
  if [ -r "/proc/$p/status" ]; then bad "test client $p still running"; else ok "test client $p exited"; fi
done

echo; echo "=== SHUTDOWN ==="
"$MEI/mei" stop || true
sleep 2
stray=""
for n in ryogami matugen mei-shell mei-hub; do
  p="$(pgrep -x "$n" 2>/dev/null | tr '\n' ',' || true)"
  [ -n "$p" ] && stray="$stray $n=$p"
done
for p in $(pgrep -x quickshell 2>/dev/null || true); do
  if tr '\0' ' ' < "/proc/$p/cmdline" 2>/dev/null | grep -q "$MEI/src/ryoku"; then stray="$stray quickshell=$p"; fi
done
[ -z "$stray" ] && ok "clean shutdown: no stray ryogami / matugen / mei-shell / project quickshell" || bad "stray:$stray"
if ls "$RT"/hypr/*/.socket.sock >/dev/null 2>&1; then bad "a nested control socket is still up"
else ok "the nested instance is gone (no control socket)"; fi

echo; echo "=== LIVE BUS AFTER ==="
LIVE_AFTER="$(busctl --user list --no-legend 2>/dev/null | awk -v n="$WATCH" '$1==n{print $2}')"
note "live bus $WATCH owner AFTER: ${LIVE_AFTER:-none}"
[ "$LIVE_AFTER" = "$LIVE_BEFORE" ] && ok "the live watcher owner is unchanged ($LIVE_AFTER)" || bad "live owner changed: $LIVE_BEFORE -> $LIVE_AFTER"

echo; echo "=== verify-untouched AFTER ==="
XDG_RUNTIME_DIR="$HOST_XDG" WAYLAND_DISPLAY="$HOST_WL" "$MEI/mei" verify-untouched 2>&1 | tail -2

echo; echo "RESULT: $([ "$fail" = 0 ] && echo PASS || echo FAIL)"
echo "log: $LOG"
exit "$fail"
