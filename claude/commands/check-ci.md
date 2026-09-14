Check GitHub Actions CI and Vercel deployment status for the current branch or a specific PR.

## Usage

The user may provide a PR number or branch name. If not provided, use the current branch.

## Steps

1. Detect repo and branch:

```bash
REPO=$(gh repo view --json nameWithOwner --jq .nameWithOwner)
CURRENT_BRANCH=$(git branch --show-current)
echo "Repo: $REPO, Branch: $CURRENT_BRANCH"
```

2. Check if there's an open PR for this branch:

```bash
gh pr list --head "$CURRENT_BRANCH" --json number,title,url,statusCheckRollup --limit 1
```

3. If a PR exists, show its check status:

```bash
gh pr checks <PR_NUMBER>
```

4. Also check recent workflow runs for this branch:

```bash
gh run list --branch "$CURRENT_BRANCH" --limit 5 --json databaseId,displayTitle,status,conclusion,createdAt,workflowName
```

5. If any GitHub Actions runs failed, show the failure details:

```bash
gh run view <RUN_ID> --log-failed 2>/dev/null | tail -50
```

6. If Vercel deployment failed, get the deployment logs:

```bash
# Extract deployment ID (dpl_XXXX) from the Vercel check URL in gh pr checks output
# If .vercel/project.json exists, use it. Otherwise try without --scope.
npx vercel inspect <DEPLOYMENT_ID> --logs 2>/dev/null | tail -30
```

If `vercel inspect` fails with "Deployment not found", the project may be in a different team scope. Check `.vercel/project.json` for the org/team ID, or ask the user which Vercel team to use.

7. Report a summary:
   - Overall status (passing/failing/pending)
   - List each check with its status
   - For failures, show the relevant error output
   - Link to the PR or run on GitHub

## Notes

- If no branch is specified and we're on master, show the latest runs on master instead
- If a PR number is provided directly (e.g., `/check-ci 4952`), use that instead of branch detection
- Keep output concise — only show failure details for failed checks
- Vercel deployment IDs look like `dpl_XXXX` and can be extracted from the Vercel check URL
