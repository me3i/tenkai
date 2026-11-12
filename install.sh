#!/usr/bin/env bash
# install.sh — set Tenkai up on a fresh Arch Linux + Hyprland machine.
#
#   ./install.sh                 check, build, then ask before each system change
#   ./install.sh --yes           answer "yes" to the non-Hyprland prompts too
#   ./install.sh --dry-run       print what would happen, touch nothing
#   ./install.sh --skip-build    only do the system steps (binaries already built)
#   ./install.sh --help
#
# What it does, in order:
#   1. dependency check (pacman list printed, nothing installed)
#   2. build: the three Go daemons, the Tenkai.Blobs C++/QML plugin, and the
#      QML module tree under .run/qml
#   3. systemd user units (tenkai-shell.service, tenkai-hub.service) + daemon-reload
#   4. kitty: include the generated colour file (prompted)
#   5. terminal: this repo's Fish + Starship prompt files (prompted)
#   6. Hyprland configs: deploy the bundled Lua config to ~/.config/hypr
#      (interactive y/N only, *.tenkai-install.bak backups; keyboard.lua is
#      seeded once and never overwritten)
#   7. Hyprland autostart: `tenkai start` as a drop-in the deployed
#      hyprland.lua loads — INTERACTIVE y/N ONLY, never --yes. Runs after 6:
#      an appended hook is lost when the bundled config is reinstalled.
#   8. Hyprland binding: verify tenkai-wm-hyprland runs, probe whether this
#      compositor takes `hyprctl eval` (Lua config) or `hyprctl keyword`, and
#      dispatch one value through the shell's own seam to prove Settings can
#      drive Hyprland. Prompted; --yes-wm-bind answers it.
#   9. wallpapers: copy any bundled images into ~/Pictures/Wallpapers/
#  10. fonts: install the bundled OFL Space Grotesk / Fraunces user-locally,
#      and print the pacman line for the Nerd/Material Symbols fonts
#
# Everything it writes outside this checkout is named and prompted for. It never
# installs packages and never runs sudo; the one Hyprland-config deploy (step 6)
# is interactive y/N only and always writes *.tenkai-install.bak backups first.
#
# Idempotent: a second run rebuilds nothing that is up to date, rewrites no
# identical unit, appends no second autostart line and no second kitty include.
#
# The systemd units and the autostart line are ALTERNATIVES, not both: the units
# start the daemons directly, while `tenkai start` runs Tenkai's own live-session
# script (which starts the same daemons and records their pids). Use one.
#
# The terminal forces colour off when there is no tty or NO_COLOR is set.
set -uo pipefail

TENKAI_DIR="${TENKAI_DIR:-$(cd "$(dirname "$0")" && pwd)}"
RUN="$TENKAI_DIR/.run"
SYS_GO_BIN="$RUN/bin"
QML_ROOT="$RUN/qml/Tenkai"
BLOBS_BUILD="$RUN/build/blobs"
UNIT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
HYPR_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/hypr"
KITTY_CONF="${XDG_CONFIG_HOME:-$HOME/.config}/kitty/kitty.conf"
KITTY_INCLUDE='include ~/.cache/tenkai/kitty-colors.conf'
FISH_CONF="${XDG_CONFIG_HOME:-$HOME/.config}/fish/config.fish"
STARSHIP_CONF="${XDG_CONFIG_HOME:-$HOME/.config}/starship.toml"
TERM_SRC="$TENKAI_DIR/src/tenkai-configs/terminal"
MARK='tenkai-install'
STEP_TOTAL=10

ASSUME_YES=0
DRY_RUN=0
SKIP_BUILD=0
WM_BIND_YES=0

# ── palette ───────────────────────────────────────────────────────────────────
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  R=$'\e[0m'   # reset
  B=$'\e[1m'   # bold
  D=$'\e[2m'   # dim
  WH=$'\e[1;37m'
  GY=$'\e[0;90m'
  GR=$'\e[1;32m'
  MG=$'\e[1;35m'
  YL=$'\e[1;33m'
  RD=$'\e[1;31m'

  # ── two colours, one note: a purple UI under a white mark, gold to close ──
  FRAME_PINK=$'\e[38;5;213m'     # the box outlines only: ╭ ─ ╮ │ ╰ ╯
  UI_PURPLE=$'\e[38;5;141m'      # step headers, small text, arrows, spinners
  BANNER_WHITE=$'\e[1;37m'       # the tagline, step titles and closing lines
  CELESTIAL_GOLD=$'\e[38;5;220m' # success, and the closing line
  # The earlier names stay as aliases, so no call site has to change.
  DEEP_BLUE=$FRAME_PINK          # every frame rule
  SOFT_PURPLE=$UI_PURPLE         # step headers and the turning star
  TWINKLE_CYAN=$UI_PURPLE        # accents, and the shooting star
  RYOKU_ORANGE=$DEEP_BLUE        # banner art, in pink now (the frame colour)
  STAR_WHITE=$BANNER_WHITE       # tagline, step titles, closing lines
  THIN=$DEEP_BLUE
  WH=$STAR_WHITE
  GOLD=$CELESTIAL_GOLD
  CY=$TWINKLE_CYAN               # info arrows (was cyan)
  BL=$SOFT_PURPLE                # suggested commands (was bold blue)
else
  R='' B='' D='' WH='' GY='' CY='' GR='' MG='' BL='' YL='' RD=''
  FRAME_PINK='' UI_PURPLE='' BANNER_WHITE='' CELESTIAL_GOLD=''
  DEEP_BLUE='' SOFT_PURPLE='' STAR_WHITE='' TWINKLE_CYAN='' RYOKU_ORANGE=''
  THIN='' GOLD=''
fi

say()  { printf '%s\n' "$*"; }
dim()  { printf '%s%s%s\n' "$D" "$*" "$R"; }
ok()   { printf '  %s✓%s %s\n' "$GR" "$R" "$*"; }
warn() { printf '  %s⚠%s %s\n' "$YL" "$R" "$*"; }
bad()  { printf '  %s✗%s %s\n' "$RD" "$R" "$*"; }
info() { printf '  %s→%s %s\n' "$CY" "$R" "$*"; }
die()  { printf '\n%s✗ %s%s\n' "$RD" "$*" "$R" >&2; exit 1; }

# ── the night sky ─────────────────────────────────────────────────────────────
# Motion is for eyes only: a real terminal, no NO_COLOR, never a dry run.
# Everywhere else these helpers print nothing and sleep for nothing, so a piped
# log or a CI run sees exactly the same bytes as the unanimated installer.
_motion() { [ -t 1 ] && [ -z "${NO_COLOR:-}" ] && [ "$DRY_RUN" = 0 ]; }

_celestial_glyphs=(✦ ✧ ✶ ✷ ✸ ✹ ✺ ✻)

