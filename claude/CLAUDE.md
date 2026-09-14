# Shared Agent Instructions

Portable rules for every coding agent on any machine. This file is public (it lives in the
dotfiles repo and is linked as `~/.claude/CLAUDE.md`), so it must never hold private
details: no hosts, IPs, tokens, company repos or personal paths. Those go in `~/CLAUDE.md`.

<!-- codex:sync-start -->

## Instruction Discovery

Before changing files, read the nearest applicable parent `CLAUDE.md` and any runtime-standard agent instruction files. Treat the nearest applicable parent instructions as active even when the filename comes from another agent runtime.
For agent-process questions, read `~/.claude/CLAUDE.md` and `~/CLAUDE.md` before searching repo commands or guessing tool names.
Before infrastructure, deploy, release, install, update, or publish work, reread the repo's release/deployment docs and package scripts first; if Sam gives an exact command, run that exact command or stop and explain why before substituting.
For Expo/React Native projects, default mobile JS/assets releases to OTA (`yarn version:bump-ota && yarn update` from the app package); use native build bumps only when native config/dependencies/runtime changed or Sam explicitly asks for a new binary.

## Skills

When a skill is invoked, follow its workflow exactly. If you need to deviate, surface the deviation first and wait for approval.

## The Queue

Everything I ask for goes on disk before it goes anywhere else. `queue`
(`~/.local/bin/queue`) is the tool; the `queue` skill is the workflow. Use it
**whether or not I invoke it and whether or not I say the words "queue up"**.

Capture on TWO triggers and nothing else:

1. **I say "queue up"** — or any mangling of it: `queue up`, `queue this`,
   `queu up`, `que up`, `qeueu up`, `add to the queue`. I type fast; match the
   intent, not the spelling.
2. **It is an obvious follow-up to something already queued** — a correction or
   a detail about an item that is already in there. `queue note <id> "..."`, or
   `queue add` if it is genuinely different work.

That is the whole list. A screenshot with a complaint, a "why is this…", a "we
should…", a bug I mention in passing — none of those go in. If I want it queued
I will say so; otherwise answer me or fix it. The queue is for asks that would
otherwise be LOST, never a log of a conversation or a record of the work in
hand: if you are going to act on it in this exchange, it does not need the
queue.

When a trigger fires, capture BEFORE you reply, verbatim in my words:

```bash
queue add "queue up: the live pill is not vertically centred, this is all over too"
```

One `queue add` per ask; five things listed is five items.

**todo, doing, done. That is it.** `todo` → `doing` (`--by`) → `done`
(`--commit` AND `--proof`). Skipping a state is refused.

**This is not a ticket system.** Queueing is to get shit done. I will requeue
additional fixes if I need them.

- **`doing` means hands are on it** — actively writing it, debug logging out in
  the wild, or something that genuinely cannot be settled yet. It is not a
  holding pen. **Never park an item there waiting for a deploy.**
- **`done` is done.** Do not hold work open waiting for my blessing and do not
  end a report with a list of things awaiting it. I will say if there is a
  follow-up, and that is a new item or a `queue requeue`, not a state you kept
  warm.
- **`--proof` is something you RAN and what it answered.** Take whatever
  actually settles the question, and do not wait on a deploy to get it. For most
  code that is a gate you PROVE-FAILED — broke the assertion, watched it fail,
  restored it, watched it pass — which is a stronger claim than a deploy because
  it also says what would catch the regression. Go to the running product only
  when nothing else can settle it: something rendered, something
  deploy-dependent, a database row. A commit sha is never proof on its own,
  because a claim made from a sha alone is why this tool exists.
- **`blocked`, `wontdo` and `dropped` are exits, not steps.** Waiting on me,
  you proposing to abandon something, and my ruling.
- **`dropped` is mine alone.** Abandoning something I asked for is my call, and
  a tool that lets an agent do it is a tool that lets an inconvenient request
  disappear. If you think something should not be done, propose it with
  `queue wontdo <id> --why "..."` and SAY SO — that keeps it on the list with a
  `?` until I rule with `queue drop` or `queue requeue`. You take it to the
  edge, I make the call.
- Never say something is done in a message without the matching `queue`
  transition behind it.

When I ask what is left, run `queue ls` and tell me what it says — never answer
from memory or from a summary. `queue show <id>` gives one item's whole history.

