#!/usr/bin/env bash
# Launch chrome-devtools-mcp pinned to Chrome's browser-level CDP WebSocket.
#
# Why this exists: the default `--browserUrl` flow asks Chrome's HTTP discovery
# endpoint for a target, then opens a CDP WS to that single page. The page-
# level WS dies whenever the page navigates / reloads / closes — which was the
# original cause of the "MCP error -32000: Connection closed" we kept hitting.
#
# The /json/version endpoint exposes a *browser*-level WS
# (`webSocketDebuggerUrl`). That WS survives page-level events. Resolving it
# at startup and passing it via --wsEndpoint pins the MCP to the browser, not
# any one tab.
#
# Chrome is normally launched via the `canary` script on :9222. On cold boot,
# this wrapper also tries to launch it once before polling, so the MCP bridge
# does not depend on the user opening Canary before Codex starts.
#
# Poll behavior: this script is run under a launchd-managed supergateway, so if
# it exits the whole stack respawns. To avoid a respawn storm when Chrome isn't
# up yet (e.g., right after login), we poll /json/version for up to 60s before
# giving up.

set -euo pipefail

PORT=9222
LOG=/tmp/chrome-mcp.log
POLL_MAX_SECONDS=60
POLL_INTERVAL=2

if ! curl -fsS --max-time 2 "http://127.0.0.1:${PORT}/json/version" >/dev/null 2>&1; then
  "$HOME/.local/bin/canary" >/tmp/chrome-mcp-canary.log 2>&1 || true
fi

WS=""
elapsed=0
while [ $elapsed -lt $POLL_MAX_SECONDS ]; do
  if WS=$(curl -fsS --max-time 2 "http://127.0.0.1:${PORT}/json/version" 2>/dev/null | jq -r '.webSocketDebuggerUrl // empty') && [ -n "$WS" ]; then
    break
  fi
  WS=""
  sleep $POLL_INTERVAL
  elapsed=$((elapsed + POLL_INTERVAL))
done

if [ -z "$WS" ]; then
  echo "chrome-devtools-mcp wrapper: Chrome did not appear on 127.0.0.1:${PORT} within ${POLL_MAX_SECONDS}s" >&2
  echo "  Launch it via the 'canary' script and the supergateway will retry." >&2
  exit 1
fi

# Verbose protocol tracing is a firehose: it dumps every CDP frame into
# --logFile and grows the log by tens of GB/hour under normal use (a single
# wait_for poll loop ballooned it to 69 GB once). It is NOT inert. So it is
# OFF by default and only enabled when explicitly diagnosing a disconnect:
#   CHROME_MCP_DEBUG=1
if [ "${CHROME_MCP_DEBUG:-0}" = "1" ]; then
  export DEBUG="${DEBUG:-pw:protocol,puppeteer:*,chrome-devtools-mcp:*}"
fi

exec npx -y chrome-devtools-mcp@latest \
  --wsEndpoint "$WS" \
  --logFile "$LOG" \
  "$@"
