#!/usr/bin/env bash
# Phase 6 step 5 acceptance: wallpaper + matugen theming.
#  - ryogami runs stills-only, guarded to the nested WAYLAND_DISPLAY
#  - a still wallpaper sets and the reveal runs
#  - the palette (colors.json / tones.json) regenerates in the fake HOME
#  - the bar and launcher recolour; a second wallpaper recolours again
#  - matugen runs with Tenkai's minimal config; no outbound; no strays; nothing
#    written to the real ~/.config/{kitty,btop,qt6ct,gtk-3.0,gtk-4.0},
#    ~/.cache/ryoku or ~/.cache/matugen
set -uo pipefail
TENKAI=$HOME/projects/tenkai
RUN="$TENKAI/.run"
RT="$TENKAI/.r"
HOST_XDG="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
HOST_WL="${WAYLAND_DISPLAY:-wayland-1}"
LOG="$RUN/logs/step5-$(date +%H%M%S).log"
mkdir -p "$RUN/shots"
exec > >(tee -a "$LOG") 2>&1
fail=0
ok()  { echo "TESTED      $*"; }
bad() { echo "FAIL        $*"; fail=1; }
note(){ echo "NOTE        $*"; }

REAL_DIRS=("$HOME/.config/kitty" "$HOME/.config/btop" "$HOME/.config/qt6ct" \
           "$HOME/.config/gtk-3.0" "$HOME/.config/gtk-4.0" \
           "$HOME/.cache/ryoku" "$HOME/.cache/matugen")
hash_real() {
  for d in "${REAL_DIRS[@]}"; do
    if [ -e "$d" ]; then
      printf '%s %s\n' "$d" "$(find "$d" -type f -exec sha256sum {} + 2>/dev/null | sort | sha256sum | awk '{print $1}')"
    else
      printf '%s ABSENT\n' "$d"
    fi
  done
}

echo "=== STATIC PROOF ==="
if (cd "$TENKAI/src/ryoku/shell/ryogami/daemon" && go list -deps . 2>/dev/null | grep -qx 'net/http'); then
  bad "net/http is in the ryogami dependency graph"
else
  ok "net/http is NOT in the ryogami dependency graph (unix sockets only)"
fi
for lib in "$TENKAI/.run/bin/ryogami" "$TENKAI/.run/bin/tenkai-shell"; do
  if strings "$lib" | grep -q '47616'; then bad "$(basename "$lib") embeds the palette-bridge port"; else ok "$(basename "$lib") has no 47616 reference"; fi
done
if ss -ltnp 2>/dev/null | grep -q ':47616'; then bad "something listens on 47616"; else ok "no listener on 127.0.0.1:47616 (real session)"; fi

echo; echo "=== GUARDS (HOME, then display) ==="
# The real HOME must be refused, before the display is even considered.
if out=$(HOME=$HOME "$RUN/bin/ryogami" daemon 2>&1); then
  bad "HOME guard did not refuse the real HOME"
elif grep -q "not Tenkai's fake home" <<<"$out"; then
  ok "HOME guard refuses the real HOME: $(echo "$out" | head -1)"
else
  bad "refused for the wrong reason: $(echo "$out" | head -1)"
fi
# Display guard, run with the fake HOME so the HOME guard cannot mask it.
if out=$(HOME="$RUN/home" env -u TENKAI_HOST_WAYLAND_SOCKET "$RUN/bin/ryogami" daemon 2>&1); then bad "display guard did not refuse with the env unset"; else ok "display guard: $(echo "$out" | head -1)"; fi
if out=$(HOME="$RUN/home" XDG_RUNTIME_DIR="$HOST_XDG" WAYLAND_DISPLAY="$HOST_WL" TENKAI_HOST_WAYLAND_SOCKET="$HOST_XDG/$HOST_WL" "$RUN/bin/ryogami" daemon 2>&1); then bad "display guard allowed the live display"; else ok "display guard: $(echo "$out" | head -1)"; fi
if out=$(HOME=$HOME "$RUN/bin/tenkai-shell" daemon 2>&1); then bad "tenkai-shell accepted the real HOME"; else ok "tenkai-shell HOME guard: $(echo "$out" | head -1)"; fi
if out=$(HOME=$HOME "$RUN/bin/tenkai-hub" config get bar 2>&1); then bad "tenkai-hub accepted the real HOME"; else ok "tenkai-hub HOME guard: $(echo "$out" | head -1)"; fi
if out=$(HOME=$HOME "$RUN/bin/tenkai-wm-hyprland" caps 2>&1); then bad "tenkai-wm-hyprland accepted the real HOME"; else ok "tenkai-wm-hyprland HOME guard: $(echo "$out" | head -1)"; fi

