#!/usr/bin/env bash
# install.sh — set Mei up on a fresh Arch Linux + Hyprland machine.
#
#   ./install.sh                 check, build, then ask before each system change
#   ./install.sh --yes           answer "yes" to the non-Hyprland prompts too
#   ./install.sh --dry-run       print what would happen, touch nothing
#   ./install.sh --skip-build    only do the system steps (binaries already built)
#   ./install.sh --help
#
# What it does, in order:
#   1. dependency check (pacman list printed, nothing installed)
#   2. build: the three Go daemons, the Ryoku.Blobs C++/QML plugin, and the
#      QML module tree under .run/qml
#   3. systemd user units (mei-shell.service, mei-hub.service) + daemon-reload
#   4. Hyprland autostart: `mei start` — INTERACTIVE y/N ONLY, never --yes
#   5. kitty: include the generated colour file (prompted)
#   6. terminal: this repo's Fish + Starship prompt files (prompted)
#   7. Hyprland configs: deploy the bundled Lua config to ~/.config/hypr
#      (interactive y/N only, *.mei-install.bak backups; keyboard.lua is
#      seeded once and never overwritten)
#   8. wallpapers: copy any bundled images into ~/Pictures/Wallpapers/
#   9. fonts: install the bundled OFL Space Grotesk / Fraunces user-locally,
#      and print the pacman line for the Nerd/Material Symbols fonts
#
# Everything it writes outside this checkout is named and prompted for. It never
# installs packages and never runs sudo; the one Hyprland-config deploy (step 7)
# is interactive y/N only and always writes *.mei-install.bak backups first.
#
# Idempotent: a second run rebuilds nothing that is up to date, rewrites no
# identical unit, appends no second autostart line and no second kitty include.
#
# The systemd units and the autostart line are ALTERNATIVES, not both: the units
# start the daemons directly, while `mei start` runs Mei's own live-session
# script (which starts the same daemons and records their pids). Use one.
set -uo pipefail

MEI_DIR="${MEI_DIR:-$(cd "$(dirname "$0")" && pwd)}"
RUN="$MEI_DIR/.run"
SYS_GO_BIN="$RUN/bin"
QML_ROOT="$RUN/qml/Ryoku"
BLOBS_BUILD="$RUN/build/blobs"
UNIT_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/systemd/user"
HYPR_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/hypr"
KITTY_CONF="${XDG_CONFIG_HOME:-$HOME/.config}/kitty/kitty.conf"
KITTY_INCLUDE='include ~/.cache/mei/kitty-colors.conf'
FISH_CONF="${XDG_CONFIG_HOME:-$HOME/.config}/fish/config.fish"
STARSHIP_CONF="${XDG_CONFIG_HOME:-$HOME/.config}/starship.toml"
TERM_SRC="$MEI_DIR/src/mei-configs/terminal"
MARK='mei-install'

ASSUME_YES=0
DRY_RUN=0
SKIP_BUILD=0

say()  { printf '%s\n' "$*"; }
step() { printf '\n=== %s ===\n' "$*"; }
ok()   { printf '  ok    %s\n' "$*"; }
warn() { printf '  warn  %s\n' "$*"; }
bad()  { printf '  FAIL  %s\n' "$*"; }
die()  { printf '\ninstall.sh: %s\n' "$*" >&2; exit 1; }

# run <command...>: show it, then run it unless this is a dry run. In a dry run
# the whole "would have" line is the output, so nothing can be half-applied.
run() {
  printf '  $ %s\n' "$*"
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
  sed -n '2,34p' "$0" | grep '^#' | sed 's/^# \{0,1\}//'
}

while [ $# -gt 0 ]; do
  case "$1" in
    -y | --yes) ASSUME_YES=1 ;;
    --dry-run) DRY_RUN=1 ;;
    --skip-build) SKIP_BUILD=1 ;;
    -h | --help) usage; exit 0 ;;
    *) die "unknown argument: $1 (try --help)" ;;
  esac
  shift
done

[ -f "$MEI_DIR/mei" ] || die "no ./mei beside this script — run install.sh from the checkout"
[ -n "${MEI_TEST:-}" ] && die "MEI_TEST is set: this is a nested test session, not an install"
[ "$(id -u)" = 0 ] && die "do not run this as root: it builds and installs into your own account"

say "Mei installer"
say "  checkout: $MEI_DIR"

# ── 1. dependencies ───────────────────────────────────────────────────────────

