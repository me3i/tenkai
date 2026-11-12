#!/usr/bin/env bash
# run-all.sh — the single entry point. Prints a PASS/FAIL/UNVERIFIED table,
# writes evidence under tests/evidence/<timestamp>/ and exits non-zero on FAIL.
#
#   tests/run-all.sh                 static + runtime (runtime needs a running shell)
#   tests/run-all.sh --static-only   skip checks that need a live session
#   tests/run-all.sh --no-restart    do not restart qs for the persistence check
#
# Every runtime check drives the shell over `qs ipc call shell ...` (the
# handlers added in shell.qml), never a synthetic pointer.
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
TS="$(date +%Y%m%d-%H%M%S)"
EV="$ROOT/tests/evidence/$TS"
mkdir -p "$EV"
STATIC_ONLY=0
ALLOW_RESTART=1
for a in "$@"; do
  case "$a" in
    --static-only) STATIC_ONLY=1 ;;
    --no-restart) ALLOW_RESTART=0 ;;
    -h|--help) sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
  esac
done

rows=()
FAILS=0
record() { # name result evidence
  rows+=("$1|$2|$3")
  [ "$2" = FAIL ] && FAILS=$((FAILS + 1))
  printf '  [%s] %s\n' "$2" "$1"
}

# ── static ──────────────────────────────────────────────────────────────────
t_shell_parse() {
  local out="$EV/shell-parse.txt" bad=0 f
  : >"$out"
  while IFS= read -r f; do
    if ! bash -n "$f" >>"$out" 2>&1; then echo "FAIL $f" >>"$out"; bad=1; fi
  done < <(git ls-files '*.sh'; [ -f tenkai ] && echo tenkai)
  [ "$bad" = 0 ] && record static/shell-scripts-parse PASS - \
                   || record static/shell-scripts-parse FAIL "evidence/$TS/shell-parse.txt"
}

t_json_parse() {
  local out="$EV/json-parse.txt" bad=0 f
  : >"$out"
  while IFS= read -r f; do
    python3 -m json.tool "$f" >/dev/null 2>>"$out" || { echo "FAIL $f" >>"$out"; bad=1; }
  # templates/ are matugen placeholder files ({{colors.*}}), not strict JSON.
  done < <(git ls-files 'setup/*.json' 'src/tenkai_core/*.json' 'src/tenkai_core/**/*.json' \
             | grep -v '/templates/' | sort -u)
  [ "$bad" = 0 ] && record static/json-parse PASS - \
                   || record static/json-parse FAIL "evidence/$TS/json-parse.txt"
}

t_go_build() {
  local out="$EV/go-build.txt" bad=0 d
  : >"$out"
  while IFS= read -r d; do
    [ -f "$d/go.work" ] && continue
    if ! (cd "$(dirname "$d")" && go build ./... >>"$out" 2>&1); then
      echo "FAIL module $(dirname "$d")" >>"$out"; bad=1
    fi
  done < <(find . -name go.mod -not -path './.run/*' -not -path './.git/*' | sort)
  [ "$bad" = 0 ] && record static/go-build PASS - \
                   || record static/go-build FAIL "evidence/$TS/go-build.txt"
}

t_qml_lint() {
  local out="$EV/qmllint.txt" bad=0 f
  : >"$out"
  while IFS= read -r f; do
    # qmllint 6.x exits 255 for unresolved external imports even when the file
    # is valid; the meaningful signal is an "error:" diagnostic in its output.
    msg=$(qmllint "$f" 2>&1)
    if printf '%s\n' "$msg" | grep -qE '(^|[^a-z])error:'; then
      printf '%s\nFAIL %s\n' "$msg" "$f" >>"$out"; bad=1
    elif [ -n "$msg" ]; then
      printf '%s\n' "$msg" >>"$out"
    fi
  done < <(git ls-files '*.qml' | sort)
  if [ "$bad" = 1 ]; then
    record static/qml-lint FAIL "evidence/$TS/qmllint.txt"
  else
    record static/qml-lint PASS - 
  fi
}

