Autonomous review loop: CodeRabbit + sub-agent run concurrently, fix every finding, push, repeat until clean, then merge.

## Usage

`/review-coderabbit <pr-url-or-number> [<pr-url-or-number>...] [--no-merge]`

- One or more PRs. For stacked PRs, list base first.
- Default merges once the loop settles. `--no-merge` (or "don't merge" / "skip merge" in prompt) stops after the loop.

## Flow

### 1. Triage

Per PR:

```bash
SHA=$(gh pr view N --repo OWNER/REPO --json headRefOid --jq .headRefOid)
STATUS=$(gh api /repos/OWNER/REPO/statuses/$SHA --jq '[.[] | select(.context == "CodeRabbit")] | .[0].state // ""')
LAST_CR=$(gh api repos/OWNER/REPO/issues/N/comments \
  --jq '[.[] | select(.user.login=="coderabbitai[bot]")] | last | .body // ""')
echo "$LAST_CR" | grep -iq "rate limit" && RATE_LIMITED=1 || RATE_LIMITED=0
```

If there's already unhandled feedback on the PR, skip the trigger and go straight to step 3.

### 2. Kick off both reviewers

Each round, run **both** in parallel:

**(a) CodeRabbit** — skip if `RATE_LIMITED=1`. Otherwise, unless `STATUS=pending`, trigger:
```bash
gh pr comment N --body "@coderabbitai review"
# full re-review only when user explicitly asks:
gh pr comment N --body "@coderabbitai full review"
```
Wait via background bash loop (`run_in_background: true`), one per PR concurrently:
```bash
SHA=$(gh pr view N --repo OWNER/REPO --json headRefOid --jq .headRefOid)
for i in $(seq 1 20); do
  state=$(gh api /repos/OWNER/REPO/statuses/$SHA --jq '[.[] | select(.context == "CodeRabbit")] | .[0].state')
  [ "$state" = "success" ] && { echo OK; exit 0; }
  gh api repos/OWNER/REPO/issues/N/comments \
    --jq '[.[] | select(.user.login=="coderabbitai[bot]")] | last | .body' | grep -iq "rate limit" \
    && { echo RATE_LIMITED; exit 0; }
  sleep 30
done
echo TIMEOUT
```
`RATE_LIMITED` / `TIMEOUT` → set `RATE_LIMITED=1` for this round and rely on the sub-agent.

**(b) Sub-agent** — always. Spawn `Agent` with `subagent_type: general-purpose`, `model: sonnet` (or the project's `code-review` skill if present), one per PR concurrently. Give it `gh pr diff N`, changed file paths, and PR title/description. Ask for `{path, line, severity, description, fix}` covering correctness bugs + reuse/simplification/efficiency. No style nits.

### 3. Fetch + dedupe

CodeRabbit + other reviewer threads:
```bash
gh api graphql -f query='
{
  repository(owner: "OWNER", name: "REPO") {
    pullRequest(number: N) {
      reviewThreads(last: 50) {
        nodes {
          id
          isResolved
          comments(first: 5) {
            nodes { author { login } body path line }
          }
        }
      }
    }
  }
}'
```
Keep threads where **not resolved** AND **no reply from `$ME`** (`$ME = gh api user --jq .login`). Cover every reviewer (CodeRabbit, Copilot, humans, other bots).

Review summary bodies (substantive feedback not posted inline):
```bash
gh api repos/OWNER/REPO/pulls/N/reviews \
  --jq "[.[] | select(.user.login != \"$ME\") | select((.body // \"\") != \"\") | {id, user: .user.login, state, body}]"
```

**Dedupe sub-agent findings against threads**: if a sub-agent finding overlaps a CodeRabbit thread (same file, line ±5, same root cause), **drop the sub-agent copy** — handle it via the thread so the resolution is visible in the PR. The remainder are **orphans** that get their own PR-conversation comment in step 6.

Zero unhandled threads + zero unhandled summaries + zero orphans → **step 8**.

### 4. Categorize

Read code at each `file:line`. Categorize each item:
- **Fix** — valid issue, code change required.
- **Duplicate** — same as a prior round, already fixed.
- **By design** — intentional.
- **Wrong** — reviewer misread or suggestion doesn't apply.

### 5. Execute fixes

Don't ask for confirmation on straightforward fixes. Pause only for genuine judgment calls.

Stacked PRs: fix base first, merge forward, then dependents.

Each fix: read, edit, verify with `yarn typecheck` (or project's checker).

### 6. Reply

Every unhandled thread from step 3 gets a reply (any reviewer):
- **[Fix]** → `Fixed in <sha> — <one sentence>.`
- **[Duplicate]** → `Already addressed in <sha> — <pointer>.`
- **[By design]** → 1–2 sentences why.
- **[Wrong]** → 1–2 sentences why the suggestion doesn't apply.

```bash
gh api graphql -f query='mutation {
  addPullRequestReviewThreadReply(input: {
    pullRequestReviewThreadId: "THREAD_ID",
    body: "reply text"
  }) { comment { id } }
}'
```

Sub-agent **orphans**: one PR-conversation comment per finding (`gh api repos/OWNER/REPO/issues/N/comments -f body=...`) with finding + resolution.

### 7. Commit, push, loop

Bundle fixes per-PR into one commit. Push each branch.

**Push autonomously.** Running this skill IS authorization. Force-push / history rewrites still need a fresh ask.

Pushing auto-triggers an incremental CodeRabbit review (unless rate-limited) → step 2. Repeat until step 3 returns zero unhandled across both sources.

### 8. Settled — merge

Settled across all PRs when:
- Zero unhandled threads + zero unhandled summaries + zero sub-agent findings on the last round.
- CI green (if required checks are configured).
- AND either CodeRabbit status is `success`, OR CodeRabbit was rate-limited throughout the loop.

Report per PR: rounds, what was fixed, intentionally-open threads with one-line rationale, follow-ups, whether CodeRabbit participated.

Then **merge** unless `--no-merge`:
- Repo's merge convention (check `CLAUDE.md` for forbidden modes; default `--merge`).
- Stacked PRs: base → dependents.
- From a worktree: `gh pr merge N --merge` without `--delete-branch`; delete the remote branch separately if auto-delete is off.
- Print each merge commit.

`--no-merge` → stop without merging.

## Notes

- **Autonomy.** Pause only for human-decision comments or force-push.
- **Dedupe direction.** Bias toward CodeRabbit threads so resolutions show on the PR; orphan sub-agent findings get a PR-conversation comment.
- **Round cap.** 4+ rounds → report remaining and stop.
- **Rate limit = move on.** When CodeRabbit is rate-limited, the sub-agent review is its full substitute for that round — not a placeholder to revisit. Do NOT escalate to `@coderabbitai full review`, re-trigger, or wait/poll for a "genuine" CodeRabbit pass. CodeRabbit often reports a hollow `success` status (or "Review finished") when the underlying review never ran due to the limit and no walkthrough was produced — treat that as settled anyway and proceed to merge on the strength of the sub-agent. Chasing a real CodeRabbit pass after a rate limit is out of scope.
- **No MCP needed.** `gh api` only.
