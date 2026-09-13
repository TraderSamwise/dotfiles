# VS Code config

Version-controlled VS Code user config, migrated from Cursor (2026-07-25).
The live VS Code User files are **symlinks** into this directory, so any change
made inside VS Code shows up here — just `git add vscode && git commit`.

## Contents

| Path | Purpose |
|------|---------|
| `settings.json` | User settings (theme, prettier/eslint/ruff on save, token colors, folder colors, periscope, etc.) — symlinked into VS Code |
| `keybindings.json` | Keybindings — symlinked into VS Code |
| `snippets/` | User snippets — symlinked into VS Code |
| `extensions.txt` | Desired marketplace extension set, one ID per line |
| `editor-tweaks/` | A small **local** extension (source of truth) — see below |
| `bootstrap.sh` | Restore everything on a new machine |

## How the sync works

On this machine these are symlinked into `~/Library/Application Support/Code/User/`:
`settings.json`, `keybindings.json`, `snippets`. Edit settings in VS Code → it
writes through the symlink → commit here.

## editor-tweaks (local extension)

A hand-rolled extension (not on the marketplace) providing:

- **`cmd+/`** — toggle line comment and move down, but stay put on empty lines.
- **Indent-aware up/down arrows & Enter on empty lines** — the caret lands at the
  syntactically sensible indent (matching JetBrains-ish behavior VS Code lacks):
  one level in after `{`/`(`/`[` or a trailing operator (`=`, `=>`, `&&`…), aligned
  to siblings inside brackets, at the statement base after `;`, at the brace level
  after `}`, and holding the continuation level for running method chains. Vertical
  navigation also preserves the goal column across blank lines.

`extension.js` here is the **source of truth**. The installed copy at
`~/.vscode/extensions/sam.comment-move-down-conditional-<ver>/extension.js` is a
**symlink back to this file**, so editing here + reloading VS Code is live — no
rebuild needed. Bump `package.json` `version` and run `editor-tweaks/build.sh`
only when you need VS Code to re-register it (e.g. fresh machine, or to force a
reload). Its keybindings live in `keybindings.json` (the `sam.*` commands).

## Restore on a new machine

```bash
cd ~/cs/dotfiles/vscode
./bootstrap.sh
```

Symlinks the User files, installs everything in `extensions.txt`, then builds +
installs `editor-tweaks` and re-links its `extension.js` to this repo. Existing
non-symlink User files are backed up to `_backup-<timestamp>/` first.

## Notes

- The `code` CLI isn't on PATH by default. Add it via
  `Cmd+Shift+P → Shell Command: Install 'code' command in PATH`; `bootstrap.sh`
  and `build.sh` fall back to the CLI inside the app bundle.
- Refresh `extensions.txt` from what's installed:
  `code --list-extensions | grep -v '^sam\.\|^undefined_publisher\.' > extensions.txt`
