#!/usr/bin/env bash
set -euo pipefail

workspace_name="${1:?special workspace name required}"

hyprctl dispatch setfloating active
hyprctl dispatch movetoworkspace "special:${workspace_name}"