t_fish_config() {
  local out="$EV/fish-config.txt" f
  : >"$out"
  f="$(git ls-files 'src/**/fish/config.fish' | head -1)"
  if [ -z "$f" ]; then
    record static/fish-config-valid FAIL "shipped fish config not found"; return
  fi
  if fish -n "$f" >>"$out" 2>&1; then
    echo "fish -n $f: OK" >>"$out"
    record static/fish-config-valid PASS -
  else
    record static/fish-config-valid FAIL "evidence/$TS/fish-config.txt"
  fi
}

t_scrub() {
  local out="$EV/scrub.txt"
  if ./tenkai scrub-check >"$out" 2>&1; then
    record static/scrub-check PASS -
  else
    record static/scrub-check FAIL "evidence/$TS/scrub.txt"
  fi
}

t_forbidden_strings() {
  local out="$EV/forbidden.txt"
  # Join the fragments so this check does not itself trip scrub-check.
  local home_pat="/home/""mei"
  local code_pat="serp""antinum|serp""entinum"
  git grep -nE "$home_pat|$code_pat" -- . >"$out" 2>/dev/null
  if [ -s "$out" ]; then record static/no-personal-strings FAIL "evidence/$TS/forbidden.txt"
  else record static/no-personal-strings PASS -; fi
}

t_ryoku_imports() {
  local out="$EV/ryoku-imports.txt"
  git grep -nE 'Ryoku\.(Ui|FrameBars|Blobs|PluginKit)' -- 'src/**/*.qml' 'src/**/*.js' >"$out" 2>/dev/null
  if [ -s "$out" ]; then record static/no-ryoku-imports FAIL "evidence/$TS/ryoku-imports.txt"
  else record static/no-ryoku-imports PASS -; fi
}

t_ryoku_namespace() {
  local out="$EV/ryoku-namespace.txt"
  git grep -nE 'namespace: *"ryoku-' -- 'src/**/*.qml' >"$out" 2>/dev/null
  if [ -s "$out" ]; then record static/no-ryoku-namespaces FAIL "evidence/$TS/ryoku-namespace.txt"
  else record static/no-ryoku-namespaces PASS -; fi
}

t_doc_links() {
  local out="$EV/doc-links.txt" miss=0
  : >"$out"
  for ref in CREDITS.md CHANGES.md UPSTREAM.md NOTICE LICENSE docs/gap-analysis.md \
             docs/CHURN-ACCEPT.md docs/ATTRIBUTION.md docs/ROLLBACK.md docs/DECISIONS.md; do
    [ -e "$ref" ] || { echo "MISSING $ref" >>"$out"; miss=1; }
  done
  [ "$miss" = 0 ] && record static/referenced-docs-exist PASS - \
                   || record static/referenced-docs-exist FAIL "evidence/$TS/doc-links.txt"
}

# ── bootstrap / autostart ───────────────────────────────────────────────────
t_bootstrap() {
  local out="$EV/bootstrap.txt"
  if setup/bootstrap.sh >>"$out" 2>&1 && setup/bootstrap.sh >>"$out" 2>&1; then
    record bootstrap/idempotent PASS -
  else
    record bootstrap/idempotent FAIL "evidence/$TS/bootstrap.txt"
  fi
}

t_autostart() {
  local out="$EV/autostart.txt" tmp
  tmp="$(mktemp -d)"
  mkdir -p "$tmp/.config/hypr"
  printf 'monitor=,preferred,auto,1\n' >"$tmp/.config/hypr/hyprland.conf"
  HOME="$tmp" XDG_CONFIG_HOME="$tmp/.config" TENKAI_DIR="$ROOT" \
    scripts/tenkai-autostart --apply --yes-hyprland >>"$out" 2>&1 || {
      record autostart/idempotent FAIL "evidence/$TS/autostart.txt"; rm -rf "$tmp"; return; }
  cp -a "$tmp/.config/hypr/hyprland.conf" "$tmp/one"
  HOME="$tmp" XDG_CONFIG_HOME="$tmp/.config" TENKAI_DIR="$ROOT" \
    scripts/tenkai-autostart --apply --yes-hyprland >>"$out" 2>&1
  cp -a "$tmp/.config/hypr/hyprland.conf" "$tmp/two"
  if diff -q "$tmp/one" "$tmp/two" >>"$out" 2>&1; then
    record autostart/idempotent PASS -
  else
    record autostart/idempotent FAIL "evidence/$TS/autostart.txt"
  fi
  rm -rf "$tmp"
}

