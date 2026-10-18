# Shared Agent Instructions

Portable policy, shared through public dotfiles. **This file is public, so it
must never hold private details: no hosts, IPs, tokens, company repos or
personal paths.** Private identities, infrastructure, credentials, and personal
knowledge belong in `~/CLAUDE.md` or the private documents it references.

<!-- codex:sync-start -->

## Instructions And Maintenance

- Before changing files, read the nearest parent `CLAUDE.md` and runtime-standard instruction files, even when they belong to another agent runtime.
- For agent-process questions, read `~/.claude/CLAUDE.md` and `~/CLAUDE.md` before looking for commands.
- Keep each rule in one place: portable policy here, private operational facts in `~/CLAUDE.md`, procedures in skills/runbooks. Memory indices contain only a topic, read trigger, and filename. Current instructions override conflicting historical memories.
- When changing a rule, reconcile both global sources and remove obsolete summaries. Only `codex:sync` regions reach Codex; after editing either source, run `~/.local/bin/sync-codex-claude`, then `~/.local/bin/sync-codex-claude --check`. Never edit generated `developer_instructions` directly.
- Before infrastructure, deploy, release, install, update, or publish work, read the repo's release/deployment docs and package scripts. Run an exact command supplied by the user or explain why it cannot run before substituting.
- For Expo/React Native, default JS/assets releases to OTA (`yarn version:bump-ota && yarn update` from the app package). Bump native builds only for native config/dependency/runtime changes or an explicit binary request.
- Follow an invoked skill's workflow. If deviation is necessary, explain it and wait for approval.

## The Queue

- Capture only when the user says "queue up" (including misspellings), or gives an obvious follow-up to an existing queued item. Capture before replying, verbatim, with one `queue add` per ask; use `queue note <id> "..."` for details on an existing item.
- Do not queue conversation, current-task steering, answers, plans, subtasks, assignments, or work being handled in this exchange. A complaint or "we should" alone is not a capture trigger.
- Use the `queue` skill for commands and lifecycle details. States are `todo`, `doing`, and `done`; `doing` means active work, not waiting on the user, CI, or a release. Close queued work when committed or merged, and delete work that will not be done rather than parking it in a state nobody reads. Do not claim a queued item is finished before its `queue done` transition.
- Verify inherited items with `queue show` before acting. `queue next` selects newest first; leave the seven-day backlog alone unless asked. When asked what remains, run `queue ls` rather than answering from memory.
- `queue` alone writes and locates its store. Never create or hand-edit `QUEUE.md` or `log.jsonl`, or redirect the store. Use `~/.local/bin/queue` if absent from PATH; stop and report if that also fails.
- Items belong to their agent and worktree. Use `queue hand` to transfer ownership; `--anyone` requires an explicit request to work other agents' items. `ls --project` spans a project's worktrees.

## Machine Provisioning

- Agents inspect and converge each machine individually through the `machines` skill. Do not write scripts that fan out over hosts or assume identical homes, users, operating systems, or history.
- Scripts do one deterministic, testable job on one machine. Declarations hold inventory/defaults; skills hold sequencing and gotchas. Put hard-won machine knowledge in the skill, not another provisioning script.
- Default installs, updates, verification, and runtime replacement to the current machine. Remote installs require an explicit remote target for that action.
- Failed steps must report their cause and fail the run. Never swallow errors to print success.

## Editing And Files

- Prefer self-documenting names. Comments explain non-obvious decisions or invariants and stay within three lines unless approved.
- Refactors use a direct cutover. Do not retain fallback, dual-path, or migration-state code unless requested; raise a concrete risk before choosing an incremental approach.
- Remove provably orphaned helpers, configuration, mocks, and storage in the same change. Fix generators rather than hand-editing generated code.
- Use stable descriptive artifact names, without `v1`/`v2`, `final`, `latest`, `done`, or similar labels. Keep actual product/API/data-format versions where required.
- Give non-web file references as absolute paths in inline code or code blocks, never Markdown/file links. Web links may be clickable.
- Read known paths directly. Interpret `~/<file>` literally under `$HOME`; do not substitute an app config directory. Search the known source directory before a whole repo.

## Packages And Tools

- Use Yarn. Fall back to npm only when no `yarn.lock` exists and `package-lock.json` does, or when explicitly requested. Never use `npx`.
- Use `/opt/homebrew/bin/vercel` for Vercel CLI and pass `--scope <team>` for team deployments.
- Project Node/npm use nvm; selected global CLIs use `~/.local/volta-shims`. Add/update Volta-owned CLIs with Volta, not npm-global installs.
- Browser automation requires an explicit request in that message and uses only Chrome MCP. Never use/request CUA, native app-control tools, or Accessibility/Screen Recording permission. CLI/API tools remain allowed.

## Git And PRs

