#!/usr/bin/env bash
# setup/bootstrap.sh — read setup/manifest.json and bring this machine to it.
#
#   setup/bootstrap.sh              check + download missing assets, report missing packages
#   setup/bootstrap.sh --apply      also run the manifest's package install / step commands
#   setup/bootstrap.sh --dry-run    print every action, change nothing
#   setup/bootstrap.sh --manifest P use another manifest
#
# Rules:
#   * idempotent: an asset already at its destination is never downloaded twice;
#     a dependency already present is never reinstalled; a step whose `when`
#     command succeeds is skipped.
#   * never runs sudo unless --apply was passed and the manifest says to.
#   * fails loudly: the first step that cannot complete stops the run non-zero.
#   * logs every action to stdout and, if TENKAI_BOOTSTRAP_LOG is set, to that file.
#
# The manifest is deliberately empty in this checkout (see its $comment); an
# empty manifest is success, not an error.
set -euo pipefail

TENKAI_DIR="${TENKAI_DIR:-$(cd "$(dirname "$0")/.." && pwd)}"
MANIFEST="${TENKAI_DIR}/setup/manifest.json"
APPLY=0
DRY=0

while [ $# -gt 0 ]; do
  case "$1" in
    --apply) APPLY=1 ;;
    --dry-run) DRY=1 ;;
    --manifest) shift; MANIFEST="${1:?--manifest needs a path}" ;;
    -h|--help) sed -n '2,18p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) printf 'bootstrap: unknown argument: %s\n' "$1" >&2; exit 2 ;;
  esac
  shift
done

log() {
  printf '  %s\n' "$*"
  if [ -n "${TENKAI_BOOTSTRAP_LOG:-}" ]; then
    printf '%s %s\n' "$(date -Is)" "$*" >>"$TENKAI_BOOTSTRAP_LOG"
  fi
}
die() { printf '\nbootstrap: %s\n' "$*" >&2; exit 1; }
run() {
  if [ "$DRY" = 1 ]; then log "[dry-run] $*"; return 0; fi
  log "\$ $*"
  "$@"
}

[ -f "$MANIFEST" ] || die "no manifest at $MANIFEST"
command -v jq >/dev/null 2>&1 || die "jq is required to read the manifest (sudo pacman -S --needed jq)"
jq -e . "$MANIFEST" >/dev/null 2>&1 || die "manifest is not valid JSON: $MANIFEST"

printf 'Tenkai bootstrap\n  manifest: %s\n  mode:     %s\n' "$MANIFEST" "$([ "$DRY" = 1 ] && echo dry-run || { [ "$APPLY" = 1 ] && echo apply || echo check-only; })"

missing_installs=()

# ── dependencies ────────────────────────────────────────────────────────────
while IFS= read -r dep; do
  id=$(jq -r '.id // "(unnamed)"' <<<"$dep")
  kind=$(jq -r '.kind // "command"' <<<"$dep")
  case "$kind" in
    command)
      check=$(jq -r '.check // (.names[0] // "")' <<<"$dep")
      [ -n "$check" ] || die "dependency $id: command kind needs check or names[0]"
      if command -v "$check" >/dev/null 2>&1; then
        log "ok       $id ($check)"
      else
        log "MISSING  $id ($check)"
        missing_installs+=("$dep")
      fi
      ;;
    pacman)
      missing_pkgs=()
      while IFS= read -r pkg; do
        [ -n "$pkg" ] || continue
        if pacman -Q "$pkg" >/dev/null 2>&1; then
          log "ok       $id ($pkg)"
        else
          log "MISSING  $id ($pkg)"
          missing_pkgs+=("$pkg")
        fi
      done < <(jq -r '.names[]? // empty' <<<"$dep")
      if [ "${#missing_pkgs[@]}" -gt 0 ]; then
        if [ "$APPLY" = 1 ]; then
          run sudo pacman -S --needed --noconfirm "${missing_pkgs[@]}"
        else
          log "         install with: sudo pacman -S --needed ${missing_pkgs[*]}"
          missing_installs+=("$dep")
        fi
      fi
      ;;
    *) die "dependency $id: unknown kind '$kind'" ;;
  esac
done < <(jq -c '.dependencies[]?' "$MANIFEST")

# ── assets ──────────────────────────────────────────────────────────────────
while IFS= read -r asset; do
  id=$(jq -r '.id // "(unnamed)"' <<<"$asset")
  url=$(jq -r '.url // ""' <<<"$asset")
  dest=$(jq -r '.dest // ""' <<<"$asset")
  want=$(jq -r '.sha256 // ""' <<<"$asset")
  [ -n "$url" ] && [ -n "$dest" ] || die "asset $id: url and dest are required"
  dest="${dest/#\~/$HOME}"
  dest="${dest//\$HOME/$HOME}"
  if [ -f "$dest" ]; then
    if [ -n "$want" ]; then
      got=$(sha256sum "$dest" | awk '{print $1}')
      [ "$got" = "$want" ] || die "asset $id: $dest exists but sha256 is $got, expected $want"
    fi
    log "ok       $id ($dest)"
    continue
  fi
  log "FETCH    $id -> $dest"
  if [ "$DRY" = 1 ]; then log "[dry-run] curl -fsSL $url -o $dest"; continue; fi
  command -v curl >/dev/null 2>&1 || die "asset $id: curl is required"
  tmp=$(mktemp)
  curl -fsSL "$url" -o "$tmp" || { rm -f "$tmp"; die "asset $id: download failed: $url"; }
  if [ -n "$want" ]; then
    got=$(sha256sum "$tmp" | awk '{print $1}')
    [ "$got" = "$want" ] || { rm -f "$tmp"; die "asset $id: checksum mismatch (got $got)"; }
  fi
  mkdir -p "$(dirname "$dest")"
  mv "$tmp" "$dest"
  log "wrote    $dest"
done < <(jq -c '.assets[]?' "$MANIFEST")

# ── steps ───────────────────────────────────────────────────────────────────
while IFS= read -r step; do
  id=$(jq -r '.id // "(unnamed)"' <<<"$step")
  when=$(jq -r '.when // ""' <<<"$step")
  if [ -n "$when" ] && bash -c "$when" >/dev/null 2>&1; then
    log "skip     $id (when already true)"
    continue
  fi
  mapfile -t argv < <(jq -r '.run[]?' <<<"$step")
  [ "${#argv[@]}" -gt 0 ] || die "step $id: run[] is empty"
  if [ "$APPLY" = 1 ]; then
    run "${argv[@]}" || die "step $id failed: ${argv[*]}"
  else
    log "WOULD RUN $id: ${argv[*]}"
  fi
done < <(jq -c '.steps[]?' "$MANIFEST")

# ── summary ─────────────────────────────────────────────────────────────────
if [ "${#missing_installs[@]}" -gt 0 ] && [ "$APPLY" = 0 ]; then
  printf '\nbootstrap: %d dependency group(s) missing; re-run with --apply to install them.\n' "${#missing_installs[@]}" >&2
  exit 1
fi
log "done"
