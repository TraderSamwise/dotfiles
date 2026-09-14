---
name: review-coderabbit
description: Use when the user says /review-coderabbit, asks to run a CodeRabbit review loop, wants CodeRabbit + sub-agent PR feedback checked, fixed, replied to, pushed, and repeated until clean, or provides one or more GitHub PR URLs or numbers for review.
metadata:
  short-description: Run the CodeRabbit + sub-agent PR review loop
---

# CodeRabbit + Sub-Agent Review Loop

Run an autonomous review loop: CodeRabbit and an in-runtime sub-agent reviewer run concurrently each round. Fix every finding, push, repeat until clean, then merge.

## Usage

The user may pass one or more PR URLs or numbers. For stacked PRs, list order is base first.

Default behavior is to **merge once the loop settles**. Skip merging only when the user says `--no-merge`, "don't merge", or "skip merge".

## Workflow

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

### 2. Kick Off Both Reviewers

Each round, run **both** in parallel:

**(a) CodeRabbit** — skip if `RATE_LIMITED=1`. Otherwise, unless `STATUS=pending`, trigger:

```bash
gh pr comment N --repo OWNER/REPO --body "@coderabbitai review"
# full re-review only when the user explicitly asks:
gh pr comment N --repo OWNER/REPO --body "@coderabbitai full review"
```

Wait via one process per PR, run concurrently. Bound the wait so a stalled or rate-limited review can't hang the loop:

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

`RATE_LIMITED` / `TIMEOUT` → treat as rate-limited for this round and rely on the sub-agent. Do not leave wait processes running when finishing the turn.

**(b) Sub-agent** — always run, regardless of CodeRabbit state. One per PR concurrently, using a lower-tier model (e.g. Sonnet on Claude side; the runtime's standard sub-agent model on Codex side). Give it `gh pr diff N`, the changed file paths, and the PR title/description. Ask for `{path, line, severity, description, suggested fix}` covering correctness bugs and reuse/simplification/efficiency findings. No style nits already enforced by linters.

### 3. Fetch + Dedupe

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

Keep threads where **not resolved** AND **no reply from `$ME`** (`$ME = gh api user --jq .login`). Cover every reviewer — CodeRabbit, Copilot, humans, other bots.

Review summary bodies (substantive feedback not posted inline):

```bash
gh api repos/OWNER/REPO/pulls/N/reviews \
  --jq "[.[] | select(.user.login != \"$ME\") | select((.body // \"\") != \"\") | {id, user: .user.login, state, body}]"
```

**Dedupe sub-agent findings against threads.** If a sub-agent finding overlaps a CodeRabbit (or other-reviewer) thread — same file, line ±5, same root cause — **drop the sub-agent copy** and handle it via the thread so the resolution is visible in the PR. Non-overlapping sub-agent findings are **orphans** that get their own PR-conversation comment in step 6.

Zero unhandled threads + zero unhandled summaries + zero orphans → step 8.

### 4. Categorize

Read code at each referenced file and line. Categorize each item:

- `Fix` — valid issue, code change required.
- `Duplicate` — same as a prior round, already fixed.
- `By design` — code is intentional.
- `Wrong` — reviewer misread or suggestion doesn't apply.

### 5. Execute Fixes

Do not ask for confirmation on straightforward fixes. Pause only for genuine product or architectural judgment.

Stacked PRs: fix base first, then merge or rebase forward into dependents before fixing those.

Each fix: read, apply the smallest appropriate change, verify with the repo's existing checks (`yarn typecheck`, `npm test`, or the project-specific equivalent).

### 6. Reply

Every unhandled thread from step 3 gets a reply, from any reviewer:

- `Fix` → `Fixed in <sha> - <one sentence>.`
- `Duplicate` → `Already addressed in <sha> - <pointer>.`
- `By design` → one or two sentences explaining why.
- `Wrong` → one or two sentences explaining why the suggestion doesn't apply.

```bash
gh api graphql -f query='mutation {
  addPullRequestReviewThreadReply(input: {
    pullRequestReviewThreadId: "THREAD_ID",
    body: "reply text"
  }) { comment { id } }
}'
```

Sub-agent **orphans**: one PR-conversation comment per finding (`gh api repos/OWNER/REPO/issues/N/comments -f body=...`) with finding + resolution so the audit trail lives on the PR.

### 7. Commit, Push, Loop

Bundle fixes per PR into one commit. Push each branch.

**Push autonomously.** Running this skill IS authorization to push through the loop — standing "ask before push" rules do not apply here. Force-push and history rewrites still require a fresh ask.

Pushing auto-triggers an incremental CodeRabbit review (unless rate-limited) → step 2. Repeat until step 3 returns zero unhandled feedback from either source.

### 8. Settled — Merge

Settled across all PRs when:

- Zero unhandled threads + zero unhandled summaries + zero sub-agent findings on the last round.
- CI green (if any required checks are configured).
- AND either CodeRabbit status is `success` on current head, OR CodeRabbit was rate-limited throughout the loop.

Report per PR: rounds taken, what was fixed, intentionally-open threads (`By design` / `Wrong` with one-line rationale), follow-ups, whether CodeRabbit participated or was rate-limited throughout.

Then **merge** — unless the user said `--no-merge` / "don't merge" / "skip merge":

- Use the repo's merge convention (check `CLAUDE.md` for forbidden modes; default `--merge`).
- Stacked PRs: base → dependents in order.
- From a worktree: `gh pr merge N --merge` without `--delete-branch` (worktree's `checkout master` cleanup fails); delete the remote branch separately if auto-delete is off.
- Print each merge commit.

If the user asked for no merge, stop here without merging.

## Operating Notes

- Autonomy is the point. Pause only for a comment that genuinely needs a human decision, or for a force-push.
- Dedupe direction: bias toward CodeRabbit (or other-reviewer) threads so resolutions show on the PR; orphan sub-agent findings get a PR-conversation comment.
- Round cap: 4+ rounds on the same PR → report remaining items and stop.
- Use `gh api`; no MCP server is required.
