#!/usr/bin/env bash
set -euo pipefail

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:${PATH:-}"

TRAY_SCRIPT="/usr/lib/hyprwhspr/config/hyprland/hyprwhspr-tray.sh"
STATE_DIR="${HOME}/.config/hyprwhspr"

json_escape() {
  printf '%s' "${1:-}" | sed ':a;N;$!ba;s/\\/\\\\/g;s/"/\\"/g;s/\n/\\n/g'
}

read_text() {
  local path="${1:-}"

  if [[ -r "${path}" ]]; then
    tr -d '\r' < "${path}" 2>/dev/null || true
    return
  fi

  printf ''
}

file_age_seconds() {
  local path="${1:-}"
  local modified now

  if [[ ! -e "${path}" ]]; then
    printf '9999'
    return
  fi

  modified="$(stat -c %Y "${path}" 2>/dev/null || printf '0')"
  now="$(date +%s)"
  printf '%s' "$((now - modified))"
}

status_json() {
  local tray_json tray_class visualizer_state visualizer_age longform_state recording_status
  local audio_level level_percent state label detail tone overlay_visible indeterminate
  local button_label button_icon button_tone toggle_enabled

  tray_json="$("${TRAY_SCRIPT}" status 2>/dev/null || true)"
  tray_class="$(printf '%s' "${tray_json}" | sed -n 's/.*"class":"\([^"]*\)".*/\1/p')"
  visualizer_state="$(read_text "${STATE_DIR}/visualizer_state")"
  visualizer_age="$(file_age_seconds "${STATE_DIR}/visualizer_state")"
  longform_state="$(read_text "${STATE_DIR}/longform_state")"
  recording_status="$(read_text "${STATE_DIR}/recording_status")"
  audio_level="$(read_text "${STATE_DIR}/audio_level")"
  level_percent="$(
    awk -v value="${audio_level:-0}" 'BEGIN {
      numeric = value + 0
      if (numeric < 0) {
        numeric = 0
      }
      if (numeric > 1) {
        numeric = 1
      }
      printf "%d", (numeric * 100) + 0.5
    }'
  )"

  state="${tray_class:-stopped}"

  if [[ "${longform_state}" == "PROCESSING" || "${visualizer_state}" == "processing" ]]; then
    state="processing"
  elif [[ "${longform_state}" == "PAUSED" || "${visualizer_state}" == "paused" ]]; then
    state="paused"
  elif [[ "${recording_status}" == "true" || "${longform_state}" == "RECORDING" || "${visualizer_state}" == "recording" ]]; then
    state="recording"
  elif [[ "${visualizer_state}" == "success" && "${visualizer_age}" -le 3 ]]; then
    state="success"
  elif [[ "${visualizer_state}" == "error" && "${visualizer_age}" -le 4 ]]; then
    state="error"
  fi

  overlay_visible=false
  indeterminate=false
  toggle_enabled=true
  tone="accent"
  label="Voice Typing"
  detail="Tap to start dictation"
  button_label="Talk"
  button_icon="󰍬"
  button_tone="muted"

  case "${state}" in
    recording)
      overlay_visible=true
      tone="accent"
      label="Listening"
      detail="Speak now, then tap again to type"
      button_label="Stop"
      button_icon=""
      button_tone="success"
      ;;
    processing)
      overlay_visible=true
      indeterminate=true
      tone="accent"
      label="Transcribing"
      detail="Turning speech into typed text"
      button_label="Wait"
      button_icon="󱎫"
      button_tone="accent"
      toggle_enabled=false
      ;;
    paused)
      overlay_visible=true
      tone="warning"
      label="Paused"
      detail="Tap again to continue dictation"
      button_label="Resume"
      button_icon="󰐊"
      button_tone="warning"
      level_percent=36
      ;;
    success)
      overlay_visible=true
      tone="success"
      label="Inserted"
      detail="Speech was typed into the focused app"
      button_label="Talk"
      button_icon="󰍬"
      button_tone="success"
      level_percent=100
      ;;
    ready)
      tone="success"
      label="Ready"
      detail="Voice typing is ready"
      button_label="Talk"
      button_icon="󰍬"
      button_tone="success"
      ;;
    error)
      tone="error"
      label="Microphone Issue"
      detail="Voice typing could not start cleanly"
      button_label="Retry"
      button_icon="󰍭"
      button_tone="error"
      level_percent=100
      ;;
    unloaded)
      tone="warning"
      label="Model Unloaded"
      detail="Restart hyprwhspr before dictating"
      button_label="Talk"
      button_icon="󰍭"
      button_tone="warning"
      level_percent=0
      ;;
    *)
      state="stopped"
      tone="muted"
      label="Voice Typing"
      detail="Tap to start dictation"
      button_label="Talk"
      button_icon="󰍬"
      button_tone="muted"
      level_percent=0
      ;;
  esac

  printf '{"state":"%s","label":"%s","detail":"%s","tone":"%s","overlayVisible":%s,"indeterminate":%s,"progress":%s,"buttonLabel":"%s","buttonIcon":"%s","buttonTone":"%s","toggleEnabled":%s}\n' \
    "$(json_escape "${state}")" \
    "$(json_escape "${label}")" \
    "$(json_escape "${detail}")" \
    "$(json_escape "${tone}")" \
    "${overlay_visible}" \
    "${indeterminate}" \
    "${level_percent}" \
    "$(json_escape "${button_label}")" \
    "$(json_escape "${button_icon}")" \
    "$(json_escape "${button_tone}")" \
    "${toggle_enabled}"
}

stop_recording() {
  local control_file="${STATE_DIR}/recording_control"

  if [[ -p "${control_file}" || -w "${control_file}" ]]; then
    printf 'stop\n' > "${control_file}" 2>/dev/null || true
    return
  fi

  "${TRAY_SCRIPT}" record >/dev/null 2>&1 || true
}

case "${1:-status}" in
  status)
    status_json
    ;;
  record)
    "${TRAY_SCRIPT}" record >/dev/null 2>&1 || true
    ;;
  stop)
    stop_recording
    ;;
  restart)
    "${TRAY_SCRIPT}" restart >/dev/null 2>&1 || true
    ;;
  *)
    printf 'Usage: %s {status|record|stop|restart}\n' "$0" >&2
    exit 2
    ;;
esac
