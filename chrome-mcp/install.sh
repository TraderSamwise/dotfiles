#!/usr/bin/env bash
# Chrome DevTools MCP for Claude Code and Codex: an mcp-proxy on 127.0.0.1:9223 around
# chrome-devtools-mcp, attached to Chrome Canary's debug port 9222. Renders the
# LaunchAgents in launchd/, (re)loads the ones that changed, registers the server.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
AGENTS="$HOME/Library/LaunchAgents"
VOLTA_HOME="${VOLTA_HOME:-$HOME/.volta}"
URL="http://127.0.0.1:9223/mcp"

if [ ! -d "/Applications/Google Chrome Canary.app" ]; then
  echo "!! Chrome Canary not installed (brew install --cask google-chrome@canary); skipped Chrome MCP" >&2
  exit 0
fi

# The proxy runs on Volta's newest node 22, which volta/tools.txt keeps installed.
node_dir="$(ls -d "$VOLTA_HOME"/tools/image/node/22.* 2>/dev/null | sort -V | tail -1 || true)"
if [ -z "$node_dir" ]; then
  echo "!! Volta node@22 not installed (run volta/install.sh); skipped Chrome MCP" >&2
  exit 0
fi

mkdir -p "$AGENTS"
for template in "$HERE"/launchd/*.plist; do
  label="$(basename "$template" .plist)"
  dest="$AGENTS/$label.plist"
  rendered="$(mktemp)"
  sed -e "s|__NODE_BIN__|$node_dir/bin|g" -e "s|__HOME__|$HOME|g" "$template" >"$rendered"
  if [ -f "$dest" ] && cmp -s "$rendered" "$dest"; then
    rm -f "$rendered"
    echo "ok     $label"
  else
    mv "$rendered" "$dest"
    chmod 644 "$dest"
    launchctl bootout "gui/$(id -u)/$label" 2>/dev/null || true
    launchctl bootstrap "gui/$(id -u)" "$dest"
    echo "load   $label"
  fi
done

if command -v claude >/dev/null 2>&1; then
  if claude mcp get chrome-devtools >/dev/null 2>&1; then
    echo "ok     claude mcp chrome-devtools"
  else
    claude mcp add --scope user --transport http chrome-devtools "$URL"
    echo "add    claude mcp chrome-devtools"
  fi
else
  echo "!! claude not on PATH; register later: claude mcp add --scope user --transport http chrome-devtools $URL" >&2
fi

codex_config="$HOME/.codex/config.toml"
if grep -q '^\[mcp_servers\.chrome-devtools\]' "$codex_config" 2>/dev/null; then
  echo "ok     codex mcp chrome-devtools"
else
  mkdir -p "$HOME/.codex"
  printf '\n[mcp_servers.chrome-devtools]\nurl = "%s"\n' "$URL" >>"$codex_config"
  echo "add    codex mcp chrome-devtools"
fi
