#!/usr/bin/env bash
set -euo pipefail

workspace_name="$(hyprctl activewindow -j | jq -r '.workspace.name // ""')"

case "$workspace_name" in
  special:media|special:chat|special:steam)
    hyprctl dispatch togglespecialworkspace "${workspace_name#special:}"
    ;;
  *)
    hyprctl dispatch killactive
    ;;
esac