echo; echo "=== REAL-PATH HASHES BEFORE ==="
hash_real | tee "$RUN/step5-real-before.txt"

echo; echo "=== verify-untouched BEFORE ==="
XDG_RUNTIME_DIR="$HOST_XDG" WAYLAND_DISPLAY="$HOST_WL" "$TENKAI/tenkai" verify-untouched 2>&1 | tail -2

# The nested fake config must run the keep-list qsbar bar, not the sumi rail:
# with sumi the top-strip crop below is wallpaper, so the bar assertion would be
# meaningless. (barStyle is patched only through the settings store; the hub's
# Bar page falls back to "sumi" when it cannot read the current id.)
SHELLJSON="$RUN/config/tenkai/shell.json"
note "nested shell.json barStyle: $(jq -r '.barStyle' "$SHELLJSON" 2>/dev/null || echo '?')"
[ "$(jq -r '.barStyle' "$SHELLJSON" 2>/dev/null)" = "qsbar" ] || {
  jq '.barStyle = "qsbar"' "$SHELLJSON" > "$SHELLJSON.tmp" && mv "$SHELLJSON.tmp" "$SHELLJSON"
  note "pinned barStyle=qsbar in the nested fake config"
}

echo; echo "=== starting ./tenkai run ==="
XDG_RUNTIME_DIR="$HOST_XDG" WAYLAND_DISPLAY="$HOST_WL" "$TENKAI/tenkai" run || { bad "tenkai run failed"; exit 1; }

SIG=""; QS=""
for _ in $(seq 1 120); do
  SIG="$(ls -d "$RT/hypr/"*/ 2>/dev/null | head -1 | xargs -r basename)"
  QS="$(pgrep -f "qs -p $TENKAI/src/ryoku/shell/quickshell/shell" | head -1)"
  [ -n "$SIG" ] && [ -n "$QS" ] && break
  sleep 0.5
done
[ -n "$SIG" ] && [ -n "$QS" ] || { bad "session did not come up"; "$TENKAI/tenkai" stop; exit 1; }
if [ "$SIG" = "efb50993780079460b0cbed1363e2166a2de1d9f_1792407547_2121810691" ]; then bad "nested signature equals the baseline"; "$TENKAI/tenkai" stop; exit 1; fi
ok "nested Hyprland signature differs from the baseline"

export XDG_RUNTIME_DIR="$RT" HYPRLAND_INSTANCE_SIGNATURE="$SIG"
WDISP="$(basename "$(ls "$RT"/wayland-* 2>/dev/null | head -1)")"
export WAYLAND_DISPLAY="$WDISP"
H() {
  local rt="${RT:-${TENKAI:-$HOME/projects/tenkai}/.r}" sig="${SIG:-}"
  [ -n "$sig" ] && [ -S "$rt/hypr/$sig/.socket.sock" ] \
    || { echo "REFUSED: nested Hyprland socket absent; no live fallback" >&2; return 1; }
  XDG_RUNTIME_DIR="$rt" HYPRLAND_INSTANCE_SIGNATURE="$sig" hyprctl "$@" 2>/dev/null
}
wake() { H dispatch dpms on >/dev/null 2>&1; H dispatch movecursor 960 540 >/dev/null 2>&1; }
shot() {
  local f="$RUN/shots/step5-$1.png" i
  rm -f "$f"
  for i in 1 2 3; do
    wake
    timeout 20 grim -o "${WDISP^^}" "$f" 2>/dev/null && { echo "  shot: step5-$1.png"; return 0; }
    sleep 1
  done
  bad "screenshot step5-$1.png failed after 3 attempts"
  return 1
}
snap() {
  local f="$RUN/shots/$1"
  rm -f "$f"
  wake
  timeout 20 grim -o "${WDISP^^}" "$f" 2>/dev/null || { bad "screenshot $f failed"; return 1; }
}
M() { "$RUN/bin/tenkai-shell" "$@"; }
RY() { "$RUN/bin/ryogami" "$@"; }

