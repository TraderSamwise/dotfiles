# dotfiles

Portable shell, git, terminal, and editor config for macOS. Public on purpose:
nothing machine-private lives here.

## Install

```bash
git clone https://github.com/TraderSamwise/dotfiles ~/cs/dotfiles
~/cs/dotfiles/bootstrap.sh            # --no-brew, --no-vscode to skip those steps; --macos to apply macOS defaults
exec zsh
```

`bootstrap.sh` is idempotent. It installs Homebrew if missing, clones oh-my-zsh
with its plugins and the powerlevel9k theme, clones Vundle and NeoBundle for vim,
symlinks the files below into `$HOME` (moving anything it replaces to
`~/.dotfiles-backup/<stamp>/`), runs `brew bundle`, installs `xkcdpass` via `uv` when `uv` is available, and
restores VS Code (the `editor-tweaks` extension build needs `node`). With
`--macos` it also runs `macos/defaults.sh`.

| Repo path | Linked to |
|-----------|-----------|
| `zsh/zshenv`, `zsh/zprofile`, `zsh/zlogin`, `zsh/zshrc` | `~/.zshenv`, `~/.zprofile`, `~/.zlogin`, `~/.zshrc` |
| `bash/bashrc`, `bash/bash_profile`, `bash/profile` | `~/.bashrc`, `~/.bash_profile`, `~/.profile` |
| `git/config`, `git/ignore` | `~/.config/git/config`, `~/.config/git/ignore` |
| `ghostty/config` | `~/.config/ghostty/config` and `~/Library/Application Support/com.cmuxterm.app/config.ghostty` (cmux reads the Ghostty config) |
| `nvim/` (LazyVim) | `~/.config/nvim` |
| `vim/vimrc` | `~/.vimrc` |
| `tmux/tmux.conf` | `~/.tmux.conf` |
| `ripgrep/ripgreprc` | `~/.ripgreprc` |
| `micro/settings.json`, `micro/bindings.json` | `~/.config/micro/` |
| `htop/htoprc` | `~/.config/htop/htoprc` |
| `watchman/watchman-config.json` | `~/.watchman-config.json` (`WATCHMAN_CONFIG_FILE` in `zsh/zshrc`) |
| `opencode/opencode.json` | `~/.config/opencode/opencode.json` |
| `bin/git-merge`, `bin/cs` | `~/.local/bin/git-merge`, `~/.local/bin/cs` |
| `bin/oneshot-secret`, `claude/skills/oneshot-secret/SKILL.md` | `~/.local/bin/oneshot-secret`; the skill in `~/.claude/skills/oneshot-secret/` and `~/.codex/skills/oneshot-secret/`. Each machine gets its own store: run `oneshot-secret init-store` once (store `~/cs/secrets`, key in the login keychain) |
| `bin/queue`, `claude/skills/queue/SKILL.md` | `~/.local/bin/queue`; the skill in `~/.claude/skills/queue/` and `~/.codex/skills/queue/` (store: `~/cs/docs/agent-queue/<repo>/`, created on first use) |
| `hammerspoon/init.lua`, `omnibox_tab.lua`, `vscode_swipe_nav.lua` | `~/.hammerspoon/` |
| `vscode/` | VS Code User dir — see [`vscode/README.md`](vscode/README.md) |
| `Brewfile` | `brew bundle` |
| `macos/defaults.sh` | run by `bootstrap.sh --macos` |

## Keyboard

Keys that differ from the defaults, and the file that sets each.

