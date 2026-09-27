#/bin/bash
_work_slug() {
    local value
    value="$(printf '%s' "$1" | LC_ALL=C tr -c 'A-Za-z0-9_-' '-')"
    case "$value" in ''|-*) value="work-$value" ;; esac
    printf '%s' "$value"
}

local root first primary repo tree name legacy sid candidate existing
local client digest

if [ "$#" -gt 1 ]; then
    printf 'Usage: work [session-name]\n' >&2
    return 2
fi
command -v tmux >/dev/null 2>&1 || {
    printf 'work: tmux is not installed\n' >&2
    return 1
}

# The sentinel preserves trailing newlines until we can reject control
# characters explicitly, rather than accidentally using a different path.
root="$(git rev-parse --show-toplevel 2>/dev/null && printf '.')" || {
    printf 'work: not inside a Git worktree\n' >&2
    return 1
}
root="${root%.}"
root="${root%$'\n'}"
case "$root" in *$'\n'*|*$'\r'*|*$'\t'*)
    printf 'work: tabs/newlines in worktree paths are not supported\n' >&2
    return 1 ;;
esac

# The first record identifies the primary checkout (or the bare repository),
# not the .git/worktrees/<id> metadata directory of a linked checkout.
IFS= read -r -d '' first < <(git -C "$root" worktree list --porcelain -z) || return 1
case "$first" in
    'worktree '*) primary="${first#worktree }" ;;
    *) printf 'work: cannot identify the primary repository\n' >&2; return 1 ;;
esac
repo="${primary##*/}"
case "$repo" in
    .bare|.git) repo="${primary%/*}"; repo="${repo##*/}" ;;
    *.git) repo="${repo%.git}" ;;
esac
if [ "$root" = "$primary" ]; then tree=main; else tree="${root##*/}"; fi
name="$(_work_slug "${1:-$repo-$tree}")"

# Capture the originating client BEFORE creating a detached session.
client="${WORK_TMUX_CLIENT:-}"
if [ -n "${TMUX:-}" ] && [ -z "$client" ] && [ -n "${TMUX_PANE:-}" ]; then
    client="$(tmux display-message -p -t "$TMUX_PANE" '#{client_name}' 2>/dev/null)" || client=
fi

# A session renamed by the user still belongs to the same worktree.
sid=
while IFS= read -r candidate; do
    existing="$(tmux show-options -qv -t "$candidate" @worktree_root 2>/dev/null)" || existing=
    if [ "$existing" = "$root" ]; then sid="$candidate"; break; fi
done < <(tmux list-sessions -F '#{session_id}' 2>/dev/null)

# Adopt sessions made by the user's original work() without restarting any
# windows. Only the exact legacy name AND original session directory match.
legacy="${root##*/}"
if [ -z "$sid" ] && tmux has-session -t "=$legacy" 2>/dev/null; then
    existing="$(tmux display-message -p -t "=$legacy" '#{session_path}' 2>/dev/null)" || existing=
    if [ "$existing" = "$root" ]; then
        sid="$(tmux display-message -p -t "=$legacy" '#{session_id}')" || return 1
        tmux set-option -t "$sid" @worktree_root "$root" \; \
             set-option -t "$sid" @worktree_ready 1 || return 1
        if ! tmux has-session -t "=$name" 2>/dev/null; then
            tmux rename-session -t "$sid" "$name" || return 1
        fi
    fi
fi

if [ -z "$sid" ]; then
    # Same-named clones / sanitized names must not reuse an unrelated session.
    if tmux has-session -t "=$name" 2>/dev/null; then
        if [ "$#" -eq 1 ]; then
            printf 'work: session name is already in use: %s\n' "$name" >&2
            return 1
        fi
        digest="$(printf '%s' "$root" | git hash-object --stdin)" || return 1
        name="$name-${digest:0:8}"
        if tmux has-session -t "=$name" 2>/dev/null; then
            printf 'work: session name collision: %s\n' "$name" >&2
            return 1
        fi
    fi

    # work owns session creation. The picker must not create it first.
    sid="$(tmux new-session -d -P -F '#{session_id}' -s "$name" \
        -n nvim -c "$root" -e NVIM= -e NVIM_LISTEN_ADDRESS=)" || return 1

    # One tmux command queue initializes the layout. On failure we preserve
    # the partial session for inspection; we never kill a running editor.
    if ! tmux set-option -t "$sid" @worktree_root "$root" \; \
        set-option -t "$sid" @worktree_ready 0 \; \
        new-window -d -t "$sid:" -n agent  -c "$root" \; \
        new-window -d -t "$sid:" -n tests  -c "$root" \; \
        new-window -d -t "$sid:" -n server -c "$root" \; \
        new-window -d -t "$sid:" -n shell  -c "$root" \; \
        send-keys -l -t "$sid:nvim" 'nvim .' \; \
        send-keys -t "$sid:nvim" Enter \; \
        select-window -t "$sid:nvim" \; \
        set-option -t "$sid" @worktree_ready 1; then
        printf 'work: initialization failed; inspect tmux session %s (%s)\n' "$name" "$sid" >&2
        return 1
    fi
elif [ "$(tmux show-options -qv -t "$sid" @worktree_ready 2>/dev/null)" != 1 ]; then
    printf 'work: workspace initialization is incomplete; inspect session %s\n' "$sid" >&2
    return 1
fi

# Existing sessions keep their current window, panes and unsaved buffers.
if [ -n "${TMUX:-}" ]; then
    if [ -n "$client" ]; then
        tmux switch-client -c "$client" -t "$sid"
    else
        tmux switch-client -t "$sid"
    fi
else
    tmux attach-session -t "$sid"
fi