An item belongs to the agent that queued it and to the worktree it was queued
in — ids say whose (`pzjidx-3`), and both are read from the environment rather
than declared. Take work with `queue next`: your items, in this tree. Another
agent's item is refused; `queue next --anyone` is for when I ask you to do
every agent's work in this tree. `queue ls` is this tree, `--project` is every
tree of this project, and there is no view across projects. I move work between
agents with `queue hand <id> --to <agent>`.

Storage is `~/cs/docs/agent-queue/<repo-key>/`, outside every repo, because a
queue is my personal working context and never a committed project file.
`log.jsonl` is the truth and is append-only; `QUEUE.md` is derived.

**`queue` is the only thing that writes those two files, and the only thing that
decides where they go.** Never create a `QUEUE.md` or a `log.jsonl` yourself —
not in a repo, not in a worktree, not temporarily. Never edit either by hand.
Never redirect the store; the repo key comes from git and is right in every
worktree. If `queue` is not on PATH it is `~/.local/bin/queue` — and if you
still cannot run it, STOP AND SAY SO. Hand-reproducing its format is not a
fallback: it forks the truth, drops the state machine, and leaves untracked
files in a repo root one `git add -A` from being committed. That happened on
2026-08-26 and I found it, not you.

## Editing Style

- Comments must not exceed 3 lines unless explicitly approved.
- Prefer self-documenting names over comments.
- Keep comments only for non-obvious decisions, gotchas, or invariants.
- Do direct cutovers when refactoring or replacing systems; do not leave fallback, dual-path, or migration-state code unless explicitly asked.
- If direct cutover seems risky, raise the risk before choosing an incremental path.

## Deliverable Naming And Versioning

- NEVER name documents, files, or artifacts with finality/status labels like `final`, `FINAL`, `send-this`, `latest`, `done`, `current`, or `real`. It is never actually the final draft.
- ALWAYS version explicitly with `v1`, `v2`, `v3`, … and increment on every revision. Applies to filenames, artifact titles, document headers, and any in-doc version/draft labels.
- This covers everything I produce: local files, Google Drive docs, claude.ai artifacts, PDFs, etc.

## File Lookup

- For files with known paths, read them directly instead of searching.
- When Sam says "home <file>" or `~/<file>`, treat it as the literal path under `$HOME` first; do not reinterpret "home" as an app config directory unless he says config, settings, or dotdir.
- Common root files are at the project root: `README.md`, `CHANGELOG.md`, `LICENSE`, `package.json`, `tsconfig.json`, `vitest.config.ts`, `.gitignore`, `.env.example`.
- Avoid broad recursive searches from repo root when a source directory or exact path is known; broad searches often include `node_modules` and bury useful results.
## Package And CLI Defaults

- Use `yarn` for package commands. Fall back to npm only if there is no `yarn.lock` and a `package-lock.json` exists, or if explicitly asked.
- Never use `npx`.
- Use `/opt/homebrew/bin/vercel` directly for Vercel CLI; do not assume `yarn vercel` or local `node_modules/.bin/vercel` exists. Pass `--scope <team>` for team-scoped deployments.
- Project shells use nvm for `node`/`npm`; Yarn and selected global CLIs use Volta shims in `~/.local/volta-shims` (`yarn`, `codex`, `eas`, `claude`, etc.). Add/update Volta-owned CLIs with Volta, not npm-global installs.

## Hard Rules

- Never use the chrome-devtools MCP unless told to in that message — it drives Sam's real browser.

## Git And PRs

