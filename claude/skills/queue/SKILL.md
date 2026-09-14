---
name: queue
description: "Sam's request queue — capture, state and proof. Use ONLY when Sam says 'queue up' (or any misspelling: queue this, queu up, que up, add to the queue), when something is an obvious follow-up to an already-queued item, when he asks what is in his queue / what is left / what is outstanding, or before claiming anything is done. Do NOT queue things he did not ask you to queue."
user-invocable: true
---

# Queue

`~/.local/bin/queue` is the mechanism. This file is when to reach for it.

Sam's asks arrive mid-task, as a screenshot and half a sentence, and they arrive
faster than they are finished. A queue kept in a chat message is gone at the next
compaction and cannot be checked. This one is on disk, its history is
append-only, and the transition that matters refuses to run without evidence.

## Capture — only on these two triggers

**1. Sam says "queue up".** That phrase, or any mangling of it — `queue up`,
`queue this`, `queu up`, `que up`, `qeueu up`, `add to the queue`. He types
fast; match the intent, not the spelling.

**2. It is an obvious follow-up to something already queued.** A correction, a
detail, a "this is wrong too" about an item that is already in there. Put it on
that item with `queue note <id> "..."`, or `queue add` a new one if it is
genuinely a different piece of work.

**That is the whole trigger list.** Nothing else goes in — not a screenshot with
a complaint, not "why is this…", not "we should…", not a bug he mentions in
passing. If he wanted it queued he will say so, and if he did not, acting on it
or answering him is the right response.

When one of the two triggers fires, capture BEFORE you reply, verbatim in his
words:

```bash
queue add "queue up: the live pill is not vertically centred, this is all over too"
```

One `queue add` per ask; five things listed is five items.

## What does NOT go in

The queue exists for asks that would otherwise be LOST. It is not a log of a
conversation, and it is not a record of the work in hand.

Do NOT capture, and do NOT `queue note`:

- Steering of the task you are doing RIGHT NOW. "ok try 6", "no, smaller",
  "that one but wider" — that is the conversation, and the conversation is
  already the tracking. Writing it down is bookkeeping nobody reads.
- A decision reached in dialogue about work already in flight.
- Answers to questions you asked.
- Your own plan, your own subtasks, your own progress.

DO capture the thing said in passing that you are NOT about to act on: a bug
mentioned while you are deep in something else, a "we should…" about a different
part of the product, a screenshot dropped mid-task. The test is simple — **if
you are going to act on it in this exchange, it does not need the queue.**

An interactive session that reaches for `queue` on every turn has misread this.

## The lifecycle, and what each state actually claims

```
todo ─► doing ─► done
  └───────┴─────► blocked / wontdo ─► dropped
```

**Three states, and Sam named them on 2026-09-04:** *"todo, doing, done. thats
it. and doing is when actively coding it or if we have to push debug logs or if
there is a real need for verification. otherwise done is done."*

So `doing` is not a holding pen. It means hands are on it — writing the code,
debug logging out in the wild, or something that genuinely cannot be settled
yet. **Never park an item in `doing` to wait for a release.** He also said:
*"queue tasks should not wait on deployment UNLESS there is uncertainty of the
fix to a high degree. queueing is to just get shit done. ill requeue additional
fixes if needed."* And: *"queue system is not a ticket system."*

`blocked`, `wontdo` and `dropped` are EXITS, not steps in that flow — waiting on
Sam, proposing to abandon, and his ruling. They are why the diagram has a second
line.

There were three states after `doing` — `landed` for a commit, `shipped` for
something a person could reach, `verified` for Sam confirming it. He collapsed
them on 2026-09-03: *"Shipped and landed are the same thing to me. Once it's
done it's done, move on. I'll report if there is a follow up."*

`wontdo` is a proposal and `dropped` is Sam's ruling — see below. An agent never
reaches `dropped` on its own.

| state | what it claims | what the tool demands |
|---|---|---|
| `todo` | he asked for it | his words |
| `doing` | hands are on it, or it truly cannot be settled yet | `--by` |
| `done` | it is written, and something you ran says so | `--commit` **and** `--proof` |
| `wontdo` | you propose abandoning it | `--why`, and it stays listed |
| `dropped` | **Sam agreed to abandon it** | Sam only |

