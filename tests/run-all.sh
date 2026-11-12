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

echo "Tenkai audit-2 — evidence in tests/evidence/$TS"
t_shell_parse; t_json_parse; t_go_build; t_qml_lint; t_scrub
t_forbidden_strings; t_ryoku_imports; t_ryoku_namespace; t_doc_links
t_bootstrap; t_autostart
if [ "$STATIC_ONLY" = 0 ]; then
  t_shell_log; t_workspace; t_settings; t_icons
fi

printf '\n%-48s %-11s %s\n' TEST RESULT EVIDENCE
printf '%-48s %-11s %s\n' '------------------------------------------------' '-----------' '--------'
for r in "${rows[@]}"; do
  IFS='|' read -r n res ev <<<"$r"
  printf '%-48s %-11s %s\n' "$n" "$res" "$ev"
done
printf '\nFAILURES: %d\n' "$FAILS"
[ "$FAILS" = 0 ]
