




## Bash completion
if [ -f /usr/share/bash-completion/bash_completion ]; then
    . /usr/share/bash-completion/bash_completion
elif [ -f /etc/bash_completion ]; then
    . /etc/bash_completion
fi

[[ $(command -v fzf) ]]       && eval "$(fzf --bash)"         # Fuzzy finder
[[ $(command -v direnv) ]]    && eval "$(direnv hook bash)"   # per dir .env files
[[ $(command -v mise) ]]      && eval "$(mise activate bash)" # Automatic tool handling 

# Starship and zoxide overwrite a PROMPT_COMMAND and may cause issues if the order is different
[[ $(command -v starship) ]]  && eval "$(starship init bash)" # Starship shell
[[ $(command -v zoxide) ]]    && eval "$(zoxide init bash)"


if [[ $(command -v mise) ]] then
  export PATH="$HOME/.local/share/mise/shims:$PATH"
fi