```bash
queue start q7 --by claude
queue done  q7 --commit 3bd219a5 \
  --proof "grep of live bundle entry-f13f49de: 'How many places?' x1"
queue block q7 --why "needs the outpainted image, which I cannot generate"
queue wontdo q7 --why "cannot reproduce; propose abandoning"   # PROPOSAL only
```

Illegal jumps are refused. Nothing is done that nobody started.

## Proof is the whole point

`--proof` is a thing you **ran** and what it answered. A commit sha is not
proof — `done` asks for both because a sha alone is exactly the claim that made
this tool necessary.

**Take whatever actually settles the question, and do not wait for a deploy to
get it.** For most code that is a gate you PROVE-FAILED: broke the assertion,
watched it fail, restored it, watched it pass. That is a stronger claim than a
deploy, because it says what would catch the regression.

Reach for the running product only when nothing else can settle it — something
rendered, something deploy-dependent, a row in a database:

- a gate or test you prove-failed, named, with its count
- a grep of the **deployed** bundle for a string only that change introduces
- a live API response
- a DB row you selected
- a screenshot you actually looked at

On 2026-08-26 a page reorder was reported done when only the inner panel had
moved, and a capacity field was reported as existing when it was two clicks deep
on another tab. Both claims came from a commit rather than from the running
product. That is the failure this contract exists to make impossible.

**Then move on.** Do not hold work open waiting for Sam to confirm it, and do
not end a report with a list of things awaiting his blessing — that is the noise
he removed the states for. He will say if there is a follow-up, and a follow-up
is `queue requeue` or a new item, not a state you were keeping warm.

## Abandoning something is not yours to decide

`drop` is **Sam's**. It is the only thing that takes an ask off the list for
good, and an agent reaching for it is an agent making an inconvenient request
disappear — the exact failure this tool exists to prevent.

When you think something should not be done, propose it:

```bash
queue wontdo q7 --why "cannot reproduce without knowing which artifact he meant"
```

`wontdo` **stays on the list** with a `?` until Sam rules on it, and he rules by
running `queue drop q7 --why "..."` or `queue requeue q7`. Say out loud that you
have proposed it; do not let a `?` sit there silently hoping he never asks.

`wontdo` → `dropped` is now the only pair of its kind left: you get it to the
edge, Sam makes the call. Nothing an agent runs removes an ask from view.

## Reporting

When Sam asks what is left, run `queue ls` and report **that**, not your memory
of it. Never answer "what's in my queue" from context.

```bash
queue ls                  # outstanding in this repo
queue ls --all            # every repo
queue ls --state blocked
queue show q7             # one item, all its history
```

## Where it lives

`~/cs/docs/agent-queue/<repo-key>/` — `log.jsonl` is the truth, `QUEUE.md` is
derived. Outside every repo, because a queue is Sam's personal working context
and never a committed project file. The repo key is derived from the git common
dir, so every worktree of a repo shares one queue.

**`queue` is the only thing that ever writes those two files, and the only
thing that decides where they go.** On 2026-08-26 an agent hand-wrote a
`QUEUE.md` and a `log.jsonl` into the root of a project repo — same format,
restarted ids, a full path where the repo key belongs — duplicating two asks the
real store already held. Untracked files in a repo root are one `git add -A`
away from being committed, and Sam found them, not us.

So:

- **Never create `QUEUE.md` or `log.jsonl` anywhere.** Not in a repo, not in a
  worktree, not "temporarily". If you are typing JSON that looks like a queue
  event, stop — you are reimplementing the tool.
- **Never edit either file by hand**, wherever it lives. Run `queue`.
- **Never pass `--repo` to point the store somewhere else.** The key comes from
  git and is correct in every worktree.
- **If `queue` is not on PATH, stop and say so.** It is `~/.local/bin/queue`.
  Reproducing its format by hand is not a fallback; it silently forks the truth
  and loses the state machine that is the entire point.
- Find a stray pair in a repo? Check the real store holds the same asks, delete
  the strays, and tell Sam.

## Rules

- Capture first, answer second. An ask lost mid-task is the failure mode.
- Never edit `QUEUE.md` or `log.jsonl` by hand. Run `queue`.
- Never claim something is done in a message without the matching
  `queue` transition behind it.
- One item per ask. If he lists five things, that is five `queue add` calls.
