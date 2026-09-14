#!/usr/bin/env bash
# Claude Code status line - inspired by powerlevel9k style
# Receives JSON via stdin

input=$(cat)

# Extract fields
cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // empty')
model=$(echo "$input" | jq -r '.model.display_name // empty')
used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
vim_mode=$(echo "$input" | jq -r '.vim.mode // empty')
session_name=$(echo "$input" | jq -r '.session_name // empty')

# ANSI colors using $'...' so escape sequences are interpreted
RESET=$'\033[0m'
BOLD=$'\033[1m'
CYAN=$'\033[36m'
GREEN=$'\033[32m'
YELLOW=$'\033[33m'
MAGENTA=$'\033[35m'
BLUE=$'\033[34m'
RED=$'\033[31m'
DIM=$'\033[2m'

# Shorten home directory
if [ -n "$cwd" ]; then
  home="$HOME"
  short_cwd="${cwd/#$home/~}"
else
  short_cwd="~"
fi

# Git branch (skip optional lock to avoid conflicts)
git_branch=""
if [ -n "$cwd" ] && git -C "$cwd" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  branch=$(git -C "$cwd" --no-optional-locks symbolic-ref --short HEAD 2>/dev/null || git -C "$cwd" --no-optional-locks rev-parse --short HEAD 2>/dev/null)
  if [ -n "$branch" ]; then
    git_branch=" ${DIM}${GREEN}${branch}${RESET}"
  fi
fi

# Context usage progress bar
ctx_str=""
if [ -n "$used_pct" ]; then
  pct_int=${used_pct%.*}
  if [ "$pct_int" -ge 80 ] 2>/dev/null; then
    ctx_color=$RED
  elif [ "$pct_int" -ge 50 ] 2>/dev/null; then
    ctx_color=$YELLOW
  else
    ctx_color=$GREEN
  fi
  # Build a 10-character progress bar
  bar_width=10
  filled=$(( pct_int * bar_width / 100 ))
  empty=$(( bar_width - filled ))
  bar=""
  for i in $(seq 1 $filled); do bar="${bar}█"; done
  for i in $(seq 1 $empty); do bar="${bar}░"; done
  ctx_str=" ${ctx_color}${bar}${RESET}${DIM}${pct_int}%${RESET}"
fi

# Model name (short)
model_str=""
if [ -n "$model" ]; then
  model_str=" ${DIM}${MAGENTA}${model}${RESET}"
fi

# Session name
session_str=""
if [ -n "$session_name" ]; then
  session_str=" ${DIM}[${session_name}]${RESET}"
fi

# Vim mode
vim_str=""
if [ -n "$vim_mode" ]; then
  if [ "$vim_mode" = "INSERT" ]; then
    vim_str=" ${GREEN}INSERT${RESET}"
  else
    vim_str=" ${YELLOW}NORMAL${RESET}"
  fi
fi

# User and host
user=$(whoami)
host=$(hostname -s)

printf '%s' "${CYAN}${user}@${host}${RESET} ${BLUE}${short_cwd}${RESET}${git_branch}${ctx_str}${model_str}${session_str}${vim_str}"