# The animation loop itself, always started in the background.
# $1 = label, $2 = spin|star. In spin mode one glyph turns, cycling the glyph
# shape each step; in star mode a single star crosses a strip of sky.
_celestial_sky() {
  local label="$1" mode="$2" i=0 j=0 k cells col
  while :; do
    col="$SOFT_PURPLE"
    [ $((i % 2)) -eq 1 ] && col="$TWINKLE_CYAN"
    if [ "$mode" = star ]; then
      cells=''
      for ((k = 0; k < 20; k++)); do
        if [ "$k" -eq $((j % 20)) ]; then cells+="$TWINKLE_CYAN✦$D"; else cells+='·'; fi
      done
      printf '\r  %s%s%s %s ' "$D" "$cells" "$R" "$label"
    else
      printf '\r  %s%s%s %s ' "$col" "${_celestial_glyphs[i]}" "$R" "$label"
    fi
    i=$(( (i + 1) % ${#_celestial_glyphs[@]} ))
    j=$(( j + 1 ))
    sleep 0.12
  done
}

# celestial_spin <label> <spin|star> <shown command> <command...>
# Runs the command with its output captured while a star turns (or shoots) above
# it, then prints that output dimmed beneath the result. The animation is a child
# we start and kill by its recorded PID — never by name — so it cannot leak or
# outlive the command it belongs to. <shown command> is what a dry run prints, so
# the log never exposes the internal helper that does the real work.
celestial_spin() {
  local label="$1" mode="$2" show="$3" log pid rc=0
  shift 3
  printf '  %s$ %s%s\n' "$D" "$show" "$R"
  [ "$DRY_RUN" = 1 ] && return 0
  if ! _motion; then
    "$@" || rc=$?
    return "$rc"
  fi
  log="$(mktemp)"
  _celestial_sky "$label" "$mode" &
  pid=$!
  "$@" >>"$log" 2>&1 || rc=$?
  kill "$pid" 2>/dev/null
  wait "$pid" 2>/dev/null
  printf '\r%*s\r' "$(( ${#label} + 24 ))" ''
  [ -s "$log" ] && sed "s|^|${D}  │ |; s|\$|${R}|" "$log"
  rm -f "$log"
  return "$rc"
}

# A full-width section header: a hairline cyan rule, the count in cyan, the
# title in white. No heavy box — the eye should land on the icons underneath.
step() {
  local n="$1" title="$2"
  local cnt sep text inner_w=58 pad rule
  rule="$(printf '─%.0s' $(seq 1 $inner_w))"
  cnt=" STEP $n/$STEP_TOTAL "
  sep="· "
  text="$cnt$sep$title"
  pad=$(( inner_w - ${#text} ))
  [ "$pad" -lt 0 ] && pad=0
  printf '\n%s╭%s╮%s\n' "$THIN" "$rule" "$R"
  printf '%s│%s%s%s%s%s%s%*s%s│%s\n' \
    "$THIN" "$SOFT_PURPLE" "$cnt" "$GY" "$sep" "$WH" "$title" "$pad" "" "$THIN" "$R"
  printf '%s╰%s╯%s\n' "$THIN" "$rule" "$R"
}

# The banner: a six-row hanko seal (天 / 界 stacked inside a double rule) joined
# to the ANSI-shadow TENKAI block art by a hairline divider. Six rows tall on
# both sides, 56 columns wide, so it centres with one column of air each side
# inside the 58-column installer frame. Keep every row exactly 56 columns.
BANNER_W=56
BANNER_ROWS=(
  '╔════╗ │  ████████╗███████╗███╗   ██╗██╗  ██╗ █████╗ ██╗'
  '║    ║ │  ╚══██╔══╝██╔════╝████╗  ██║██║ ██╔╝██╔══██╗██║'
  '║ 天 ║ │     ██║   █████╗  ██╔██╗ ██║█████╔╝ ███████║██║'
  '║ 界 ║ │     ██║   ██╔══╝  ██║╚██╗██║██╔═██╗ ██╔══██║██║'
  '║    ║ │     ██║   ███████╗██║ ╚████║██║  ██╗██║  ██║██║'
  '╚════╝ │     ╚═╝   ╚══════╝╚═╝  ╚═══╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝'
)
TAGLINE='The Celestial Lite version of Ryoku Quickshell'

# The opened and closed gate of the installer.
print_banner() {
  local row
  printf '\n%s' "$RYOKU_ORANGE$B"
  for row in "${BANNER_ROWS[@]}"; do printf ' %s\n' "$row"; done
  printf '%s' "$R"
  printf '%s      %s%s\n' "$GY" "$TAGLINE" "$R"
  printf '%s   checkout:%s %s\n' "$GY" "$R" "$TENKAI_DIR"
  printf '\n'
}

# One framed content line inside the success banner. $1 = leading spaces,
# $2 = content (may carry ANSI), $3 = *visible* width of the content.
fl() {
  local lead="$1" content="$2" width="$3"
  printf '%s│%*s%s%*s%s│%s\n' "$THIN" "$lead" "" "$content" "$((58 - lead - width))" "" "$THIN" "$R"
}

# A breath of sky before the closing frame: four stars brighten and fade, then
# the box lands. Well under a second, and silent anywhere but a terminal.
_celestial_twinkle() {
  local i
  _motion || return 0
  printf '\n'
  for i in 1 2 3 4; do
    if [ $((i % 2)) -eq 0 ]; then
      printf '\r%s   ·   ✦   ·   %s✧%s   ·   ✦   ·   ✧   %s' \
        "$D" "$TWINKLE_CYAN" "$R" "$D"
    else
      printf '\r%s   ✦   ·   ✧   %s✦%s   ·   ✧   ·   ✦   %s' \
        "$D" "$SOFT_PURPLE" "$R" "$D"
    fi
    sleep 0.15
  done
  printf '\r%*s\r' 48 ''
}

print_success() {
  local W=58 row rule c
  rule="$(printf '─%.0s' $(seq 1 $W))"
  _celestial_twinkle
  printf '\n%s╭%s╮%s\n' "$THIN" "$rule" "$R"
  fl 0 "" 0
  for row in "${BANNER_ROWS[@]}"; do fl 1 "${RYOKU_ORANGE}${B}${row}${R}" "$BANNER_W"; done
  fl 0 "" 0
  fl 6 "${WH}${TAGLINE}${R}" 46
  fl 0 "" 0
  # The closing line arrives: purple, twice, then it settles on gold.
  if _motion; then
    for c in "$TWINKLE_CYAN" "$SOFT_PURPLE" "$CELESTIAL_GOLD"; do
      fl 14 "${c}${B}Tenkai is installed and ready.${R}" 30
      if [ "$c" != "$CELESTIAL_GOLD" ]; then
        printf '\033[1A\r'
        sleep 0.18
      fi
    done
  else
    fl 14 "${CELESTIAL_GOLD}${B}Tenkai is installed and ready.${R}" 30
  fi
  fl 0 "" 0
  fl 9 "${WH}Log out and log back in -- your desktop${R}" 39
  fl 21 "${WH}will be Tenkai.${R}" 15
  fl 0 "" 0
  printf '%s╰%s╯%s\n' "$THIN" "$rule" "$R"
  printf '\n'
}

# run <command...>: show it, then run it unless this is a dry run. In a dry run
# the whole "would have" line is the output, so nothing can be half-applied.
run() {
  printf '  %s$ %s%s\n' "$D" "$*" "$R"
  [ "$DRY_RUN" = 1 ] && return 0
  "$@"
}

# confirm <question>: a real interactive y/N, defaulting to no. Returns 1 (skip)
# when there is no terminal, so a piped or cron run can never answer for itself.
confirm() {
  local reply=''
  if [ "$DRY_RUN" = 1 ]; then
    say "  (dry run: would ask \"$1\")"
    return 1
  fi
  if [ ! -t 0 ]; then
    say "  (no terminal: skipped \"$1\" — run it by hand if you want it)"
    return 1
  fi
  read -r -p "  $1 [y/N] " reply || reply=''
  case "$reply" in [yY] | [yY][eE][sS]) return 0 ;; *) return 1 ;; esac
}

# confirm_yes <question>: same, but --yes answers it. Used for the systemd units
# and the kitty include (idempotent, outside-config writes). NEVER used for the
# Hyprland autostart line: that one needs a human even under --yes.
confirm_yes() {
  if [ "$ASSUME_YES" = 1 ]; then
    say "  --yes: $1"
    return 0
  fi
  confirm "$1"
}

usage() {
  cat <<'USAGE'
install.sh — set Tenkai up on a fresh Arch Linux + Hyprland machine.

  ./install.sh                 check, build, then ask before each system change
  ./install.sh --yes           answer "yes" to the non-Hyprland prompts too
  ./install.sh --dry-run       print what would happen, touch nothing
  ./install.sh --skip-build    only do the system steps (binaries already built)
  ./install.sh --yes-wm-bind   answer yes to step 8 (prove shell → Hyprland)
  ./install.sh --help          this text

In order: dependencies, build, systemd user units, the kitty colour include, the
Fish + Starship terminal files, the bundled Hyprland Lua config, Hyprland
autostart, wallpapers, and the bundled fonts. Nothing is installed and no sudo
is run; every write outside this checkout is named and prompted for. The
Hyprland-config deploy and the Hyprland autostart are INTERACTIVE y/N only —
--yes does not answer them. Second runs are safe.
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    -y | --yes) ASSUME_YES=1 ;;
    --dry-run) DRY_RUN=1 ;;
    --skip-build) SKIP_BUILD=1 ;;
    --yes-wm-bind) WM_BIND_YES=1 ;;
    -h | --help) usage; exit 0 ;;
    *) die "unknown argument: $1 (try --help)" ;;
  esac
  shift
