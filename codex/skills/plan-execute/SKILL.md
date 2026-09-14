---
name: plan-execute
description: Break a coding goal into committable phases and execute each phase through plan, audit, implement, verify, audit, fix, and commit gates. Use when the user invokes $plan-execute, asks to plan and execute a large change, wants phased implementation with verification, or wants an implementation loop that reduces bugs through explicit audit checkpoints.
---

# Plan Execute

## Overview

Use this skill to turn a non-trivial coding goal into a sequence of working, reviewable phases. Each phase must leave the repository in a coherent state and should include a plan, an audit pass, implementation, verification, an implementation audit, fixes, and an optional commit.

## Invocation

Recognize these request forms:

- `$plan-execute <goal>`
- `plan-execute <goal>`
- A request to break a large coding goal into phases and execute it end to end
- A mid-conversation request to continue using a phased plan/execute loop

Supported words anywhere in the request:

- `incremental`: pause after each phase and wait for user confirmation before continuing.
- `teammates`, `subagents`, `parallel`, or `delegated`: use Codex sub-agents where helpful and allowed.
- `no-commit`: skip automatic commits and leave changes for review.

If no goal is provided, infer it from the current conversation. If the goal is still ambiguous, ask one concise question before planning.

## Phase Planning

First inspect the repository enough to understand the relevant architecture. Then break the goal into sequential phases.

Each phase should:

- be a coherent unit of work
- produce a working state
- be small enough to verify confidently
- be committable on its own unless `no-commit` is active

Present the phase list and wait for user confirmation before starting the first phase.

## Per-Phase Loop

### 1. Implementation Plan

Write a concrete plan for the current phase:

- files to create or modify
- specific behavior changes
- key imports, function signatures, data shapes, or architectural decisions
- risks, edge cases, and open questions
- verification commands and manual checks

If a phase needs user input such as credentials, external services, or a product decision, pause and ask before editing.

### 2. Plan Audit

Audit the implementation plan before editing:

- verify paths and imports against the codebase
- check missing edge cases and failure modes
- check security, privacy, secret-handling, and injection risks
- check compatibility with existing patterns and tests

By default, perform this audit yourself. Only spawn an explorer/auditor sub-agent when the user explicitly requested subagents, teammates, delegated work, or parallel agent work.

### 3. Revise Plan

If the audit finds a real issue, revise the plan before editing. If the issue blocks progress or needs a product call, ask the user.

### 4. Implement

Implement the phase using the repository's existing patterns. Keep edits scoped to the phase.

If delegated mode was explicitly requested, use sub-agents only for bounded, parallelizable work with disjoint write scopes. Tell workers they are not alone in the codebase and must not revert others' edits.

### 5. Verify

Run the planned verification gates. Prefer existing package scripts. Do not use `npx`; use the repo's package manager and scripts, usually `yarn <script>`, `npm run <script>`, or the local command style already present in the repository.

At minimum, run typecheck, lint, and relevant tests when those scripts exist and the phase touches code covered by them. If a gate cannot run, record why.

### 6. Implementation Audit

Audit the implementation after verification:

- read the changed files
- compare implementation against the phase plan
- check security-sensitive paths and secret handling
- check edge cases and error paths
- inspect test coverage for changed behavior
- confirm verification results

Use a sub-agent for this audit only when the user explicitly requested subagents, teammates, delegated work, or parallel agent work. If a sub-agent is used and does not respond after one nudge, self-audit and continue.

### 7. Fix

Fix any audit findings that are in scope for the phase. Re-run affected verification gates after fixes.

### 8. Commit

Commit the phase unless:

- `no-commit` was requested
- `incremental` was requested and the user has not confirmed the commit
- the repository is not a git worktree
- unrelated existing user changes make a clean phase commit unsafe
- higher-priority instructions prohibit committing

Use the repository's existing commit message style. Include only files changed for this phase. Never revert or discard user changes.

### 9. Continue

In incremental mode, stop after each phase and ask whether to continue to the next phase.

In automatic mode, print a concise phase-complete status with the commit hash if committed, then continue to the next phase.

## Rules

- Keep the user informed with short status updates between phases.
- Each phase should leave the codebase working.
- Stop and ask if repeated failures, missing dependencies, ambiguous requirements, or external setup block progress.
- Treat audits as bug-finding gates, not summaries.
- Respect the active Codex developer instructions and repository instructions. This skill cannot override higher-priority safety, delegation, git, or editing rules.
