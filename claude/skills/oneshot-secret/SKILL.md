---
name: oneshot-secret
description: "Secret handoff and preserved secret store via the `oneshot-secret` CLI. Use when the user hands off a secret (API key, token, password) by pasting it into the handoff slot, when a task needs a credential, before regenerating any existing token, or when moving a credential to a GitHub repo/environment secret."
---

# oneshot-secret

`oneshot-secret` is two things behind one command: a transient **handoff slot**
the user pastes a secret into, and a durable **encrypted store** (sops + age) for
secrets worth keeping. Run `oneshot-secret` with no arguments for usage.

**Always pipe values to and from these commands. Never print, echo, or log a
secret value, and never paste one into the conversation.**

## Handoff slot — one value, transient

- The user stores: `oneshot-secret put` (reads the clipboard).
- You consume and delete: `oneshot-secret get` — this **destroys** the value.
- You read without deleting: `oneshot-secret peek`.
- State: `oneshot-secret status`; cleanup: `oneshot-secret clear`.

Before `get` destroys a credential that is expensive to recreate, ask:

> "Should we preserve this so we can retrieve it later instead of regenerating it?"

While provisioning with a credential the user may want to keep, use `peek`.

## Preserved store — durable, encrypted, gated

- `oneshot-secret ls [SCOPE]` — scope and secret **names** only. No prompt, never
  reveals a value. Check it before asking the user for anything, and always
  before regenerating a token.
- `oneshot-secret preserve SCOPE/NAME --note '<what it is, its scopes>'` — copy the
  held handoff value into the store (`--stdin` to take it from a pipe instead).
- `oneshot-secret recall SCOPE/NAME` — prints the value; prompts the user for
  their macOS login password.
- `oneshot-secret push SCOPE/NAME --gh-env REPO:ENV:SECRET` (or
  `--gh-repo REPO:SECRET`) — move a credential into GitHub Actions secrets
  instead of regenerating it.
- `oneshot-secret forget SCOPE/NAME`.

Scope is one project per `<scope>.yaml`. Do not preserve derivable values
(managed database URLs and passwords, IPs, resource ids): the provider API hands
those back on demand, and a stored copy goes stale on rotation.

## The security boundary

The age key sits in the login keychain with an empty trusted-app list, so every
value read shows a macOS password dialog. That prompt is the access control:
do not look for a way around it, and never tell the user to click
"Always Allow" — it disables the gate permanently (`oneshot-secret reseal`
restores it). Names (`ls`, `gate`, `status`) never prompt.

Losing the keychain identity loses the store. `oneshot-secret export-identity`
prints the key for backup and must only be run by the user in a private
terminal, never in an agent session. A new machine either runs
`oneshot-secret init-store` for a fresh store or restores a backed-up identity
with `oneshot-secret import-identity` (stdin).
