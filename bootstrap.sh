#!/usr/bin/env bash
# Set up this machine from the dotfiles repo. Idempotent: re-running only fixes
# what is missing. Anything replaced is moved to ~/.dotfiles-backup/<stamp>/.
set -euo pipefail

DOTFILES="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
BACKUP="$HOME/.dotfiles-backup/$(date +%Y%m%d-%H%M%S)"
WITH_BREW=1
WITH_VSCODE=1
WITH_MACOS=0
WITH_CHROME_MCP=0

for arg in "$@"; do
  case "$arg" in
    --no-brew) WITH_BREW=0 ;;
    --no-vscode) WITH_VSCODE=0 ;;
    --macos) WITH_MACOS=1 ;;
    --chrome-mcp) WITH_CHROME_MCP=1 ;;
    -h|--help) echo "usage: $0 [--no-brew] [--no-vscode] [--macos] [--chrome-mcp]"; exit 0 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

FAILED=()
step() { # step <description> <command...>
  if "${@:2}"; then return 0; fi
  FAILED+=("$1")
  echo "!! FAILED: $1" >&2
}

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
  step "clone $url" git clone --depth=1 "$url" "$dest"
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
link bash/bashrc "$HOME/.bashrc"
link bash/bash_profile "$HOME/.bash_profile"
link bash/profile "$HOME/.profile"
link ghostty/config "$HOME/.config/ghostty/config"
link ghostty/config "$HOME/Library/Application Support/com.cmuxterm.app/config.ghostty"
link nvim "$HOME/.config/nvim"
link vim/vimrc "$HOME/.vimrc"
link htop/htoprc "$HOME/.config/htop/htoprc"
link watchman/watchman-config.json "$HOME/.watchman-config.json"
link opencode/opencode.json "$HOME/.config/opencode/opencode.json"
link bin/git-merge "$HOME/.local/bin/git-merge"
link bin/cs "$HOME/.local/bin/cs"
link bin/queue "$HOME/.local/bin/queue"
link bin/claude-router "$HOME/.local/bin/claude-router"
for script in canary chrome-devtools-mcp-wrapper.sh chrome-mcp-healthcheck.sh chrome-mcp-log-trim.sh chrome-mcp-restart; do
  link "bin/$script" "$HOME/.local/bin/$script"
done
link bin/sync-codex-claude "$HOME/.local/bin/sync-codex-claude"
link bin/agent-config-apply "$HOME/.local/bin/agent-config-apply"
link bin/clip-drop "$HOME/.local/bin/clip-drop"
link claude/CLAUDE.md "$HOME/.claude/CLAUDE.md"
link claude/statusline-command.sh "$HOME/.claude/statusline-command.sh"
# Claude Code rewrites settings.json itself, so it is copied once rather than linked.
if [ ! -e "$HOME/.claude/settings.json" ]; then
  mkdir -p "$HOME/.claude"
  cp "$DOTFILES/claude/settings.json" "$HOME/.claude/settings.json"
  echo "create $HOME/.claude/settings.json"
else
  # An existing machine keeps its own settings.json, so new hooks would never
  # reach it. Merge just the agent-config hook in, idempotently.
  python3 - "$HOME/.claude/settings.json" <<'MERGEHOOK'
import json, sys, pathlib
p = pathlib.Path(sys.argv[1])
st = json.loads(p.read_text())
cmd = "~/.local/bin/agent-config-apply >/dev/null 2>&1"
groups = st.setdefault("hooks", {}).setdefault("SessionStart", [])
if not groups:
    groups.append({"hooks": []})
entries = groups[0].setdefault("hooks", [])
if not any(h.get("command", "").startswith("~/.local/bin/agent-config-apply") for h in entries):
    entries.append({"type": "command", "command": cmd})
    p.write_text(json.dumps(st, indent=2) + "\n")
    print("hook   SessionStart agent-config-apply")
else:
    print("ok     SessionStart agent-config-apply")
MERGEHOOK
fi
for f in $(cd "$DOTFILES" && ls claude/commands/*.md claude/hooks/*.js); do
  link "$f" "$HOME/.claude/${f#claude/}"
done
for f in $(cd "$DOTFILES" && ls claude/skills/*/SKILL.md); do
  link "$f" "$HOME/.claude/${f#claude/}"
