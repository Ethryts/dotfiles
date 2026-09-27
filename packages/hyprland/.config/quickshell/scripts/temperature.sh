#!/usr/bin/env bash
set -euo pipefail

temperature_text() {
  local path raw c

  for path in /sys/class/thermal/thermal_zone6/temp /sys/class/thermal/thermal_zone*/temp; do
    [[ -r "${path}" ]] || continue
    raw="$(<"${path}")"
    [[ "${raw}" =~ ^[0-9]+$ ]] || continue
    (( raw > 0 )) || continue

    c=$((raw / 1000))
    printf ' %d°C\n' "${c}"
    return
  done

  printf ' n/a\n'
}

case "${1:-get}" in
  get)
    temperature_text
    ;;
  *)
    printf 'Usage: %s {get}\n' "$0" >&2
    exit 2
    ;;
esac