done

[ -f "$TENKAI_DIR/tenkai" ] || die "no ./tenkai beside this script — run install.sh from the checkout"
[ -n "${TENKAI_TEST:-}" ] && die "TENKAI_TEST is set: this is a nested test session, not an install"
[ "$(id -u)" = 0 ] && die "do not run this as root: it builds and installs into your own account"

print_banner
if [ "$DRY_RUN" = 1 ]; then
  info "dry run — nothing will be written, every prompt is shown as skipped"
  say ""
fi

# ── 1. dependencies ───────────────────────────────────────────────────────────

step 1 "dependencies"

# Checked BEFORE building, and never installed here: the exact pacman line is
# printed and the run stops, so an install is always an explicit act.
MISSING_PKGS=()
check_pkg() { # $1 = package, $2 = command that proves it
  if command -v "$2" >/dev/null 2>&1; then
    ok "$1 ($2)"
  else
    bad "$1 — $2 not found"
    MISSING_PKGS+=("$1")
  fi
}

check_pkg quickshell qs
check_pkg hyprland Hyprland
check_pkg go go
check_pkg cmake cmake
check_pkg matugen matugen
check_pkg kitty kitty
# Audio is driven through `wpctl` (src/tenkai_core/shell/ipc/control.go:81), which ships
# with wireplumber; pipewire comes in with it. `pw-cli` was checked here but is
# never called by the shell.
check_pkg wireplumber wpctl
check_pkg networkmanager nmcli
# Keep-list features that shell out at runtime: the brightness steps and the
# battery readout (modules/bar/BrightnessControl.qml, barstyles/qsbar/TenkaiPower.js).
check_pkg brightnessctl brightnessctl
check_pkg upower upower
# The terminal: Tenkai ships the owner's own Fish config and Starship preset, and
# step 6 installs them, so both are dependencies of a complete install.
check_pkg fish fish
check_pkg starship starship

# The rest is not in the required list, but a build or a running shell needs it.
BUILD_MISSING=()
check_build() { # $1 = package, $2 = command
  if command -v "$2" >/dev/null 2>&1; then
    ok "$1 ($2)"
  else
    bad "$1 — $2 not found"
    BUILD_MISSING+=("$1")
  fi
}
check_build qt6-declarative qmake6
check_build ninja ninja
check_build gcc c++
check_build python3 python3
check_build jq jq
check_build grim grim
check_build slurp slurp
check_build wl-clipboard wl-copy

if [ "${#MISSING_PKGS[@]}" -gt 0 ]; then
  say ""
  say "  Install the required packages, then run this again:"
  say ""
  say "  ${BL}sudo pacman -S --needed ${MISSING_PKGS[*]}${R}"
  die "${#MISSING_PKGS[@]} required package(s) missing"
fi

if [ "${#BUILD_MISSING[@]}" -gt 0 ]; then
  say ""
  say "  Not on the required list, but needed to build or run Tenkai. If the build"
  say "  fails below, this is the line:"
  say ""
  say "  ${BL}sudo pacman -S --needed ${BUILD_MISSING[*]}${R}"
  say ""
fi

# ── 2. build ──────────────────────────────────────────────────────────────────

step 2 "build"

if [ "$SKIP_BUILD" = 1 ]; then
  say "  ${GY}--skip-build: not building${R}"
