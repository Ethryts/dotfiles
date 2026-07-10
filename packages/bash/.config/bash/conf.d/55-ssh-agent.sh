# Unify SSH agent across shells.
# - Prefer an existing agent (systemd/desktop) if SSH_AUTH_SOCK already works.
# - Otherwise start our own agent with a stable socket path.

[[ $- != *i* ]] && return

have() { command -v "$1" >/dev/null 2>&1; }

# Quick check: does current SSH_AUTH_SOCK point to a working agent?
agent_works() { ssh-add -l >/dev/null 2>&1; }

# If we already have a working agent, do nothing.
if agent_works; then
  return
fi

# Choose a stable socket path.
# Prefer XDG_RUNTIME_DIR (best), else fall back to XDG_CACHE_HOME.
SOCK_DIR="${XDG_RUNTIME_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}}/ssh"
SOCK_PATH="$SOCK_DIR/agent.sock"
mkdir -p "$SOCK_DIR"

# If a socket exists and talking to it works, use it.
export SSH_AUTH_SOCK="$SOCK_PATH"
if agent_works; then
  return
fi

# Socket exists but dead → remove it.
if [[ -S "$SOCK_PATH" ]]; then
  rm -f "$SOCK_PATH"
fi

# Start a new agent bound to our stable socket.
if have ssh-agent; then
  # Start agent and export env vars for this shell
  eval "$(ssh-agent -a "$SOCK_PATH" -s)" >/dev/null

  if have ssh-add; then
    # Add the default keys if they exist
    ssh-add -q "$HOME/.ssh/id_ed25519" "$HOME/.ssh/id_rsa" 2>/dev/null || true
  fi
fi