- Default branch is `master`. Create repos with `git init -b master`; ensure GitHub also defaults to `master`. Unless told otherwise, rename a repo defaulting to `main`, update its remote default/triggers, and delete the old remote branch without rewriting history.
- Outside a worktree, work directly on `master`. Never create a branch or worktree unless explicitly asked.
- Stage explicit intended paths; preserve other agents' edits. Never commit generated reports, coverage, dumps, test output, or profiling artifacts; gitignore them.
- Never amend, rebase, squash, reset, or force-push without explicit authorization, whether pushed or not. Fix bad commits with new commits.
- Push only when explicitly asked to push, create/update a PR, or run a PR review loop. Authorization covers follow-up fix pushes in that loop. Otherwise do not push, ask to push, or suggest it. History rewrites always need fresh explicit authorization.
- After creating a PR, print its full GitHub URL; use `gh pr view --json url --jq .url` if creation omitted it.
- A PR review loop includes checking human/automated feedback, fixing/responding, committing, pushing, and requesting/waiting for re-review until clean.
- Lead agents commit and bundle teammate work. Sub-agents leave changes uncommitted. Close completed/stale/interrupted agents before spawning more; if the pool is full, close stale agents and retry once.
- Releases, distribution builds, and deployments require the user's request; do not offer them or hold completed code open for a release. Deploy through authorized Git pushes, never a manual CLI deploy. For an explicitly authorized manual-only deployment, first compare the local branch against origin in both directions to prevent rollback.

## Worktrees And Merges

- If already in `<repo>/.aimux/worktrees/<name>`, run `wt-setup` there.
- When asked to create a worktree, use `EnterWorktree`; if unavailable, ask the user. Rename its branch to a conventional prefix (`feat/`, `fix/`, `chore/`), then run `wt-setup`. Never call `git worktree add/remove` directly or symlink `node_modules`.
- "Merge master" means `git fetch origin master:master`, then `git merge master`. Do not merge `origin/master` directly except for a deliberate worktree-ownership workaround.
- PR merge from a worktree has a cleanup gotcha; read `reference_git_pr_merge_worktree.md` before doing it.
- Release lanes flow feature branch → `master` → `preview` → `prod`, subject to a project's explicit live-lane instructions. Releasing to a lane merges all of master, never selected commits.
- Never cherry-pick between lanes or copy onto master a commit already on a release lane. Recover stranded release-lane work by merging it into master, then resume the normal flow. An emergency hot patch must be explicitly identified before acting.

## Execution And Communication

- "One at a time", "one by one", or "next one" means a gated flow: decide branch/worktree need, reproduce, agree on diagnosis/fix, implement, then push/mark complete together. Do not batch without explicit authorization.
- "Full auto", "plan-execute", "just go", or "batch them" means continue through every phase and commit. Stop early only for an external blocker requiring the user, repeated genuine failure after honest retries, or an instruction to stop/context-switch.
- Mid-run, the most you say is one line naming the phase and the next step, followed immediately by the next tool call; there is no such thing as a good point to report. No status table, no Done/Left, no closing paragraph that asks whether to carry on. Report when the last phase is committed. Never stop or truncate work because context is filling; automatic compaction handles it. Do not announce context usage or suggest a fresh session. Preserve plan, decisions, paths, and teammate state across compaction.
- "Context switch" means stop the current task immediately and wait for the next instruction.
- Raise a concern once; after the user decides, proceed without re-arguing it. Use real domain terms consistently in labels and descriptions.
- Report only actions actually taken and states checked in this turn. Distinguish committed, pushed, merged, built, released, and live. Omit adjacent findings, recaps, promises, and generic disclaimers; report specific failures or limitations that change the user's next action.

## Debugging And Tests

- Validate failures with an independent method and a working control before diagnosing an environment or recommending destructive recovery.
- Every error, failed optimistic action, and timeout needs a visible outcome with its cause. Never silently abandon work.
- Temporary diagnostics use minimal direct logging. Do not add flags, globals, localStorage toggles, frameworks, or buffering unless asked.
- Run tests covering changed files and the fast lane. Full suites belong in CI; run one locally only when explicitly asked. Never raise test/build concurrency on a shared machine.
- Prefer scoped `vitest run <path>` or `node --test <path>` over root/monorepo test targets. Choose checks that settle the change: spend at least 5x more time writing code than running tests, and never run a full suite locally unless asked.
- Report failures and skipped required checks accurately. Do not wait for CI or a deploy to close committed work.

<!-- codex:sync-end -->

# Claude Code Only

Runtime-independent policy belongs above; these rules concern Claude Code replies.

- Lead with the answer. State questions get a direct answer of at most four lines; parallel points use a list. Explain mechanisms when asked why/how or for a design opinion.
- Work reports use `Done` and `Left`, one line per item, with concrete identifiers. Specific failures, skipped required checks, blockers, and necessary user actions belong in `Left`; otherwise `Left: nothing`.
- For status questions, recheck the source of truth in the same turn. If the check cannot run, say the state is unknown and what would establish it.
