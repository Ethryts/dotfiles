#!/usr/bin/env bash
set -euo pipefail

NVIM_BIN="${NVIM_BIN:-nvim}"
IMAGEUI_TEST_TMP="${IMAGEUI_TEST_TMP:-$(mktemp -d -t imageui.nvim-test.XXXXXX)}"
export IMAGEUI_TEST_TMP
export NVIM_LOG_FILE="${NVIM_LOG_FILE:-$IMAGEUI_TEST_TMP/nvim.log}"
export XDG_CACHE_HOME="${XDG_CACHE_HOME:-$IMAGEUI_TEST_TMP/xdg-cache}"
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$IMAGEUI_TEST_TMP/xdg-config}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$IMAGEUI_TEST_TMP/xdg-data}"
export XDG_STATE_HOME="${XDG_STATE_HOME:-$IMAGEUI_TEST_TMP/xdg-state}"
cd "$(dirname "$0")/.."
"$NVIM_BIN" --headless -u tests/minimal_init.lua -l tests/run.lua