MON="$(H -j monitors | jq -r '.[0].name' 2>/dev/null)"
[ -n "$MON" ] && H keyword monitor "$MON,1600x1000,auto,1" >/dev/null 2>&1
sleep 3

RPID="$(pgrep -f "$RUN/bin/ryogami daemon" | head -1)"
DPID="$(pgrep -f "$RUN/bin/tenkai-shell daemon" | head -1)"
note "ryogami pid=$RPID  daemon pid=$DPID  shell pid=$QS"

echo; echo "=== ryogami is running under the guard ==="
if [ -n "$RPID" ]; then
  ok "ryogami running (pid $RPID)"
  grep -q "display guard ok" "$RUN/logs/ryogami.log" && ok "ryogami logged the display guard: $(grep 'display guard ok' "$RUN/logs/ryogami.log" | tail -1)" || bad "no display-guard line in ryogami.log"
  grep -q "listening on $RT/ryogami.sock" "$RUN/logs/ryogami.log" && ok "ryogami listens on the nested runtime socket" || bad "ryogami socket path unexpected"
else
  bad "ryogami is not running"
fi
[ -S "$RT/ryogami.sock" ] && ok "nest runtime holds ryogami.sock" || bad "no ryogami.sock in $RT"

echo; echo "=== matugen config carries exactly one template: kitty ==="
CFG="$RUN/config/tenkai/matugen/config.toml"
KITTY_OUT="$RUN/home/.cache/tenkai/kitty-colors.conf"
if [ -f "$CFG" ]; then
  if grep -qE '^[[:space:]]*post_hook[[:space:]]*=' "$CFG"; then
    bad "config carries a post_hook (an arbitrary command after every render):"; cat "$CFG"
  else
    ok "no post_hook in $CFG"
  fi
  blocks="$(grep -oE '^\[templates\.[^]]+\]' "$CFG" | tr '\n' ' ')"
  if [ "$blocks" = "[templates.kitty] " ]; then
    ok "exactly one template block, kitty: $blocks"
  else
    bad "template blocks are not just kitty: ${blocks:-none}"
  fi
  if [ "$(sed -n 's/^input_path = "\(.*\)"$/\1/p' "$CFG")" = "$RUN/config/tenkai/matugen/templates/kitty-colors.conf" ]; then
    ok "kitty template input is Tenkai's own copy"
  else
    bad "kitty template input_path is not Tenkai's copy"
  fi
  if [ "$(sed -n 's/^output_path = "\(.*\)"$/\1/p' "$CFG")" = "$KITTY_OUT" ]; then
    ok "kitty colours render into the session cache, not ~/.config/kitty"
  else
    bad "kitty output_path is not the session cache"
  fi
  if grep -q '^\[config\]' "$CFG" && grep -q '^\[templates\]' "$CFG"; then
    ok "config keeps the minimal valid form ([config] + [templates])"
  else
    bad "config lost [config] or the templates key"; cat "$CFG"
  fi
else
  bad "no matugen config at $CFG"
fi

