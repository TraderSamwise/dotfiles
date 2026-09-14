#!/usr/bin/env node
// SessionStart hook: auto-inject the current git repo's agent-memory INDEX into context.
//
// The global memory index lives in ~/CLAUDE.md and is always loaded; the per-repo
// indexes under ~/cs/docs/agent-memory/repos/<repo-key>/INDEX.md were "read on demand"
// — i.e. only if the agent remembered to. That made repo memories unreliable (e.g.
// missing "host X needs the VPN" and escalating instead). This loads the repo's index
// every session so the pointers are always in front of the agent. It injects the INDEX
// only (pointers), mirroring the global pattern — read the linked file before acting.
//
// repo-key derivation matches ~/CLAUDE.md: basename(dirname(<git-common-dir>)) — identical
// in a main checkout and all its worktrees. Fail-safe: any error => no output, never blocks.

const { execFileSync } = require("child_process");
const fs = require("fs");
const os = require("os");
const path = require("path");

try {
  let cwd = process.cwd();
  try {
    const data = JSON.parse(fs.readFileSync(0, "utf8"));
    if (data && typeof data.cwd === "string" && data.cwd) cwd = data.cwd;
  } catch {
    // no/invalid stdin — fall back to process.cwd()
  }

  let commonDir = "";
  try {
    commonDir = execFileSync(
      "git",
      ["-C", cwd, "rev-parse", "--path-format=absolute", "--git-common-dir"],
      {
        encoding: "utf8",
        stdio: ["ignore", "pipe", "ignore"],
      },
    ).trim();
  } catch {
    process.exit(0); // not a git repo
  }
  if (!commonDir) process.exit(0);

  const repoKey = path.basename(path.dirname(commonDir));
  const indexPath = path.join(
    os.homedir(),
    "cs",
    "docs",
    "agent-memory",
    "repos",
    repoKey,
    "INDEX.md",
  );
  if (!fs.existsSync(indexPath)) process.exit(0);

  const index = fs.readFileSync(indexPath, "utf8").trim();
  if (!index) process.exit(0);

  const header =
    `Repo-specific agent memory for \`${repoKey}\` (auto-loaded from ` +
    `~/cs/docs/agent-memory/repos/${repoKey}/INDEX.md). These are POINTERS — when a task ` +
    `touches one of these topics, read the linked file in that same directory BEFORE acting.\n\n`;

  process.stdout.write(
    JSON.stringify({
      hookSpecificOutput: {
        hookEventName: "SessionStart",
        additionalContext: header + index,
      },
    }),
  );
} catch {
  process.exit(0); // never block session start
}