- Default branch is ALWAYS `master`, never `main`. Create new repos with `git init -b master`; after `gh repo create`, ensure the default is `master`. When you land in a repo that defaults to `main`, rename it to `master` (`git branch -m main master`, `git push -u origin master`, `gh repo edit <repo> --default-branch master`, `git push origin --delete main`) unless I say otherwise. Point every CI/deploy/production trigger at `master`.
- When you are NOT in a worktree, work directly on `master` — do not create a branch unless I explicitly ask for one. This holds for every project of mine. Committing straight to `master` is the default, not a fallback. Branching unasked also yanks the branch out from under any other agent sharing the checkout, so their commits land somewhere I never asked for.
- Never commit generated artifacts — reports, coverage snapshots, corpus dumps, test output, profiling results: if a script writes it, gitignore it instead.
- Never rewrite history unless I explicitly ask: no amend, rebase, squash, reset or force-push, pushed or not. Fix a bad commit with another commit.
- Pushing is allowed only when I explicitly say "push", ask to open/create/update a PR, or ask for a PR review loop. In those authorized contexts, push without asking — including follow-up fix commits pushed during a review loop; do NOT prompt for permission on each push once the context is authorized. Outside an authorized context, do not push after committing, do not ask, and do not suggest. (Force-push / history rewrites are never covered by this — they always require a fresh explicit ask.)
- Always print the full GitHub PR URL after creating a PR. If `gh pr create` does not surface it, run `gh pr view --json url --jq .url`.
- A PR review loop means: check reviewer feedback, fix/respond, commit, push, request or wait for re-review, and repeat until clean. This includes CodeRabbit, Copilot, and similar workflows.
- Lead/root agents handle commits and bundle teammate work at natural breakpoints.
- Sub-agents/teammates never commit; they leave changes uncommitted and keep working through assigned tasks.
- Close completed, stale, or interrupted sub-agents before spawning more; do not leave them occupying concurrency slots.
- If spawning a sub-agent fails because the pool/thread limit is saturated, immediately close stale or completed sub-agents and retry once before continuing without the requested sub-agent review.

## Worktrees

- Never create a worktree unless I explicitly ask for one.
- If already inside an Aimux worktree at `<repo>/.aimux/worktrees/<name>`, skip creation and run `wt-setup` from that worktree.
- If I ask to create a worktree, use the `EnterWorktree` tool if your runtime has it (Claude Code does; otherwise ask me), rename the branch to a conventional prefix (`feat/`, `fix/`, `chore/`, etc.), then run `wt-setup`.
- Do not use `git worktree add/remove` directly. Do not symlink `node_modules`.

## Sequential Work

When I say "one at a time", "one by one", "next one", or similar, use a gated collaborative flow:

1. Decide whether a worktree/branch is needed.
2. Reproduce or confirm the issue.
3. Agree on the diagnosis and fix.
4. Implement.
5. Push/mark complete together.

Do not chain through the list autonomously unless I explicitly say "do them autonomously", "just go", "batch them", or similar.

## Context Switch

When I say "context switch", drop the current task immediately and wait for the next instruction.

## Git Merge And PR Merge

- "Merge master" means `git fetch origin master:master`, then `git merge master`.
- Do not merge `origin/master` directly unless working around worktree ownership constraints with eyes open.
- Merging a PR from inside a worktree has a local-cleanup gotcha — see memory `reference_git_pr_merge_worktree.md`.

### Release lanes: master → preview, full merge, always

**Every branch flows ONE way: feature branch → `master` → `preview` → `prod`.**
Releasing to a lane means merging **all of master** into it. Full yolo. Not a
cherry-pick, not a subset, not "just this commit".

**NEVER cherry-pick between lanes, and never cherry-pick a commit onto `master`
that already exists on `preview` or `prod`.** A cherry-pick copies content under
a new SHA, so git no longer sees the two as the same change — the next
master→lane merge then conflicts on every line both sides touched, and the merge
has to be hand-resolved. That is not a hypothetical: it happened 2026-08-17,
produced nine conflicts, and silently blocked a
preview push that looked like it had succeeded.

If work is stranded on `preview` that `master` lacks, the fix is to merge
**preview into master** and then resume the normal one-way flow. Never the
reverse, and never a cherry-pick.

**The only exception is an emergency hot patch**, and it must be named as one out
loud before doing it. Everything else waits for master.

## Debug Logging

- When temporary logging is needed, log directly; do not add runtime flags, globals, or localStorage toggles unless asked.
- Keep logging minimal. No logging frameworks, tracers, buffering systems, or fancy table/grouped console output unless asked.

## Running Tests

Run the test files covering what you changed, not the whole suite. Full-suite
targets (`test-ci`, `test:ci`, `yarn test` at a monorepo root) exist to saturate
a CI runner; on this machine ten agents doing that at once oversubscribes the
CPU by an order of magnitude.

- Default to `vitest run <path>` / `node --test <path>` scoped to the touched files.
- Run the full suite only when I ask, or as the final gate before a PR.
- Never raise `TEST_CONCURRENCY` / `TURBO_CONCURRENCY` to "speed things up" —
  those caps exist because the machine is shared with other agents.

<!-- codex:sync-end -->

# Claude Code Only


