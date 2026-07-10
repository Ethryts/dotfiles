
if ! command -v bat >/dev/null 2>&1 && command -v batcat >/dev/null 2>&1; then
    alias bat=batcat
fi

if ! command -v fd >/dev/null 2>&1 && command -v fdfind >/dev/null 2>&1; then
    alias fd=fdfind
fi

# Using function instead to ensure that the arguments are passed correctly
open() {
    xdg-open "$@" >/dev/null 2>&1 &
}