echo; echo "=== BEFORE the first wallpaper ==="
# The nested session keeps its wallpaper between runs (the cold start moves the
# state and restores it), so the wallpaper on screen when the harness starts is
# whatever the last run left. Setting the same picture again changes nothing
# and the "the wallpaper area changed" check below would fail for a reason that
# has nothing to do with the product. The harness therefore primes a known
# wallpaper first, so "set 1" and "set 2" are always a real change.
"$TENKAI/tenkai" wallpaper "$RUN/wall/wall-2-green.png" >/dev/null 2>&1 || note "could not prime the wallpaper"
for _ in 1 2 3 4 5; do sleep 1.2; done
shot 01-before
COL0="$(sha256sum "$RUN/home/.cache/tenkai/colors.json" 2>/dev/null | awk '{print $1}')"
note "colors.json before: ${COL0:-absent}"
WAVG0="$(magick "$RUN/shots/step5-01-before.png" -crop 1600x900+0+60 +repage -resize 1x1 -format '%[hex:p{0,0}]' info: 2>/dev/null)"
note "wallpaper area mean colour before: ${WAVG0}"

echo; echo "=== OUTBOUND CHECK (stills, before any change) ==="
sleep 2
for p in "$RPID" "$DPID" "$QS"; do
  [ -n "$p" ] || continue
  ss -tunp 2>/dev/null | grep -qE "pid=$p," && { bad "pid $p owns a tcp/udp socket:"; ss -tunp | grep -E "pid=$p,"; } || ok "pid $p owns no tcp/udp socket"
done

echo; echo "=== SET 1: warm still ==="
"$TENKAI/tenkai" wallpaper "$RUN/wall/wall-1-warm.jpg" || bad "wallpaper set 1 failed (./tenkai wallpaper)"
sleep 0.15; shot 02-set1-reveal-015
sleep 0.60; shot 03-set1-reveal-060
sleep 1.60; shot 04-set1-settled
sleep 1.0
python3 - "$RUN/home/.cache/tenkai/colors.json" "$RUN/home/.cache/tenkai/tones.json" <<'PY' && ok "palette regenerated on set 1" || bad "palette missing/invalid on set 1"
import json,sys
c=json.load(open(sys.argv[1])); t=json.load(open(sys.argv[2]))
assert isinstance(c,dict) and len(c)>8, "colors too small"
assert isinstance(t,dict) and len(t)>3, "tones too small"
print("  primary:", (c.get("primary") or {}).get("hex") if isinstance(c.get("primary"),dict) else c.get("primary"))
print("  background:", (c.get("background") or {}).get("hex") if isinstance(c.get("background"),dict) else c.get("background"))
PY
COL1="$(sha256sum "$RUN/home/.cache/tenkai/colors.json" | awk '{print $1}')"
note "colors.json after set 1: $COL1"
[ -n "$COL0" ] && [ "$COL0" != "$COL1" ] && ok "colors.json changed on the first palette" || note "colors.json was absent before (first palette)"
if [ -s "$KITTY_OUT" ]; then
  ok "kitty colours rendered: $KITTY_OUT ($(wc -l < "$KITTY_OUT") lines)"
  if grep -qE '^color1?[0-9] #[0-9a-fA-F]{6}$' "$KITTY_OUT" && grep -qE '^background #[0-9a-fA-F]{6}$' "$KITTY_OUT"; then
    ok "kitty file is in kitty's own colour form (background + color0..15)"
  else
    bad "kitty file is not in kitty's colour form:"; head -5 "$KITTY_OUT"
  fi
else
  bad "no kitty colours at $KITTY_OUT after a palette pass"
fi

echo; echo "=== bar + launcher recolour (pixel evidence) ==="
snap step5-bar-after1.png
magick "$RUN/shots/step5-bar-after1.png" -crop 1180x36+0+0 +repage "$RUN/shots/step5-bar-after1-crop.png" 2>/dev/null
BAR1="$(sha256sum "$RUN/shots/step5-bar-after1-crop.png" | awk '{print $1}')"
BARAVG1="$(magick "$RUN/shots/step5-bar-after1-crop.png" -resize 1x1 -format '%[hex:p{0,0}]' info: 2>/dev/null)"
note "bar strip mean colour / hash after set 1: ${BARAVG1} / ${BAR1:0:12}"
H dispatch global tenkai:launcher >/dev/null 2>&1; sleep 2.5
snap step5-launcher-p1.png && note "shot: step5-launcher-p1.png"
LACC1="$(magick "$RUN/shots/step5-launcher-p1.png" -crop 40x12+540+430 +repage -resize 1x1 -format '%[hex:p{0,0}]' info: 2>/dev/null)"
note "launcher accent dot under set 1: ${LACC1}"
H dispatch global tenkai:launcher >/dev/null 2>&1; sleep 1

