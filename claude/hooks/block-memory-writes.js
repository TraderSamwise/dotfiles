#!/usr/bin/env node
// Hard-block writes to the per-cwd auto-memory system.
//
// That feature is banned: it keys storage by working directory, so every
// worktree (and every repo) is its own silo — knowledge written in one is
// invisible everywhere else. Durable knowledge instead lives in
// ~/cs/docs/agent-memory/ (indexed from ~/CLAUDE.md) or a repo's committed
// CLAUDE.md / AGENTS.md. See the "Agent Memory" section of ~/CLAUDE.md.

const fs = require("fs");

let data;
try {
  data = JSON.parse(fs.readFileSync(0, "utf8"));
} catch {
  process.exit(0); // can't parse input — don't block
}

const input = data.tool_input || {};
const target = input.file_path || input.path || input.notebook_path || "";

if (/\/\.claude\/projects\/[^/]+\/memory\//.test(target)) {
  process.stderr.write(
    "BLOCKED: the per-cwd auto-memory system is banned (it silos knowledge per " +
      "working directory — every worktree is a black hole). Do NOT write to " +
      "~/.claude/projects/*/memory/. Put durable knowledge in ~/cs/docs/agent-memory/ " +
      "with a one-line entry in the ~/CLAUDE.md Agent Memory Index, or in the repo's " +
      "committed CLAUDE.md / AGENTS.md. Then run ~/.local/bin/sync-codex-claude."
  );
  process.exit(2); // exit 2 = block the tool call, feed stderr back to the model
}

process.exit(0);
