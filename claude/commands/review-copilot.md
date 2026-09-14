Autonomous Copilot review loop: wait for review, fix feedback, push, re-request, repeat until clean.

## Usage

`/review-copilot <pr-url-or-number> [<pr-url-or-number>...]` — one or more PRs. For stacked PRs, list base first.

## Prerequisites

Requires the `copilot-review` MCP server with tools:

- `copilot_review_status` — check if review is in progress / done
- `copilot_rerequest` — click the re-request button

Load tool schemas via `ToolSearch("select:mcp__copilot-review__copilot_rerequest,mcp__copilot-review__copilot_review_status")` before first use.

## Loop

Repeat until no new unaddressed feedback appears on any PR:

### 1. Wait for Copilot review to finish

For each PR, call `copilot_review_status`. If `in_progress: true`, sleep 20s and re-check. Continue until all PRs report `in_progress: false`.

If any PR's status is `can_rerequest: true` and hasn't been re-requested this round, re-request it first, then poll.

### 2. Fetch new unaddressed feedback

Use GraphQL `reviewThreads` (not REST — REST misses some Copilot comments):

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
            nodes {
              author { login }
              body
              path
              line
            }
          }
        }
      }
    }
  }
}'
```

Filter to threads where:

- Thread is **not resolved**
- No reply from us (`$ME` / the PR author) exists yet

**Handle every reviewer, not just Copilot.** This loop is _driven_ by Copilot's review cycle (steps 1 & 7), but while we're on the PR we address and reply to **all** unhandled threads regardless of who opened them — Copilot, CodeRabbit, humans, other bots. Leaving another reviewer's comment dangling defeats the purpose. (`$ME = gh api user --jq .login`.)

Also sweep **review summary bodies** for substantive feedback that wasn't posted as an inline thread:

```bash
gh api repos/OWNER/REPO/pulls/N/reviews \
  --jq --arg me "$ME" '[.[] | select(.user.login != $me) | select(.body != null and .body != "") | {id, user: .user.login, state, body}]'
```

For those, reply at the PR-conversation level (`gh api repos/OWNER/REPO/issues/N/comments -f body=...`) since they have no thread to reply into.

If zero unhandled threads **and** zero unhandled review summaries across all PRs → **done, exit the loop**.

### 3. Categorize each comment

Read the current code at each file:line. Categorize:

- **Fix** — Valid issue, needs a code change.
- **Duplicate** — Same issue raised in a prior round and already fixed. Reply pointing to the existing fix.
- **By design** — Code is intentional; explain why.
- **Wrong** — The reviewer misread the code or the suggestion doesn't apply.

### 4. Execute fixes

**Do NOT ask for user confirmation** unless a comment requires genuine judgment (e.g., an architectural question with no clear answer, or a suggestion that would change behavior). For straightforward fixes (null checks, case normalization, error handling, trailing slash cleanup, etc.), just fix them.

For stacked PRs: apply fixes to the correct branch. Base-PR fixes go on the base branch, then merge forward into dependent branches before fixing those.

For each fix:

- Read the file, apply the change
- Verify with `yarn typecheck` (or the project's type checker)

### 5. Commit and push

Bundle fixes per-PR into a single commit with a descriptive message. Push each branch.

### 6. Reply to EVERY comment

Every unhandled thread from step 2 gets a reply — **from any reviewer**, no exceptions. Reply format:

- **[Fix]** → `Fixed in <sha> — <one sentence>.`
- **[Duplicate]** → `Already addressed in <sha> — <pointer>.`
- **[By design]** → 1–2 sentences explaining why.
- **[Wrong]** → 1–2 sentences explaining why the suggestion doesn't apply.

Use GraphQL `addPullRequestReviewThreadReply` with the thread ID:

```bash
gh api graphql -f query='mutation {
  addPullRequestReviewThreadReply(input: {
    pullRequestReviewThreadId: "THREAD_ID",
    body: "reply text"
  }) { comment { id } }
}'
```

### 7. Re-request review and loop

Call `copilot_rerequest` for each PR, then go back to step 1.

## Notes

- **Autonomy is the point.** This skill runs hands-off. Only pause for user input when a comment genuinely needs a human decision.
- **Handle the whole PR, not just Copilot.** The wait/re-request logic in steps 1 & 7 is scoped to Copilot's review cycle, but feedback handling in steps 2–6 covers **every** reviewer's unresolved threads. Don't exit with another reviewer's comment left unanswered.
- **Don't over-fix.** If Copilot keeps raising the same issue round after round despite it being addressed, reply once more and move on — don't loop forever.
- **Track rounds.** If you've gone 4+ rounds on the same PR, report the remaining open items and ask the user if they want to continue or stop.
- **Push permissions.** Ensure `Bash(git push *)` is in the project's allow list before starting. If push prompts, flag it immediately.
