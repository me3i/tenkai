#!/usr/bin/env bash
# The checks behind Mei's acceptance gate (the safety, quality and document
# gates). Every one of them can fail: the ones that look at files are proven
# able to fail by ./mei accept --prove.
#
#   usage: accept-safety.sh <gate> [extra-file]
set -uo pipefail
MEI="$(cd "$(dirname "$0")/../.." && pwd)"
RUN="$MEI/.run"
cd "$MEI" || exit 1

gate="${1:-}"
extra="${2:-}"
fail(){ echo "FAIL: $*"; exit 1; }
ok(){ echo "ok: $*"; }

case "$gate" in

s1) # the live session is untouched
  ./mei verify-untouched | tail -2
  [ "${PIPESTATUS[0]}" = 0 ] || fail "verify-untouched failed"
  ok "the live session is untouched"
  ;;

s2) # no personal values in the tracked tree
  ./mei scrub-check || fail "scrub-check failed"
  ok "the tracked tree carries nothing personal"
  ;;

s3) # no Mei process holds the live runtime or the live display
  bash docs/tests/leak-check.sh || fail "the leak check found something"
  ok "nothing of Mei's holds the live runtime or the live display"
  ;;

s4) # no process is ever signalled by name
  # The gate's own files carry the words it looks for (that is the proof it
  # can fail), and a comment may name them; a real call is what is forbidden.
  hits="$(grep -rnE '\b(pkill|killall|pidof)\b' --include='*.sh' --include='mei' \
            --include='*.py' docs mei 2>/dev/null \
            | grep -vE 'docs/tests/accept(-safety)?\.sh:' \
            | grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' | head -5)"
  [ -z "$hits" ] || fail "a script signals a process by name: $hits"
  if [ -n "$extra" ]; then
    grep -qE '\b(pkill|killall|pidof)\b' "$extra" || fail "the proof file was not caught"
    ok "the check catches a file that signals by name"
  fi
  ok "no script signals a process by name"
  ;;

s5) # the guarded input tool refuses the live display
  bash docs/tests/input-guard-selftest.sh || fail "the input guard's self-test failed"
  ok "the input tool is fail-closed"
  ;;

s6) # no outbound connection, no listening socket
  bash docs/tests/picker-outbound.sh || fail "a wallpaper source reaches out"
  # a nested session, and then: no TCP socket of Mei's, and no listener
  ( cd "$MEI" && XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}" WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-1}" ./mei run ) >/dev/null 2>&1
  sleep 12
  pids="$(cat "$RUN/pids" 2>/dev/null | awk '{print $1}' | tr '\n' ' ')"
  tcp=""
  for p in $pids; do
    [ -d "/proc/$p" ] || continue
    tcp="$tcp $(find "/proc/$p/fd" -mindepth 1 -maxdepth 1 -exec readlink {} + 2>/dev/null | grep -c 'socket:' || true)"
  done
  listeners="$(ss -tulnp 2>/dev/null | grep -cE "pid=($(echo $pids | tr ' ' '|'))" || true)"
  ( cd "$MEI" && XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}" WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-1}" ./mei stop ) >/dev/null 2>&1
  [ "${listeners:-0}" = "0" ] || fail "a Mei process listens on a TCP or UDP socket"
  ok "Mei listens on nothing and reaches out to nothing"
  ;;