else
  mkdir -p "$SYS_GO_BIN" "$QML_ROOT" "$RUN/go"

  # Project-local Go state, vendored deps, no toolchain download, no CGO: the
  # same environment the project pins for a reproducible build.
  export GOTOOLCHAIN=local
  export GOFLAGS=-mod=vendor
  export GOPATH="$RUN/go"
  export GOCACHE="$RUN/go/cache"
  export CGO_ENABLED=0

  # The build runs inside the spinner's child, so the star turns for exactly as
  # long as the compiler does.
  _go_build_one() { ( cd "$1" && nice -n 10 go build -trimpath -p 2 -o "$2" ./ ); }

  go_build() { # $1 = source dir, $2 = output name
    local src="$TENKAI_DIR/src/tenkai_core/$1" out="$SYS_GO_BIN/$2"
    [ -d "$src" ] || die "missing source dir: $src"
    celestial_spin "building $2" spin \
      "cd ${src#$TENKAI_DIR/} && nice -n 10 go build -trimpath -p 2 -o $out ./" \
      _go_build_one "$src" "$out" \
      || die "go build failed in $src"
    [ -x "$out" ] || die "$2 was not produced"
    ok "$out"
  }

  go_build shell/ipc tenkai-shell
  go_build hub/backend tenkai-hub
  # The Hyprland window-manager provider: the neutral binds, window rules and
  # output layout the Hub and the shell delegate to. Written by the Settings
  # GUI, so it has to exist before the first open.
  go_build wm/hyprland tenkai-wm-hyprland
  # The wallpaper daemon shares the session with the shell; without it the
  # wallpaper module has nothing to talk to.
  go_build shell/ryogami/daemon ryogami

  # Tenkai.Blobs — the SDF metaball plugin behind the frame. Prebuilt upstream
  # because a target machine has no toolchain; here we do have one.
  [ -d "$TENKAI_DIR/src/tenkai_core/shell/plugin" ] || die "missing src/tenkai_core/shell/plugin"
  CMAKE_GEN=()
  command -v ninja >/dev/null 2>&1 && CMAKE_GEN=(-G Ninja)
  celestial_spin "configuring Tenkai.Blobs" spin \
    "cmake -S src/tenkai_core/shell/plugin -B .run/build/blobs ${CMAKE_GEN[*]} -DCMAKE_BUILD_TYPE=Release" \
    cmake -S "$TENKAI_DIR/src/tenkai_core/shell/plugin" -B "$BLOBS_BUILD" \
      "${CMAKE_GEN[@]}" -DCMAKE_BUILD_TYPE=Release \
    || { rm -rf "$BLOBS_BUILD"; die "cmake configure failed — a build dir left by a failed run is cleared here; install ninja, gcc and Qt6 Quick/ShaderTools/Multimedia, then run this again"; }
  # The long one: a comet crosses the sky while the SDF plugin compiles.
  celestial_spin "building Tenkai.Blobs" star "nice -n 10 cmake --build .run/build/blobs -j2" \
    nice -n 10 cmake --build "$BLOBS_BUILD" -j2 \
    || die "cmake build failed"
  # A dry run configures/builds nothing; only a real run may assert the artifact.
  if [ "$DRY_RUN" = 0 ]; then
    [ -d "$BLOBS_BUILD/qml/Tenkai/Blobs" ] || die "the Blobs module was not produced"
  fi

  # One QML import path for the whole tree. `cp -a src/. dst/` overwrites in
  # place, so a second run refreshes the modules without nesting a copy.
  sync_dir() { # $1 = source, $2 = destination
    if [ ! -d "$1" ]; then
      # A dry run builds nothing, so build artifacts are absent by definition.
      [ "$DRY_RUN" = 1 ] && { say "  (dry run: would copy $1/. -> $2/)"; return 0; }
      die "missing QML module source: $1"
    fi
    mkdir -p "$2"
    run cp -a "$1/." "$2/"
  }
  sync_dir "$TENKAI_DIR/src/tenkai_core/ui" "$QML_ROOT/Ui"
  sync_dir "$TENKAI_DIR/src/tenkai_core/shell/framebars" "$QML_ROOT/FrameBars"
  sync_dir "$TENKAI_DIR/src/tenkai_core/shell/quickshell/plugins/kit" "$QML_ROOT/PluginKit"
  sync_dir "$TENKAI_DIR/src/tenkai_core/wm/hyprland/qml" "$QML_ROOT/Wm/Hyprland"
  sync_dir "$BLOBS_BUILD/qml/Tenkai/Blobs" "$QML_ROOT/Blobs"

  # The wallpaper picker (ryogami's wall-ui), bundled so the daemon never reads
  # the distro's /usr/share/ryogami. It lives beside the binary, not under
  # .run/qml, because the daemon hands this directory to the picker as
  # RYOGAMI_WALL_INSTALL and the picker resolves its scripts from that root.
  WALL_UI_SRC="$TENKAI_DIR/src/tenkai_core/shell/ryogami/wall-ui"
  WALL_UI_DST="$RUN/ryogami-wall-ui"
  sync_dir "$WALL_UI_SRC" "$WALL_UI_DST"
  [ -d "$WALL_UI_SRC/data/scripts" ] && sync_dir "$WALL_UI_SRC/data/scripts" "$WALL_UI_DST/scripts"
  [ -f "$WALL_UI_DST/shell.qml" ] || [ "$DRY_RUN" = 1 ] || die "the wall-ui entry point is missing at $WALL_UI_DST/shell.qml"

  ok "QML modules under $QML_ROOT (Ui, FrameBars, PluginKit, Wm/Hyprland, Blobs)"
  ok "wallpaper picker under $WALL_UI_DST"
fi

# A dry run builds nothing, so it must not fail these two (that is the point of
# printing them). A real run stops here rather than installing an empty tree.
if [ "$DRY_RUN" = 0 ]; then
  [ -x "$SYS_GO_BIN/tenkai-shell" ] || die "tenkai-shell is not built at $SYS_GO_BIN/tenkai-shell"
  [ -d "$QML_ROOT/Ui" ] || die "the QML modules are not assembled under $QML_ROOT"
  [ -f "$RUN/ryogami-wall-ui/shell.qml" ] || die "the bundled wallpaper picker is missing at $RUN/ryogami-wall-ui/shell.qml"
fi

# ── 3. systemd user units ────────────────────────────────────────────────────

step 3 "systemd user units"

# Both units are ALTERNATIVES to the autostart line in step 4 — they start the
# daemons themselves. Nothing is enabled here; enabling is your call, because
# `graphical-session.target` also decides what an autostart line would duplicate.
write_unit() { # $1 = file name, stdin = content
  local name="$1" tmp content changed=0
  tmp="$(mktemp)"
  cat > "$tmp"
  content="$(cat "$tmp")"
  if [ -f "$UNIT_DIR/$name" ] && cmp -s "$tmp" "$UNIT_DIR/$name"; then
    ok "$name unchanged"
  else
    say "  would write $UNIT_DIR/$name"
    # Dim the file body: it is reference material, not the point of the run.
    printf '%s\n' "$content" | sed "s|^|${D}    │ |; s|\$|${R}|"
    if [ "$DRY_RUN" = 1 ]; then
      ok "$name (dry run)"
    elif confirm_yes "write $UNIT_DIR/$name?"; then
      mkdir -p "$UNIT_DIR"
      install -m 0644 "$tmp" "$UNIT_DIR/$name"
      changed=1
      ok "$name written"
    else
      warn "$name not written"
    fi
  fi
  rm -f "$tmp"
  [ "$changed" = 1 ] && UNIT_CHANGED=1
  return 0
}

UNIT_CHANGED=0
write_unit tenkai-shell.service <<UNIT
[Unit]
# Tenkai's shell daemon: the bar, the launcher, the OSD, notifications, the tray,
# the clipboard watcher and every other surface. Supervised here as an
# alternative to the Hyprland autostart line — use one, never both.
Description=Tenkai shell daemon
PartOf=graphical-session.target
After=graphical-session.target
ConditionEnvironment=WAYLAND_DISPLAY
StartLimitIntervalSec=60
StartLimitBurst=5

[Service]
Type=simple
WorkingDirectory=$TENKAI_DIR
ExecStart=$SYS_GO_BIN/tenkai-shell daemon
Restart=always
RestartSec=2
# Kill only the daemon, not its cgroup: apps launched from the shell outlive a
# shell reload.
KillMode=process
Slice=session.slice

[Install]
WantedBy=graphical-session.target
UNIT

write_unit tenkai-hub.service <<UNIT
[Unit]
# tenkai-hub is a command-line backend, not a daemon: the shell starts it on demand
# for Settings saves. This unit only re-applies the persisted runtime overrides
# (displays, keybinds, advanced window options) once the session is up, which is
# useful if you run the daemons through systemd instead of \`tenkai start\`.
Description=Tenkai settings backend: re-apply the runtime overrides at session start
After=graphical-session.target tenkai-shell.service
PartOf=graphical-session.target
ConditionEnvironment=WAYLAND_DISPLAY