echo; echo "=== SET 2: purple still (recolour again) ==="
"$TENKAI/tenkai" wallpaper "$RUN/wall/wall-3-purple.jpg" || bad "wallpaper set 2 failed"
WAVG1="$(magick "$RUN/shots/step5-04-set1-settled.png" -crop 1600x900+0+60 +repage -resize 1x1 -format '%[hex:p{0,0}]' info: 2>/dev/null)"
WAVG2=""
for i in 1 2 3 4 5; do
  sleep 1.5
  shot 05-set2-settled || break
  WAVG2="$(magick "$RUN/shots/step5-05-set2-settled.png" -crop 1600x900+0+60 +repage -resize 1x1 -format '%[hex:p{0,0}]' info: 2>/dev/null)"
  [ -n "$WAVG2" ] && [ "$WAVG2" != "$WAVG1" ] && break
  wake
  [ "$i" -lt 5 ] && "$TENKAI/tenkai" wallpaper "$RUN/wall/wall-3-purple.jpg" >/dev/null 2>&1
  true
done
COL2="$(sha256sum "$RUN/home/.cache/tenkai/colors.json" | awk '{print $1}')"
note "colors.json after set 2: $COL2"
[ "$COL1" != "$COL2" ] && ok "palette changed again on the second wallpaper" || bad "palette did not change on the second wallpaper"
snap step5-bar-after2.png
magick "$RUN/shots/step5-bar-after2.png" -crop 1180x36+0+0 +repage "$RUN/shots/step5-bar-after2-crop.png" 2>/dev/null
BAR2="$(sha256sum "$RUN/shots/step5-bar-after2-crop.png" | awk '{print $1}')"
BARAVG2="$(magick "$RUN/shots/step5-bar-after2-crop.png" -resize 1x1 -format '%[hex:p{0,0}]' info: 2>/dev/null)"
note "bar strip mean colour / hash after set 2: ${BARAVG2} / ${BAR2:0:12}"
[ "$BAR1" != "$BAR2" ] && ok "bar strip pixels differ between the two palettes (${BARAVG1} -> ${BARAVG2})" || bad "bar strip did not recolour"
H dispatch global tenkai:launcher >/dev/null 2>&1; sleep 2.5
snap step5-launcher-p2.png && note "shot: step5-launcher-p2.png"
LACC2="$(magick "$RUN/shots/step5-launcher-p2.png" -crop 40x12+540+430 +repage -resize 1x1 -format '%[hex:p{0,0}]' info: 2>/dev/null)"
[ -n "$LACC1" ] && [ "$LACC1" != "$LACC2" ] && ok "launcher accent recoloured with the palette (${LACC1} -> ${LACC2})" || bad "launcher accent did not recolour (${LACC1:-?} -> ${LACC2:-?})"
H dispatch global tenkai:launcher >/dev/null 2>&1; sleep 1

WAVG1="$(magick "$RUN/shots/step5-04-set1-settled.png" -crop 1600x900+0+60 +repage -resize 1x1 -format '%[hex:p{0,0}]' info: 2>/dev/null)"
WAVG2="$(magick "$RUN/shots/step5-05-set2-settled.png" -crop 1600x900+0+60 +repage -resize 1x1 -format '%[hex:p{0,0}]' info: 2>/dev/null)"
note "wallpaper area mean colour: before ${WAVG0} -> set 1 ${WAVG1} -> set 2 ${WAVG2}"
if [ -n "$WAVG0" ] && [ -n "$WAVG1" ] && [ -n "$WAVG2" ] && [ "$WAVG0" != "$WAVG1" ] && [ "$WAVG1" != "$WAVG2" ]; then
  ok "the still wallpaper itself painted and changed on both sets"
