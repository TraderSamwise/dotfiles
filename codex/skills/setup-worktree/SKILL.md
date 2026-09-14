---
name: setup-worktree
description: Set up a git worktree per Sam's global rules. Use when Sam says setup worktree, set up worktree, init worktree, worktree setup, wt-setup, or asks how to create or prepare a worktree.
---

# Setup Worktree

`~/CLAUDE.md` is policy. `~/.local/bin/wt-setup` is the executable setup path.

## Workflow

1. Read the Worktrees section of `~/CLAUDE.md`.
2. Do not create a worktree unless Sam explicitly asked for one.
3. If already inside an Aimux worktree at `<repo>/.aimux/worktrees/<name>`, skip creation and run:

```bash
wt-setup
```

4. If a worktree exists elsewhere, run:

```bash
wt-setup <main-repo-path>
```

5. If Sam explicitly asks to create a new worktree and this runtime has no `EnterWorktree` tool, say that plainly and ask Sam to create/enter it through Aimux or a runtime with `EnterWorktree`.

## Rules

- Use `wt-setup`, not hand-rolled env symlinks or dependency installs.
- Do not run `git worktree add/remove` directly.
- Do not symlink `node_modules`.