s7) # a clean stop leaves nothing behind
  ( cd "$MEI" && XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}" WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-1}" ./mei stop ) >/dev/null 2>&1
  sleep 2
  stray="$(pgrep -f "quickshell/shell/shell.qml" 2>/dev/null | head -3)"
  [ -z "$stray" ] || fail "a Mei process is still running: $stray"
  for f in "$RUN"/state/mei/*.lock "$RUN"/pids/*.lock; do
    [ -e "$f" ] && fail "a lock file was left behind: $f"
  done
  ok "the stop left nothing behind"
  ;;

s8) # nothing is written outside the project
  # the nested session's own paths must all be inside the project
  ( cd "$MEI" && XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}" WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-1}" ./mei run ) >/dev/null 2>&1
  sleep 10
  p="$(pgrep -f 'quickshell/shell/shell.qml' | head -1)"
  bad=""
  if [ -n "$p" ] && [ -r "/proc/$p/environ" ]; then
    for v in HOME XDG_CONFIG_HOME XDG_CACHE_HOME XDG_STATE_HOME XDG_DATA_HOME XDG_RUNTIME_DIR; do
      val="$(tr '\0' '\n' < "/proc/$p/environ" | sed -n "s/^$v=//p" | head -1)"
      case "$val" in
      "$MEI"/*|"$MEI") ;;
      *) bad="$bad $v=$val" ;;
      esac
    done
  fi
  ( cd "$MEI" && XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}" WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-1}" ./mei stop ) >/dev/null 2>&1
  [ -z "$bad" ] || fail "the nested session writes outside the project:$bad"
  ok "every path the nested session uses is inside the project"
  ;;

q1) # the code is clean
  find src/ryoku/shell/quickshell -name '*.qml' -print0 2>/dev/null | \
    xargs -0 -n1 -I{} sh -c 'qmllint -I src/ryoku/shell/quickshell/shell "{}" 2>&1 | grep -i "error" | head -3' | head -10
  if find src/ryoku/shell/quickshell -name '*.qml' -print0 2>/dev/null | \
       xargs -0 -n1 -I{} sh -c 'qmllint -I src/ryoku/shell/quickshell/shell "{}" 2>&1 | grep -qi "error"' | grep -q .; then
    fail "qmllint reports errors in the kept QML"
  fi
  ( cd src/ryoku/shell/ipc && GOFLAGS=-mod=vendor GOPROXY=off go vet ./... >/dev/null 2>&1 ) || fail "go vet failed"
  ( cd src/ryoku/shell/ipc && GOFLAGS=-mod=vendor GOPROXY=off go build -o /dev/null ./... >/dev/null 2>&1 ) || fail "go build failed"
  ( cd src/ryoku/shell/ipc && GOFLAGS=-mod=vendor GOPROXY=off go test ./... >"$RUN/logs/accept-go-test.log" 2>&1 ) || fail "go test failed (see $RUN/logs/accept-go-test.log)"
  if command -v shellcheck >/dev/null 2>&1; then
    shellcheck -S warning mei docs/tests/*.sh >"$RUN/logs/accept-shellcheck.log" 2>&1 || fail "shellcheck found something (see $RUN/logs/accept-shellcheck.log)"
    ok "shellcheck is clean"
  else
    echo "note: shellcheck is not installed, so that part of the gate was not run"
  fi
  # R5: no matugen spawn may omit Mei's -c config. The session's .run/bin shim
  # enforces the same rule at runtime (it injects the config and refuses a path
  # outside the project); this is the static half, and it is proved able to fail
  # by handing it a doctored spawn (docs/tests/matugen-calls.sh <file>).
  bash "$MEI/docs/tests/matugen-calls.sh" || fail "a matugen call does not carry Mei's -c config"
  ok "the code is clean"
  ;;

q2) # no dead code, no personal strings, no ryoku names outside the allowed ones
  if [ -n "$extra" ]; then
    grep -qE 'https?://' "$extra" || fail "the proof file was not caught"
    ok "the check catches a file with an outbound URL"
  fi
  # a ryoku-named string outside the places where it belongs.
  # Allowed on purpose: the helper binaries keep their real names
  # (ryoku-cmd-brightness, ryoku-cmd-radio, ryoku-eq, ...); `src/ryoku` is
  # this project's own path; `ryoku-frame` is the layer-shell namespace the
  # live Hyprland layer rules point at, so renaming it would need a config
  # change that is out of bounds.
  stray="$(grep -rn 'ryoku' --include='*.qml' --include='*.go' --include='*.sh' \
             src docs/tests mei 2>/dev/null \
             | grep -vE 'docs/tests/accept-safety\.sh:' \
             | grep -vE 'ryoku[-./]|[/\{]ryoku|\*ryoku\*|ryoku\||Ryoku\.Ui|ryoku\.ui' \
             | head -8)"
  [ -z "$stray" ] || fail "a ryoku-named string is outside the allowed places: $stray"
  # every QML file in the kept set has to be referenced somewhere
  unreferenced=""
  while IFS= read -r f; do
    b="$(basename "$f" .qml)"
    grep -rq "\b$b\b" src/ryoku/shell/quickshell/shell --include='*.qml' 2>/dev/null || unreferenced="$unreferenced $b"
  done < <(find src/ryoku/shell/quickshell/shell -name '*.qml' -not -path '*/services/*' -not -path '*/modules/*' 2>/dev/null)
  [ -z "$unreferenced" ] || fail "a QML file is never referenced:$unreferenced"
  ok "no dead code and no stray names"
  ;;

q5) # the documents are there and say what is true
  for f in docs/MODULES.md docs/LIVE-CHECKLIST.md docs/ROLLBACK.md CHANGES.md CREDITS.md NOTICE UPSTREAM.md; do
    [ -f "$f" ] || fail "the document is missing: $f"
  done
  # Only documents can make an unproven claim: code comments and the
  # vendored READMEs say "lightweight" about other people's software.
  if grep -rni "lightweight" --include='*.md' docs README.md CHANGES.md 2>/dev/null \
       | grep -v "never" | grep -v vendor \
       | head -3 | grep -q .; then
    fail "a document claims to be lightweight without numbers"
  fi
  ok "the documents are there and make no unproven claim"
  ;;

*) echo "unknown gate: $gate"; exit 2 ;;
esac
exit 0
