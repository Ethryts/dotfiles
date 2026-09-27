
have() { command -v "$1" >/dev/null 2>&1; }
# Work setup environment

work() {
    ~/.config/bash/scripts/work.sh "$@"
    # local root name
    #
    # root="$(git rev-parse --show-toplevel 2>/dev/null)" || {
    #     echo "Not inside a git repository"
    #     return 1
    # }
    #
    # name="$(basename "$root")"
    #
    # if ! tmux has-session -t "=$name" 2>/dev/null; then
    #     tmux new-session -d -s "$name" -n nvim -c "$root"
    #     tmux new-window -t "$name:" -n agent  -c "$root"
    #     tmux new-window -t "$name:" -n tests  -c "$root"
    #     tmux new-window -t "$name:" -n server -c "$root"
    #     tmux new-window -t "$name:" -n shell  -c "$root"
    #
    #     tmux send-keys -t "$name:nvim" 'nvim .' Enter
    #     tmux select-window -t "$name:nvim"
    # fi
    #
    # tmux switch-client -t "$name"
}