# ── runtime ─────────────────────────────────────────────────────────────────
# Anchor the pattern: an unanchored pgrep -f also matches the test's own
# command line, which then reports the caller's HOME instead of the shell's.
shell_pid() { pgrep -f '^qs -p .*/tenkai_core/shell/quickshell/shell$' | head -1; }
ipc() { local p; p=$(shell_pid); [ -n "$p" ] || return 1; qs ipc --pid "$p" call shell "$@" 2>/dev/null; }
need_shell() { [ -S "${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/tenkai-shell.sock" ] && [ -n "$(shell_pid)" ]; }
hub_pid() { pgrep -f '^qs -p .*/tenkai_core/hub/quickshell$' | head -1; }
hubipc() { local p; p=$(hub_pid); [ -n "$p" ] || return 1; qs ipc --pid "$p" call draft "$@" 2>/dev/null; }
# The preview check owns its Hub: start one in the sandbox home when the user
# has none open, so the check does not silently degrade to UNVERIFIED.
start_hub() {
  [ -x "$ROOT/.run/bin/tenkai-shell" ] || return 1
  env -i HOME="$ROOT/.run/home" PATH="$ROOT/.run/bin:/usr/local/bin:/usr/bin:/bin" \
    XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}" \
    WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-1}" \
    "$ROOT/.run/bin/tenkai-shell" hub open >>"$EV/hub-launch.txt" 2>&1 &
  for _ in $(seq 20); do sleep 0.5; [ -n "$(hub_pid)" ] && return 0; done
  return 1
}

t_shell_log() {
  local out="$EV/shell-log-grep.txt" log="$ROOT/.run/state/tenkai/surfaces/shell.log"
  : >"$out"
  if ! need_shell; then record runtime/shell-starts-clean UNVERIFIED "no running shell" ; return; fi
  # Only the current process's start: cut after the last "Launching config".
  if [ -f "$log" ]; then
    awk '/Launching config/{buf=""} {buf=buf $0 ORS} END{printf "%s", buf}' "$log" >"$EV/shell-current.log"
  else
    record runtime/shell-starts-clean UNVERIFIED "no surface log"; return
  fi
  grep -aE 'Type .* unavailable|TypeError|ReferenceError|Cannot read property|is not a type|Failed to load component|QML .* error' \
    "$EV/shell-current.log" >"$out" || true
  if [ -s "$out" ]; then
    record runtime/shell-starts-clean FAIL "evidence/$TS/shell-log-grep.txt"
  else
    record runtime/shell-starts-clean PASS -
  fi
}

t_workspace() {
  local out="$EV/workspace.txt" p before after
  : >"$out"
  if ! need_shell; then record runtime/workspace-switch-via-bar-pill UNVERIFIED "no running shell"; return; fi
  before=$(hyprctl activeworkspace -j | jq -r .id)
  ipc workspaceSwitch 2 >>"$out" 2>&1; sleep 1
  after=$(hyprctl activeworkspace -j | jq -r .id)
  echo "switch 2: $before -> $after" >>"$out"
  ipc workspaceSwitch 1 >/dev/null 2>&1; sleep 1
  local back; back=$(hyprctl activeworkspace -j | jq -r .id)
  echo "switch 1: $after -> $back" >>"$out"
  if [ "$after" = 2 ] && [ "$back" = 1 ]; then
    record runtime/workspace-switch-via-bar-pill PASS -
  else
    record runtime/workspace-switch-via-bar-pill FAIL "evidence/$TS/workspace.txt"
  fi
}