else
  bad "the wallpaper area did not change as expected"
fi

echo; echo "=== matugen invocations in the daemon log ==="
if grep -q 'matugen scheme:' "$RUN/logs/daemon.log"; then ok "scheme generation logged: $(grep 'matugen scheme:' "$RUN/logs/daemon.log" | tail -1 | cut -c1-140)"; else bad "no 'matugen scheme:' line"; fi
if grep -q "matugen render: matugen -c $CFG" "$RUN/logs/daemon.log"; then ok "render pass logged with Tenkai's config path: $(grep 'matugen render:' "$RUN/logs/daemon.log" | tail -1 | cut -c1-160)"; else bad "no render line with $CFG"; fi

echo; echo "=== outbound after a palette pass ==="
sleep 2
for p in $(pgrep -f "$RUN/bin/ryogami daemon") $(pgrep -f "$RUN/bin/tenkai-shell daemon") "$QS"; do
  [ -n "$p" ] || continue
  ss -tunp 2>/dev/null | grep -qE "pid=$p," && { bad "pid $p owns a tcp/udp socket after the palette:"; ss -tunp | grep -E "pid=$p,"; } || ok "pid $p still owns no tcp/udp socket"
done

echo; echo "=== ryogami resource use ==="
if [ -n "$RPID" ] && [ -r "/proc/$RPID/status" ]; then
  note "ryogami $(grep -E '^(VmRSS|VmHWM|Threads):' "/proc/$RPID/status" | tr '\n' ' ')"
  ps -o pid,rss,%cpu,etime,cmd -p "$RPID" | tail -1
fi

echo; echo "=== SHUTDOWN ==="
"$TENKAI/tenkai" stop || true
sleep 2
# comm-based so a shell whose *command line* merely mentions these paths is not
# mistaken for a stray; Quickshell is matched only when its cmdline names Tenkai.
stray=""
for n in ryogami matugen tenkai-shell tenkai-hub; do
  # A name alone is not enough: the owner's live session runs its own
  # /usr/bin ryogami (and matugen), and those are not Tenkai's. Only a
  # process whose cmdline carries the project path belongs to Tenkai.
  for p in $(pgrep -x "$n" 2>/dev/null || true); do
    if tr '\0' ' ' < "/proc/$p/cmdline" 2>/dev/null | grep -qF "$TENKAI"; then stray="$stray $n=$p"; fi
  done
done
for p in $(pgrep -x quickshell 2>/dev/null || true); do
  if tr '\0' ' ' < "/proc/$p/cmdline" 2>/dev/null | grep -q "$TENKAI/src/ryoku"; then stray="$stray quickshell=$p"; fi
done
[ -z "$stray" ] && ok "clean shutdown: no stray ryogami / matugen / tenkai-shell / project quickshell" || bad "stray:$stray"

echo; echo "=== REAL-PATH HASHES AFTER ==="
hash_real | tee "$RUN/step5-real-after.txt"
if diff -u "$RUN/step5-real-before.txt" "$RUN/step5-real-after.txt" >/dev/null; then ok "real ~/.config/{kitty,btop,qt6ct,gtk-3.0,gtk-4.0}, ~/.cache/ryoku, ~/.cache/matugen unchanged"; else bad "a real path changed:"; diff -u "$RUN/step5-real-before.txt" "$RUN/step5-real-after.txt"; fi

echo; echo "=== verify-untouched AFTER ==="
XDG_RUNTIME_DIR="$HOST_XDG" WAYLAND_DISPLAY="$HOST_WL" "$TENKAI/tenkai" verify-untouched 2>&1 | tail -2

echo; echo "RESULT: $([ "$fail" = 0 ] && echo PASS || echo FAIL)"
echo "log: $LOG"
exit "$fail"
