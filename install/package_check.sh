#!/usr/bin/env bash
set -euo pipefail
IFS=$'\n\t'

usage() {
  cat <<'EOF'
Usage: package_check.sh [--missing] [--verbose] [--packages <p1> <p2> ...]
  --missing   Print only missing packages (one per line)
  --verbose   Print status lines for each package
  --packages  Provide packages on the command line instead of packages.txt

Notes:
- Packages are treated as *commands* expected to exist in PATH.
- Use command alternatives separated by |, e.g. bat|batcat.
- When reading packages.txt, blank lines and lines starting with # are ignored.
EOF
}

have() { command -v "$1" >/dev/null 2>&1; }

have_any() {
  local spec="$1"
  local cmd
  local choices

  IFS='|' read -r -a choices <<< "$spec"
  for cmd in "${choices[@]}"; do
    if have "$cmd"; then
      return 0
    fi
  done

  return 1
}

MISSING_ONLY=0
VERBOSE=0
USE_CLI_PACKAGES=0
PACKAGES=()

# Resolve paths relative to this script
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
PKG_FILE="$SCRIPT_DIR/packages.txt"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --missing)  MISSING_ONLY=1; shift ;;
    --verbose)  VERBOSE=1; shift ;;
    --packages) USE_CLI_PACKAGES=1; shift; PACKAGES+=("$@"); break ;;
    -h|--help)  usage; exit 0 ;;
    *) echo "Unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

if [[ "$USE_CLI_PACKAGES" -eq 0 ]]; then
  if [[ ! -f "$PKG_FILE" ]]; then
    echo "packages.txt not found: $PKG_FILE" >&2
    exit 1
  fi

  while IFS= read -r line || [[ -n "$line" ]]; do
    # Trim leading/trailing whitespace (simple)
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"

    # Skip blanks and comments
    [[ -z "$line" ]] && continue
    [[ "$line" == \#* ]] && continue

    PACKAGES+=("$line")
  done < "$PKG_FILE"
fi

# De-dupe is optional; keeping it simple and predictable
for pkg in "${PACKAGES[@]}"; do
  [[ -z "$pkg" ]] && continue

  if have_any "$pkg"; then
    if [[ "$MISSING_ONLY" -eq 0 && "$VERBOSE" -eq 1 ]]; then
      echo "$pkg is installed"
    fi
  else
    if [[ "$MISSING_ONLY" -eq 1 ]]; then
      echo "$pkg"
    elif [[ "$VERBOSE" -eq 1 ]]; then
      echo "$pkg is not installed"
    fi
  fi
done

exit 0