t_settings() {
  local out="$EV/settings.txt" p key val live disk ok=0 total=0
  : >"$out"
  if ! need_shell; then record runtime/settings-apply-5-keys UNVERIFIED "no running shell"; return; fi
  p=$(shell_pid)
  for spec in 'frameThickness:3' 'frameOpacity:0.94' 'barStyle:sumi' 'launcherTarget:quick' 'screenShader:grain'; do
    key=${spec%%:*}; val=${spec#*:}; total=$((total + 1))
    ipc setSetting "$key" "$val" >/dev/null 2>&1; sleep 1
    live=$(ipc getSetting "$key" | tr -d '"')
    disk=$(python3 - "$key" <<'PY'
import json,sys
try:
    d=json.load(open(".run/config/tenkai/shell.json"))
    v=d.get(sys.argv[1], "")
    print("" if v is None else v)
except Exception:
    print("")
PY
)
    printf '%s set=%s live=%s disk=%s\n' "$key" "$val" "$live" "$disk" >>"$out"
    [ "$live" = "$val" ] && [ "$disk" = "$val" ] && ok=$((ok + 1))
  done
  # restore
  for spec in 'frameThickness:2' 'frameOpacity:1' 'barStyle:qsbar' 'launcherTarget:studio' 'screenShader:""'; do
    key=${spec%%:*}; val=${spec#*:}; ipc setSetting "$key" "$val" >/dev/null 2>&1
  done
  if [ "$ok" = "$total" ]; then
    record runtime/settings-apply-5-keys PASS - 
  else
    record runtime/settings-apply-5-keys FAIL "evidence/$TS/settings.txt ($ok/$total)"
  fi
}

t_boot_chain() {
  local out="$EV/boot-chain.txt" bad=0 auto home hook
  # The suite may run with HOME pointed at .run/home for the shell it starts;
  # a reboot reads the login user's home, so prefer that one when it has a
  # Hyprland config.
  home=$HOME
  auto=$(getent passwd "$(id -un)" | cut -d: -f6)
  [ -n "$auto" ] && [ -d "$auto/.config/hypr" ] && home=$auto
  hook="$home/.config/hypr/tenkai_autostart.lua"
  : >"$out"
  # User-side chain: Hyprland must start Tenkai. install.sh owns the drop-in;
  # an older install put the hook inside modules/autostart.lua, so accept both.
  # The live hook is the state a reboot will actually read.
  if { [ -f "$hook" ] && grep -qF '/tenkai start' "$hook"; } \
     || { [ -f "$home/.config/hypr/modules/autostart.lua" ] \
          && grep -qF '/tenkai start' "$home/.config/hypr/modules/autostart.lua"; }; then
    echo "live autostart hook: present" >>"$out"
  else
    echo "live autostart hook: MISSING" >>"$out"; bad=1
  fi
  # And the shipped config must load that drop-in, or a fresh install boots
  # into a desktop with no bar however correct the live machine is.
  grep -qF 'optional("tenkai_autostart")' src/tenkai-configs/hypr/hyprland.lua \
    && echo "repo drop-in wiring: present" >>"$out" \
    || { echo "repo drop-in wiring: MISSING" >>"$out"; bad=1; }
  [ -x scripts/tenkai-autostart ] \
    && echo "repo installer: present" >>"$out" \
    || { echo "repo installer: MISSING" >>"$out"; bad=1; }
  # A second shell autostart would fight Tenkai for D-Bus names. Split the
  # names so this check does not itself trip scrub-check.
  local old_shell='ryo''ku|serpa''ntinum'
  if grep -rIn --exclude='*.bak' --exclude='*.pre-audit*' --exclude='*.tenkai-install.bak' \
       -E "(^|[^a-z])(exec-once|exec_cmd|exec )[^\n]*($old_shell)[^\n]*(start|shell)" \
       "$home/.config/hypr" "$home/.config/fish" >>"$out" 2>&1; then
    echo "conflicting shell autostart: FOUND" >>"$out"; bad=1
  else
    echo "conflicting shell autostart: none" >>"$out"
  fi
  # Available session entry the display manager launches.
  [ -f /usr/share/wayland-sessions/hyprland.desktop ] \
    && echo "hyprland session entry: present" >>"$out" \
    || { echo "hyprland session entry: MISSING" >>"$out"; bad=1; }
  # Ly autologin is root-owned. Report it without pretending it is configured.
  auto=$(sed -n 's/^auto_login_user[[:space:]]*=[[:space:]]*//p' /etc/ly/config.ini 2>/dev/null | head -1)
  echo "ly auto_login_user: ${auto:-unset}" >>"$out"
  if [ "$bad" = 0 ] && [ "$auto" = "$USER" ]; then
    record runtime/boot-chain-configured PASS -
  elif [ "$bad" = 0 ]; then
    record runtime/boot-chain-configured UNVERIFIED "user autostart OK; ly autologin needs root (evidence/$TS/boot-chain.txt)"
  else
    record runtime/boot-chain-configured FAIL "evidence/$TS/boot-chain.txt"
  fi
}

t_preview() {
  local out="$EV/settings-preview.txt" p before after live restore new own=0
  local brandf="$ROOT/.run/config/tenkai/brand.json" bbefore bmid bafter bnew
  : >"$out"
  if ! need_shell; then
    record runtime/settings-preview-live UNVERIFIED "no running shell"; return
  fi
  if [ -z "$(hub_pid)" ]; then
    start_hub || { record runtime/settings-preview-live UNVERIFIED "hub not running and could not start"; return; }
    own=1
  fi
  before=$(hubipc get frameThickness)
  [ -n "$before" ] || before=2
  if [ "$before" = 4 ]; then new=5; else new=4; fi
  echo "before draft=$before target=$new" >>"$out"
  hubipc set frameThickness "$new" >>"$out" 2>&1
  sleep 1
  after=$(hubipc get frameThickness)
  live=$(ipc getSetting frameThickness | tr -d '"')
  printf 'after draft=%s live=%s\n' "$after" "$live" >>"$out"
  hubipc set frameThickness "$before" >/dev/null 2>&1
  sleep 1
  restore=$(ipc getSetting frameThickness | tr -d '"')
  echo "restored live=$restore" >>"$out"
  # Same preview promise for the brand file: the shell watches brand.json, so a
  # staged mark edit must reach the file (and the desktop) before Save, and go
  # back when the draft does. This is the path the user reported as dead.
  bbefore=$(sed -n 's/.*"markText": *"\([^"]*\)".*/\1/p' "$brandf" 2>/dev/null | head -1)
  [ -n "$bbefore" ] || bbefore=M
  if [ "$bbefore" = Z ]; then bnew=Y; else bnew=Z; fi
  echo "brand before=$bbefore target=$bnew" >>"$out"
  hubipc set markText "\"$bnew\"" >>"$out" 2>&1
  sleep 1
  bmid=$(sed -n 's/.*"markText": *"\([^"]*\)".*/\1/p' "$brandf" 2>/dev/null | head -1)
  echo "brand staged on disk=$bmid" >>"$out"
  hubipc set markText "\"$bbefore\"" >/dev/null 2>&1
  sleep 1
  bafter=$(sed -n 's/.*"markText": *"\([^"]*\)".*/\1/p' "$brandf" 2>/dev/null | head -1)
  echo "brand restored on disk=$bafter" >>"$out"
  [ "$own" = 1 ] && kill "$(hub_pid)" 2>/dev/null
  if [ "$after" = "$new" ] && [ "$live" = "$new" ] && [ "$bmid" = "$bnew" ] && [ "$bafter" = "$bbefore" ]; then
    record runtime/settings-preview-live PASS -
  else
    record runtime/settings-preview-live FAIL "evidence/$TS/settings-preview.txt"
  fi
}

t_gestures() {
  local out="$EV/gestures.txt" bad=0 opt val
  : >"$out"
  if ! command -v hyprctl >/dev/null 2>&1; then
    record runtime/gestures-enabled UNVERIFIED "no hyprctl"; return
  fi
  # Hyprland 0.51+ removed gestures:workspace_swipe and ..._fingers; the bound
  # gesture is declared with hl.gesture and cannot be introspected at runtime.
  # What is observable is that the session accepted the declaration (no config
  # errors) and that the tuning knobs are explicitly in effect.
  if [ -n "$(hyprctl configerrors 2>/dev/null)" ]; then
    echo "configerrors:" >>"$out"; hyprctl configerrors >>"$out" 2>&1; bad=1
  fi
  for pair in 'gestures:workspace_swipe_distance=300' \
              'gestures:workspace_swipe_cancel_ratio=0.500000' \
              'gestures:workspace_swipe_min_speed_to_force=30' \
              'gestures:workspace_swipe_direction_lock=true' \
              'gestures:workspace_swipe_direction_lock_threshold=10' \
              'gestures:workspace_swipe_create_new=true'; do
    opt=${pair%%=*}; val=${pair#*=}
    line=$(hyprctl getoption "$opt" 2>&1 | tr '\n' ' ')
    printf '%s: %s\n' "$opt" "$line" >>"$out"
    case "$line" in
      *"$val"*) ;;
      *) echo "MISSING $opt expected $val" >>"$out"; bad=1 ;;
    esac
    case "$line" in
      *"set: true"*) ;;
      *) echo "NOT SET $opt (live keyword/eval not applied)" >>"$out"; bad=1 ;;
    esac
  done
  if [ "$bad" = 0 ]; then
    record runtime/gestures-enabled PASS -
  else
    record runtime/gestures-enabled FAIL "evidence/$TS/gestures.txt"
  fi
}

