#!/usr/bin/env bash
# Every test for the components restored in this pass, in one run.
#
#   docs/tests/restored-modules.sh
#
# Each harness starts and stops its own nested session and runs
# verify-untouched itself. The live session is never touched.
set -uo pipefail
TENKAI=$HOME/projects/tenkai
RUN="$TENKAI/.run"
STAMP="$(date +%H%M%S)"
LOG="$RUN/logs/restored-modules-$STAMP.log"
mkdir -p "$RUN/logs"
exec > >(tee -a "$LOG") 2>&1

TESTS=(
  "control-centre matrix|docs/tests/control-center-matrix.sh"
  "power menu|docs/tests/power-menu.sh"
  "osd feed|docs/tests/osd-module.sh"
  "clipboard history|docs/tests/clipboard-module.sh"
  "polkit prompt|docs/tests/polkit-module.sh"
  "screenshot helper|docs/tests/screenshot-module.sh"
  "idle module|docs/tests/idle-module.sh"
  "start and fallback|docs/tests/start-fallback.sh"
  "picker sources|docs/tests/picker-outbound.sh"
)

declare -A RESULT
echo "restored modules: $(date -Is)"
for entry in "${TESTS[@]}"; do
  name="${entry%%|*}"; script="${entry##*|}"
  printf '\n========== %s (%s) ==========\n' "$name" "$script"
  # A test that failed halfway can leave a nested session behind, and the next
  # test's "./tenkai run" would then refuse to start. Every test starts clean.
  ( cd "$TENKAI" && ./tenkai stop ) >/dev/null 2>&1
  ( cd "$TENKAI" && XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}" ./tenkai live-stop ) >/dev/null 2>&1
  # Each sub-test's log lives under the project, like everything else Tenkai
  # writes. It used to go to /tmp/opencode, a directory this project does not
  # own: when it disappeared every sub-test "failed" on the redirect alone.
  sub_log="$RUN/logs/restored-${name// /-}-$STAMP.log"
  if bash "$TENKAI/$script" >"$sub_log" 2>&1; then
    grep -E "TESTED|PASS|FAIL" "$sub_log" | tail -4 | sed 's/^/  /'
    RESULT[$name]="PASS"
  else
    grep -E "TESTED|PASS|FAIL" "$sub_log" | tail -6 | sed 's/^/  /'
    RESULT[$name]="FAIL"
  fi
done
printf '\n========== summary ==========\n'
for entry in "${TESTS[@]}"; do
  name="${entry%%|*}"
  printf '%-24s %s\n' "$name" "${RESULT[$name]:-?}"
done
fail=0
for v in "${RESULT[@]}"; do [ "$v" = "PASS" ] || fail=1; done
echo
[ "$fail" = 0 ] && echo "RESTORED MODULES: PASS" || echo "RESTORED MODULES: FAIL"
echo "log: $LOG"
exit $fail
