Review a PR's open feedback (comments from any reviewer — Copilot, humans, other bots), categorize each one, execute fixes if approved, and reply to every comment.

## Usage

`/review-feedback <pr-number>` — PR number is required.

## Hard contract

**Every open reviewer comment must receive a reply before this skill exits — no exceptions.** Whether the disposition is fix, by-design, already-fixed, or wrong, the reviewer gets a response. Silent fixes are not allowed.

## Steps

### 0. Setup

```bash
REPO=$(gh repo view --json nameWithOwner --jq .nameWithOwner)
ME=$(gh api user --jq .login)
```

### 1. Fetch open feedback from ALL reviewers

Pull review comments and review summaries from any reviewer (Copilot, human, other bots). Exclude the current user's own comments.

```bash
PR=<PR_NUMBER>

# Top-level inline review comments (not replies), from anyone except $ME.
gh api repos/$REPO/pulls/$PR/comments \
  --jq --arg me "$ME" '[
    .[] | select(.in_reply_to_id == null) | select(.user.login != $me) |
    {id, user: .user.login, path, line, body, created_at}
  ]' 2>/dev/null

# Review summaries (state + body) from non-author reviewers. Useful when the
# substance is in the review body rather than inline comments.
gh api repos/$REPO/pulls/$PR/reviews \
  --jq --arg me "$ME" '[
    .[] | select(.user.login != $me) | select(.body != null and .body != "") |
    {id, user: .user.login, state, submitted_at, body}
  ]' 2>/dev/null
```

### 2. Filter out already-replied threads

For each top-level inline comment, skip it if the current user has already posted a reply on that thread. Replies have `in_reply_to_id` pointing to the parent comment.

```bash
gh api repos/$REPO/pulls/$PR/comments \
  --jq --arg me "$ME" --argjson pid <PARENT_ID> '[
    .[] | select(.in_reply_to_id == $pid) | select(.user.login == $me)
  ] | length' 2>/dev/null
```

A thread with a reply from `$ME` is considered handled — leave it alone unless the user explicitly asks to revisit it.

### 3. If nothing's open

Two sub-cases — distinguish them before responding:

**3a. Feedback has come in at some point but every open thread is handled.** Inline + review-body lists from step 1 are empty AND there was at least one non-me review or comment in the PR's history. → Say "All feedback addressed" and stop. Do NOT poll — the PR is in a quiet steady state and the user invoked the skill to act on existing feedback, not to wait around.

**3b. PR is brand new and no reviewer has weighed in yet.** Both `reviews` (excluding mine, and excluding empty-body APPROVED/COMMENT entries that carry no inline children) and `comments` (excluding mine) are zero-length from the step 1 fetches. → **Announce that you're polling and start immediately. Do NOT ask permission** — the user invoked the skill on a new PR; the implicit ask is "wait for feedback". Say something like _"No feedback yet — polling every 30 s up to 5 min."_ and start the loop.

Polling is allowed **only** in case 3b (or case 4 below). For case 3a, never poll.

Poll cadence: every 30 s up to 5 min. Re-check both endpoints (Copilot often lands as a review body, not inline comments):

```bash
gh api repos/$REPO/pulls/$PR/comments \
  --jq --arg me "$ME" '[.[] | select(.in_reply_to_id == null) | select(.user.login != $me)] | length' 2>/dev/null

gh api repos/$REPO/pulls/$PR/reviews \
  --jq --arg me "$ME" '[.[] | select(.user.login != $me) | select(.body != null and .body != "")] | length' 2>/dev/null
```

When either count goes 0 → N, send a terminal notification and resume from step 1.

### 4. If a review was requested but hasn't been submitted yet

If the PR has open `requested_reviewers` (someone the author specifically asked to review) and that reviewer hasn't commented, treat it the same as 3b — announce and poll, no permission ask. Same cadence (every 30 s up to 5 min), same notification on arrival.

```bash
gh api repos/$REPO/pulls/$PR/comments \
  --jq --arg me "$ME" '[.[] | select(.in_reply_to_id == null) | select(.user.login != $me)] | length' 2>/dev/null
```

### 5. Categorize each open comment