[Service]
Type=oneshot
WorkingDirectory=$TENKAI_DIR
ExecStart=$SYS_GO_BIN/tenkai-hub overrides apply

[Install]
WantedBy=graphical-session.target
UNIT

if [ "$UNIT_CHANGED" = 1 ]; then
  run systemctl --user daemon-reload || warn "daemon-reload failed; run it yourself"
else
  say "  units are up to date; no daemon-reload needed"
fi
say ""
say "  ${GY}Not enabled on purpose. To use the units instead of the autostart line:${R}"
say "    ${BL}systemctl --user enable --now tenkai-shell.service tenkai-hub.service${R}"

# ── 4. kitty colours ────────────────────────────────────────────────────────

step 4 "kitty colours"

# Tenkai's palette pass writes ~/.cache/tenkai/kitty-colors.conf; kitty only reads it
# if its own config includes it. Tenkai never writes ~/.config/kitty itself.
if [ ! -f "$KITTY_CONF" ]; then
  warn "no $KITTY_CONF — kitty is not configured for this user"
  say "  create it with:"
  say "    ${BL}mkdir -p ${KITTY_CONF%/*} && printf '%s\\n' '$KITTY_INCLUDE' >> $KITTY_CONF${R}"
elif grep -qF "$KITTY_INCLUDE" "$KITTY_CONF"; then
  ok "$KITTY_CONF already includes the Tenkai colour file"
else
  say "  add:  $KITTY_INCLUDE"
  if confirm_yes "append that include to $KITTY_CONF (a backup is written first)?"; then
    cp -a "$KITTY_CONF" "$KITTY_CONF.$MARK.bak"
    {
      printf '\n# %s: Tenkai (matugen) colour file\n' "$MARK"
      printf '%s\n' "$KITTY_INCLUDE"
    } >> "$KITTY_CONF"
    ok "appended to $KITTY_CONF (backup: $KITTY_CONF.$MARK.bak)"
  else
    say "  or by hand:"
    say "    printf '%s\\n' '$KITTY_INCLUDE' >> $KITTY_CONF"
  fi
fi
say ""
info "The file itself appears the first time Tenkai runs a palette pass."
info "Kitty re-reads its config on SIGUSR1: ${BL}pkill -USR1 -x kitty${R}"

# ── 5. terminal: full environment (kitty + fish + starship + fastfetch) ─────

step 5 "terminal (kitty, fish, starship, fastfetch)"

# Tenkai ships the owner's exact terminal environment: kitty style/conf (opacity,
# padding, fonts), Fish behaviour (config + conf.d + functions), the Starship
# prompt preset, and the Fastfetch look-and-feel. Everything is copied whole and
# never merged into an existing file: the target is backed up first, and an
# identical file is left alone, so a second run changes nothing.
copy_config() { # $1 = file in this checkout, $2 = destination
  local src="$1" dst="$2"
  if [ ! -f "$src" ]; then
    warn "no ${src#$TENKAI_DIR/} in this checkout; skipped"
    return 0
  fi
  if [ -f "$dst" ] && cmp -s "$src" "$dst"; then
    ok "$dst already matches"
    return 0
  fi
  if [ -f "$dst" ]; then
    say "  $dst differs from the bundled copy"
  else
    say "  $dst does not exist yet"
  fi
  if ! confirm_yes "install $dst from the checkout?"; then
    warn "$dst not touched"
    return 0
  fi
  mkdir -p "$(dirname "$dst")"
  [ -f "$dst" ] && cp -a "$dst" "$dst.$MARK.bak"
  if [ "$DRY_RUN" = 1 ]; then
    ok "$dst (dry run)"
    return 0
  fi
  install -m 0644 "$src" "$dst"
  ok "$dst written${backup:+ (backup: $backup)}"
  return 0
}

# --- kitty: style + theme + user config, plus the generated palette include ---
copy_config "$TERM_SRC/kitty/kitty.conf" "$KITTY_CONF"
copy_config "$TERM_SRC/kitty/current-font.conf" "$HOME/.config/kitty/current-font.conf"
copy_config "$TERM_SRC/kitty/current-theme.conf" "$HOME/.config/kitty/current-theme.conf"
copy_config "$TERM_SRC/kitty/user.conf" "$HOME/.config/kitty/user.conf"

# The generated palette (from `./tenkai colours`) is read by kitty only if its
# config includes it. Tenkai never writes ~/.config/kitty itself; one idempotent
# include line is appended here (idempotent via grep) — prompted, and the
# target is backed up to *.tenkai-install.bak first. Skipped entirely on a dry run.
if [ "$DRY_RUN" = 0 ] && [ -f "$KITTY_CONF" ] && ! grep -qsF "include ~/.cache/tenkai/kitty-colors.conf" "$KITTY_CONF"; then
  if [ -f "$HOME/.cache/tenkai/kitty-colors.conf" ]; then
    if confirm_yes "append the palette include to $KITTY_CONF (a backup is written first)?"; then
      cp -a "$KITTY_CONF" "$KITTY_CONF.$MARK.bak"
      printf '%s\n' 'include ~/.cache/tenkai/kitty-colors.conf' >> "$KITTY_CONF"
      ok "palette include appended"
    else
      warn "palette include not added"
    fi
  else
    warn "$HOME/.cache/tenkai/kitty-colors.conf missing; palette include not added"
  fi
fi

