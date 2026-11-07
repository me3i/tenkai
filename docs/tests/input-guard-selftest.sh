#!/usr/bin/env bash
# The input guard's self-test.
#
# The guard is what stands between a nested test and the owner's live
# session, so it has to be proven able to refuse. Every case here uses a
# stand-in path or a stub tool: nothing connects to a compositor, and the
# live session is never touched.
set -uo pipefail
TENKAI="$(cd "$(dirname "$0")/../.." && pwd)"
GUARD="$TENKAI/docs/tests/tools/nested-input.sh"
RT="$TENKAI/.r"
LIVE_RT="$(sed -n 's/^XDG_RUNTIME_DIR=//p' "$TENKAI/docs/baseline/env.txt" 2>/dev/null | head -1)"
[ -n "$LIVE_RT" ] || LIVE_RT="/run/user/$(id -u)"
LIVE_NAME="$(sed -n 's/^WAYLAND_DISPLAY=//p' "$TENKAI/docs/baseline/env.txt" 2>/dev/null | head -1)"

fail=0
ok(){ echo "TESTED      $*"; }
bad(){ echo "FAIL        $*"; fail=1; }

# A stub tool: it reports the environment it was given and touches nothing.
STUB="$TENKAI/.run/input-guard-stub.sh"
mkdir -p "$TENKAI/.run"
cat > "$STUB" <<'EOF'
#!/usr/bin/env bash
echo "STUB display=$WAYLAND_DISPLAY runtime=$XDG_RUNTIME_DIR"
EOF
chmod +x "$STUB"

# A stand-in nested socket. It is a plain file under the nested runtime: the
# guard only checks the path, and the stub never connects.
mkdir -p "$RT"
: > "$RT/wayland-selftest"

echo "input guard self-test: $(date -Is)"

echo
echo "=== A: a plain display name resolves under the nested runtime ==="
out="$(NESTED_INPUT_DISPLAY="wayland-selftest" "$GUARD" "$STUB" 2>&1)"; rc=$?
case "$rc:$out" in
0:*"-> $RT/wayland-selftest"*) ok "a plain name resolves inside the nested runtime" ;;
*) bad "the guard did not resolve the plain name under the nested runtime (exit $rc): $out" ;;
esac
case "$out" in
*"$LIVE_RT"*) bad "the guard resolved the name to the live runtime: $out" ;;
*) ok "the resolved path is not under the live runtime" ;;
esac

echo
echo "=== B: the live display is refused ==="
out="$(WAYLAND_DISPLAY="$LIVE_RT/$LIVE_NAME" "$GUARD" "$STUB" 2>&1)"; rc=$?
[ "$rc" = 3 ] && ok "the guard refuses the live socket by absolute path (exit 3)" \
  || bad "the guard accepted the live socket by absolute path (exit $rc): $out"
case "$out" in *"live runtime"*) ok "the refusal says why: the live runtime" ;;
*) bad "the refusal does not name the live runtime: $out" ;;
esac
# A stand-in name with no socket behind it must be refused: the guard never
# reaches for a display it cannot prove is the nested one. (A live name with a
# nested socket of the same name is the nested one, and that is right.)
out="$(NESTED_INPUT_DISPLAY="wayland-no-such-display" "$GUARD" "$STUB" 2>&1)"; rc=$?
case "$rc:$out" in
3:*REFUSED*) ok "a display with no nested socket behind it is refused (exit 3)" ;;
*) bad "the guard accepted a display with no nested socket (exit $rc): $out" ;;
esac

echo
echo "=== C: any other socket outside the nested runtime is refused ==="
out="$(NESTED_INPUT_DISPLAY="$TENKAI/.run/wayland-not-nested" "$GUARD" "$STUB" 2>&1)"; rc=$?
[ "$rc" = 3 ] && ok "a socket outside the nested runtime is refused (exit 3)" \
  || bad "the guard accepted a socket outside the nested runtime (exit $rc): $out"

echo
echo "=== D: the nested display is allowed, with the right environment ==="
out="$(NESTED_INPUT_DISPLAY="wayland-selftest" "$GUARD" "$STUB" 2>&1)"; rc=$?
case "$rc:$out" in
0:*"STUB display=wayland-selftest runtime=$RT"*) ok "the guard passes the nested display and runtime to the tool" ;;
*) bad "the guard did not pass the nested display through (exit $rc): $out" ;;
esac
case "$out" in *"-> $RT/wayland-selftest"*) ok "the guard prints the resolved socket path" ;;
*) bad "the guard did not print the resolved socket path: $out" ;;
esac

echo
echo "=== E: nothing was sent to the live session ==="
( cd "$TENKAI" && ./tenkai verify-untouched >/dev/null 2>&1 ) && ok "verify-untouched PASS" \
  || bad "verify-untouched FAILED"
rm -f "$STUB" "$RT/wayland-selftest"

[ "$fail" = 0 ] && echo "INPUT GUARD: PASS" || echo "INPUT GUARD: FAIL"
exit $fail