Read the current code at each file:line referenced. Categorize:

- **Fix** — Valid issue that needs a code change.
- **By design** — The code is intentional. Reviewer is correct that it looks odd; explain why it stays.
- **Already fixed** — Was addressed in a later commit but no reply was posted.
- **Wrong** — Reviewer misread the code or the suggestion doesn't apply.

### 6. Present categorized list to user

Show a numbered list with category, reviewer, file:line, and a one-line summary:

```
1. [Fix] @Copilot bitunix.exchange.ts:941 — Align fetchPositionMode default with fetchBalance
2. [By design] @alice ChartCore.ts:815 — Viewport preserved across bar clears (ViewScaleState handles it)
3. [Already fixed] @bob TealchartWidget.ts:935 — Always call setPaneYRanges even when empty
4. [Wrong] @Copilot orderForm.ts:42 — Suggests adding null check we don't need (already guaranteed by caller)
```

### 7. Get user confirmation

Ask: "Proceed with these dispositions, or adjust any?" Wait. Never act on an unconfirmed disposition. The user may reclassify items (e.g. "1 is actually by-design, write a reply").

### 8. Execute fixes (for [Fix] items)

For each confirmed `[Fix]`:

- Read the file, apply the fix, verify it compiles (`yarn typecheck` in the affected package), run tests if available.
- Stage, commit (small focused commit per logical change), push.
- Capture the resulting commit SHA — needed for the reply.

For `[By design]`, `[Already fixed]`, and `[Wrong]` items: no code change in this step.

### 9. Reply to EVERY open comment

Mandatory. Every item from step 6 gets a reply, regardless of disposition.

```bash
gh api repos/$REPO/pulls/$PR/comments/<COMMENT_ID>/replies \
  -f body="<reply>"
```

Reply shape per disposition (keep terse — 1–2 sentences max):

- **[Fix]** → `Fixed in <sha> — <one sentence on what changed>.`
- **[By design]** → 1–2 sentences explaining the architectural reasoning. Not just "intentional" — explain _why_ (constraint, prior incident, downstream contract).
- **[Already fixed]** → `Already addressed in <sha> — <one-sentence pointer>.`
- **[Wrong]** → 1–2 sentences explaining why the suggestion doesn't apply (caller guarantees it, type system enforces it, etc.).

If the substance was in a review body rather than an inline comment, post a reply at the PR-conversation level instead:

```bash
gh api repos/$REPO/issues/$PR/comments \
  -f body="<reply addressing @reviewer's summary review>"
```

### 10. Verify nothing was missed

After replies are posted, re-run step 2's filter and confirm zero open comments remain (unless the user explicitly chose to defer one). If anything slipped through, post the missing reply now.

### 11. Re-review loop

After any round that changed code, re-trigger the reviewer and wait for the next pass, then repeat the whole cycle until the reviewer returns no actionable comments.

- CodeRabbit: post `@coderabbitai review`. Copilot/human: `gh api -X POST repos/$REPO/pulls/$PR/requested_reviewers -f 'reviewers[]=Copilot'`.
- Poll every 30 s up to ~6 min for a new review after the latest push (CodeRabbit signal: `Actionable comments posted: N`; Copilot: a new review `submitted_at`). Notify when it lands.
- New actionable comments → back to step 5 and loop. Zero → done, exit and report.

Stop only on: a clean pass, an explicit user stop, or a non-converging loop (reviewer re-flags something already dispositioned, or no convergence after ~4 rounds — surface it instead of churning commits).

## Notes

- **Any reviewer counts** — this skill was renamed from `/review-copilot` precisely to stop being Copilot-specific. Don't filter by reviewer login; filter by "not me".
- **The reply contract is the point.** A fix without a reply leaves the reviewer with no acknowledgement that their comment was read. Always close the loop in-thread.
- **Don't fix without confirmation.** The user owns the disposition; the skill executes it.
- **Replies must be substantive.** "Done" is not enough — say what was changed (Fix), why it stays (By design), where it was already done (Already fixed), or why the suggestion misses (Wrong).
- **Re-running is safe.** The step-2 filter excludes already-handled threads, so a partial run can be resumed without double-posting.
