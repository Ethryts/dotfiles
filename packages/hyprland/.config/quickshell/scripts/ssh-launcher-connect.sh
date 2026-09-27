#!/usr/bin/env bash
set -euo pipefail

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

HOST_ALIAS="${1:-}"
HOST_LABEL="${2:-${HOST_ALIAS}}"
LOG_FILE="/tmp/quickshell-ssh-launcher.log"

resolve_ssh_auth_sock() {
  local candidate=""
  local runtime_dir="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"

  if [[ -n "${SSH_AUTH_SOCK:-}" && -S "${SSH_AUTH_SOCK}" ]]; then
    return 0
  fi

  if command -v systemctl >/dev/null 2>&1; then
    candidate="$(
      systemctl --user show-environment 2>/dev/null \
        | awk -F= '$1 == "SSH_AUTH_SOCK" { print substr($0, index($0, "=") + 1); exit }' \
        || true
    )"

    if [[ -n "${candidate}" && -S "${candidate}" ]]; then
      export SSH_AUTH_SOCK="${candidate}"
      return 0
    fi
  fi

  for candidate in \
    "${runtime_dir}/ssh/agent.sock" \
    /tmp/ssh-*/agent.*; do
    if [[ -S "${candidate}" ]]; then
      export SSH_AUTH_SOCK="${candidate}"
      return 0
    fi
  done

  if command -v gpgconf >/dev/null 2>&1; then
    candidate="$(gpgconf --list-dirs agent-ssh-socket 2>/dev/null || true)"

    if [[ -n "${candidate}" && -S "${candidate}" ]]; then
      export SSH_AUTH_SOCK="${candidate}"
      return 0
    fi
  fi

  return 1
}

notify_failure() {
  local message="${1:-SSH launcher failed}"

  if command -v notify-send >/dev/null 2>&1; then
    notify-send "SSH Launcher" "${message}" >/dev/null 2>&1 || true
  fi
}

if [[ -z "${HOST_ALIAS}" ]]; then
  notify_failure "Missing SSH host alias."
  exit 1
fi

KITTY_BIN="$(command -v kitty || true)"
if [[ -z "${KITTY_BIN}" ]]; then
  notify_failure "kitty is not available in PATH."
  exit 1
fi

resolve_ssh_auth_sock || true

if ! nohup setsid "${KITTY_BIN}" \
  --detach \
  --title "SSH: ${HOST_LABEL}" \
  ssh "${HOST_ALIAS}" >> "${LOG_FILE}" 2>&1 < /dev/null & then
  notify_failure "Could not start kitty for ${HOST_ALIAS}."
  exit 1
fi
