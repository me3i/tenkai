#!/usr/bin/env bash
# The nested input guard.
#
# Every synthetic key or pointer event in a nested test goes through this
# script. It refuses to run unless the display it is pointed at is the
# NESTED one:
#
#   - the socket has to resolve inside Mei's own nested runtime directory
#     (.r, the XDG_RUNTIME_DIR the nested session runs under), and
#   - it must not be the live display recorded in the baseline, and it must
#     not live under the live runtime directory.
#
# It prints the resolved socket path, so the log always says where the input
# went. A refusal exits 3 and nothing is sent.
#
# usage: nested-input.sh <tool> [args...]
#        the target display is NESTED_INPUT_DISPLAY, or the caller's
#        WAYLAND_DISPLAY (which is then checked against the live one)
set -uo pipefail
here="$(cd "$(dirname "$0")" && pwd)"
MEI="$(cd "$here/../../.." && pwd)"
NESTED_RT="$MEI/.r"
BASELINE="$MEI/docs/baseline/env.txt"

die(){ echo "nested-input: REFUSED: $*" >&2; exit 3; }

[ $# -ge 1 ] || die "no tool given"
tool="$1"; shift

# The live display, as the baseline recorded it.
live_name="$(sed -n 's/^WAYLAND_DISPLAY=//p' "$BASELINE" 2>/dev/null | head -1)"
live_rt="$(sed -n 's/^XDG_RUNTIME_DIR=//p' "$BASELINE" 2>/dev/null | head -1)"
[ -n "$live_rt" ] || live_rt="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

# The target: the named display, or the caller's, or the nested one.
name="${NESTED_INPUT_DISPLAY:-${WAYLAND_DISPLAY:-}}"
if [ -z "$name" ]; then
  sock="$(ls "$NESTED_RT"/wayland-* 2>/dev/null | head -1)"
  [ -n "$sock" ] || die "no nested display under $NESTED_RT"
  name="$(basename "$sock")"
fi

# Resolve the socket. A plain name is a nested display by definition: the
# nested runtime is the only runtime a nested test may send input to, so the
# live socket cannot be reached by name at all (the live and the nested
# socket carry the same name, and the nested one is the one that is used).
case "$name" in
  /*) sock="$name" ;;
  *)  sock="$NESTED_RT/$name" ;;
esac
echo "nested-input: target display '$name' -> $sock"

case "$sock" in
  "$live_rt"/*) die "that socket is under the live runtime ($sock)" ;;
esac
case "$sock" in
  "$NESTED_RT"/*) ;;
  *) die "that socket is not under the nested runtime ($NESTED_RT)" ;;
esac
[ -e "$sock" ] || die "the socket does not exist ($sock)"

export XDG_RUNTIME_DIR="$NESTED_RT"
export WAYLAND_DISPLAY="$name"
exec "$tool" "$@"