t_scale() {
  local out="$EV/scale.txt" bad=0 names zoom
  : >"$out"
  names=$(hyprctl monitors -j 2>/dev/null | jq -r '.[] | select(.scale != 1) | .name')
  hyprctl monitors -j 2>/dev/null | jq '.[] | {name, scale, width, height}' >>"$out"
  if [ -n "$names" ]; then
    printf 'NOT 1.0: %s\n' "$names" >>"$out"; bad=1
  fi
  zoom=$(hyprctl getoption cursor:zoom_factor 2>&1 | sed -n 's/^float: //p')
  printf 'cursor:zoom_factor=%s\n' "$zoom" >>"$out"
  [ "$zoom" = "1.000000" ] || bad=1
  if [ "$bad" = 0 ]; then
    record runtime/scale-is-1 PASS -
  else
    record runtime/scale-is-1 FAIL "evidence/$TS/scale.txt"
  fi
}

t_icons() {
  local out="$EV/icons.txt" bad=0 p h x f
  : >"$out"
  # The shell runs with HOME/XDG_DATA_HOME/FONTCONFIG_FILE pointed at .run, so
  # ask fontconfig with the shell's own environment, not the caller's.
  p=$(shell_pid)
  if [ -z "$p" ]; then
    record runtime/icons-all-resolve UNVERIFIED "no running shell"; return
  fi
  h=$(tr '\0' '\n' <"/proc/$p/environ" | sed -n 's/^HOME=//p')
  x=$(tr '\0' '\n' <"/proc/$p/environ" | sed -n 's/^XDG_DATA_HOME=//p')
  f=$(tr '\0' '\n' <"/proc/$p/environ" | sed -n 's/^FONTCONFIG_FILE=//p')
  env HOME="$h" XDG_DATA_HOME="$x" FONTCONFIG_FILE="$f" fc-match "Material Symbols Rounded" >>"$out" 2>&1
  if ! env HOME="$h" XDG_DATA_HOME="$x" FONTCONFIG_FILE="$f" \
       fc-match "Material Symbols Rounded" | grep -qi 'Material Symbols'; then
    echo "MISSING Material Symbols Rounded inside shell env" >>"$out"; bad=1
  fi
  if git grep -niE 'Unrealised|Daydream|VIP Rawy|JF Flat|Abberance|Xenophobia|Reckoner|sabana|VEXA' \
       -- 'src/**/*.qml' 'src/**/*.js' 'src/**/*.lua' >>"$out" 2>/dev/null; then
    bad=1
  fi
  [ "$bad" = 0 ] && record runtime/icons-all-resolve PASS - \
                 || record runtime/icons-all-resolve FAIL "evidence/$TS/icons.txt"
}

