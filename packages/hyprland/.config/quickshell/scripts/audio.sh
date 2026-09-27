#!/usr/bin/env bash
set -euo pipefail

STEP_PCT=1

trim() {
  local value="${1-}"
  value="${value#"${value%%[![:space:]]*}"}"
  value="${value%"${value##*[![:space:]]}"}"
  printf '%s' "${value}"
}

json_escape() {
  local value="${1-}"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\n'/\\n}"
  value="${value//$'\r'/\\r}"
  value="${value//$'\t'/\\t}"
  printf '%s' "${value}"
}

json_bool() {
  if [[ "${1:-no}" == "yes" ]]; then
    printf 'true'
  else
    printf 'false'
  fi
}

overlay_emit() {
  local kind="$1"
  local value="$2"

  quickshell ipc call overlay "${kind}" "${value}" >/dev/null 2>&1 || true
}

device_lines_wpctl() {
  wpctl status 2>/dev/null | awk '
    /^Audio$/ { media="audio"; section=""; next }
    /^Video$/ { media="video"; section=""; next }
    /^Settings$/ { media="settings"; section=""; next }
    media == "audio" && /Sinks:/ { section="output"; next }
    media == "audio" && /Sources:/ { section="input"; next }
    media == "audio" && (/Devices:/ || /Filters:/ || /Streams:/) { section=""; next }
    media == "audio" && (section == "output" || section == "input") {
      active = ($0 ~ /\*/) ? "yes" : "no"
      line = $0
      if (match(line, /[0-9]+\.[[:space:]]+/)) {
        id_part = substr(line, RSTART, RLENGTH)
        gsub(/[^0-9]/, "", id_part)
        label = substr(line, RSTART + RLENGTH)
        sub(/[[:space:]]+\[[^]]*\][[:space:]]*$/, "", label)
        gsub(/^[[:space:]]+|[[:space:]]+$/, "", label)
        printf "%s\t%s\t%s\t%s\n", section, id_part, active, label
      }
    }
  '
}

device_label_from_lines() {
  local wanted_kind="$1"
  local wanted_id="$2"
  local lines="$3"
  local kind id active label

  while IFS=$'\t' read -r kind id active label; do
    [[ -n "${kind}" ]] || continue

    if [[ "${kind}" == "${wanted_kind}" && "${id}" == "${wanted_id}" ]]; then
      printf '%s' "${label}"
      return 0
    fi
  done <<< "${lines}"

  return 1
}

node_name_for_id() {
  local id="$1"

  wpctl inspect "${id}" 2>/dev/null | awk -F' = ' '
    $1 ~ /^[[:space:]]*\*?[[:space:]]*node\.name$/ {
      value = $2
      gsub(/^"|"$/, "", value)
      print value
      exit
    }
  '
}

move_existing_streams() {
  local kind="$1"
  local id="$2"
  local target_name stream_id

  command -v pactl >/dev/null 2>&1 || return 0

  target_name="$(node_name_for_id "${id}")"
  [[ -n "${target_name}" ]] || return 0

  if [[ "${kind}" == "output" ]]; then
    while IFS=$'\t' read -r stream_id _; do
      [[ "${stream_id}" =~ ^[0-9]+$ ]] || continue
      pactl move-sink-input "${stream_id}" "${target_name}" >/dev/null 2>&1 || true
    done < <(pactl list short sink-inputs 2>/dev/null || true)
  elif [[ "${kind}" == "input" ]]; then
    while IFS=$'\t' read -r stream_id _; do
      [[ "${stream_id}" =~ ^[0-9]+$ ]] || continue
      pactl move-source-output "${stream_id}" "${target_name}" >/dev/null 2>&1 || true
    done < <(pactl list short source-outputs 2>/dev/null || true)
  fi
}

volume_state() {
  local raw volume percent muted

  if command -v wpctl >/dev/null 2>&1; then
    raw="$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null || true)"
    if [[ "${raw}" == *"Volume:"* ]]; then
      muted="no"
      [[ "${raw}" == *"[MUTED]"* ]] && muted="yes"
      volume="$(printf '%s\n' "${raw}" | awk '/Volume:/{print $2}' | head -n 1)"

      if [[ "${volume}" =~ ^[0-9]*\.?[0-9]+$ ]]; then
        percent="$(awk -v v="${volume}" 'BEGIN{printf "%d", (v * 100) + 0.5}')"
      else
        percent=0
      fi

      printf '%s %s\n' "${percent}" "${muted}"
      return
    fi
  fi

  if command -v pactl >/dev/null 2>&1; then
    raw="$(pactl get-sink-volume @DEFAULT_SINK@ 2>/dev/null | head -n 1 || true)"
    percent="$(printf '%s\n' "${raw}" | grep -oE '[0-9]+%' | head -n 1 | tr -d '%' || true)"
    muted="$(pactl get-sink-mute @DEFAULT_SINK@ 2>/dev/null | awk '{print $2}' || true)"

    if [[ "${percent}" =~ ^[0-9]+$ ]]; then
      printf '%s %s\n' "${percent}" "${muted:-no}"
      return
    fi
  fi

  printf '0 no\n'
}

