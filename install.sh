#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

DRY_RUN=0
RESTOW=0
DELETE=0
PACKAGES=()

usage() {
  cat <<'EOF'
Usage: ./install.sh [--dry-run] [--restow] [--delete] [package ...]

Examples:
  ./install.sh                 Install all default dotfile packages
  ./install.sh --dry-run       Show what Stow would do
  ./install.sh nvim            Install only the Neovim config
  ./install.sh --delete nvim   Remove Neovim dotfile links

Options:
  --dry-run   Run Stow in simulate mode
  --restow    Recreate package symlinks
  --delete    Remove package symlinks
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --dry-run) DRY_RUN=1; shift ;;
    --restow) RESTOW=1; shift ;;
    --delete) DELETE=1; shift ;;
    -h|--help) usage; exit 0 ;;
    --*) echo "Unknown argument: $1" >&2; usage; exit 2 ;;
    *) PACKAGES+=("$1"); shift ;;
  esac
done

if [[ "$RESTOW" -eq 1 && "$DELETE" -eq 1 ]]; then
  echo "Choose only one of --restow or --delete." >&2
  exit 2
fi

if [[ "${EUID:-$(id -u)}" -eq 0 ]]; then
  echo "Do not run this as root. Run as the target user." >&2
  exit 1
fi

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$SCRIPT_DIR"
PACKAGE_DIR="$REPO_ROOT/packages"
PKG_CHECK="$REPO_ROOT/install/package_check.sh"
TARGET_HOME="${HOME:?HOME is not set}"

if [[ ! -d "$PACKAGE_DIR" ]]; then
  echo "Package directory not found: $PACKAGE_DIR" >&2
  exit 1
fi

if [[ ! -x "$PKG_CHECK" ]]; then
  echo "package_check.sh not found or not executable: $PKG_CHECK" >&2
  exit 1
fi

MISSING_PACKAGES="$("$PKG_CHECK" --missing || true)"
if [[ -n "$MISSING_PACKAGES" ]]; then
  echo "Missing required commands:"
  echo "$MISSING_PACKAGES"
  echo
  echo "On Arch Linux, install them with:"
  echo "  sudo pacman -S stow neovim ripgrep fd bat fzf jq"
  exit 1
fi

if [[ "${#PACKAGES[@]}" -eq 0 ]]; then
  while IFS= read -r -d '' package_path; do
    PACKAGES+=("$(basename -- "$package_path")")
  done < <(find "$PACKAGE_DIR" -mindepth 1 -maxdepth 1 -type d -print0 | sort -z)
fi

STOW_ARGS=(-d "$PACKAGE_DIR" -t "$TARGET_HOME" --verbose)

if [[ "$DRY_RUN" -eq 1 ]]; then
  STOW_ARGS+=(--simulate)
fi

if [[ "$RESTOW" -eq 1 ]]; then
  STOW_ARGS+=(--restow)
elif [[ "$DELETE" -eq 1 ]]; then
  STOW_ARGS+=(--delete)
fi

echo "Stow directory: $PACKAGE_DIR"
echo "Target home:    $TARGET_HOME"
echo "Packages:"
printf '  %s\n' "${PACKAGES[@]}"
echo

stow "${STOW_ARGS[@]}" "${PACKAGES[@]}"