# --- fish: config + conf.d (no functions bundle shipped yet) ---
copy_config "$TERM_SRC/fish/config.fish" "$FISH_CONF"
if [ -d "$TERM_SRC/fish/conf.d" ]; then
  for confd in "$TERM_SRC/fish/conf.d"/*; do
    [ -f "$confd" ] || continue
    copy_config "$confd" "$HOME/.config/fish/conf.d/$(basename "$confd")"
  done
fi

# --- starship prompt preset ---
copy_config "$TERM_SRC/starship.toml" "$STARSHIP_CONF"

# --- fastfetch: look-and-feel + assets ---
# Copied file-by-file with the same rules as everything else: identical files
# are left alone, differing/missing files are listed and installed only after a
# yes, and existing targets are backed up to *.tenkai-install.bak first. A dry run
# writes nothing.
if [ -d "$TERM_SRC/fastfetch/fastfetch" ]; then
  FF_DEST="$HOME/.config/fastfetch"
  FF_PLAN=()
  while IFS= read -r -d '' src; do
    base="$(basename "$src")"
    if [ -f "$FF_DEST/$base" ] && cmp -s "$src" "$FF_DEST/$base"; then
      continue
    fi
    FF_PLAN+=("$base")
  done < <(find "$TERM_SRC/fastfetch/fastfetch" -maxdepth 1 -type f -print0)
  if [ "${#FF_PLAN[@]}" -eq 0 ]; then
    ok "fastfetch files already in place"
  else
    for base in "${FF_PLAN[@]}"; do
      if [ -f "$FF_DEST/$base" ]; then
        say "  $FF_DEST/$base differs from the bundled copy"
      else
        say "  $FF_DEST/$base does not exist yet"
      fi
    done
    if [ "$DRY_RUN" = 1 ]; then
      say "  (dry run: nothing written)"
    elif confirm_yes "install ${#FF_PLAN[@]} fastfetch file(s) into $FF_DEST?"; then
      mkdir -p "$FF_DEST"
      for base in "${FF_PLAN[@]}"; do
        if [ -f "$FF_DEST/$base" ]; then
          cp -a "$FF_DEST/$base" "$FF_DEST/$base.$MARK.bak"
        fi
        install -m 0644 "$TERM_SRC/fastfetch/fastfetch/$base" "$FF_DEST/$base"
      done
      ok "fastfetch files deployed"
    else
      warn "fastfetch files not touched"
    fi
  fi
else
  warn "no fastfetch bundle in this checkout"
fi

# Report what was installed.
if [ -f "$FISH_CONF" ] && ! grep -qsF 'starship init fish' "$FISH_CONF"; then
  warn "$FISH_CONF does not call starship; the prompt will be plain fish"
fi
if [ "$(getent passwd "$(id -un)" | cut -d: -f7)" != "$(command -v fish 2>/dev/null)" ]; then
  say "  ${GY}fish is installed but is not your login shell. To use it:${R}"
  say "    ${BL}chsh -s $(command -v fish)${R}"
fi

# ── 6. Hyprland configs ─────────────────────────────────────────────────────

step 6 "Hyprland configs (Lua)"

# Tenkai ships the owner's Hyprland Lua config so a fresh install is not stuck
# with Hyprland defaults. Files are copied whole, never merged; existing
# targets are backed up to <name>.tenkai-install.bak before being overwritten.
# This step is INTERACTIVE y/N only (never --yes, never a piped answer) —
# overwriting a live ~/.config/hypr is a human decision. Nothing is deleted;
# files only in your checkout stay exactly where they are.
#
# keyboard.lua is the exception: it is user-owned, seeded once, and never
# overwritten by an install (mirrors how hyprland.lua treats it).
#
# The bundled configs try ~/.config/tenkai (and ~/.cache/tenkai) first and fall back
# to the legacy ~/.config/ryoku / ~/.cache/ryoku paths, so they work both on a
# pure Tenkai install and on a hybrid box with stock Ryoku still present.
HYPR_SRC="$TENKAI_DIR/src/tenkai-configs/hypr"
HYPR_DEST="$HYPR_DIR"

deploy_hypr() {
  if [ ! -d "$HYPR_SRC" ]; then
    warn "no bundled hypr configs at $HYPR_SRC; skipped"
    return 0
  fi
  local src rel dst
  local -a plan=() new=() over=()
  while IFS= read -r -d '' src; do
    rel="${src#"$HYPR_SRC"/}"
    dst="$HYPR_DEST/$rel"
    if [ "$rel" = "keyboard.lua" ] && [ -f "$dst" ]; then
      say "  keep  $dst (user-owned, seeded once — not overwritten)"
      continue
    fi
    # identical content AND, for a script, a working exec bit: an earlier
    # 0644 deploy is re-installed rather than left inert.
    if [ -f "$dst" ] && cmp -s "$src" "$dst" && { [ ! -x "$src" ] || [ -x "$dst" ]; }; then
      continue
    fi
    plan+=("$rel")
    if [ -f "$dst" ]; then over+=("$rel"); else new+=("$rel"); fi
  done < <(find "$HYPR_SRC" -type f -print0)

  if [ "${#plan[@]}" -eq 0 ]; then
    ok "all bundled hypr files already in place"
    return 0
  fi
  say "  would install ${#plan[@]} bundled file(s) into $HYPR_DEST:"
  for rel in "${new[@]}";  do say "    ${GR}new${R}        $rel"; done
  for rel in "${over[@]}"; do say "    ${YL}overwrite${R}  $rel  (backup: $rel.$MARK.bak)"; done
  if [ "$DRY_RUN" = 1 ]; then
    say "  (dry run: nothing written)"
    return 0
  fi
  if ! confirm "install/overwrite these ${#plan[@]} file(s) under $HYPR_DEST?"; then
    warn "hypr configs not installed — your existing config is untouched"
    return 0
  fi
  for rel in "${plan[@]}"; do
    dst="$HYPR_DEST/$rel"
    mkdir -p "$(dirname "$dst")"
    if [ -f "$dst" ]; then
      cp -a "$dst" "$dst.$MARK.bak"
    fi
    # scripts/ carries the helpers the bundled binds exec, so the exec bit is
    # part of the file being installed (a 0644 script is a bind that fails).
    mode=0644
    [ -x "$HYPR_SRC/$rel" ] && mode=0755
    install -m "$mode" "$HYPR_SRC/$rel" "$dst"
  done
  ok "hypr configs installed (${#plan[@]} files; backups are *.$MARK.bak)"
}
deploy_hypr

# The generated compositor-settings drop-in (docs/DECISIONS.md §2) is written by
# tenkai-hub on Save. A fresh install gets the empty shipped copy so the file
# hyprland.lua optional()s exists; an existing one is never overwritten, or an
# install would wipe the session's saved settings.
DROPIN_SRC="$TENKAI_DIR/src/tenkai-configs/hypr-dropins/tenkai_settings.lua"
DROPIN_DST="$HYPR_DIR/tenkai_settings.lua"
if [ -f "$DROPIN_DST" ]; then
  say "  keep  $DROPIN_DST (generated by Settings; not overwritten)"
elif [ -f "$DROPIN_SRC" ]; then
  if [ "$DRY_RUN" = 1 ]; then
    say "  (dry run: would seed $DROPIN_DST)"
  else
    run mkdir -p "$HYPR_DIR"
    install -m 0644 "$DROPIN_SRC" "$DROPIN_DST"
    ok "seeded $DROPIN_DST (Settings rewrites it on Save)"
  fi
fi

# --- keybind helpers: the tenkai-* scripts the bundled binds exec --------------
#
# modules/binds.lua execs these by bare name, and modules/env.lua puts
# ~/.local/bin first, so a link there is what makes the key work on a machine
# that has never had an upstream install. Linked, not copied: the checkout stays the
# single source. A name that already exists is never overwritten — it is
# reported and left alone, because a stock upstream install has its own copy.
LOCAL_BIN="$HOME/.local/bin"
HELPER_SRC=(
  "$TENKAI_DIR/src/tenkai_core/shell/scripts/tenkai-app"
  "$TENKAI_DIR/src/tenkai_core/shell/scripts/tenkai-summon"
  "$TENKAI_DIR/src/tenkai_core/shell/scripts/tenkai-volume"
  "$TENKAI_DIR/src/tenkai_core/shell/scripts/tenkai-restart-audio"
  "$TENKAI_DIR/src/tenkai_core/shell/scripts/tenkai-cmd-brightness"
  "$HYPR_SRC/scripts/tenkai-monitor"
  "$HYPR_SRC/scripts/tenkai-workspace"
)

deploy_helper_links() {
  local src dst
  local -a plan=()
  for src in "${HELPER_SRC[@]}"; do
    if [ ! -f "$src" ]; then
      warn "missing ${src#"$TENKAI_DIR"/} — its bind will not resolve"
      continue
    fi
    dst="$LOCAL_BIN/${src##*/}"
    if [ -L "$dst" ] && [ "$(readlink -f "$dst")" = "$(readlink -f "$src")" ]; then
      continue
    fi
    if [ -e "$dst" ] || [ -L "$dst" ]; then
      warn "$dst already exists (not Tenkai's link) — left alone"
      continue
    fi
    plan+=("$src")
  done
  if [ "${#plan[@]}" -eq 0 ]; then
    ok "keybind helpers already linked in $LOCAL_BIN"
    return 0
  fi
  local names="" n
  for n in "${plan[@]}"; do names+="${n##*/} "; done
  say "  link ${#plan[@]} helper(s) into $LOCAL_BIN: ${names% }"
  if [ "$DRY_RUN" = 1 ]; then
    say "  (dry run: nothing written)"
    return 0
  fi
  if ! confirm "link these into $LOCAL_BIN?"; then
    warn "not linked — those keybinds will not resolve"
    return 0
  fi
  mkdir -p "$LOCAL_BIN"
  for src in "${plan[@]}"; do
    ln -sfn "$src" "$LOCAL_BIN/${src##*/}"
  done
  ok "${#plan[@]} keybind helper(s) linked in $LOCAL_BIN"
}

