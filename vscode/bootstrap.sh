#!/usr/bin/env bash
# Restore this VS Code config on a machine by symlinking the User files
# to this repo and installing the extension set. Idempotent.
set -euo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CODE_USER="$HOME/Library/Application Support/Code/User"          # macOS
CODE_CLI="/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"
[ -x "$CODE_CLI" ] || CODE_CLI="$(command -v code || true)"

mkdir -p "$CODE_USER"
STAMP="$(date +%Y%m%d-%H%M%S)"

link() {
  local target="$REPO/$1" dest="$CODE_USER/$1"
  if [ -e "$dest" ] && [ ! -L "$dest" ]; then
    mkdir -p "$CODE_USER/_backup-$STAMP"
    mv "$dest" "$CODE_USER/_backup-$STAMP/$1"
  fi
  ln -sfn "$target" "$dest"
  echo "linked $1"
}

link settings.json
link keybindings.json
link snippets

if [ -n "$CODE_CLI" ]; then
  while read -r ext; do
    [ -z "$ext" ] && continue
    "$CODE_CLI" --install-extension "$ext" --force >/dev/null && echo "ext  $ext"
  done < "$REPO/extensions.txt"

  # Build + install the local editor-tweaks extension, then symlink its live
  # copy back to the repo source so future edits stay live.
  if command -v node >/dev/null 2>&1; then
    "$REPO/editor-tweaks/build.sh"
    INST="$(ls -d "$HOME/.vscode/extensions/sam.comment-move-down-conditional-"* 2>/dev/null | sort -V | tail -1 || true)"
    [ -n "$INST" ] && ln -sf "$REPO/editor-tweaks/extension.js" "$INST/extension.js" && echo "linked editor-tweaks extension.js -> repo"
  else
    echo "!! node not found; skipped editor-tweaks. Install node, then rerun vscode/bootstrap.sh."
  fi
else
  echo "!! 'code' CLI not found; skipped extensions. Install them from extensions.txt."
fi

echo "Done."