Everything below this line stays out of Codex. Add a rule here only when it is meaningless to Codex — Claude Code output style, Claude-Code-only MCP servers, Claude-Code-only tools and context handling.

## Message Shape

Length rules failed because they cap size, not form, and because "unless it matters" lets me override every one of them. So: form is mandated, and there is no exception clause.

**Every message you send is exactly one of these four shapes. If what you are writing is not one of them, it is wrong — cut it until it is.**

1. **Answer** — a direct answer, at most 4 lines, no preamble. A yes/no question gets yes or no first, then at most one clause.
2. **List** — labeled items, one line each. This is the DEFAULT whenever there is more than one thing to say. Prose paragraphs are not a valid shape for multi-item content.
3. **Done / Left** — the only shape for reporting work. Two headed lists, nothing else. No narrative, no rationale, no "worth knowing".
4. **Explanation** — prose, only when I asked why, how, or for a design opinion. This is the only shape where paragraphs are allowed.

### First line

The first line is the answer alone. Not context, not what you checked, not what you were about to say. If I stopped reading after line one, I should have what I asked for.

### Banned moves

These are not "avoid" — they are never correct. No judgment call, no "this case warrants it":

- Mechanism when I asked for state. I asked what, not why it works.
- Any section I did not ask for — "two things to note", "worth knowing", "one caveat", adjacent findings, next steps, risks.
- Self-assessment of any kind: what you got wrong, what you learned, how you'll do better, what a mistake reveals. Fix it and move on.
- Recaps, restating my own message back to me, closing summaries.
- Explaining a correction. Make it, state the new fact in one line, stop.
- Hedging finished work: "not tested in production", "you may want to verify", "worth double-checking", "in theory this should work", "unverified at runtime", "to be fully transparent", "I should note".
- Restating obvious limits nobody implied ("this only affects X", "this won't fix Y").

Real failures, skipped steps, and gates you did not run are REPORTED, in the Left list. That is the result, not a disclaimer.

### Before sending

Check the message against this section. If it is prose and I did not ask why — rewrite it as a list. If it contains a section I did not ask for — delete that section. You gate code with typecheck and tests; gate the message the same way.

## Status Questions

When I ask where we are in a plan, what shipped, what is in the last build, what is committed / pushed / merged, whether the release is out, or what is next:

**Never state a push, merge, build or release state from memory — re-read the source of truth in
the same turn you say it.** This applies to a state I asked about AND to one you volunteer, which
is where it actually goes wrong: a "still unpushed" line carried forward into report after report
while I had pushed hours earlier. What you knew a turn ago is not evidence. `git fetch` then
`git rev-list --left-right --count origin/<branch>...<branch>`, `gh run list`, the deployment
list — whichever answers the claim — and if you cannot run it, say the state is unknown rather
than repeating the last one you saw.

- Verdict in the first line. Yes or no, shipped or not, merged or not, in the build or not.
- Be exact about which state holds — committed, pushed, merged, built, released, live are different things. Name the one that is true instead of blurring them into "done".
- One line per item. Always a list, never prose.
- Check before answering, then give the answer, not the check. No verification narration, no command transcripts, no reasoning trail.
- Unknown after checking: say unknown in one line, and what would settle it.
- "What's next" is a separate question. Answer it when I ask it.

Worked example — "did we build locally from source?" is answered like this:

> App: yes — OTA v3 (`ffdcd2f3`) carries the keyboard fix, live on TestFlight.
> CLI: no — installed bundle predates both Exposé commits.

Not with the investigation that produced it.

## Reporting Work

Use the Done / Left shape. Nothing else goes in the message.

- **Done** — what is finished, one line each, with the identifier that proves it: commit hash, PR number, file path, test count.
- **Left** — what is not finished, one line each. Includes failures, skipped steps, gates not run, and anything blocked. If nothing is left, write "Left: nothing".
- A caveat that changes what I do next ("needs an app reload", "only applies after redeploy") is one line in Left, stated once.
- If it typechecks, lints, and tests pass, it is Done, plainly. No confidence qualifiers.
- Never amplify severity with words that carry no action: a real working issue gets one sincere line in Left, and a closing paragraph about what a mistake reveals or what pattern it fits gets cut entirely.

## Context Management

- Warn me when context usage exceeds 70% and suggest compacting.
- Compact at natural breakpoints when possible.
- Preserve current plan, key decisions, file paths, and active teammate state across compaction.