# The doc contract and the code contract are two halves of one promise: a
# read-only §2 is what made the Hub's compositor controls inert for a whole pass.
t_decisions_live() {
  local out="$EV/decisions.txt"
  : >"$out"
  awk '/^## 2\./,/^## 3\./' docs/DECISIONS.md >"$out" 2>&1
  # the heading itself must be the new contract: the body may quote the old one
  if grep -q 'Live apply' "$out" && grep -q 'tenkai_settings.lua' "$out" \
     && ! grep -q '^## 2\. Settings never writes' "$out"; then
    record static/decisions-md-says-live-apply PASS -
  else
    record static/decisions-md-says-live-apply FAIL "evidence/$TS/decisions.txt"
  fi
}

# install.sh must prove the shell→Hyprland seam by default. The dry run prints
# the step and runs no hyprctl, so this asserts the plan, not the effect.
t_install_wm_bind() {
  local out="$EV/install-wm-bind.txt"
  : >"$out"
  ./install.sh --dry-run >>"$out" 2>&1
  if grep -q 'Hyprland binding' "$out" && grep -q 'prove the shell can drive Hyprland' "$out"; then
    record runtime/install-probes-wm-bind PASS -
  else
    record runtime/install-probes-wm-bind FAIL "evidence/$TS/install-wm-bind.txt"
  fi
}

