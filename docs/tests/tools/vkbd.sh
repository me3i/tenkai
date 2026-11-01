#!/usr/bin/env bash
# vkbd — the nested tests' virtual keyboard.
#
# The harnesses call this as .run/tools/vkbd/vkbd <code>..., the way a keyboard
# reports keys (15 = Tab, 28 = Return, 57 = Space, 30 = A). Each code is
# translated to the libxkbcommon name wtype types, and wtype injects it through
# the virtual-keyboard protocol on the display the caller names.
#
# Every call goes through docs/tests/tools/nested-input.sh, which resolves that
# display to Mei's own nested runtime (.r) and refuses anything else, so this
# can never type into the owner's live session. Called on its own, outside the
# guard, it is inert: wtype has nowhere to send a key.
#
# This file is the source; ./mei links it to .run/tools/vkbd/vkbd at provision
# time (mei_provision_bin), which is the path the harnesses use.
set -uo pipefail

die() { echo "vkbd: $*" >&2; exit 2; }

command -v wtype >/dev/null 2>&1 \
  || die "wtype is not installed; it is how this harness types into the nested session"

# evdev key code -> libxkbcommon keysym name. The codes the harnesses use are
# the point; the rest of the keyboard is here so a new test does not have to
# extend the table before it can type.
keysym() {
  local c="$1"
  case "$c" in
    1) echo Escape ;;
    2|3|4|5|6|7|8|9|10) echo $(( c - 1 )) ;;
    11) echo 0 ;;
    12) echo minus ;; 13) echo equal ;; 14) echo BackSpace ;; 15) echo Tab ;;
    16) echo q ;; 17) echo w ;; 18) echo e ;; 19) echo r ;; 20) echo t ;;
    21) echo y ;; 22) echo u ;; 23) echo i ;; 24) echo o ;; 25) echo p ;;
    26) echo bracketleft ;; 27) echo bracketright ;; 28) echo Return ;;
    29) echo Control_L ;;
    30) echo a ;; 31) echo s ;; 32) echo d ;; 33) echo f ;; 34) echo g ;;
    35) echo h ;; 36) echo j ;; 37) echo k ;; 38) echo l ;;
    39) echo semicolon ;; 40) echo apostrophe ;; 41) echo grave ;;
    42) echo Shift_L ;; 43) echo backslash ;;
    44) echo z ;; 45) echo x ;; 46) echo c ;; 47) echo v ;; 48) echo b ;;
    49) echo n ;; 50) echo m ;;
    51) echo comma ;; 52) echo period ;; 53) echo slash ;; 54) echo Shift_R ;;
    55) echo KP_Multiply ;; 56) echo Alt_L ;; 57) echo space ;; 58) echo Caps_Lock ;;
    59) echo F1 ;; 60) echo F2 ;; 61) echo F3 ;; 62) echo F4 ;; 63) echo F5 ;;
    64) echo F6 ;; 65) echo F7 ;; 66) echo F8 ;; 67) echo F9 ;; 68) echo F10 ;;
    *) return 1 ;;
  esac
}

[ $# -ge 1 ] || die "usage: vkbd <evdev key code>..."

for code in "$@"; do
  name="$(keysym "$code")" || die "unknown key code '$code'"
  wtype -k "$name" || die "wtype could not type '$name' (key code $code)"
done