step "1. dependencies"

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
check_pkg pipewire pw-cli
check_pkg networkmanager nmcli
# The terminal: Mei ships the owner's own Fish config and Starship preset, and
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
  say "Install the required packages, then run this again:"
  say ""
  say "  sudo pacman -S --needed ${MISSING_PKGS[*]}"
  die "${#MISSING_PKGS[@]} required package(s) missing"
fi

if [ "${#BUILD_MISSING[@]}" -gt 0 ]; then
  say ""
  say "Not on the required list, but needed to build or run Mei. If the build"
  say "fails below, this is the line:"
  say ""
  say "  sudo pacman -S --needed ${BUILD_MISSING[*]}"
  say ""
fi

# ── 2. build ──────────────────────────────────────────────────────────────────

step "2. build"

if [ "$SKIP_BUILD" = 1 ]; then
  say "  --skip-build: not building"
else
  mkdir -p "$SYS_GO_BIN" "$QML_ROOT" "$RUN/go"

  # Project-local Go state, vendored deps, no toolchain download, no CGO: the
  # same environment docs/04-plan.md pins for a reproducible build.
  export GOTOOLCHAIN=local
  export GOFLAGS=-mod=vendor
  export GOPATH="$RUN/go"
  export GOCACHE="$RUN/go/cache"
  export CGO_ENABLED=0

  go_build() { # $1 = source dir, $2 = output name
    local src="$MEI_DIR/src/ryoku/$1" out="$SYS_GO_BIN/$2"
    [ -d "$src" ] || die "missing source dir: $src"
    say "  building $2"
    ( cd "$src" && nice -n 10 go build -trimpath -p 2 -o "$out" ./ ) \
      || die "go build failed in $src"
    [ -x "$out" ] || die "$2 was not produced"
    ok "$out"
  }

  go_build shell/ipc mei-shell
  go_build hub/backend mei-hub
  # The wallpaper daemon shares the session with the shell; without it the
  # wallpaper module has nothing to talk to.
  go_build shell/ryogami/daemon ryogami

  # Ryoku.Blobs — the SDF metaball plugin behind the frame. Prebuilt upstream
  # because a target machine has no toolchain; here we do have one.
  [ -d "$MEI_DIR/src/ryoku/shell/plugin" ] || die "missing src/ryoku/shell/plugin"
  say "  configuring Ryoku.Blobs"
  CMAKE_GEN=()
  command -v ninja >/dev/null 2>&1 && CMAKE_GEN=(-G Ninja)
  run cmake -S "$MEI_DIR/src/ryoku/shell/plugin" -B "$BLOBS_BUILD" \
      "${CMAKE_GEN[@]}" -DCMAKE_BUILD_TYPE=Release \
    || die "cmake configure failed (Qt6 6.5+ with Quick/ShaderTools/Multimedia is required)"
  say "  building Ryoku.Blobs"
  run nice -n 10 cmake --build "$BLOBS_BUILD" -j2 || die "cmake build failed"
  [ -d "$BLOBS_BUILD/qml/Ryoku/Blobs" ] || die "the Blobs module was not produced"

  # One QML import path for the whole tree. `cp -a src/. dst/` overwrites in
  # place, so a second run refreshes the modules without nesting a copy.
  sync_dir() { # $1 = source, $2 = destination
    [ -d "$1" ] || die "missing QML module source: $1"
    mkdir -p "$2"
    run cp -a "$1/." "$2/"
  }
  sync_dir "$MEI_DIR/src/ryoku/ui" "$QML_ROOT/Ui"
  sync_dir "$MEI_DIR/src/ryoku/shell/framebars" "$QML_ROOT/FrameBars"
  sync_dir "$MEI_DIR/src/ryoku/shell/quickshell/plugins/kit" "$QML_ROOT/PluginKit"
  sync_dir "$MEI_DIR/src/ryoku/wm/hyprland/qml" "$QML_ROOT/Wm/Hyprland"
  sync_dir "$BLOBS_BUILD/qml/Ryoku/Blobs" "$QML_ROOT/Blobs"

  ok "QML modules under $QML_ROOT (Ui, FrameBars, PluginKit, Wm/Hyprland, Blobs)"
fi

# A dry run builds nothing, so it must not fail these two (that is the point of
# printing them). A real run stops here rather than installing an empty tree.
if [ "$DRY_RUN" = 0 ]; then
  [ -x "$SYS_GO_BIN/mei-shell" ] || die "mei-shell is not built at $SYS_GO_BIN/mei-shell"
  [ -d "$QML_ROOT/Ui" ] || die "the QML modules are not assembled under $QML_ROOT"
