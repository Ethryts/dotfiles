#!/usr/bin/env bash
set -euo pipefail

STEP_PCT=1

overlay_emit() {
  local value

  value="$(brightness_text)"
  [[ "${value}" =~ ^-?[0-9]+$ ]] || return
  (( value >= 0 )) || return

  quickshell ipc call overlay brightness "${value}" >/dev/null 2>&1 || true
}

brightness_text() {
  local percent dir cur max

  if command -v brightnessctl >/dev/null 2>&1; then
    percent="$(brightnessctl -m 2>/dev/null | awk -F, 'NR==1{gsub(/%/, "", $4); printf "%d", $4 + 0.5}' || true)"
    if [[ -n "${percent}" ]]; then
      printf '%d\n' "${percent}"
      return
    fi
  fi

  for dir in /sys/class/backlight/*; do
    [[ -d "${dir}" ]] || continue
    [[ -r "${dir}/brightness" && -r "${dir}/max_brightness" ]] || continue

    cur="$(<"${dir}/brightness")"
    max="$(<"${dir}/max_brightness")"

    if [[ "${cur}" =~ ^[0-9]+$ && "${max}" =~ ^[0-9]+$ ]] && (( max > 0 )); then
      percent=$(((100 * cur + (max / 2)) / max))
      printf '%d\n' "${percent}"
      return
    fi
  done

  printf -- '-1\n'
}

brightness_adjust() {
  local direction="${1:-up}"

  if command -v brightnessctl >/dev/null 2>&1; then
    if [[ "${direction}" == "up" ]]; then
      brightnessctl -n2 set +"${STEP_PCT}"% >/dev/null 2>&1 || brightnessctl set +"${STEP_PCT}"% >/dev/null 2>&1 || true
    else
      brightnessctl -n2 set "${STEP_PCT}"%- >/dev/null 2>&1 || brightnessctl set "${STEP_PCT}"%- >/dev/null 2>&1 || true
    fi
    overlay_emit
    return
  fi

  if command -v light >/dev/null 2>&1; then
    if [[ "${direction}" == "up" ]]; then
      light -A "${STEP_PCT}" >/dev/null 2>&1 || true
    else
      light -U "${STEP_PCT}" >/dev/null 2>&1 || true
    fi
    overlay_emit
    return
  fi

  # Fallback when no backlight utility is available.
  # Requires write access to /sys/class/backlight/*/brightness.
  local dir bfile mfile cur max delta next
  for dir in /sys/class/backlight/*; do
    [[ -d "${dir}" ]] || continue
    bfile="${dir}/brightness"
    mfile="${dir}/max_brightness"
    [[ -r "${bfile}" && -r "${mfile}" ]] || continue
    [[ -w "${bfile}" ]] || continue

    cur="$(<"${bfile}")"
    max="$(<"${mfile}")"
    [[ "${cur}" =~ ^[0-9]+$ && "${max}" =~ ^[0-9]+$ ]] || continue
    (( max > 0 )) || continue

    delta=$(( max * STEP_PCT / 100 ))
    (( delta < 1 )) && delta=1

    if [[ "${direction}" == "up" ]]; then
      next=$(( cur + delta ))
    else
      next=$(( cur - delta ))
    fi

    (( next < 1 )) && next=1
    (( next > max )) && next=max
    printf '%s\n' "${next}" > "${bfile}" 2>/dev/null || true
    overlay_emit
    return
  done
}

brightness_set() {
  local target="${1:-1}"

  [[ "${target}" =~ ^[0-9]+$ ]] || target=1
  (( target < 1 )) && target=1
  (( target > 100 )) && target=100

  if command -v brightnessctl >/dev/null 2>&1; then
    brightnessctl -n2 set "${target}"% >/dev/null 2>&1 || brightnessctl set "${target}"% >/dev/null 2>&1 || true
    overlay_emit
    return
  fi

  if command -v light >/dev/null 2>&1; then
    light -S "${target}" >/dev/null 2>&1 || true
    overlay_emit
    return
  fi

  local dir bfile mfile max next
  for dir in /sys/class/backlight/*; do
    [[ -d "${dir}" ]] || continue
    bfile="${dir}/brightness"
    mfile="${dir}/max_brightness"
    [[ -r "${mfile}" ]] || continue
    [[ -w "${bfile}" ]] || continue

    max="$(<"${mfile}")"
    [[ "${max}" =~ ^[0-9]+$ ]] || continue
    (( max > 0 )) || continue

    next=$(((max * target + 50) / 100))
    (( next < 1 )) && next=1
    (( next > max )) && next=max
    printf '%s\n' "${next}" > "${bfile}" 2>/dev/null || true
    overlay_emit
    return
  done
}

case "${1:-get}" in
  get)
    brightness_text
    ;;
  up)
    brightness_adjust up
    ;;
  down)
    brightness_adjust down
    ;;
  set)
    brightness_set "${2:-1}"
    ;;
  *)
    printf 'Usage: %s {get|up|down|set <percent>}\n' "$0" >&2
    exit 2
    ;;
esac
