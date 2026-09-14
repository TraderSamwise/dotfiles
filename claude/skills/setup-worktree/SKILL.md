---
name: setup-worktree
description: "Set up a git worktree per the user's global CLAUDE.md rules. Use when the user says: setup worktree, set up worktree, init worktree, /setup-worktree. Also use when the user asks to create a new worktree (which requires explicit ask per global rules)."
user-invocable: true
---

# Setup Worktree

Follow the **"Worktrees"** section of `~/CLAUDE.md` exactly. That section is the source of truth — do not reinterpret it.

## What to do

1. **Read `~/CLAUDE.md`** if you haven't this session, specifically the "Worktrees" section.

2. **If you are already inside a worktree** (e.g. an aimux worktree was created for you):
   - Skip the `EnterWorktree` and branch-rename steps.
   - Just run `wt-setup` from inside the current worktree. The script lives at `~/.local/bin/wt-setup` and handles symlinking `.env` files (root + `apps`/`packages`/`services`), the `.vercel` dir, and running `yarn install --frozen-lockfile`.
   - The main repo path is the parent repo this worktree was created from. For aimux worktrees under `<repo>/.aimux/worktrees/<name>`, the main repo is `<repo>`.

3. **If no worktree exists yet** and the user has explicitly asked for one:
   - Use the `EnterWorktree` tool — never `git worktree add` directly.
   - Rename the branch from `worktree-<name>` to a conventional-commit prefix (`feat/`, `fix/`, `chore/`, etc.) with `git branch -m`.
   - Then run `wt-setup` from inside the new worktree.

## Hard rules (from global CLAUDE.md)

- Do **NOT** symlink `node_modules` — yarn workspace symlinks break across worktrees. `wt-setup` already handles this correctly.
- Do **NOT** create a worktree unless the user explicitly asked for one. "Fix this bug" / "implement X" do not imply a worktree.
- Use `wt-setup`, not a hand-rolled symlink + install sequence. The script is the canonical setup.