fi

# ── 3. systemd user units ────────────────────────────────────────────────────

step "3. systemd user units"

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
    say "$content" | sed 's/^/    | /'
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
write_unit mei-shell.service <<UNIT
[Unit]
# Mei's shell daemon: the bar, the launcher, the OSD, notifications, the tray,
# the clipboard watcher and every other surface. Supervised here as an
# alternative to the Hyprland autostart line — use one, never both.
Description=Mei shell daemon
PartOf=graphical-session.target
After=graphical-session.target
ConditionEnvironment=WAYLAND_DISPLAY
StartLimitIntervalSec=60
StartLimitBurst=5

[Service]
Type=simple
WorkingDirectory=$MEI_DIR
ExecStart=$SYS_GO_BIN/mei-shell daemon
Restart=always
RestartSec=2
# Kill only the daemon, not its cgroup: apps launched from the shell outlive a
# shell reload.
KillMode=process
Slice=session.slice

[Install]
WantedBy=graphical-session.target
UNIT

write_unit mei-hub.service <<UNIT
[Unit]
# mei-hub is a command-line backend, not a daemon: the shell starts it on demand
# for Settings saves. This unit only re-applies the persisted runtime overrides
# (displays, keybinds, advanced window options) once the session is up, which is
# useful if you run the daemons through systemd instead of \`mei start\`.
Description=Mei settings backend: re-apply the runtime overrides at session start
After=graphical-session.target mei-shell.service
PartOf=graphical-session.target
ConditionEnvironment=WAYLAND_DISPLAY

[Service]
Type=oneshot
WorkingDirectory=$MEI_DIR
ExecStart=$SYS_GO_BIN/mei-hub overrides apply

[Install]
WantedBy=graphical-session.target
UNIT

if [ "$UNIT_CHANGED" = 1 ]; then
  run systemctl --user daemon-reload || warn "daemon-reload failed; run it yourself"
else
  say "  units are up to date; no daemon-reload needed"
fi
say ""
say "  Not enabled on purpose. To use the units instead of the autostart line:"
say "    systemctl --user enable --now mei-shell.service mei-hub.service"

# ── 4. Hyprland autostart ────────────────────────────────────────────────────

step "4. Hyprland autostart"

# The one Hyprland file this script could ever change — and only after an
# interactive y/N. --yes does not answer this one, and a non-tty run only prints
# the line to paste.
AUTOSTART_LUA="$HYPR_DIR/modules/autostart.lua"
LUA_CONF="$HYPR_DIR/hyprland.lua"
CLASSIC_CONF="$HYPR_DIR/hyprland.conf"

if grep -rqsF -- "$MEI_DIR/mei start" "$HYPR_DIR" 2>/dev/null; then
  ok "an autostart line for this checkout already exists under $HYPR_DIR"
elif [ -f "$CLASSIC_CONF" ]; then
  say "  Hyprland config: $CLASSIC_CONF (hyprlang)"
  say "  add:  exec-once = $MEI_DIR/mei start"
  if confirm "append that line to $CLASSIC_CONF (a backup is written first)?"; then
    cp -a "$CLASSIC_CONF" "$CLASSIC_CONF.$MARK.bak"
    {
      printf '\n# %s: start the Mei shell at session start\n' "$MARK"
      printf 'exec-once = %s\n' "$MEI_DIR/mei start"
    } >> "$CLASSIC_CONF"
    ok "appended to $CLASSIC_CONF (backup: $CLASSIC_CONF.$MARK.bak)"
  else
    warn "not modified — add the line above yourself if you want Mei to autostart"
  fi
elif [ -f "$LUA_CONF" ]; then
  # Hyprland's Lua config: startup commands live in an
  # hl.on("hyprland.start", function() ... end) hook (modules/autostart.lua is
  # where the keyring and the like are started). Appending a hook of our own is
  # independent of what that file already contains, and runs once per session.
  TARGET="$LUA_CONF"
  [ -f "$AUTOSTART_LUA" ] && TARGET="$AUTOSTART_LUA"
  say "  Hyprland config: $LUA_CONF (Lua)"
  say "  add, at the end of $TARGET:"
  say "    hl.on(\"hyprland.start\", function()"
  say "        hl.exec_cmd(\"$MEI_DIR/mei start\")"
  say "    end)"
  if confirm "append that hook to $TARGET (a backup is written first)?"; then
    cp -a "$TARGET" "$TARGET.$MARK.bak"
    {
      printf '\n-- %s: start the Mei shell at session start\n' "$MARK"
      printf 'hl.on("hyprland.start", function()\n'
      printf '    hl.exec_cmd("%s")\n' "$MEI_DIR/mei start"
      printf 'end)\n'
    } >> "$TARGET"
    ok "appended to $TARGET (backup: $TARGET.$MARK.bak)"
  else
    warn "not modified — add the hook above yourself if you want Mei to autostart"
  fi
