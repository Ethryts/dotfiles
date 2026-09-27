#!/usr/bin/env bash
set -euo pipefail

sanitize_message() {
  local input="${1:-}"
  input="${input//$'\t'/ }"
  input="${input//$'\n'/ }"
  printf '%s\n' "${input}" | sed 's/[[:space:]]\+/ /g; s/^ //; s/ $//'
}

flush_profile() {
  local profile_id="${1:-}"
  local active="${2:-no}"
  local degraded="${3:-no}"
  local degraded_reason="${4:-}"
  local cpu_driver="${5:-}"
  local platform_driver="${6:-}"

  [[ -n "${profile_id}" ]] || return 0

  printf 'profile\t%s\t%s\t%s\t%s\t%s\t%s\n' \
    "${profile_id}" \
    "${active}" \
    "${degraded}" \
    "${degraded_reason}" \
    "${cpu_driver}" \
    "${platform_driver}"
}

list_profiles() {
  local output line current_id="" current_active="no" current_degraded="no" current_degraded_reason="" current_cpu="" current_platform=""

  if ! command -v powerprofilesctl >/dev/null 2>&1; then
    printf 'error\tpowerprofilesctl is not installed\n'
    return
  fi

  if ! output="$(powerprofilesctl list 2>&1)"; then
    printf 'error\t%s\n' "$(sanitize_message "${output}")"
    return
  fi

  while IFS= read -r line; do
    [[ -n "${line}" ]] || continue

    if [[ "${line}" =~ ^[[:space:]]*\*?[[:space:]]*([[:alnum:]-]+):[[:space:]]*$ ]]; then
      flush_profile "${current_id}" "${current_active}" "${current_degraded}" "${current_degraded_reason}" "${current_cpu}" "${current_platform}"
      if [[ "${line}" == *"*"* ]]; then
        current_active="yes"
      else
        current_active="no"
      fi
      current_id="${BASH_REMATCH[1]}"
      current_degraded="no"
      current_degraded_reason=""
      current_cpu=""
      current_platform=""
      continue
    fi

    if [[ "${line}" =~ ^[[:space:]]*CpuDriver:[[:space:]]*(.+)$ ]]; then
      current_cpu="${BASH_REMATCH[1]}"
      continue
    fi

    if [[ "${line}" =~ ^[[:space:]]*PlatformDriver:[[:space:]]*(.+)$ ]]; then
      current_platform="${BASH_REMATCH[1]}"
      continue
    fi

    if [[ "${line}" =~ ^[[:space:]]*Degraded:[[:space:]]*(.+)$ ]]; then
      current_degraded_reason="${BASH_REMATCH[1]}"
      if [[ "${current_degraded_reason}" == "no" ]]; then
        current_degraded="no"
        current_degraded_reason=""
      else
        current_degraded="yes"
      fi
    fi
  done <<< "${output}"

  flush_profile "${current_id}" "${current_active}" "${current_degraded}" "${current_degraded_reason}" "${current_cpu}" "${current_platform}"
}

set_profile() {
  local profile_id="${1:-}"
  local output

  if ! command -v powerprofilesctl >/dev/null 2>&1; then
    printf 'error\tpowerprofilesctl is not installed\n'
    return
  fi

  if [[ -z "${profile_id}" ]]; then
    printf 'error\tMissing profile id\n'
    return
  fi

  if ! output="$(powerprofilesctl set "${profile_id}" 2>&1)"; then
    printf 'error\t%s\n' "$(sanitize_message "${output}")"
    return
  fi

  printf 'ok\t%s\n' "${profile_id}"
}

case "${1:-list}" in
  list)
    list_profiles
    ;;
  set)
    set_profile "${2:-}"
    ;;
  *)
    printf 'Usage: %s {list|set <profile>}\n' "$0" >&2
    exit 2
    ;;
esac