deploy_helper_links

# ── 7. Hyprland autostart ────────────────────────────────────────────────────

step 7 "Hyprland autostart"

# The one Hyprland write this script can make, and only after an interactive
# y/N. --yes does not answer it; a non-tty run only prints the hook.
#
# The hook lives in its own drop-in, not appended to hyprland.lua or
# modules/autostart.lua: step 6 reinstalls those from the checkout on every run,
# so an appended block is gone on the next install (fresh install observed:
# hook appended at the old step 4, file overwritten at the old step 7, desktop
# boots with no bar). The shipped hyprland.lua optional()s this file, so a fresh
# install and an upgrade both pick it up and a re-run never duplicates it.
AUTOSTART_LUA="$HYPR_DIR/modules/autostart.lua"
LUA_CONF="$HYPR_DIR/hyprland.lua"
CLASSIC_CONF="$HYPR_DIR/hyprland.conf"
HOOK_FILE="$HYPR_DIR/tenkai_autostart.lua"
HOOK_CMD="$TENKAI_DIR/tenkai start"

# The live files only: a *.bak still carries a hook this script later removed.
if grep -qsF -- "$HOOK_CMD" "$HOOK_FILE" "$AUTOSTART_LUA" "$LUA_CONF" "$CLASSIC_CONF" 2>/dev/null; then
  ok "an autostart line for this checkout already exists under $HYPR_DIR"
elif [ -f "$CLASSIC_CONF" ]; then
  say "  Hyprland config: $CLASSIC_CONF (hyprlang)"
  say "  add:  exec-once = $HOOK_CMD"
  if confirm "append that line to $CLASSIC_CONF (a backup is written first)?"; then
    cp -a "$CLASSIC_CONF" "$CLASSIC_CONF.$MARK.bak"
    {
      printf '\n# %s: start the Tenkai shell at session start\n' "$MARK"
      printf 'exec-once = %s\n' "$HOOK_CMD"
    } >> "$CLASSIC_CONF"
    ok "appended to $CLASSIC_CONF (backup: $CLASSIC_CONF.$MARK.bak)"
  else
    warn "not modified — add the line above yourself if you want Tenkai to autostart"
  fi
elif [ -f "$LUA_CONF" ]; then
  say "  Hyprland config: $LUA_CONF (Lua)"
  say "  write, in $HOOK_FILE:"
  say "    hl.on(\"hyprland.start\", function()"
  say "        hl.exec_cmd(\"$HOOK_CMD\")"
  say "    end)"
  if confirm "write $HOOK_FILE (loaded by hyprland.lua)?"; then
    mkdir -p "$(dirname "$HOOK_FILE")"
    {
      printf '-- %s: start the Tenkai shell at session start\n' "$MARK"
      printf 'hl.on("hyprland.start", function()\n'
      printf '    hl.exec_cmd("%s")\n' "$HOOK_CMD"
      printf 'end)\n'
    } > "$HOOK_FILE"
    ok "wrote $HOOK_FILE"
  else
    warn "not modified — add the hook above yourself if you want Tenkai to autostart"
  fi
else
  warn "no $CLASSIC_CONF and no $LUA_CONF: is Hyprland configured for this user?"
  say "  add this to your Hyprland config by hand, once:"
  say "    exec-once = $HOOK_CMD"
fi

# ── 8. Hyprland binding ─────────────────────────────────────────────────────

step 8 "Hyprland binding (shell → compositor)"

# Steps 2 and 6 install the pieces (tenkai-wm-hyprland in .run/bin, the bundled
# Lua config); this step proves they are wired to each other. It is the only
# place a fresh install learns that this compositor needs `hyprctl eval` (Lua
# config) instead of `hyprctl keyword`, and it dispatches a real value through
# the shell's own path (`tenkai-hub desktop set`, the verb the Hub's Window
# Manager page and the shell's setSetting IPC both use) to prove the binding
# works before the user ever opens Settings.
#
# It changes nothing: the probe reads general:gaps_in and dispatches that same
# value back. Interactive by default; --yes-wm-bind answers it; --dry-run prints
# the plan and runs no hyprctl.
WM_BIN="$SYS_GO_BIN/tenkai-wm-hyprland"
HUB_BIN="$SYS_GO_BIN/tenkai-hub"

bind_wm() {
  local cur mode="" kw_out="" eval_out="" rc=0
  if [ ! -x "$WM_BIN" ]; then
    warn "$WM_BIN is missing — the shell has no window-manager provider"
    warn "  rerun without --skip-build (step 2 builds it)"
    return 1
  fi
  ok "wm provider present: $WM_BIN"
  if ! command -v hyprctl >/dev/null 2>&1; then
    warn "hyprctl not on PATH — cannot probe the compositor (is this a Hyprland session?)"
    return 1
  fi
  if [ -z "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
    warn "HYPRLAND_INSTANCE_SIGNATURE is unset — not a live Hyprland session"
    return 1
  fi
  cur=$(hyprctl getoption general:gaps_in 2>/dev/null | sed -n 's/^css gap data: \([0-9][0-9]*\).*/\1/p' | head -1)
  [ -n "$cur" ] || cur=4
  say "  probe: general:gaps_in is $cur; dispatching the same value back"
  if [ "$DRY_RUN" = 1 ]; then
    say "  (dry run: would probe hyprctl keyword, then eval via $HUB_BIN desktop set)"
    return 0
  fi
  if ! kw_out=$(hyprctl keyword general:gaps_in "$cur" 2>&1); then rc=1; fi
  case "$kw_out" in
    *"unknown request"*|*"Unknown request"*|*error*|*Error*) [ "$rc" = 0 ] && rc=1 ;;
  esac
  if [ "$rc" = 0 ] && [ -z "$kw_out" ]; then
    mode=keyword
  else
    mode=eval
    say "  ${GY}hyprctl keyword is unavailable here (Lua config manager) — using hyprctl eval${R}"
    say "  ${GY}keyword said: ${kw_out:-no output}${R}"
  fi
  if [ ! -x "$HUB_BIN" ]; then
    warn "$HUB_BIN is missing — the shell cannot apply settings yet"
    return 1
  fi
  if eval_out=$(HOME="$HOME" XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}" \
       PATH="$SYS_GO_BIN:$PATH" "$HUB_BIN" desktop set desktop.appearance.gapsIn "$cur" 2>&1); then
    ok "wm binding works: $HUB_BIN desktop set applied general:gaps_in=$cur (mode: $mode)"
    say "  ${GY}$eval_out${R}"
  else
    warn "wm binding FAILED: $HUB_BIN desktop set could not dispatch"
    say "  ${GY}${eval_out:-no output}${R}"
    return 1
  fi
  return 0
}

