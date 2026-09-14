#!/usr/bin/env bash
# Install the Volta runtimes, package managers and CLIs listed in tools.txt, then write
# ~/.local/volta-shims — the only Volta binaries zsh/zshenv puts on PATH. Idempotent.
set -euo pipefail

TOOLS="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)/tools.txt}"
export VOLTA_HOME="${VOLTA_HOME:-$HOME/.volta}"
SHIMS="$HOME/.local/volta-shims"

if ! command -v volta >/dev/null 2>&1; then
  echo "!! volta not installed (brew install volta); skipped Volta tools" >&2
  exit 0
fi

installed="$(volta list all --format plain 2>/dev/null || true)"

# True when `volta list all` already has the tool, matching a version prefix if given.
have() {
  local spec="$1" name version
  case "$spec" in
    @*/*@*) name="${spec%@*}"; version="${spec##*@}" ;;
    @*) name="$spec"; version="" ;;
    *@*) name="${spec%@*}"; version="${spec##*@}" ;;
    *) name="$spec"; version="" ;;
  esac
  awk -v n="$name" -v v="$version" '
    $1 == "runtime" || $1 == "package-manager" || $1 == "package" {
      at = index(substr($2, 2), "@") + 1
      pn = substr($2, 1, at - 1); pv = substr($2, at + 1)
      if (pn == n && (v == "" || pv == v || index(pv, v ".") == 1)) found = 1
    }
    END { exit found ? 0 : 1 }' <<<"$installed"
}

last_node="" last_yarn="" defaults_changed=0
shim_names=()
while read -r spec shims; do
  if [ -z "${spec:-}" ] || [ "${spec#\#}" != "$spec" ]; then
    continue
  fi
  case "$spec" in
    node@*) last_node="$spec" ;;
    yarn@*) last_yarn="$spec" ;;
  esac
  if have "$spec"; then
    echo "ok     volta $spec"
  else
    volta install "$spec"
    echo "install volta $spec"
    case "$spec" in node@*|yarn@*) defaults_changed=1 ;; esac
  fi
  for s in $shims; do
    shim_names+=("$s")
  done
done <"$TOOLS"

# `volta install` makes each runtime the default, so an install mid-list can leave the
# wrong one; re-assert the last listed versions.
if [ "$defaults_changed" = 1 ]; then
  if [ -n "$last_node" ]; then volta install "$last_node" >/dev/null; fi
  if [ -n "$last_yarn" ]; then volta install "$last_yarn" >/dev/null; fi
  echo "default volta ${last_node} ${last_yarn}"
fi

mkdir -p "$SHIMS"
for s in ${shim_names[@]+"${shim_names[@]}"}; do
  f="$SHIMS/$s"
  printf '#!/bin/sh\nexec "$HOME/.volta/bin/%s" "$@"\n' "$s" >"$f.tmp"
  if [ -f "$f" ] && cmp -s "$f" "$f.tmp"; then
    rm -f "$f.tmp"
    echo "ok     shim $s"
  else
    mv "$f.tmp" "$f"
    chmod 755 "$f"
    echo "shim   $s"
  fi
done
