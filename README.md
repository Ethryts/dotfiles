# Dotfiles

Dotfiles are managed with GNU Stow. Each directory in `packages/` is a Stow
package whose contents mirror paths under `$HOME`.

## Bootstrap A New Machine

On Arch Linux:

```bash
sudo pacman -S git stow neovim ripgrep fd bat fzf jq
git clone <repo-url> ~/dev/dotfiles
cd ~/dev/dotfiles
stow nvim
```

On Ubuntu:

```bash
sudo apt update
sudo apt install git stow neovim ripgrep fd-find bat fzf jq
git clone <repo-url> ~/dev/dotfiles
cd ~/dev/dotfiles
stow nvim
```

That links `packages/nvim/.config/nvim` to `~/.config/nvim`.
Do not run Stow with `sudo`; `~` means the home directory of the user running
the command.

## Daily Use

Install every package:

```bash
stow bash nvim starship
```

Preview changes:

```bash
stow --simulate --verbose nvim
```

Install selected packages:

```bash
stow nvim starship
```

Recreate links:

```bash
stow --restow nvim
```

Remove links:

```bash
stow --delete nvim
```

If Stow reports a conflict, move or back up the existing file manually before
running the installer again.
