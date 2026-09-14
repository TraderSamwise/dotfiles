#!/bin/bash
# Restart the chrome-devtools-mcp proxy when it is unhealthy.
#
# Guards against two distinct failure modes:
#
#  1. Dead child / "Not connected" (the common one). `mcp-proxy --shell`
#     propagates a dropped Claude client connection as stdin EOF to the
#     stdio chrome-devtools-mcp child, which then logs "Parent death
#     detected (stdin end)" and exits. launchd KeepAlive only watches the
#     mcp-proxy process — which stays alive — so the dead child is never
#     respawned and every tools/list returns -32603 "Not connected". We
#     detect this by doing a real MCP handshake + tools/list against :9223
#     and kickstart the unit if it fails. A single retry absorbs the
#     transient window right after a restart while the wrapper polls Chrome.
#
#  2. Stale-connection pileup. Old Claude sessions leave ESTABLISHED TCP
#     connections that never close, eventually wedging the proxy. Restart
#     past a threshold.

set -uo pipefail

LABEL="local.chrome-devtools-mcp"
PORT=9223
URL="http://127.0.0.1:${PORT}/mcp"
MAX_CONNECTIONS=20
TS="$(date)"

restart() {
  echo "$TS: $1 — kickstarting $LABEL"
  launchctl kickstart -k "gui/$(id -u)/$LABEL"
  exit 0
}

# Full MCP handshake + tools/list. Returns 0 only if the proxy has a live
# child that reports tools. Closes its own session so the probe does not
# itself contribute to stale-connection pileup.
probe_tools() {
  local hdr sid tools
  hdr="$(mktemp)"
  curl -s -D "$hdr" -o /dev/null -m 12 -X POST "$URL" \
    -H 'Content-Type: application/json' \
    -H 'Accept: application/json, text/event-stream' \
    -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"healthcheck","version":"1.0"}}}' 2>/dev/null
  sid="$(grep -i '^mcp-session-id:' "$hdr" | awk '{print $2}' | tr -d '\r')"
  rm -f "$hdr"
  [ -z "$sid" ] && return 1

  curl -s -m 5 -X POST "$URL" \
    -H 'Content-Type: application/json' \
    -H 'Accept: application/json, text/event-stream' \
    -H "mcp-session-id: $sid" \
    -d '{"jsonrpc":"2.0","method":"notifications/initialized"}' >/dev/null 2>&1

  tools="$(curl -s -m 12 -X POST "$URL" \
    -H 'Content-Type: application/json' \
    -H 'Accept: application/json, text/event-stream' \
    -H "mcp-session-id: $sid" \
    -d '{"jsonrpc":"2.0","id":2,"method":"tools/list","params":{}}' 2>/dev/null)"

  # Exercise a real CDP call, not just the static tool list. tools/list passes
  # even when Chrome's browser WS is dead (e.g. Canary auto-updated and the
  # bridge is still pinned to the old --wsEndpoint), so a browser restart would
  # otherwise read as "healthy" forever. list_pages actually round-trips to
  # Chrome and fails ("Could not connect", 404, -32000) when the pin is stale.
  pages="$(curl -s -m 12 -X POST "$URL" \
    -H 'Content-Type: application/json' \
    -H 'Accept: application/json, text/event-stream' \
    -H "mcp-session-id: $sid" \
    -d '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"list_pages","arguments":{}}}' 2>/dev/null)"

  # Close the probe session so it doesn't linger server-side.
  curl -s -m 5 -X DELETE "$URL" -H "mcp-session-id: $sid" >/dev/null 2>&1

  echo "$tools" | grep -q '"name"' || return 1
  echo "$pages" | grep -qiE 'could not connect|"isError": *true|-32000|Unexpected server response' && return 1
  echo "$pages" | grep -q 'Pages'
}

# Be patient: a legitimate cold start (npx fetch + Chrome WS connect) can take
# 20s+, and the wrapper polls Chrome for up to 60s. Only declare the child dead
# after several spaced retries so a probe that lands mid-startup doesn't trigger
# a spurious restart.
probe_ok=0
for attempt in 1 2 3 4; do
  if probe_tools; then
    probe_ok=1
    break
  fi
  sleep 8
done
[ "$probe_ok" -eq 1 ] || restart "tools/list probe failed after retries (dead child / Not connected)"

# Stale-connection pileup.
count=$(lsof -i :$PORT 2>/dev/null | grep -c ESTABLISHED)
if [ "$count" -gt "$MAX_CONNECTIONS" ]; then
  restart "$count ESTABLISHED connections on :$PORT (threshold $MAX_CONNECTIONS)"
fi

echo "$TS: healthy (tools/list OK, $count connections on :$PORT)"
