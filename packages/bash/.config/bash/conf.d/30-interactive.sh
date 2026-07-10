




## Bash completion
if [ -f /usr/share/bash-completion/bash_completion ]; then
    . /usr/share/bash-completion/bash_completion
elif [ -f /etc/bash_completion ]; then
    . /etc/bash_completion
fi

# Fuzzy  finder for history via ctrl-r
[[ $(command -v fzf) ]] && eval "$(fzf --bash)"
[[ $(command -v zoxide) ]] && eval "$(zoxide init bash)"
