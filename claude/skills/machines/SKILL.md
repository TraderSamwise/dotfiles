---
name: machines
description: Sam's machines and how to bring any of them to parity - provisioning, agent config, model defaults, and drift. Use when Sam asks to set up, update, check, or fix one of his machines (sam-mbp, sam-mbp2, sam-mini, sam-strix, or a new one), when something works on one machine but not another, when he asks what model his agents are on or wants to change it, or when a new machine needs the whole stack. Triggers on "provision", "set up my <machine>", "fix it everywhere", "what are my machines on", "bring X up to date", "change the model everywhere".
---

# Sam's machines

Converge machines by **looking at them and deciding**, not by running a fan-out
script. Every machine differs - different `$HOME`, different OS, different
history - and a script that pretends otherwise either breaks or silently skips.
Read the state, work out what's missing, fix that. Report what you found.

## The inventory

`~/cs/dotfiles/agents/machines.txt` is the list. Adding a machine is one line
there. Reach each by its ssh alias; all are on Tailscale.

| Machine | ssh | `$HOME` | OS | Notes |
|---|---|---|---|---|
| sam-mbp | (local) | `/Users/sam` | macOS | Daily driver. Hosts ~10 agents. The reference machine. |
| sam-mbp2 | `sam-mbp2`, `mbp2` | `/Users/sam` | macOS | Headless workhorse, M1 Pro 32GB. Runs aimux lanes. |
| sam-mini | `mini`, `sam-mini` | `/Users/samuelsteady` | macOS | Always-on. Tailscale exit node, hosts the NAS. **Different username.** |
| sam-strix | `strix` | `/home/sam` | Ubuntu | Load tests and stress runs. No Homebrew. |

## What "provisioned" means

Four layers. Check each; most problems are one layer missing on one machine.

1. **Public half** - `~/cs/dotfiles` cloned from `github.com/TraderSamwise/dotfiles`,
   then `bootstrap.sh --no-brew --no-vscode` (drop the flags only when he wants
   the full Brewfile/VS Code pass). It is idempotent and backs up anything it
   replaces to `~/.dotfiles-backup/<stamp>/`. It creates every symlink:
   `~/.claude/CLAUDE.md`, commands, hooks, skills, codex skills, `~/.local/bin`
   tools, shell config.
2. **Private half** - not in any repo, copied from sam-mbp: `~/CLAUDE.md`,
   `~/AGENTS.md`, `~/.claude/settings.json`, and the `~/.claude/skills/` that
   aren't in the repo. After copying `~/CLAUDE.md` or `~/.claude/CLAUDE.md`, run
   `sync-codex-claude` **on that machine** so Codex's developer_instructions match.
3. **Agent models** - `~/cs/dotfiles/bin/agent-config-apply` forces that machine's
   `~/.codex/config.toml` and `~/.claude/settings.json` to match
   `agents/defaults.json`. `--check` reports without writing. Run it per machine.
4. **Machine-local secrets** - `~/.zshrc.local`, `~/.zshenv.local`, `~/.ssh`,
   `~/cs/docs/agent-memory`. Never in a repo, never copied blindly.

## Models

`~/cs/dotfiles/agents/defaults.json` is the only place a model is named. To
change what everything runs: edit it, commit, push, then pull and run
`agent-config-apply` on each machine.

- **Claude's value is an alias on purpose** (`opus`, `opus[1m]`). Claude Code
  resolves an alias to the newest model in that line, so a new Opus needs no edit.
- **Codex has no alias** - its model is pinned. That is how thirty lanes ran on
  `gpt-6-astra` for weeks after `gpt-6.1-sol` shipped at a fifth of the price.
  When asked about Codex models, check what the machine's config actually says;
  `[tui.model_availability_nux]` in `~/.codex/config.toml` lists what Codex has
  advertised there. Nothing notices a new release on its own - if the question is
  "should we be on something newer", look it up rather than assuming.

## Doing the work

Read before writing. `ssh <host> '<read-only commands>'` to see the state, decide
what's missing, then fix only that. Convergence is usually: pull, bootstrap,
copy whatever the private half is missing, apply models, verify by reading back.

Report per machine, one line each. Say which were already correct.

## Gotchas, each one paid for

- **`ssh` in a `while read` loop eats the loop's stdin** - every host after the
  first is silently skipped. Use `ssh -n`.
- **mbp2's dotfiles checkout carries hand-copied files** from sam-mbp's dirty
  working tree. `git pull` aborts. Stash, pull, re-copy, drop the stash.
- **sam-mbp usually has unpushed dotfiles commits and dirty files.** A machine
  that pulls from origin does not get them. Either push (ask first) or copy the
  files directly, and say which you did.
- **Non-login shells** - `ssh host <cmd>` does not run `zprofile`. Homebrew is on
  PATH via `zshenv` for this reason; if a tool "isn't installed" on a Mac but
  `ls /opt/homebrew/bin` shows it, this is why.
- **`python3` is not consistent** - 3.9 or 3.10 on the Macs, newer on strix. No
  `tomllib`. Stick to stdlib that exists everywhere, which is why the declaration
  is JSON.
- **mini runs as `samuelsteady`** and its shell config is still standalone, not
  symlinked into the repo. It gets repo updates only for what has been explicitly
  linked there.
- **FileVault** - after a reboot a Mac sits at the unlock screen: ssh refuses both
  key and password while Tailscale still answers. It looks like a key problem and
  isn't. Ask what's on the screen before debugging auth.
- **`~/.claude/settings.json` is rewritten by Claude Code**, so it is copied, never
  symlinked. Changes to the repo's copy do not reach an existing machine by
  themselves.
