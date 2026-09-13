# dotfiles

Portable shell, git, and editor config for macOS. Public on purpose: nothing
machine-private lives here.

## Install

```bash
git clone https://github.com/TraderSamwise/dotfiles ~/cs/dotfiles
~/cs/dotfiles/bootstrap.sh            # --no-brew, --no-vscode to skip those steps
exec zsh
```

`bootstrap.sh` is idempotent. It installs Homebrew if missing, clones oh-my-zsh
with its plugins and the powerlevel9k theme, symlinks the files below into
`$HOME` (moving anything it replaces to `~/.dotfiles-backup/<stamp>/`), runs
`brew bundle`, installs `xkcdpass` via `uv` when `uv` is available, and restores
VS Code (the `editor-tweaks` extension build needs `node`).

| Repo path | Linked to |
|-----------|-----------|
| `zsh/zshenv`, `zsh/zprofile`, `zsh/zlogin`, `zsh/zshrc` | `~/.zshenv`, `~/.zprofile`, `~/.zlogin`, `~/.zshrc` |
| `git/config`, `git/ignore` | `~/.config/git/config`, `~/.config/git/ignore` |
| `tmux/tmux.conf` | `~/.tmux.conf` |
| `ripgrep/ripgreprc` | `~/.ripgreprc` |
| `micro/settings.json`, `micro/bindings.json` | `~/.config/micro/` |
| `vscode/` | VS Code User dir — see [`vscode/README.md`](vscode/README.md) |
| `Brewfile` | `brew bundle` |

## Machine-private config

Each shell file sources a sibling that this repo never tracks (`*.local` is
gitignored):

| File | Loaded by | Put here |
|------|-----------|----------|
| `~/.zshenv.local` | every zsh, including scripts | tokens that non-interactive tools need |
| `~/.zprofile.local` | login shells | login-only env |
| `~/.zshrc.local` | interactive shells, last | aliases, conda, extra PATH, other tokens |
| `~/.gitconfig` | git, after `~/.config/git/config` | `[user]`, credential helpers |

`~/.gitconfig` must exist: when it is absent, `git config --global` writes into
the XDG file, which is this repo. `bootstrap.sh` creates it.

## Editing

Edit files in this repo; the symlinks make changes live. Installers that append
to `~/.zshrc` (`conda init`, bun) and `sed -i` on a linked file write into this
repo or replace the symlink: move such blocks into `~/.zshrc.local`, and check
`git status` here after installing things. A `pre-commit` hook
(`.githooks/`, enabled by `bootstrap.sh`) runs `gitleaks` and refuses the commit
if it finds a credential or if `gitleaks` is not installed.
