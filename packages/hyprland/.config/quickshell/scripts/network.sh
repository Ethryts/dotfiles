#!/usr/bin/env bash
set -euo pipefail

network_text() {
  local wifi_signal ethernet

  if command -v nmcli >/dev/null 2>&1; then
    ethernet="$(nmcli -t -f DEVICE,TYPE,STATE dev status 2>/dev/null | awk -F: '$2=="ethernet" && $3=="connected"{print $1; exit}' || true)"
    if [[ -n "${ethernet}" ]]; then
      printf 'ethernet\n'
      return
    fi

    wifi_signal="$(nmcli -t -f active,signal dev wifi 2>/dev/null | awk -F: '$1=="yes"{print $2; exit}' || true)"
    if [[ -n "${wifi_signal}" ]]; then
      printf 'wifi:%s\n' "${wifi_signal}"
      return
    fi
  fi

  if ip route get 1.1.1.1 >/dev/null 2>&1; then
    printf 'ethernet\n'
  else
    printf 'offline\n'
  fi
}

split_escaped_fields() {
  local input="$1"
  local current=""
  local escaped=0
  local index char

  SPLIT_FIELDS=()

  for (( index = 0; index < ${#input}; ++index )); do
    char="${input:index:1}"

    if (( escaped )); then
      current+="${char}"
      escaped=0
      continue
    fi

    if [[ "${char}" == "\\" ]]; then
      escaped=1
      continue
    fi

    if [[ "${char}" == ":" ]]; then
      SPLIT_FIELDS+=("${current}")
      current=""
      continue
    fi

    current+="${char}"
  done

  SPLIT_FIELDS+=("${current}")
}

wifi_device_name() {
  local line

  while IFS= read -r line; do
    [[ -n "${line}" ]] || continue
    split_escaped_fields "${line}"
    if [[ "${SPLIT_FIELDS[1]:-}" == "wifi" ]]; then
      printf '%s\n' "${SPLIT_FIELDS[0]}"
      return
    fi
  done < <(nmcli -t -e yes -f DEVICE,TYPE,STATE dev status 2>/dev/null || true)
}

build_saved_wifi_map() {
  declare -gA SAVED_WIFI_BY_SSID=()
  local line uuid ssid

  while IFS= read -r line; do
    [[ -n "${line}" ]] || continue
    split_escaped_fields "${line}"
    [[ "${SPLIT_FIELDS[1]:-}" == "802-11-wireless" ]] || continue
    uuid="${SPLIT_FIELDS[0]:-}"
    [[ -n "${uuid}" ]] || continue
    ssid="$(nmcli -g 802-11-wireless.ssid connection show uuid "${uuid}" 2>/dev/null | head -n 1 || true)"
    [[ -n "${ssid}" ]] || continue
    SAVED_WIFI_BY_SSID["${ssid}"]="${uuid}"
  done < <(nmcli -t -e yes -f UUID,TYPE connection show 2>/dev/null || true)
}

network_details() {
  local wifi_line wifi_signal wifi_name ethernet_name line

  if command -v nmcli >/dev/null 2>&1; then
    ethernet_name="$(nmcli -t -f DEVICE,TYPE,STATE dev status 2>/dev/null | awk -F: '$2=="ethernet" && $3=="connected"{print $1; exit}' || true)"
    if [[ -n "${ethernet_name}" ]]; then
      printf 'ethernet\t%s\n' "${ethernet_name}"
      return
    fi

    while IFS= read -r line; do
      [[ -n "${line}" ]] || continue
      split_escaped_fields "${line}"
      if [[ "${SPLIT_FIELDS[0]:-}" == "yes" ]]; then
        wifi_name="${SPLIT_FIELDS[1]:-Wi-Fi}"
        wifi_signal="${SPLIT_FIELDS[2]:-0}"
        wifi_line="yes"
        break
      fi
    done < <(nmcli -t -e yes -f active,ssid,signal dev wifi 2>/dev/null || true)

    if [[ -n "${wifi_line:-}" ]]; then
      printf 'wifi\t%s\t%s\n' "${wifi_name:-Wi-Fi}" "${wifi_signal:-0}"
      return
    fi
  fi

  if ip route get 1.1.1.1 >/dev/null 2>&1; then
    printf 'ethernet\tConnected\n'
  else
    printf 'offline\tOffline\n'
  fi
}

network_list() {
  local line in_use bssid ssid signal security active saved security_kind connectable details current_kind current_name current_signal
  declare -A BEST_SIGNAL=()
  declare -A BEST_BSSID=()
  declare -A BEST_ACTIVE=()
  declare -A BEST_SECURITY=()

  if ! command -v nmcli >/dev/null 2>&1; then
    network_details
    return
  fi

  details="$(network_details)"
  IFS=$'\t' read -r current_kind current_name current_signal <<< "${details}"
  printf 'current\t%s\t%s\t%s\n' "${current_kind:-offline}" "${current_name:-Offline}" "${current_signal:-}"

  build_saved_wifi_map

  while IFS= read -r line; do
    [[ -n "${line}" ]] || continue
    split_escaped_fields "${line}"

    in_use="${SPLIT_FIELDS[0]:-}"
    bssid="${SPLIT_FIELDS[1]:-}"
    ssid="${SPLIT_FIELDS[2]:-}"
    signal="${SPLIT_FIELDS[3]:-0}"
    security="${SPLIT_FIELDS[4]:-}"

    [[ -n "${ssid}" ]] || ssid="Hidden network"
    [[ "${signal}" =~ ^[0-9]+$ ]] || signal=0

    if [[ -v BEST_SIGNAL["${ssid}"] ]] && (( signal < BEST_SIGNAL["${ssid}"] )) && [[ "${in_use}" != "*" ]]; then
      continue
    fi

    BEST_SIGNAL["${ssid}"]="${signal}"
    BEST_BSSID["${ssid}"]="${bssid}"
    BEST_ACTIVE["${ssid}"]="${in_use}"
    BEST_SECURITY["${ssid}"]="${security}"
  done < <(nmcli -t -e yes -f IN-USE,BSSID,SSID,SIGNAL,SECURITY dev wifi list --rescan auto 2>/dev/null || true)

  for ssid in "${!BEST_SIGNAL[@]}"; do
    active="no"
    saved="no"
    security_kind="secured"
    connectable="no"

    [[ "${BEST_ACTIVE["${ssid}"]}" == "*" ]] && active="yes"
    [[ -n "${SAVED_WIFI_BY_SSID["${ssid}"]:-}" ]] && saved="yes"

    security="${BEST_SECURITY["${ssid}"]}"
    if [[ -z "${security}" || "${security}" == "--" ]]; then
      security_kind="open"
      connectable="yes"
    elif [[ "${saved}" == "yes" ]]; then
      connectable="yes"
    fi

    printf 'network\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' \
      "${active}" \
      "${saved}" \
      "${security_kind}" \
      "${ssid}" \
      "${BEST_BSSID["${ssid}"]}" \
      "${BEST_SIGNAL["${ssid}"]}" \
      "${security}" \
      "${connectable}"
  done | sort
}

network_connect() {
  local ssid="${1:-}"
  local bssid="${2:-}"
  local saved="${3:-no}"
  local open_network="${4:-no}"
  local wifi_device saved_uuid

  [[ -n "${ssid}" ]] || {
    printf 'error\tMissing SSID\n'
    return
  }

  if ! command -v nmcli >/dev/null 2>&1; then
    printf 'error\tNetworkManager tools are unavailable\n'
    return
  fi

  build_saved_wifi_map
  saved_uuid="${SAVED_WIFI_BY_SSID["${ssid}"]:-}"
  wifi_device="$(wifi_device_name)"

  if [[ -n "${saved_uuid}" && ( "${saved}" == "yes" || "${open_network}" != "yes" ) ]]; then
    if nmcli --wait 10 connection up uuid "${saved_uuid}" >/dev/null 2>&1; then
      printf 'ok\tConnected to %s\n' "${ssid}"
      return
    fi
  fi

  if [[ "${open_network}" == "yes" && -n "${wifi_device}" ]]; then
    if [[ -n "${bssid}" ]]; then
      if nmcli --wait 10 device wifi connect "${ssid}" ifname "${wifi_device}" bssid "${bssid}" >/dev/null 2>&1; then
        printf 'ok\tConnected to %s\n' "${ssid}"
        return
      fi
    elif nmcli --wait 10 device wifi connect "${ssid}" ifname "${wifi_device}" >/dev/null 2>&1; then
      printf 'ok\tConnected to %s\n' "${ssid}"
      return
    fi
  fi

  if [[ "${saved}" != "yes" && "${open_network}" != "yes" ]]; then
    printf 'needs-auth\tSaved password required in Network Settings\n'
    return
  fi

  printf 'error\tUnable to connect to %s\n' "${ssid}"
}

case "${1:-get}" in
  get)
    network_text
    ;;
  details)
    network_details
    ;;
  list)
    network_list
    ;;
  connect)
    network_connect "${2:-}" "${3:-}" "${4:-no}" "${5:-no}"
    ;;
  *)
    printf 'Usage: %s {get|details|list|connect <ssid> <bssid> <saved> <open>}\n' "$0" >&2
    exit 2
    ;;
esac
