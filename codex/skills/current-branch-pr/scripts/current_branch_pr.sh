#!/bin/zsh
set -euo pipefail

branch="$(git branch --show-current 2>/dev/null || true)"

if [[ -z "${branch}" ]]; then
  echo "No PR"
  exit 0
fi

url="$(gh pr list --head "${branch}" --json url --jq '.[0].url' 2>/dev/null || true)"

if [[ -n "${url}" && "${url}" != "null" ]]; then
  echo "${url}"
else
  echo "No PR"
fi
