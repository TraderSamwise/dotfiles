---
name: queue
description: "Sam's request queue — capture and three states. Use ONLY when Sam says 'queue up' (or any misspelling: queue this, queu up, que up, add to the queue), when something is an obvious follow-up to an already-queued item, when he asks what is in his queue / what is left / what is outstanding, when he asks for this agent's own report ('/queue mine', 'what's next for you', 'what are we working on', 'what shipped', 'what landed', 'what's in flight', 'status'), or before claiming anything is done. Do NOT queue things he did not ask you to queue."
user-invocable: true
---

# Queue

`~/.local/bin/queue` is the mechanism. This file is when to reach for it.

Sam's asks arrive mid-task, as a screenshot and half a sentence, and they arrive
faster than they are finished. A queue kept in a chat message is gone at the next
compaction and cannot be checked. This one is on disk and its history is
append-only, so what was asked for survives being forgotten.

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

## The lifecycle

```
todo ─► doing ─► done
  └──────────────┘
```

**Three states and nothing else.** Sam named them on 2026-09-04 — _"todo, doing,
done. thats it."_ — and said it again on 2026-10-17 when `blocked`, `wontdo` and
`dropped` were removed from the tool: _"only 3 states."_

`doing` is not a holding pen. It means hands are on it — writing the code, debug
logging out in the wild. **Never park an item in `doing` to wait for a release.**
_"queue tasks should not wait on deployment UNLESS there is uncertainty of the
fix to a high degree. queueing is to just get shit done. ill requeue additional
fixes if needed."_ And: _"queue system is not a ticket system."_

Waiting on Sam is still `todo`. There is no state for it, because a state whose
only job is to say "stuck" is a state nobody reads — say it to him instead.

| state   | what it claims        | what the tool demands |
| ------- | --------------------- | --------------------- |
| `todo`  | he asked for it       | his words             |
| `doing` | hands are on it       | `--by`                |
| `done`  | it is committed       | **nothing**           |

```bash
queue start 947602-130 --by claude
queue done  947602-130
queue delete 947602-130            # it will not be done; it leaves the list
```

`todo → done` is legal. If you finished something without marking `doing`, close
it — do not walk it through a state to satisfy the tool.

## Done the second it is done

**Committed or merged IS the gate.** 2026-10-17: _"as soon as a feature is merged
or if done on master as soon as committed it is marked as done. ALWAYS. no 'test
it and ill mark as done' no 'human confirmation' if the feature has been
committed it is done."_

So `queue done <id>` takes no arguments and runs the moment the commit lands. Not
after CI, not after a deploy, not after Sam looks at it.

`--commit` and `--proof` still exist and are still recorded if you pass them.
They are not conditions, and **you do not hold an item open to assemble them**.
Requiring proof is what taught agents to sit on `doing` collecting evidence
instead of closing work and moving to the next thing — _"done requires nothing
holy fuck. done should be the first thing you do the second you are done."_

What has not changed: do not SAY something is done without the transition behind
it, and do not report a thing as finished that is not committed. The tool stopped
checking; the honesty did not become optional.

## Work that will not be done gets deleted

2026-10-17: _"if something is 'wont do' delete it."_

```bash
queue delete 947602-130 --why "cannot reproduce"   # --why is optional, and logged
```

There is no `wontdo` proposal and no `dropped` ruling any more. If it should not
be done, remove it and say so in your reply. The log is append-only, so a delete
is a tombstone — `queue show` can still account for the id, every view drops it.

## Order: newest first

**`queue next` takes the NEWEST unclaimed item**, not the oldest. 2026-10-17:
_"working through the queue autonomously should ALWAYS be in most recent to
oldest order. assume the most recently added things are the things i care about
the most."_

Usually he names the work. Newest-first is what "do the queue" means when he
does not.

## The backlog: a todo that has sat 7 days

A `todo` nobody has touched for seven days leaves the working list. It is not a
state and nothing moves it — `ls` and `next` derive it and skip it, so you
**cannot** pick one up by accident.

```bash
queue backlog                      # only the shelved ones
queue backlog --mine --project     # same filters as ls
```

**Leave the backlog alone unless Sam asks.** It exists so the two of you can
clean it out together; it is not a source of work to pick from. Never work a
backlog item on your own initiative, and do not propose one as "what's next".

## Reporting

When Sam asks what is left, run `queue ls` and report **that**, not your memory
of it. Never answer "what's in my queue" from context.

```bash
queue ls                  # the working list here, newest first
queue ls --project        # every worktree of this project
queue backlog             # the 7-day-old todos, only when he asks
queue show 947602-130     # one item, all its history
```

## `/queue mine [window] [all]` — what landed and what is in flight

Answer Sam's "what are we on and what shipped" in one tight report. Do not drift
into unrelated code or inventory agents he is not asking about.

**Args**, any order; if ambiguous, pick the most specific reading and proceed:

1. **Window** — `30m`, `2h`, `1d`, or `last 6 hours`, `since yesterday`, `today`.
   Default **24h**.
2. **Scope** — `all` / `everything` / `project-wide` / `fleet` means every agent
   and every master commit. Default **self**: this agent's own work.

**Self** is this agent's work in the window:

- **Commits** — `git log --since=<window>` on master and on my branch, by my
  author handle, else by my branch.
- **PRs** — open and merged PRs whose `headRefName` is my branch or one I cut.
- **Queue** — `queue ls --mine`, newest first, `doing` before `todo`. `queue`
  has no time filter, so take creation times from the FIRST event per id in
  `log.jsonl`, never from memory.
- **Branch state** — current branch, ahead/behind master, uncommitted files,
  unpushed commits.
- **Open thread** with whoever dispatched me, if any (`aimux thread list`).

**If I am an overseer** — this session has `aimux message send --from <me>` to
several agents — self also covers the agents I dispatched: their branches, PRs
and in-flight work in the window. Otherwise it is just my own branch and queue.

**Collect**, in parallel, keeping calls tight:

- `git fetch` first, then `git log --since=<window> --pretty=format:'%h %ai %s' origin/master`.
- `gh pr list --state merged --search "merged:>=<ISO>" --json number,title,mergeCommit,author --limit 50`.
- `gh pr list --state open --json number,title,headRefName,author,updatedAt --limit 50`.
- `aimux list --json` — status of each agent, and which entry is me.
- The repo's deployed-version check, if its docs name one; with `all`, also
  how far the release lane is behind master (`git rev-list --count`).

With `all`: every master commit grouped by author, every open PR with its owner
inferred from branch or author, every active agent.

**Report** — these sections, one line per item, `none` for an empty one:

```
LANDED (<N> in last <window>)
- PR #<n> <title> — <merge sha> — <owner if known>

IN FLIGHT
- <agent> on <branch>: <one-line status> — <PR if open>

QUEUE (<N> mine in last <window>)
- <id> <state> <one line>
next: <id>
```

With `all`, add `MASTER COMMITS (not in the merged-PR list)`. End with one line
on the deployed lane vs master, when the repo has one. Under ~20 lines unless
`all` over a long window.

**Leave out** agent chatter and "quiet, nothing new" lines, idle agents,
history of how the work got here, blockers unless one exists right now, and any
deploy detail beyond that one line (that is `/triage`).

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