else
  warn "no $CLASSIC_CONF and no $LUA_CONF: is Hyprland configured for this user?"
  say "  add this to your Hyprland config by hand, once:"
  say "    exec-once = $MEI_DIR/mei start"
fi

# ── 5. kitty colours ────────────────────────────────────────────────────────

step "5. kitty colours"

# Mei's palette pass writes ~/.cache/mei/kitty-colors.conf; kitty only reads it
# if its own config includes it. Mei never writes ~/.config/kitty itself.
if [ ! -f "$KITTY_CONF" ]; then
  warn "no $KITTY_CONF — kitty is not configured for this user"
  say "  create it with:"
  say "    mkdir -p ${KITTY_CONF%/*} && printf '%s\\n' '$KITTY_INCLUDE' >> $KITTY_CONF"
elif grep -qF "$KITTY_INCLUDE" "$KITTY_CONF"; then
  ok "$KITTY_CONF already includes the Mei colour file"
else
  say "  add:  $KITTY_INCLUDE"
  if confirm_yes "append that include to $KITTY_CONF (a backup is written first)?"; then
    cp -a "$KITTY_CONF" "$KITTY_CONF.$MARK.bak"
    {
      printf '\n# %s: Mei (matugen) colour file\n' "$MARK"
      printf '%s\n' "$KITTY_INCLUDE"
    } >> "$KITTY_CONF"
    ok "appended to $KITTY_CONF (backup: $KITTY_CONF.$MARK.bak)"
  else
    say "  or by hand:"
    say "    printf '%s\\n' '$KITTY_INCLUDE' >> $KITTY_CONF"
  fi
fi
say ""
say "  The file itself appears the first time Mei runs a palette pass."
say "  Kitty re-reads its config on SIGUSR1: pkill -USR1 -x kitty"

# ── 6. terminal: full environment (kitty + fish + starship + fastfetch) ─────

step "6. terminal (kitty + fish + starship + fastfetch)"

# Mei ships the owner's exact terminal environment: kitty style/conf (opacity,
# padding, fonts), Fish behaviour (config + conf.d), the Starship prompt preset,
# and the Fastfetch look-and-feel. Everything is copied whole and never merged
# into an existing file: the target is backed up first and an identical file is
# left alone, so a second run changes nothing.
copy_config() { # $1 = file in this checkout, $2 = destination
  local src="$1" dst="$2"
  if [ ! -f "$src" ]; then
    warn "no ${src#$MEI_DIR/} in this checkout; skipped"
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

# ── 6. terminal: full environment (kitty + fish + starship + fastfetch) ───────

step "6. terminal (kitty + fish + starship + fastfetch)"

# Mei ships the owner's exact terminal environment: kitty style/conf (opacity,
# padding, fonts), Fish behaviour (config + conf.d + functions), the Starship
# prompt preset, and the Fastfetch look-and-feel. Everything is copied whole and
# never merged into an existing file: the target is backed up first, and an
# identical file is left alone, so a second run changes nothing.

# --- kitty: style + theme + user config, plus the generated palette include ---
copy_config "$TERM_SRC/kitty/kitty.conf" "$KITTY_CONF"
copy_config "$TERM_SRC/kitty/current-font.conf" "$HOME/.config/kitty/current-font.conf"
copy_config "$TERM_SRC/kitty/current-theme.conf" "$HOME/.config/kitty/current-theme.conf"
copy_config "$TERM_SRC/kitty/user.conf" "$HOME/.config/kitty/user.conf"

# The generated palette (from `./mei colours`) is read by kitty only if its
# config includes it. Mei never writes ~/.config/kitty itself; one idempotent
# include line is appended here (idempotent via grep) — prompted, and the
# target is backed up to *.mei-install.bak first. Skipped entirely on a dry run.
if [ "$DRY_RUN" = 0 ] && [ -f "$KITTY_CONF" ] && ! grep -qsF "include ~/.cache/mei/kitty-colors.conf" "$KITTY_CONF"; then
  if [ -f "$HOME/.cache/mei/kitty-colors.conf" ]; then
    if confirm_yes "append the palette include to $KITTY_CONF (a backup is written first)?"; then
      cp -a "$KITTY_CONF" "$KITTY_CONF.$MARK.bak"
      printf '%s\n' 'include ~/.cache/mei/kitty-colors.conf' >> "$KITTY_CONF"
      ok "palette include appended"
    else
      warn "palette include not added"
    fi
  else
    warn "$HOME/.cache/mei/kitty-colors.conf missing; palette include not added"
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
# yes, and existing targets are backed up to *.mei-install.bak first. A dry run
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
  say "  fish is installed but is not your login shell. To use it:"
  say "    chsh -s $(command -v fish)"
fi

# ── 7. Hyprland configs ─────────────────────────────────────────────────────

step "7. Hyprland configs (Lua)"

# Mei ships the owner's Hyprland Lua config so a fresh install is not stuck
# with Hyprland defaults. Files are copied whole, never merged; existing
# targets are backed up to <name>.mei-install.bak before being overwritten.
# This step is INTERACTIVE y/N only (never --yes, never a piped answer) —
# overwriting a live ~/.config/hypr is a human decision. Nothing is deleted;
# files only in your checkout stay exactly where they are.
#
# keyboard.lua is the exception: it is user-owned, seeded once, and never
# overwritten by an install (mirrors how hyprland.lua treats it).
#
# The bundled configs try ~/.config/mei (and ~/.cache/mei) first and fall back
# to the legacy ~/.config/ryoku / ~/.cache/ryoku paths, so they work both on a
# pure Mei install and on a hybrid box with stock Ryoku still present.
HYPR_SRC="$MEI_DIR/src/mei-configs/hypr"
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
    if [ -f "$dst" ] && cmp -s "$src" "$dst"; then
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
  for rel in "${new[@]}";  do say "    new        $rel"; done
  for rel in "${over[@]}"; do say "    overwrite  $rel  (backup: $rel.$MARK.bak)"; done
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
    install -m 0644 "$HYPR_SRC/$rel" "$dst"
  done
  ok "hypr configs installed (${#plan[@]} files; backups are *.$MARK.bak)"
}
deploy_hypr

