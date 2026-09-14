#!/bin/bash
# Bound the chrome-devtools-mcp logs. mcp-proxy runs with --debug and streams
# unbounded into supergateway.log (StandardOutPath); nothing else rotates it,
# so it grows until the next reboot clears /tmp. This caps each log: when it
# passes MAX_BYTES, keep only the last KEEP_BYTES.
#
# Copy-truncate (tail -> in-place truncate via `>`) is deliberate: the proxy
# holds these files open via launchd O_APPEND handles. `mv` would swap the
# inode and orphan the daemon's fd (writes vanish, space not freed until
# restart). Truncating the same inode keeps the live handle valid.
set -uo pipefail

MAX_BYTES=$((50 * 1024 * 1024))
KEEP_BYTES=$((5 * 1024 * 1024))

LOGS=(
  /tmp/chrome-mcp-supergateway.log
  /tmp/chrome-mcp-supergateway.err
  /tmp/chrome-mcp.log
  /tmp/chrome-mcp-healthcheck.log
  /tmp/chrome-mcp-canary.log
)

for f in "${LOGS[@]}"; do
  [ -f "$f" ] || continue
  size=$(stat -f%z "$f" 2>/dev/null || echo 0)
  [ "$size" -gt "$MAX_BYTES" ] || continue
  tmp="${f}.trim.$$"
  if tail -c "$KEEP_BYTES" "$f" > "$tmp" 2>/dev/null; then
    cat "$tmp" > "$f"            # truncate same inode, keep daemon's fd valid
    rm -f "$tmp"
    echo "$(date): trimmed $f (${size}B -> ~${KEEP_BYTES}B)"
  else
    rm -f "$tmp"
  fi
done