if [ "$WM_BIND_YES" = 1 ]; then
  say "  --yes-wm-bind: binding without asking"
  bind_wm || warn "wm binding not proven — Settings→Window Manager may not reach the compositor"
elif confirm "prove the shell can drive Hyprland now (dispatches one unchanged value)?"; then
  bind_wm || warn "wm binding not proven — Settings→Window Manager may not reach the compositor"
else
  warn "skipped — Settings→Window Manager will not reach the compositor until this is done"
  say "  close it later with: ./install.sh --skip-build --yes-wm-bind"
fi

# ── 9. wallpapers ───────────────────────────────────────────────────────────

step 9 "wallpapers"

# The repo ships NO wallpapers (the owner's set is not redistributable), so
# this step mostly reports and prepares the directory Tenkai's wallpaper daemon
# scans by default: ~/Pictures/Wallpapers. Drop image files into
# src/tenkai-assets/wallpapers/ before running ./install.sh and they are copied
# there; or copy images yourself at any time. Existing files in that directory
# are never touched without an explicit yes, and differing files are backed up
# to *.tenkai-install.bak first.
WP_SRC="$TENKAI_DIR/src/tenkai-assets/wallpapers"
WP_DEST="$HOME/Pictures/Wallpapers"

if [ "$DRY_RUN" = 1 ]; then
  say "  (dry run: would mkdir -p $WP_DEST and copy any bundled images)"
else
  run mkdir -p "$WP_DEST"
fi

WP_PLAN=()
if [ -d "$WP_SRC" ]; then
  while IFS= read -r -d '' src; do
    rel="${src#"$WP_SRC"/}"
    dst="$WP_DEST/$rel"
    if [ -f "$dst" ] && cmp -s "$src" "$dst"; then
      continue
    fi
    WP_PLAN+=("$rel")
  done < <(find "$WP_SRC" -type f \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' -o -iname '*.avif' \) -print0)
fi

if [ "${#WP_PLAN[@]}" -eq 0 ]; then
  say "  no wallpapers bundled in this checkout (see src/tenkai-assets/wallpapers/README.md)"
  say "  Matugen has no fallback image until you drop one into:"
  say "    $WP_DEST"
else
  for rel in "${WP_PLAN[@]}"; do say "    copy  $rel -> $WP_DEST/"; done
  if [ "$DRY_RUN" = 1 ]; then
    say "  (dry run: nothing written)"
  elif confirm_yes "copy ${#WP_PLAN[@]} wallpaper(s) into $WP_DEST?"; then
    for rel in "${WP_PLAN[@]}"; do
      dst="$WP_DEST/$rel"
      mkdir -p "$(dirname "$dst")"
      if [ -f "$dst" ]; then
        cp -a "$dst" "$dst.$MARK.bak"
      fi
      install -m 0644 "$WP_SRC/$rel" "$dst"
    done
    ok "wallpapers installed into $WP_DEST"
  else
    warn "wallpapers not copied"
  fi
fi

# ── 10. fonts ───────────────────────────────────────────────────────────────

step 10 "fonts"

# Bundled OFL fonts (Space Grotesk + Fraunces) install user-locally — no
# sudo. The remaining fonts Tenkai's QML references live in the official Arch
# repos; install.sh never runs sudo, so the pacman line is printed instead.
FONT_SRC="$TENKAI_DIR/src/tenkai-assets/fonts"
FONT_DEST="${XDG_DATA_HOME:-$HOME/.local/share}/fonts/tenkai"
fonts_written=0
for fam in space-grotesk fraunces; do
  [ -d "$FONT_SRC/$fam" ] || { warn "no bundled fonts at $FONT_SRC/$fam; skipped"; continue; }
  for f in "$FONT_SRC/$fam"/*.ttf; do
    [ -f "$f" ] || continue
    base="$(basename "$f")"
    dst="$FONT_DEST/$base"
    if [ -f "$dst" ] && cmp -s "$f" "$dst"; then
      ok "$base already installed"
      continue
    fi
    if [ "$DRY_RUN" = 1 ]; then
      say "  (dry run: would install $dst)"
      fonts_written=1
      continue
    fi
    mkdir -p "$FONT_DEST"
    install -m 0644 "$f" "$dst"
    ok "installed $dst"
    fonts_written=1
  done
done
if [ "$DRY_RUN" = 0 ] && [ "$fonts_written" = 1 ]; then
  if command -v fc-cache >/dev/null 2>&1; then
    run fc-cache -f "$FONT_DEST" || warn "fc-cache failed; run it yourself"
  else
    warn "fc-cache not found; refresh the font cache yourself"
  fi
fi

MISSING_FONTS=()
if command -v fc-list >/dev/null 2>&1; then
  fc-list | grep -qi "JetBrainsMono Nerd Font"   || MISSING_FONTS+=(ttf-jetbrains-mono-nerd)
  fc-list | grep -qi "SpaceMono Nerd Font"       || MISSING_FONTS+=(ttf-space-mono-nerd)
  fc-list | grep -qi "Material Symbols"           || MISSING_FONTS+=(ttf-material-symbols-variable)
  if [ "${#MISSING_FONTS[@]}" -gt 0 ]; then
    say "  optional icon/mono fonts not found; to install them (needs sudo):"
    say "    ${BL}sudo pacman -S --needed ${MISSING_FONTS[*]}${R}"
  else
    ok "nerd/material fonts already present"
  fi
else
  say "  fc-list not found; cannot check Nerd/Material Symbols fonts"
  say "    ${BL}sudo pacman -S --needed ttf-jetbrains-mono-nerd ttf-space-mono-nerd ttf-material-symbols-variable${R}"
fi

# ── done ─────────────────────────────────────────────────────────────────────

print_success

say "  ${GY}binaries:${R}  $SYS_GO_BIN/{tenkai-shell,tenkai-hub,tenkai-wm-hyprland,ryogami}"
say "  ${GY}QML:${R}       $QML_ROOT"
say ""
say "  ${WH}Next:${R}"
say "    ${BL}./tenkai status${R}                 # nothing running yet"
say "    ${BL}./tenkai start${R}                  # join this Hyprland session now"
say ""
say "  A second run of this script is safe: it rebuilds only what changed,"
say "  rewrites no identical unit, reinstalls no identical hypr file or font,"
say "  and adds no second autostart line or kitty include."
