# -- Editors ---
export EDITOR=nvim
export VISUAL=nvim

if command -v bat >/dev/null 2>&1; then
  export PAGER=bat
  export MANPAGER="bat -plman"
elif command -v batcat >/dev/null 2>&1; then
  export PAGER=batcat
  export MANPAGER="batcat -plman"
else
  export PAGER=less
fi


#--- XDG Base Directory Specification ---
export XDG_CONFIG_HOME="$HOME/.config"
export XDG_DATA_HOME="$HOME/.local/share"
export XDG_CACHE_HOME="$HOME/.cache"

#--- GO PATH ---
# IF go is installed add gopath to path
if command -v go &> /dev/null; then
  export GOPATH="$HOME/go"
  export PATH="$PATH:$GOPATH/bin"
fi
