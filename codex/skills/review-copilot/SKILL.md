---
name: review-copilot
description: Review GitHub Copilot PR feedback using the GitHub CLI. Use when the user says /review-copilot with a PR number, asks to check Copilot review comments, or wants Copilot feedback summarized, triaged, and responded to on a PR.
---

# Review Copilot

## Overview
Fetch Copilot PR review comments with `gh`, categorize them against current code, and either fix in code or reply on the PR.

## Workflow
1. Detect repo: `gh repo view --json nameWithOwner --jq .nameWithOwner`.
2. Fetch Copilot inline comments:
   - `gh api repos/$REPO/pulls/<PR>/comments --jq '.[] | select(.user.login == "Copilot") | {id, path, line, body}'`
3. If no comments, poll every 30s up to 5 minutes, then report none found.
4. For each comment, open the file and line, inspect current code, and categorize:
   - `Fix` — valid issue, needs code change
   - `By design` — intentional, explain why
   - `Already fixed` — addressed by later commits
5. Present a numbered list: `1. [Fix] path:line — summary`.
6. Ask the user what to fix.
7. Execute fixes and commit. For `By design` or `Already fixed`, reply on the PR:
   - `gh api repos/$REPO/pulls/<PR>/comments/<ID>/replies -f body="<reply>"`
8. Optionally re-poll after changes.

## GitHub CLI notes
- Prefer `gh` for PR data, reviews, and comments.
- If queries fail due to missing scopes, run:
  - `gh auth refresh -h github.com -s read:org`
- If API requests fail with network errors inside the sandbox, rerun with escalated permissions.