# ── 8. wallpapers ───────────────────────────────────────────────────────────

step "8. wallpapers"

# The repo ships NO wallpapers (the owner's set is not redistributable), so
# this step mostly reports and prepares the directory Mei's wallpaper daemon
# scans by default: ~/Pictures/Wallpapers. Drop image files into
# src/mei-assets/wallpapers/ before running ./install.sh and they are copied
# there; or copy images yourself at any time. Existing files in that directory
# are never touched without an explicit yes, and differing files are backed up
# to *.mei-install.bak first.
WP_SRC="$MEI_DIR/src/mei-assets/wallpapers"
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
  say "  no wallpapers bundled in this checkout (see src/mei-assets/wallpapers/README.md)"
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

# ── 9. fonts ────────────────────────────────────────────────────────────────

step "9. fonts"

# Bundled OFL fonts (Space Grotesk + Fraunces) install user-locally — no
# sudo. The remaining fonts Mei's QML references live in the official Arch
# repos; install.sh never runs sudo, so the pacman line is printed instead.
FONT_SRC="$MEI_DIR/src/mei-assets/fonts"
FONT_DEST="${XDG_DATA_HOME:-$HOME/.local/share}/fonts/mei"
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
  fc-list | grep -qi "Material Symbols"          || MISSING_FONTS+=(ttf-material-symbols-variable)
  if [ "${#MISSING_FONTS[@]}" -gt 0 ]; then
    say "  optional icon/mono fonts not found; to install them (needs sudo):"
    say "    sudo pacman -S --needed ${MISSING_FONTS[*]}"
  else
    ok "nerd/material fonts already present"
  fi
else
  say "  fc-list not found; cannot check Nerd/Material Symbols fonts"
  say "    sudo pacman -S --needed ttf-jetbrains-mono-nerd ttf-space-mono-nerd ttf-material-symbols-variable"
fi

# ── done ─────────────────────────────────────────────────────────────────────

step "done"

say "  binaries:  $SYS_GO_BIN/{mei-shell,mei-hub,ryogami}"
say "  QML:       $QML_ROOT"
say ""
say "  Next:"
say "    ./mei status                 # nothing running yet"
say "    ./mei start                  # join this Hyprland session now"
say ""
say "  A second run of this script is safe: it rebuilds only what changed,"
say "  rewrites no identical unit, reinstalls no identical hypr file or font,"
say "  and adds no second autostart line or kitty include."