# shell setSetting(desktop.*) -> tenkai-hub desktop set -> hyprctl eval -> the
# live compositor. Reads the real value first so the test never guesses, and
# restores it through the same path.
t_hypr_live() {
  local out="$EV/hyprd-live.txt" key opt cur want got bad=0
  : >"$out"
  if [ -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" ] || ! command -v hyprctl >/dev/null 2>&1; then
    record runtime/hyprland-live-apply UNVERIFIED "no live Hyprland session"; return
  fi
  if ! need_shell; then
    record runtime/hyprland-live-apply UNVERIFIED "no running shell"; return
  fi
  # key|hyprctl option|kind
  local -a cases=(
    "desktop.appearance.gapsIn|general:gaps_in|int"
    "desktop.appearance.blurEnabled|decoration:blur:enabled|bool"
    "desktop.appearance.blurSpecial|decoration:blur:special|bool"
  )
  local c
  for c in "${cases[@]}"; do
    IFS='|' read -r key opt kind <<<"$c"
    if [ "$kind" = bool ]; then
      cur=$(hyprctl getoption "$opt" 2>/dev/null | sed -n 's/^bool: \(true\|false\).*/\1/p' | head -1)
      [ "$cur" = true ] && want=false || want=true
    else
      cur=$(hyprctl getoption "$opt" 2>/dev/null | sed -n 's/^[a-z ]*: *\([0-9][0-9]*\).*/\1/p' | head -1)
      [ -z "$cur" ] && cur=2
      if [ "$cur" = 9 ]; then want=8; else want=9; fi
    fi
    printf '%s before=%s want=%s\n' "$opt" "${cur:-?}" "$want" >>"$out"
    if [ -z "$cur" ]; then
      echo "  cannot read $opt" >>"$out"; bad=1; continue
    fi
    # JSON on the wire: numbers and booleans keep their type through the IPC
    ipc setSetting "$key" "$want" >>"$out" 2>&1
    sleep 1
    if [ "$kind" = bool ]; then
      got=$(hyprctl getoption "$opt" 2>/dev/null | sed -n 's/^bool: \(true\|false\).*/\1/p' | head -1)
    else
      got=$(hyprctl getoption "$opt" 2>/dev/null | sed -n 's/^[a-z ]*: *\([0-9][0-9]*\).*/\1/p' | head -1)
    fi
    printf '%s live=%s\n' "$opt" "${got:-?}" >>"$out"
    [ "$got" = "$want" ] || bad=1
    ipc setSetting "$key" "$cur" >/dev/null 2>&1
    sleep 1
    if hyprctl getoption "$opt" 2>/dev/null | grep -q "$cur"; then
      echo "  restored $opt=$cur" >>"$out"
    else
      echo "  RESTORE FAILED $opt (wanted $cur)" >>"$out"; bad=1
    fi
  done
  [ "$bad" = 0 ] && record runtime/hyprland-live-apply PASS - \
                 || record runtime/hyprland-live-apply FAIL "evidence/$TS/hyprd-live.txt"
}

echo "Tenkai audit-5 — evidence in tests/evidence/$TS"
t_shell_parse; t_json_parse; t_go_build; t_qml_lint; t_scrub; t_fish_config
t_forbidden_strings; t_ryoku_imports; t_ryoku_namespace; t_doc_links; t_decisions_live
t_bootstrap; t_autostart; t_install_wm_bind
if [ "$STATIC_ONLY" = 0 ]; then
  t_shell_log; t_workspace; t_settings; t_preview; t_hypr_live; t_gestures; t_scale; t_icons; t_boot_chain
fi

printf '\n%-48s %-11s %s\n' TEST RESULT EVIDENCE
printf '%-48s %-11s %s\n' '------------------------------------------------' '-----------' '--------'
for r in "${rows[@]}"; do
  IFS='|' read -r n res ev <<<"$r"
  printf '%-48s %-11s %s\n' "$n" "$res" "$ev"
done
printf '\nFAILURES: %d\n' "$FAILS"
[ "$FAILS" = 0 ]
