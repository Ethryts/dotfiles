#!/usr/bin/env bash
set -euo pipefail

# Ensure tools are resolvable when launched from desktop sessions.
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

OSK_SCRIPT="${HOME}/.config/hypr/scripts/osk_control.sh"
SERVICE_NAME="mobi.phosh.OSK.service"

read_osk_policy() {
  local json text class policy

  if [[ -x "${OSK_SCRIPT}" ]]; then
    json="$(${OSK_SCRIPT} status 2>/dev/null || true)"
    text="$(printf '%s' "${json}" | sed -n 's/.*"text":"\([^"]*\)".*/\1/p')"
    class="$(printf '%s' "${json}" | sed -n 's/.*"class":"\([^"]*\)".*/\1/p')"

    if [[ -n "${class}" || -n "${text}" ]]; then
      if [[ "${class}" == *"off"* || "${text}" == *"OFF"* ]]; then
        policy="off"
      else
        policy="auto"
      fi

      printf '%s\n' "${policy}"
      return
    fi
  fi

  printf 'off\n'
}

get_osk_state() {
  local json text tooltip class policy

  if [[ -x "${OSK_SCRIPT}" ]]; then
    json="$(${OSK_SCRIPT} status 2>/dev/null || true)"
    text="$(printf '%s' "${json}" | sed -n 's/.*"text":"\([^"]*\)".*/\1/p')"
    tooltip="$(printf '%s' "${json}" | sed -n 's/.*"tooltip":"\([^"]*\)".*/\1/p')"
    class="$(printf '%s' "${json}" | sed -n 's/.*"class":"\([^"]*\)".*/\1/p')"

    if [[ -n "${class}" || -n "${text}" ]]; then
      policy="$(read_osk_policy)"

      printf '{"policy":"%s","tooltip":"%s"}\n' "${policy}" "${tooltip}"
      return
    fi
  fi

  printf '{"policy":"off","tooltip":"On-screen keyboard unavailable."}\n'
}

toggle_osk() {
  if [[ -x "${OSK_SCRIPT}" ]]; then
    "${OSK_SCRIPT}" toggle >/dev/null 2>&1 || true
  fi
}

apply_osk() {
  if [[ -x "${OSK_SCRIPT}" ]]; then
    "${OSK_SCRIPT}" apply >/dev/null 2>&1 || true
  fi
}

apply_smart_osk() {
  local posture="${1:-laptop}"
  local screen_count="${2:-1}"
  local policy

  [[ "${screen_count}" =~ ^[0-9]+$ ]] || screen_count=1
  policy="$(read_osk_policy)"

  if [[ "${policy}" != "auto" ]]; then
    systemctl --user stop "${SERVICE_NAME}" >/dev/null 2>&1 || true
    return
  fi

  if [[ "${posture}" == "tablet" && "${screen_count}" -le 1 ]]; then
    apply_osk
    return
  fi

  systemctl --user stop "${SERVICE_NAME}" >/dev/null 2>&1 || true
}

case "${1:-get}" in
  get)
    get_osk_state
    ;;
  toggle)
    toggle_osk
    ;;
  apply)
    apply_osk
    ;;
  apply-smart)
    apply_smart_osk "${2:-laptop}" "${3:-1}"
    ;;
  *)
    printf 'Usage: %s {get|toggle|apply|apply-smart <posture> <screen-count>}\n' "$0" >&2
    exit 2
    ;;
esac
