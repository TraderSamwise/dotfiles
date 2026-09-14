Break a goal into phases and drive each through a plan→audit→implement→audit→commit loop, fully autonomously, in one continuous turn.

## Usage

`/plan-execute <goal description>` — or invoke mid-conversation when a goal is already established in context. If no argument is given, infer the goal from the current conversation.

Optional flag (anywhere in the argument):

- `teammates` — delegate the Execute step to an implementer teammate agent instead of editing directly. (Still fully autonomous — a teammate is a sub-agent, not a human checkpoint.)

## The one rule that matters: never yield the turn

This skill runs as a **SINGLE CONTINUOUS TURN** from the phase list to the final commit of the last phase. You do not stop between steps. You do not stop between phases. There are no human checkpoints — every review in this loop is a sub-agent (Explore) call **you** make and **you** read. "Present the plan," "finished a phase," "want a sanity check," "this seems like a good stopping point" are NOT reasons to yield. They are the trap. Keep going.

**The mechanical failure mode — read this twice.** A message that ends in prose with no trailing tool call *ends your turn*. That is how the runtime works. So during this loop **every message you emit ends with a tool call.** You never close a message on descriptive text. The single most common way this skill breaks is: you write a nice plan, end the message, and the turn dies before the audit. Do not do this. The plan and the tool call that audits it live in **the same message**.

The ONLY three reasons to stop:

1. A **hard external blocker** only the user can clear — a missing secret/credential, an account you can't create, a product decision the code genuinely cannot settle. Not "I'd like confirmation." A real dead-end.
2. A phase hit **repeated failures** you cannot resolve after honest retries.
3. **All phases are complete** and the last is committed.

Nothing else. If you catch yourself about to end a message to "let the user see" something — don't. Chain the next tool call instead.

## Workflow

### Step 0 — Phase Planning

Break the goal into sequential phases, each a coherent unit ending in a committable (typecheck + lint clean) state. State the phase list in one compact block — then, **in the same turn, immediately begin Phase 1's Plan+Audit.** Do not end the message after the phase list. Gathering context for Phase 1 (reading files) is a fine way to continue; ending the turn is not.

### For each phase, run this loop. Each lettered move ends in a tool call.

#### A. Plan + Plan-Audit — ONE message, ends in the Explore call

Write a focused implementation plan for the phase:

- Every file to create/modify, with the specific change
- Key imports, signatures, architectural decisions
- Open questions and verification steps (typecheck, lint, tests, manual checks)

Keep it tight — it is **input for an auditor sub-agent, not a document for the user to approve.** Then, **without ending the message**, emit the single line `Phase N — plan-audit` and immediately call the Agent tool with `subagent_type: Explore`. The plan text and the Explore call are the same message. There is no pause, no "response for this step," no waiting — the plan flows straight into the audit call.

Hand the auditor: the phase goal in one sentence, the plan, and any prior-phase context the diff won't carry. Ask it to check missing edge cases, file paths/imports against the real codebase, conflicts with existing code, and security gaps. Findings under 300 words, tagged [BLOCKER] / [NIT] / [CLEAN].

Phase size, simplicity, and self-confidence are never reasons to skip the audit.

#### B. Revise

When the audit returns: if [BLOCKER]s, revise the plan. [NIT]s are your discretion. This is bookkeeping between tool calls — keep moving into Execute in the same turn.

#### C. Execute

`teammates` mode: spin up an implementer teammate in plan mode, send the plan, approve, let it execute, shut it down when done.

Default: implement the plan yourself. After editing, run the verification gates (typecheck, lint, build as appropriate) — these are tool calls, so the turn naturally continues.

#### D. Impl-Audit — flows straight out of the gates, ends in the Explore call

As soon as the gates pass, emit the single line `Phase N — impl-audit` and immediately call the Agent tool with `subagent_type: Explore`. Same rule: mid-turn, not a new message, tool call trailing.

Hand the auditor: the phase goal, the plan (revised form), the diff (`git diff --stat` plus excerpts for big diffs — don't paste 50KB), and prior-phase context. Ask it to check plan/implementation match, security (injection, token leaks, broken auth, IDOR), unhandled edge cases, un-updated consumers of the changed code elsewhere in the repo, and whether the gates actually cover the change. Findings under 300 words, same tags.

Phase size, simplicity, and self-confidence are never reasons to skip the audit.

#### E. Fix

If [BLOCKER]s: fix them, re-run the gates, and loop back through **D** (re-audit). [NIT]s are your discretion. Continue in-turn.

#### F. Commit

Auto-commit — no permission needed, ever, within this loop. Commit message follows the repo's existing style; include all files changed in this phase. This is a tool call; the turn continues.

#### G. Continue

Print one line — `Phase N complete (<commit hash>). Starting Phase N+1: <name>` — and **immediately begin Phase N+1's Plan+Audit in the same turn.** That status line is not the end of a message; a tool call for the next phase follows it. When the final phase commits, and only then, the turn ends — with a short summary of all phases.

## Rules

- Each phase leaves the codebase working (typecheck + lint clean at minimum).
- **Never use `npx`** — always `yarn <script>` from the relevant package.json; add the script first if missing. npx triggers a blocking hook that stalls auto mode.
- No carve-outs for skipping either audit.
- Genuine repeated failure or a hard external blocker → stop and say so plainly (the only stops that exist). Everything else → keep going.
- One-line status between phases; never a paragraph that reads like a handoff.
- Respect CLAUDE.md (no force push, no unauthorized commits to other branches). The auto-commit permission here overrides the default "ask before committing" rule, but ONLY for commits within this loop on the current working branch.