audio_state_json() {
  local percent muted
  local device_lines=""
  local output_devices=""
  local input_devices=""
  local current_output_id=""
  local current_output_label=""
  local current_input_id=""
  local current_input_label=""
  local output_sep=""
  local input_sep=""
  local status_message=""
  local status_tone="info"
  local devices_available="false"
  local kind id active label entry

  read -r percent muted < <(volume_state)

  if command -v wpctl >/dev/null 2>&1; then
    device_lines="$(device_lines_wpctl || true)"

    if [[ -n "${device_lines}" ]]; then
      while IFS=$'\t' read -r kind id active label; do
        [[ -n "${kind}" ]] || continue
        entry="{\"id\":\"$(json_escape "${id}")\",\"label\":\"$(json_escape "${label}")\",\"active\":$(json_bool "${active}")}"

        if [[ "${kind}" == "output" ]]; then
          output_devices+="${output_sep}${entry}"
          output_sep=","
          if [[ "${active}" == "yes" ]]; then
            current_output_id="${id}"
            current_output_label="${label}"
          fi
        elif [[ "${kind}" == "input" ]]; then
          input_devices+="${input_sep}${entry}"
          input_sep=","
          if [[ "${active}" == "yes" ]]; then
            current_input_id="${id}"
            current_input_label="${label}"
          fi
        fi
      done <<< "${device_lines}"
    else
      status_message="Unable to read PipeWire audio devices"
      status_tone="warning"
    fi
  else
    status_message="Audio device switching requires wpctl"
    status_tone="warning"
  fi

  if [[ -n "${output_devices}" || -n "${input_devices}" ]]; then
    devices_available="true"
  fi

  printf '{'
  printf '"volumePercent":%s,' "${percent}"
  printf '"muted":%s,' "$(json_bool "${muted}")"
  printf '"currentOutputId":"%s",' "$(json_escape "${current_output_id}")"
  printf '"currentOutputLabel":"%s",' "$(json_escape "${current_output_label}")"
  printf '"currentInputId":"%s",' "$(json_escape "${current_input_id}")"
  printf '"currentInputLabel":"%s",' "$(json_escape "${current_input_label}")"
  printf '"devicesAvailable":%s,' "${devices_available}"
  printf '"statusMessage":"%s",' "$(json_escape "${status_message}")"
  printf '"statusTone":"%s",' "$(json_escape "${status_tone}")"
  printf '"outputDevices":[%s],' "${output_devices}"
  printf '"inputDevices":[%s]' "${input_devices}"
  printf '}\n'
}

emit_volume_overlay() {
  local percent muted

  read -r percent muted < <(volume_state)

  if [[ "${muted}" == "yes" ]]; then
    overlay_emit mute 1
  else
    overlay_emit volume "${percent}"
  fi
}

volume_status() {
  volume_state
}

volume_text() {
  local raw volume percent muted icon

  if command -v wpctl >/dev/null 2>&1; then
    raw="$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null || true)"
    if [[ "${raw}" == *"Volume:"* ]]; then
      muted="no"
      [[ "${raw}" == *"[MUTED]"* ]] && muted="yes"
      volume="$(printf '%s\n' "${raw}" | awk '/Volume:/{print $2}' | head -n 1)"

      if [[ "${volume}" =~ ^[0-9]*\.?[0-9]+$ ]]; then
        percent="$(awk -v v="${volume}" 'BEGIN{printf "%d", (v * 100) + 0.5}')"
      else
        percent=0
      fi

      if [[ "${muted}" == "yes" ]]; then
        printf '\n'
      else
        if (( percent < 34 )); then
          icon=""
        elif (( percent < 67 )); then
          icon=""
        else
          icon=""
        fi

        printf '%s %d%%\n' "${icon}" "${percent}"
      fi
      return
    fi
  fi

  if command -v pactl >/dev/null 2>&1; then
    raw="$(pactl get-sink-volume @DEFAULT_SINK@ 2>/dev/null | head -n 1 || true)"
    percent="$(printf '%s\n' "${raw}" | grep -oE '[0-9]+%' | head -n 1 | tr -d '%' || true)"
    muted="$(pactl get-sink-mute @DEFAULT_SINK@ 2>/dev/null | awk '{print $2}' || true)"

    if [[ "${muted}" == "yes" ]]; then
      printf '\n'
      return
    fi

    if [[ "${percent}" =~ ^[0-9]+$ ]]; then
      if (( percent < 34 )); then
        icon=""
      elif (( percent < 67 )); then
        icon=""
      else
        icon=""
      fi

      printf '%s %d%%\n' "${icon}" "${percent}"
      return
    fi
  fi

  printf ' --%%\n'
}

