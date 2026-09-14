---
name: current-branch-pr
description: Echo the GitHub pull request URL for the current git branch or worktree if one exists, or say that there is no PR. Use when the user asks for the PR for the current branch, current worktree, or wants the current branch PR opened or echoed.
---

# Current Branch PR

## Workflow
1. Run the bundled script from the current repo or worktree root:
   ```bash
   ~/.codex/skills/current-branch-pr/scripts/current_branch_pr.sh
   ```
2. If it prints a URL, return that URL directly to the user.
3. If it prints `No PR`, tell the user there is no PR for the current branch.

## Notes
- The script uses the current checked-out branch and `gh pr list --head` to find the PR.
- Prefer this skill over manually reassembling `gh` commands when the user only wants the current branch PR.
