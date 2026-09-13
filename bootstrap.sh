#!/usr/bin/env bash
# Set up this machine from the dotfiles repo. Idempotent: re-running only fixes
# what is missing. Anything replaced is moved to ~/.dotfiles-backup/<stamp>/.
set -euo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
BACKUP="$HOME/.dotfiles-backup/$(date +%Y%m%d-%H%M%S)"
WITH_BREW=1
WITH_VSCODE=1

for arg in "$@"; do
  case "$arg" in
    --no-brew) WITH_BREW=0 ;;
    --no-vscode) WITH_VSCODE=0 ;;
    -h|--help) echo "usage: $0 [--no-brew] [--no-vscode]"; exit 0 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

link() {
  local src="$DOTFILES/$1" dest="$2"
  if [ -L "$dest" ] && [ "$(readlink "$dest")" = "$src" ]; then
    echo "ok     $dest"
    return
  fi
  if [ -e "$dest" ] || [ -L "$dest" ]; then
    local saved="$BACKUP/${dest#"$HOME"/}"
    mkdir -p "$(dirname "$saved")"
    chmod 700 "$HOME/.dotfiles-backup"
    mv "$dest" "$saved"
    echo "backup $dest -> $saved"
  fi
  mkdir -p "$(dirname "$dest")"
  ln -s "$src" "$dest"
  echo "link   $dest"
}

clone() {
  local url="$1" dest="$2"
  if [ -d "$dest" ]; then
    echo "ok     $dest"
    return
  fi
  git clone --depth=1 "$url" "$dest" || echo "!! clone failed: $url (rerun once git and network work)" >&2
}

load_brew() {
  local brew_bin
  for brew_bin in /opt/homebrew/bin/brew /usr/local/bin/brew; do
    [ -x "$brew_bin" ] && eval "$("$brew_bin" shellenv)" && return
  done
  return 0
}

load_brew
if [ "$WITH_BREW" = 1 ] && ! command -v brew >/dev/null 2>&1; then
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || true
  load_brew
  if ! command -v brew >/dev/null 2>&1; then
    echo "!! Homebrew install failed (needs an admin account and network); continuing without brew" >&2
    WITH_BREW=0
  fi
fi

# git writes --global settings to the XDG file when ~/.gitconfig is absent, which
# would put identity/credentials into this public repo. Keep ~/.gitconfig present.
if [ ! -e "$HOME/.gitconfig" ]; then
  printf '# Machine-private git config: [user], credential helpers.\n# Shared settings: ~/.config/git/config (dotfiles).\n' > "$HOME/.gitconfig"
  echo "create $HOME/.gitconfig"
fi

link zsh/zshenv "$HOME/.zshenv"
link zsh/zprofile "$HOME/.zprofile"
link zsh/zlogin "$HOME/.zlogin"
link zsh/zshrc "$HOME/.zshrc"
link git/config "$HOME/.config/git/config"
link git/ignore "$HOME/.config/git/ignore"
link tmux/tmux.conf "$HOME/.tmux.conf"
link ripgrep/ripgreprc "$HOME/.ripgreprc"
link micro/settings.json "$HOME/.config/micro/settings.json"
link micro/bindings.json "$HOME/.config/micro/bindings.json"

clone https://github.com/ohmyzsh/ohmyzsh.git "$HOME/.oh-my-zsh"
clone https://github.com/zsh-users/zsh-autosuggestions "$HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions"
clone https://github.com/zsh-users/zsh-syntax-highlighting "$HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting"
clone https://github.com/bhilburn/powerlevel9k "$HOME/.oh-my-zsh/custom/themes/powerlevel9k"

if git -C "$DOTFILES" rev-parse --git-dir >/dev/null 2>&1; then
  git -C "$DOTFILES" config core.hooksPath .githooks
  git -C "$DOTFILES" config user.email 78459398+TraderSamwise@users.noreply.github.com
else
  echo "skip   pre-commit hook ($DOTFILES is not a git checkout)"
fi

if [ "$WITH_BREW" = 1 ]; then
  brew bundle --file "$DOTFILES/Brewfile" || echo "!! brew bundle failed; rerun: brew bundle --file $DOTFILES/Brewfile" >&2
fi

if ! command -v xkcdpass >/dev/null 2>&1 && [ ! -x "$HOME/.local/bin/xkcdpass" ]; then
  if command -v uv >/dev/null 2>&1; then
    uv tool install xkcdpass || echo "!! uv tool install xkcdpass failed" >&2
  else
    echo "skip   xkcdpass (needs uv; used by pw)"
  fi
fi

if [ "$WITH_VSCODE" = 1 ]; then
  "$DOTFILES/vscode/bootstrap.sh"
fi

cat <<EOF

Done. Machine-private config goes in files this repo never tracks:
  ~/.zshenv.local    env every shell needs (tokens for scripts)
  ~/.zprofile.local  login-only env
  ~/.zshrc.local     interactive aliases, conda, work-only PATH
  ~/.gitconfig       [user] name/email, credential helpers
Then: exec zsh
EOF
