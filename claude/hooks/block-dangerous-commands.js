#!/usr/bin/env node
/**
 * Block Dangerous Commands - PreToolUse Hook for Bash
 * Blocks dangerous patterns before execution. Logs to: ~/.claude/hooks-logs/
 *
 * SAFETY_LEVEL: 'critical' | 'high' | 'strict'
 *   critical - Only catastrophic: rm -rf ~, dd to disk, fork bombs
 *   high     - + risky: force push main, secrets exposure, git reset --hard
 *   strict   - + cautionary: any force push, sudo rm, docker prune
 *
 * Setup in .claude/settings.json:
 * {
 *   "hooks": {
 *     "PreToolUse": [{
 *       "matcher": "Bash",
 *       "hooks": [{ "type": "command", "command": "node /path/to/block-dangerous-commands.js" }]
 *     }]
 *   }
 * }
 */

const fs = require("fs");
const path = require("path");

const SAFETY_LEVEL = "high";

const PATTERNS = [
  // CRITICAL - Catastrophic, unrecoverable
  {
    level: "critical",
    id: "rm-home",
    regex: /\brm\s+(-.+\s+)*["']?~\/?["']?(\s|$|[;&|])/,
    reason: "rm targeting home directory",
  },
  {
    level: "critical",
    id: "rm-home-var",
    regex: /\brm\s+(-.+\s+)*["']?\$HOME["']?(\s|$|[;&|])/,
    reason: "rm targeting $HOME",
  },
  {
    level: "critical",
    id: "rm-home-trailing",
    regex: /\brm\s+.+\s+["']?(~\/?|\$HOME)["']?(\s*$|[;&|])/,
    reason: "rm with trailing ~/ or $HOME",
  },
  {
    level: "critical",
    id: "rm-root",
    regex: /\brm\s+(-.+\s+)*\/(\*|\s|$|[;&|])/,
    reason: "rm targeting root filesystem",
  },
  {
    level: "critical",
    id: "rm-system",
    regex:
      /\brm\s+(-.+\s+)*\/(etc|usr|var|bin|sbin|lib|boot|dev|proc|sys)(\/|\s|$)/,
    reason: "rm targeting system directory",
  },
  {
    level: "critical",
    id: "rm-cwd",
    regex: /\brm\s+(-.+\s+)*(\.\/?|\*|\.\/\*)(\s|$|[;&|])/,
    reason: "rm deleting current directory contents",
  },
  {
    level: "critical",
    id: "dd-disk",
    regex: /\bdd\b.+of=\/dev\/(sd[a-z]|nvme|hd[a-z]|vd[a-z]|xvd[a-z])/,
    reason: "dd writing to disk device",
  },
  {
    level: "critical",
    id: "mkfs",
    regex: /\bmkfs(\.\w+)?\s+\/dev\/(sd[a-z]|nvme|hd[a-z]|vd[a-z])/,
    reason: "mkfs formatting disk",
  },
  {
    level: "critical",
    id: "fork-bomb",
    regex: /:\(\)\s*\{.*:\s*\|\s*:.*&/,
    reason: "fork bomb detected",
  },

  // HIGH - Significant risk, data loss, security
  {
    level: "high",
    id: "curl-pipe-sh",
    regex: /\b(curl|wget)\b.+\|\s*(ba)?sh\b/,
    reason: "piping URL to shell (RCE risk)",
    decision: "deny",
  },
  {
    level: "high",
    id: "git-force-main",
    regex:
      /\bgit\s+push\b(?!.+--force-with-lease).+(--force|-f)\b.+\b(main|master)\b/,
    reason: "force push to main/master",
  },
  {
    level: "high",
    id: "git-reset-hard",
    regex: /\bgit\s+reset\s+--hard/,
    decision: "deny",
    reason:
      "git reset --hard is denied (it can silently discard uncommitted work). Use a non-destructive alternative: to point a clean/freshly-cut branch at another ref use `git checkout -B <branch> <ref>`; to drop specific local edits use `git restore <paths>`; to undo commits but keep changes use `git reset --soft <ref>`. If a hard reset is truly required, ask the user to run it.",
    yolo: "allow",
  },
  {
    level: "high",
    id: "git-clean-f",
    regex: /\bgit\s+clean\s+(-\w*f|-f)/,
    reason: "git clean -f deletes untracked files",
    yolo: "allow",
  },
  {
    level: "high",
    id: "chmod-777",
    regex: /\bchmod\b.+\b777\b/,
    reason: "chmod 777 is a security risk",
  },
  {
    level: "high",
    id: "cat-env",
    // Exempt .env.example / .sample / .template / .dist / .defaults — those
    // are committed templates without real secrets. Real .env.* (local,
    // production, staging, test, ...) still blocked. `\S*` allows path
    // prefixes like apps/web/.env.
    regex: /\b(cat|less|head|tail|more)\s+(?:\S+\s+)*\S*\.env(?!\.(?:example|sample|template|dist|defaults)\b)/,
    reason: "reading .env file exposes secrets",
    decision: "deny",
  },
  {
    level: "high",
    id: "cat-secrets",
    regex:
      /\b(cat|less|head|tail|more)\b.+(credentials|secrets?|\.pem|\.key|id_rsa|id_ed25519)/i,
    reason: "reading secrets file",
    decision: "deny",
  },
  {
    level: "high",
    id: "env-dump",
    // Boundary class catches env after start, whitespace, shell separators
    // (;, &, |), subshell/group openers ((, `), or quote chars used by
    // `bash -c "..."` / eval. Optional `\S*\/` lets path-prefixed forms
    // like /usr/bin/env match. `env\s*(?:[;&|]|$)` still requires env be
    // run bare (not `env VAR=1 cmd`), preserving the env-as-prefix form.
    regex: /\b(?:\S*\/)?printenv\b|(?:^|[\s;&|(`"'])\s*(?:\S*\/)?env\s*(?:[;&|]|$)/,
    reason: "env dump may expose secrets",
    decision: "deny",
  },
  {
    level: "high",
    id: "echo-secret",
    regex: /\becho\b.+\$\w*(SECRET|KEY|TOKEN|PASSWORD|API_|PRIVATE)/i,
    reason: "echoing secret variable",
    decision: "deny",
  },
  {
    level: "high",
    id: "docker-vol-rm",
    regex: /\bdocker\s+volume\s+(rm|prune)/,
    reason: "docker volume deletion loses data",
    yolo: "allow",
  },
  {
    level: "high",
    id: "rm-ssh",
    regex: /\brm\b.+\.ssh\/(id_|authorized_keys|known_hosts)/,
    reason: "deleting SSH keys",
  },

  // HIGH - Bypass yarn scripts (Claude must read package.json first)
  {
    level: "high",
    id: "npx-bypass",
    regex: /^\s*npx\s+(cypress|vitest|jest|eslint|tsc|tsup|turbo|next)\b/,
    reason:
      "Do not use npx directly. Read package.json and use the correct yarn script",
    decision: "deny",
    yolo: "allow",
  },
  {
    level: "high",
    id: "node-script-bypass",
    regex: /^\s*node\s+.*scripts\//,
    reason:
      "Do not run scripts directly with node. Read package.json and use the correct yarn script",
    decision: "deny",
    yolo: "allow",
  },
  {
    level: "high",
    id: "npm-instead-of-yarn",
    regex: /^\s*npm\s+(run|install|test|start|build)\b/,
    reason: "This project uses yarn, not npm. Read package.json and use yarn",
    decision: "deny",
    yolo: "allow",
  },

  // HIGH - Soft asks (mirrors settings.json `ask` list). Under CLAUDE_YOLO=1
  // these auto-allow so overnight loops aren't blocked on recoverable ops.
  {
    level: "high",
    id: "git-rewrite-history",
    regex: /\bgit\s+(?:commit\s+(?:[^\n]*\s)?--amend|rebase\b|push\s+(?:[^\n]*\s)?(?:--force\b|-f\b)|reset\s+(?:[^\n]*\s)?--hard\b)/,
    reason: "git amend / rebase / force-push / reset --hard rewrites history, including commits Sam has already pulled",
    yolo: "deny",
  },
  {
    level: "high",
    id: "git-checkout-restore",
    regex: /\bgit\s+(?:checkout\s+--|restore\b)/,
    reason: "git checkout -- / git restore discards working-tree changes",
    yolo: "allow",
  },
  {
    level: "high",
    id: "git-worktree-mut",
    regex: /\bgit\s+worktree\s+(add|remove)\b/,
    reason: "git worktree add/remove (use EnterWorktree per CLAUDE.md)",
    decision: "deny",
    yolo: "allow",
  },
  {
    level: "high",
    id: "git-reset-soft",
    regex: /\bgit\s+reset\s+--soft\b/,
    reason: "git reset --soft rewinds HEAD",
    yolo: "allow",
  },

  // STRICT - Cautionary, context-dependent
  {
    level: "high",
    id: "git-force-any",
    regex: /\bgit\s+push\b.+(--force|-f)\b/,
    reason: "force push / history rewrite requires explicit approval",
  },
  {
    level: "strict",
    id: "git-checkout-dot",
    regex: /\bgit\s+checkout\s+\./,
    reason: "git checkout . discards changes",
    yolo: "allow",
  },
  {
    level: "high",
    id: "sudo-rm",
    regex: /\bsudo\s+rm\b/,
    reason: "sudo rm has elevated privileges",
    decision: "deny",
  },
  {
    level: "strict",
    id: "docker-prune",
    regex: /\bdocker\s+(system|image)\s+prune/,
    reason: "docker prune removes images",
    yolo: "allow",
  },
  {
    level: "high",
    id: "crontab-r",
    regex: /\bcrontab\s+-r/,
    reason: "removes all cron jobs",
    decision: "deny",
  },
];

const LEVELS = { critical: 1, high: 2, strict: 3 };
const EMOJIS = { critical: "🚨", high: "⛔", strict: "⚠️" };
const LOG_DIR = path.join(process.env.HOME, ".claude", "hooks-logs");

function log(data) {
  try {
    if (!fs.existsSync(LOG_DIR)) fs.mkdirSync(LOG_DIR, { recursive: true });
    const file = path.join(
      LOG_DIR,
      `${new Date().toISOString().slice(0, 10)}.jsonl`,
    );
    fs.appendFileSync(
      file,
      JSON.stringify({ ts: new Date().toISOString(), ...data }) + "\n",
    );
  } catch {}
}

// Detect a Bash command that WRITES into the banned per-cwd auto-memory dir
// (~/.claude/projects/*/memory/). Reads (cat/ls/grep) and rm cleanup are allowed;
// only writes are blocked. Backstops the Write/Edit-tool hook for shell writes.
function writesToMemory(cmd) {
  const MEM = String.raw`\.claude/projects/[^/\s]+/memory/`;
  return [
    new RegExp(String.raw`(>>?|\btee\b(\s+-a)?)\s*["']?\S*` + MEM), // redirection / tee
    new RegExp(String.raw`\b(cp|mv|install|ln|touch)\b[^|;&]*` + MEM), // copy/move/link/touch in
    new RegExp(String.raw`\bsed\b[^|;&]*-i[^|;&]*` + MEM), // in-place edit
    new RegExp(String.raw`\bmkdir\b[^|;&]*\.claude/projects/[^/\s]+/memory`), // recreate dir
    new RegExp(String.raw`\bdd\b[^|;&]*of=\S*` + MEM), // dd into
  ].some((re) => re.test(cmd));
}

function checkCommand(cmd, safetyLevel = SAFETY_LEVEL) {
  const threshold = LEVELS[safetyLevel] || 2;
  for (const p of PATTERNS) {
    if (LEVELS[p.level] <= threshold && p.regex.test(cmd)) {
      return { blocked: true, pattern: p };
    }
  }
  return { blocked: false, pattern: null };
}

async function main() {
  let input = "";
  for await (const chunk of process.stdin) input += chunk;

  try {
    const data = JSON.parse(input);
    const { tool_name, tool_input, session_id, cwd, permission_mode } = data;
    if (tool_name !== "Bash") return console.log("{}");

    const cmd = tool_input?.command || "";

    // Hard-deny shell writes into the banned per-cwd auto-memory dir.
    if (writesToMemory(cmd)) {
      log({ level: "BLOCKED", id: "memory-write-bash", cmd, session_id, cwd });
      return console.log(
        JSON.stringify({
          hookSpecificOutput: {
            hookEventName: "PreToolUse",
            permissionDecision: "deny",
            permissionDecisionReason:
              "⛔ [memory-write] auto-memory is banned (per-cwd silo / worktree black hole). Do NOT write to ~/.claude/projects/*/memory/ via shell. Put durable knowledge in ~/cs/docs/agent-memory/ (global) or repos/<key>/ + the ~/CLAUDE.md Agent Memory Index. See ~/CLAUDE.md → Agent Memory.",
          },
        }),
      );
    }

    const result = checkCommand(cmd);

    // Authorized-push bypass: a non-force `git push` explicitly tagged
    // CLAUDE_AUTOPUSH=1 is an agent self-attesting an authorized push (opening a
    // PR, review loop). Emits an explicit allow so it overrides any settings
    // `ask` rule the user may re-add. Honor-system by design; force pushes never
    // bypass and stay gated by git-force-any/git-force-main.
    const FORCE_PUSH = /\bgit\s+push\b.+(--force|-f)\b/;
    if (
      /\bgit\s+push\b/.test(cmd) &&
      /\bCLAUDE_AUTOPUSH=1\b/.test(cmd) &&
      !FORCE_PUSH.test(cmd)
    ) {
      log({ level: "ALLOWED", id: "autopush-bypass", cmd, session_id, cwd });
      return console.log(
        JSON.stringify({
          hookSpecificOutput: {
            hookEventName: "PreToolUse",
            permissionDecision: "allow",
            permissionDecisionReason: "✅ authorized push (CLAUDE_AUTOPUSH=1)",
          },
        }),
      );
    }

    if (result.blocked) {
      const p = result.pattern;
      const YOLO = process.env.CLAUDE_YOLO === "1";
      if (YOLO && p.yolo === "allow") {
        log({ level: "ALLOWED-YOLO", id: p.id, cmd, session_id, cwd });
        return console.log(
          JSON.stringify({
            hookSpecificOutput: {
              hookEventName: "PreToolUse",
              permissionDecision: "allow",
              permissionDecisionReason: `✅ YOLO bypass [${p.id}] (CLAUDE_YOLO=1)`,
            },
          }),
        );
      }
      log({
        level: "BLOCKED",
        id: p.id,
        priority: p.level,
        cmd,
        session_id,
        cwd,
        permission_mode,
      });
      // Default to deny (never stall on an ask prompt). Rules that relied on the
      // old ask-default (non-critical, no explicit decision) get appended guidance
      // telling the agent to route around it or hand the command to the user.
      const guidance =
        !p.decision && p.level !== "critical"
          ? " Use a different allowed command if possible; otherwise ask the user to run it for you if it's really needed."
          : "";
      return console.log(
        JSON.stringify({
          hookSpecificOutput: {
            hookEventName: "PreToolUse",
            permissionDecision: p.decision || "deny",
            permissionDecisionReason: `${EMOJIS[p.level]} [${p.id}] ${p.reason}${guidance}`,
          },
        }),
      );
    }
    console.log("{}");
  } catch (e) {
    log({ level: "ERROR", error: e.message });
    console.log("{}");
  }
}

if (require.main === module) {
  main();
} else {
  module.exports = { PATTERNS, LEVELS, SAFETY_LEVEL, checkCommand };
}