set_default_device() {
  local kind="$1"
  local id="${2:-}"
  local device_lines label noun

  noun="output"
  [[ "${kind}" == "input" ]] && noun="input"

  if [[ ! "${id}" =~ ^[0-9]+$ ]]; then
    printf 'error\tInvalid audio %s\n' "${noun}"
    return
  fi

  if ! command -v wpctl >/dev/null 2>&1; then
    printf 'error\tAudio device switching requires wpctl\n'
    return
  fi

  device_lines="$(device_lines_wpctl || true)"
  label="$(device_label_from_lines "${kind}" "${id}" "${device_lines}" || true)"

  if [[ -z "${label}" ]]; then
    printf 'error\tAudio %s not found\n' "${noun}"
    return
  fi

  if wpctl set-default "${id}" >/dev/null 2>&1; then
    move_existing_streams "${kind}" "${id}"
    printf 'ok\t%s\t%s\n' "${kind}" "${label}"
  else
    printf 'error\tUnable to switch audio %s\n' "${noun}"
  fi
}

volume_adjust() {
  local direction="${1:-up}"
  local adjusted=0

  if command -v wpctl >/dev/null 2>&1; then
    if [[ "${direction}" == "up" ]]; then
      if wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ "${STEP_PCT}"%+ >/dev/null 2>&1; then
        adjusted=1
      fi
    else
      if wpctl set-volume @DEFAULT_AUDIO_SINK@ "${STEP_PCT}"%- >/dev/null 2>&1; then
        adjusted=1
      fi
    fi
  fi

  if (( adjusted == 0 )) && command -v pactl >/dev/null 2>&1; then
    if [[ "${direction}" == "up" ]]; then
      pactl set-sink-volume @DEFAULT_SINK@ +"${STEP_PCT}"% >/dev/null 2>&1 || true
    else
      pactl set-sink-volume @DEFAULT_SINK@ -"${STEP_PCT}"% >/dev/null 2>&1 || true
    fi
  fi

  emit_volume_overlay
}

volume_set() {
  local target="${1:-0}"
  local applied=0

  [[ "${target}" =~ ^[0-9]+$ ]] || target=0
  (( target < 0 )) && target=0
  (( target > 100 )) && target=100

  if command -v wpctl >/dev/null 2>&1; then
    if wpctl set-volume -l 1.0 @DEFAULT_AUDIO_SINK@ "$(awk -v v="${target}" 'BEGIN{printf "%.2f", v / 100}')" >/dev/null 2>&1; then
      applied=1
    fi
  fi

  if (( applied == 0 )) && command -v pactl >/dev/null 2>&1; then
    pactl set-sink-volume @DEFAULT_SINK@ "${target}"% >/dev/null 2>&1 || true
  fi

  emit_volume_overlay
}

volume_mute_toggle() {
  if command -v wpctl >/dev/null 2>&1; then
    if wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle >/dev/null 2>&1; then
      emit_volume_overlay
      return
    fi
  fi

  if command -v pactl >/dev/null 2>&1; then
    pactl set-sink-mute @DEFAULT_SINK@ toggle >/dev/null 2>&1 || true
  fi

  emit_volume_overlay
}

case "${1:-get}" in
  get)
    volume_text
    ;;
  state)
    audio_state_json
    ;;
  up)
    volume_adjust up
    ;;
  down)
    volume_adjust down
    ;;
  set)
    volume_set "${2:-0}"
    ;;
  mute)
    volume_mute_toggle
    ;;
  set-output)
    set_default_device output "${2:-}"
    ;;
  set-input)
    set_default_device input "${2:-}"
    ;;
  *)
    printf 'Usage: %s {get|state|up|down|set <percent>|mute|set-output <id>|set-input <id>}\n' "$0" >&2
    exit 2
    ;;
esac
