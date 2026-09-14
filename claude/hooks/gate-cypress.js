#!/usr/bin/env node
/**
 * Gate Cypress Commands - PreToolUse Hook for Bash
 *
 * Policy: allow a single Cypress instance to start without approval. If
 * another Cypress process is already running, force "ask" so the user can
 * either approve a parallel run or kill the existing one first.
 *
 * Detection: look for live `cypress run|open` processes via `pgrep`. We
 * intentionally don't gate on the dev server, headed-mode helpers, or the
 * cypress CLI binary itself — only the actual test runner.
 */

const { execSync } = require("child_process");

function notify(msg) {
  try {
    execSync(
      `osascript -e 'display notification ${JSON.stringify(msg)} with title "Claude Code" sound name "default"'`,
      { stdio: "ignore" },
    );
  } catch {}
}

const PATTERNS = [
  /\bcypress\s+(run|open)\b/i, // cypress run, cypress open
  /\bnpx\s+cypress\b/i, // npx cypress ...
  /cypress\/scripts\//i, // node cypress/scripts/run-e2e.js
  /test:e2e/, // yarn test:e2e
  /\baudit-keys\b/, // yarn audit-keys (spawns Cypress internally)
];

// pgrep patterns for "an actual Cypress test runner is alive right now".
// We don't match the gate hook itself or this script.
const RUNNING_PGREP_PATTERNS = [
  "cypress run",
  "cypress open",
  "cypress/scripts/run-e2e",
];

function isCypressAlreadyRunning() {
  for (const pat of RUNNING_PGREP_PATTERNS) {
    try {
      const out = execSync(`pgrep -f ${JSON.stringify(pat)}`, {
        stdio: ["ignore", "pipe", "ignore"],
      })
        .toString()
        .trim();
      if (out.length > 0) {
        // pgrep returns at least one PID — Cypress is alive.
        return { running: true, match: pat, pids: out.split(/\s+/) };
      }
    } catch {
      // pgrep exits 1 when no match — not running, keep checking.
    }
  }
  return { running: false };
}

async function main() {
  let input = "";
  for await (const chunk of process.stdin) input += chunk;

  try {
    const data = JSON.parse(input);
    if (data.tool_name !== "Bash") return console.log("{}");

    const cmd = data.tool_input?.command || "";

    // Skip read-only commands that happen to mention cypress paths
    const READ_ONLY =
      /^\s*(ls|cat|head|tail|wc|file|stat|find|grep|rg|tree|du|git)\b/;
    if (READ_ONLY.test(cmd)) return console.log("{}");

    const match = PATTERNS.find((p) => p.test(cmd));
    if (!match) return console.log("{}");

    const existing = isCypressAlreadyRunning();
    if (existing.running) {
      notify(
        `Cypress already running (pid ${existing.pids?.[0] ?? "?"}) — approve parallel run?`,
      );
      return console.log(
        JSON.stringify({
          hookSpecificOutput: {
            hookEventName: "PreToolUse",
            permissionDecision: "ask",
            permissionDecisionReason:
              `Another Cypress run is already alive (pgrep matched "${existing.match}", ` +
              `pid${(existing.pids?.length ?? 0) > 1 ? "s" : ""} ${(existing.pids || []).join(", ")}). ` +
              `Approve to run in parallel, or kill the existing run first.`,
          },
        }),
      );
    }
    // No Cypress alive — allow the run without prompting.
    return console.log("{}");
  } catch (e) {
    console.log("{}");
  }
}

main();