done
# Codex drops a skill whose SKILL.md is a symlink, so link the skill directory.
for d in $(cd "$DOTFILES" && ls -d codex/skills/*/); do
  d="${d%/}"
  link "$d" "$HOME/.codex/${d#codex/}"
done
link bin/oneshot-secret "$HOME/.local/bin/oneshot-secret"
link claude/skills/oneshot-secret "$HOME/.codex/skills/oneshot-secret"
link claude/skills/queue "$HOME/.codex/skills/queue"
link hammerspoon/init.lua "$HOME/.hammerspoon/init.lua"
link hammerspoon/omnibox_tab.lua "$HOME/.hammerspoon/omnibox_tab.lua"
link hammerspoon/vscode_swipe_nav.lua "$HOME/.hammerspoon/vscode_swipe_nav.lua"

clone https://github.com/ohmyzsh/ohmyzsh.git "$HOME/.oh-my-zsh"
clone https://github.com/zsh-users/zsh-autosuggestions "$HOME/.oh-my-zsh/custom/plugins/zsh-autosuggestions"
clone https://github.com/zsh-users/zsh-syntax-highlighting "$HOME/.oh-my-zsh/custom/plugins/zsh-syntax-highlighting"
clone https://github.com/bhilburn/powerlevel9k "$HOME/.oh-my-zsh/custom/themes/powerlevel9k"
clone https://github.com/VundleVim/Vundle.vim "$HOME/.vim/bundle/Vundle.vim"
clone https://github.com/Shougo/neobundle.vim "$HOME/.vim/bundle/neobundle.vim"

if git -C "$DOTFILES" rev-parse --git-dir >/dev/null 2>&1; then
  git -C "$DOTFILES" config core.hooksPath .githooks
  git -C "$DOTFILES" config user.email 78459398+TraderSamwise@users.noreply.github.com
else
  echo "skip   pre-commit hook ($DOTFILES is not a git checkout)"
fi

step "agent models" "$DOTFILES/bin/agent-config-apply"

if [ "$WITH_BREW" = 1 ]; then
  step "brew bundle" brew bundle --file "$DOTFILES/Brewfile"
fi

step "volta tools" "$DOTFILES/volta/install.sh"

# nvm owns `node` outside Volta-pinned projects; give a fresh machine an LTS default.
export NVM_DIR="$HOME/.nvm"
mkdir -p "$NVM_DIR"
nvm_sh="$NVM_DIR/nvm.sh"
[ -s "$nvm_sh" ] || nvm_sh="$(brew --prefix nvm 2>/dev/null || true)/nvm.sh"
if [ -s "$nvm_sh" ]; then
  (
    set +eu
    . "$nvm_sh"
    if [ "$(nvm version default)" = "N/A" ]; then
      nvm install --lts && nvm alias default 'lts/*'
    else
      echo "ok     nvm default $(nvm version default)"
    fi
  ) || { FAILED+=("nvm default node"); echo "!! FAILED: nvm default node" >&2; }
else
  echo "!! nvm not installed (brew install nvm); skipped node default" >&2
fi

if ! command -v xkcdpass >/dev/null 2>&1 && [ ! -x "$HOME/.local/bin/xkcdpass" ]; then
  if command -v uv >/dev/null 2>&1; then
    step "xkcdpass" uv tool install xkcdpass
  else
    echo "skip   xkcdpass (needs uv; used by pw)"
  fi
fi

if [ "$WITH_VSCODE" = 1 ]; then
  "$DOTFILES/vscode/bootstrap.sh"
fi

if [ "$WITH_CHROME_MCP" = 1 ]; then
  step "chrome mcp" "$DOTFILES/chrome-mcp/install.sh"
fi

if [ "$WITH_MACOS" = 1 ]; then
  "$DOTFILES/macos/defaults.sh"
fi

if [ ${#FAILED[@]} -gt 0 ]; then
  echo
  echo "INCOMPLETE - ${#FAILED[@]} step(s) failed:" >&2
  for f in "${FAILED[@]}"; do echo "  - $f" >&2; done
  echo "This machine is NOT at parity. Fix these, or ask Claude to (skill: machines)." >&2
fi

cat <<EOF

Done linking. Machine-private config goes in files this repo never tracks:
  ~/.zshenv.local    env every shell needs (tokens for scripts)
  ~/.zprofile.local  login-only env
  ~/.zshrc.local     interactive aliases, conda, work-only PATH
  ~/.gitconfig       [user] name/email, credential helpers
Then: exec zsh
EOF

exit $(( ${#FAILED[@]} > 0 ))