| Key | Does | Set in |
|-----|------|--------|
| ⌥← / ⌥→ | jump a word in zsh, micro and nvim | `ghostty/config` (`macos-option-as-alt`); nvim side in `nvim/lua/config/keymaps.lua` |
| ⌘← / ⌘→ | Home / End | `ghostty/config` |
| ⌘⇧← / ⌘⇧→ | select to line start / end | `ghostty/config`; nvim turns them into a selection via `keymodel` in `nvim/lua/config/options.lua` |
| ⌃J | newline in Claude Code (sends Shift+Enter) | `ghostty/config` |
| ⌘= / ⌘− | font size up / down | `ghostty/config` |
| ⌘⌫ | delete to line start (Ghostty sends `^U`) | `zsh/zshrc` (`bindkey '^U' backward-kill-line`) |
| ⌘⌥Space | Spotlight, leaving ⌘Space for Raycast | `macos/defaults.sh` |
| ⌃1 … ⌃0 | switch to Desktop 1–10, hiding visor apps first | `hammerspoon/init.lua` (sends hyper+N; `macos/defaults.sh` puts Desktop N on hyper+N — without that step ⌃N switches nothing) |
| ⌃⇧1 … ⌃⇧9 | move the focused app to Desktop N | `hammerspoon/init.lua` |
| ⌃⇧A | assign the focused app to the current Desktop | `hammerspoon/init.lua` |
| ⌃⇧← / ⌃⇧→ | window to the left two-thirds / right third | Rectangle (`rectangle/com.knollsoft.Rectangle.plist`) |
| ⌃⇧↑ / ⌃⇧↓ | maximize / restore the window | Rectangle |
| ⌃⌥⇧← / ⌃⌥⇧→ | move the window to the previous / next display | Rectangle |
| ⌃⌥B / ⌃⌥N | toggle / reflow Rectangle's Todo mode | Rectangle |
| visor keys | show an app on the current Space, press again to hide it | `visors` in `~/.hammerspoon/init.local.lua` (default: ⌥` Finder) |
| Tab / ⇧Tab in the Chrome address bar | move through suggestions | `hammerspoon/omnibox_tab.lua` |

Image paste in Claude Code: ⌘V works in cmux, which saves the clipboard image to
`$TMPDIR/clipboard-*.png` and pastes the path. In plain Ghostty, Terminal or
iTerm, use ⌃V inside Claude Code.

The powerlevel9k prompt needs a Powerline font in terminals other than Ghostty,
which bundles its own glyphs: `brew install --cask font-meslo-for-powerlevel10k`.

## Claude Code and Codex

| Repo path | Linked to | What it is |
|-----------|-----------|------------|
| `claude/CLAUDE.md` | `~/.claude/CLAUDE.md` | Shared agent rules. Machine-private rules go in an untracked `~/CLAUDE.md`; Claude Code loads both |
| `claude/commands/*.md` | `~/.claude/commands/` | `/plan-execute`, `/review-coderabbit`, `/review-copilot`, `/review-feedback`, `/check-ci` |
| `claude/skills/*/SKILL.md` | `~/.claude/skills/` | `queue`, `oneshot-secret`, `setup-worktree` |
| `claude/hooks/*.js` | `~/.claude/hooks/` | Bash safety gate, Cypress gate, auto-memory write block, per-repo memory index injection (no-op without `~/cs/docs/agent-memory`) |
| `claude/statusline-command.sh` | `~/.claude/statusline-command.sh` | Footer: user@host, directory, git branch, context bar, model, session, vim mode |
| `claude/settings.json` | copied once to `~/.claude/settings.json` if absent | Model, effort, auto mode, notifications, status line and hook wiring |
| `codex/skills/**` | `~/.codex/skills/` | Codex versions of plan-execute, review-coderabbit, review-copilot, current-branch-pr, commit-review-flow, setup-worktree |
| `bin/sync-codex-claude` | `~/.local/bin/sync-codex-claude` | Builds Codex `developer_instructions` from the `codex:sync` regions of `~/.claude/CLAUDE.md` then `~/CLAUDE.md` |

After editing either `CLAUDE.md`, run `sync-codex-claude`. `settings.json` is not
linked because Claude Code writes to it; copy changes into `claude/settings.json`
by hand when they are worth sharing.

## Node: Volta and nvm

`volta/tools.txt` lists the Volta runtimes, package managers and CLIs (Claude Code,
Codex, pnpm, eas, wrangler, opencode, firebase, chrome-devtools-mcp); the last `node@`
and `yarn@` lines are the defaults. `bootstrap.sh` runs `volta/install.sh`, which
installs what is missing and writes `~/.local/volta-shims`: `zsh/zshenv` removes
Volta's own `bin` from PATH, so a Volta binary is only reachable when tools.txt names
a shim for it. nvm owns plain `node`; bootstrap installs the latest LTS as its default
when none is set.

## Chrome DevTools MCP

`bootstrap.sh --chrome-mcp` runs `chrome-mcp/install.sh`: it renders the three
LaunchAgents in `chrome-mcp/launchd/` for this machine (`local.chrome-devtools-mcp`
keeps an `mcp-proxy` on `127.0.0.1:9223/mcp` around `bin/chrome-devtools-mcp-wrapper.sh`;
`local.chrome-mcp-healthcheck` restarts it when a real MCP call fails, every 60s;
`local.chrome-mcp-logtrim` caps its logs hourly), loads them, and registers
`chrome-devtools` with Claude Code and Codex. It needs Chrome Canary (Brewfile) and
Volta node 22. `canary` launches Canary on the empty debug profile with port 9222;
`chrome-mcp-restart` is the manual kick when `/mcp` shows "Not connected".

## Prompt and terminal look

A correct install looks like this; check each when a machine looks different.

- `echo $ZSH_THEME` prints `powerlevel9k/powerlevel9k`, and
  `git -C ~/.oh-my-zsh/custom/themes/powerlevel9k rev-parse --short HEAD` prints
  `66d53c0` (the archived upstream head). The prompt is **one line**: user@host
  (hidden when you are `$DEFAULT_USER` on a local shell), directory, git status,
  and rbenv / conda env when active on the left;
  exit status, background jobs, history number and time on the right.
- A two-line prompt, or a prompt with a `╭─` / `╰─` frame, means something else
  owns the prompt: a leftover powerlevel10k setup (`~/.p10k.zsh`, a
  `source ~/powerlevel10k/...` line), a `~/.zshrc.local` that sets a theme, or a
  `~/.zshrc` that is not the symlink into this repo (`ls -l ~/.zshrc`).
- The terminal is Ghostty or cmux reading `ghostty/config` (block cursor,
  `macos-option-as-alt`). Both bundle the Powerline glyphs; in
  Terminal or iTerm install `font-meslo-for-powerlevel10k` and select it, or the
  prompt shows boxes where the arrows should be.
- `ls -l ~/.config/ghostty/config` points into this repo. A machine cloned before
  the Ghostty config was added needs `git pull && ./bootstrap.sh`.

## macOS

`macos/defaults.sh` is opt-in (`bootstrap.sh --macos`, or run it directly). It
sets fast key repeat with press-and-hold off, natural scrolling off, all file
extensions shown, Dark mode, tap to click, three-finger horizontal swipe, an
auto-hiding Dock without launch animation or Space reordering, Finder path bar
and list view with search scoped to the current folder and external drives on
the desktop, screenshots saved to `~/Desktop/screenshots` in window mode, reduced
transparency, and Spotlight on ⌘⌥Space. It also imports Rectangle's shortcuts
(every other Rectangle default is cleared) and settings, quitting and reopening
Rectangle around the import. Key repeat and trackpad settings apply
after logging out; the script restarts Dock, Finder and SystemUIServer. Writing reduced transparency needs Full
Disk Access for the terminal; the script prints a warning when it cannot.

### Swapping ⌘ and ⌥ on an external keyboard

This is per device, so the script does not set it. Get the keyboard's hex
`VendorID` and `ProductID` from `hidutil list --matching keyboard`, convert each
to decimal (`printf '%d\n' 0x05ac`), then:

```bash
defaults -currentHost write -g com.apple.keyboard.modifiermapping.<vendor>-<product>-0 -array \
  '<dict><key>HIDKeyboardModifierMappingSrc</key><integer>30064771298</integer><key>HIDKeyboardModifierMappingDst</key><integer>30064771299</integer></dict>' \
  '<dict><key>HIDKeyboardModifierMappingSrc</key><integer>30064771299</integer><key>HIDKeyboardModifierMappingDst</key><integer>30064771298</integer></dict>' \
  '<dict><key>HIDKeyboardModifierMappingSrc</key><integer>30064771302</integer><key>HIDKeyboardModifierMappingDst</key><integer>30064771303</integer></dict>' \
  '<dict><key>HIDKeyboardModifierMappingSrc</key><integer>30064771303</integer><key>HIDKeyboardModifierMappingDst</key><integer>30064771302</integer></dict>'
```

Each code is `0x7000000E0` plus the HID modifier: `…298` left ⌥, `…299` left ⌘,
`…302` right ⌥, `…303` right ⌘. Alternatively set it once in System Settings >
Keyboard > Keyboard Shortcuts > Modifier Keys and read it back with
`defaults -currentHost read -g | grep modifiermapping`. A `defaults` write takes
effect at the next login.

## Machine-private config

Each shell file sources a sibling that this repo never tracks (`*.local` is
gitignored):

| File | Loaded by | Put here |
|------|-----------|----------|
| `~/.zshenv.local` | every zsh, including scripts | tokens that non-interactive tools need |
| `~/.zprofile.local` | login shells | login-only env |
| `~/.zshrc.local` | interactive shells, last | aliases, conda, extra PATH, other tokens |
| `~/.gitconfig` | git, after `~/.config/git/config` | `[user]`, credential helpers |
| `~/.config/nvim/lua/plugins/private/init.lua` | lazy.nvim (gitignored) | plugin specs from private repos |
| `~/.hammerspoon/init.local.lua` | `hammerspoon/init.lua` | `return { visors = { ... } }` plus any personal hotkeys or watchers |

`~/.gitconfig` must exist: when it is absent, `git config --global` writes into
the XDG file, which is this repo. `bootstrap.sh` creates it.

## Editing

Edit files in this repo; the symlinks make changes live. Installers that append
to `~/.zshrc` (`conda init`, bun) and `sed -i` on a linked file write into this
repo or replace the symlink: move such blocks into `~/.zshrc.local`, and check
`git status` here after installing things. htop saves settings by renaming a
temp file over `~/.config/htop/htoprc`, which replaces the symlink: copy that
file into `htop/htoprc`, then rerun `bootstrap.sh`. A `pre-commit` hook
(`.githooks/`, enabled by `bootstrap.sh`) runs `gitleaks` and refuses the commit
if it finds a credential or if `gitleaks` is not installed.
