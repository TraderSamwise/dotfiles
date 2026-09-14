---
name: commit-review-flow
description: Review recent commits in a specified git worktree using git CLI. Use when the user asks for periodic code review after commits, wants review of last N commits, a commit range, or says they will point to a worktree for review.
---

# Commit Review Flow

## Overview
Provide repeatable reviews of new commits in a worktree, with optional checkpoint tracking so reviews can be incremental.

## Workflow
1. Require a worktree path. If not provided, ask for it.
2. Identify the repo root via `git -C <worktree> rev-parse --show-toplevel`.
3. Determine the commit range:
   - If the user provides a range (e.g. `A..B`) or count (e.g. last 3), use it.
   - Otherwise, check for a checkpoint file: `~/.codex/memories/last_reviewed_<repo>.txt` containing a commit SHA.
   - If checkpoint exists, review `<checkpoint>..HEAD`.
   - If no checkpoint, review last 3 commits by default.
4. Gather context:
   - `git -C <worktree> log --oneline -n <N>`
   - `git -C <worktree> show <commit>` or `git -C <worktree> diff <range>`
5. Review output:
   - Use code-review mode: order findings by severity, cite file paths.
6. Default behavior: set/update the checkpoint to the latest reviewed commit.
   - Only skip if the user explicitly says not to.
7. Write the latest reviewed commit SHA to `~/.codex/memories/last_reviewed_<repo>.txt`.

## Notes
- Prefer `git -C <worktree>` for all commands.
- When multiple commits are reviewed, summarize per-commit or per-theme.
