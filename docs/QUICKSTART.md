# Volley Quickstart

A worked example from zero to shipping a task with Claude and Codex collaborating in the same repo.

---

## 1. Install the plugin

Inside Claude Code, run:

```
/plugin marketplace add Ryan-M-Frank/volley
/plugin install volley@volley
```

If the `/volley:*` skills aren't available immediately after installation, reload:

```
/reload-plugins
```

Then run the one-time setup (once per machine — not once per repo):

```
/volley:setup
```

Setup verifies that Codex is installed and authenticated, registers Codex as an MCP server in your Claude Code config, and confirms the MCP connection with a smoke-test call.

---

## 2. Verify everything is wired up

```
/volley:doctor
```

Doctor checks: Codex binary on PATH, `codex login` authentication, MCP server registration, and (if you're in a repo) STATE file integrity. Fix any items it flags before proceeding.

---

## 3. Open the repo you want to work in

```bash
cd my-project
claude
```

On first use in a new repo, `/volley:setup` (or the first skill that needs `.volley/`) will scaffold the `.volley/` directory with a starter `HANDOFF.md` and `.gitignore`.

---

## 4. Write your acceptance criteria into HANDOFF.md

`.volley/HANDOFF.md` is the shared context file both assistants read. Write down what you want built and what "done" looks like before asking either assistant to start:

```markdown
## Task
Add input validation to the user registration endpoint.

## Acceptance criteria
- Returns 422 with a structured error body if `email` is missing or malformed
- Returns 422 if `password` is shorter than 8 characters
- Existing passing tests remain green
- New tests cover the 422 paths
```

Commit `HANDOFF.md` so it persists across sessions. Everything else in `.volley/` is gitignored by default.

---

## 5. Get the plan reviewed by Codex

Before writing any code, get a second opinion on the approach. If you have a plan document (e.g. `.planning/PLAN.md`):

```
/volley:review-plan
```

Volley passes the plan to Codex via MCP (read-only, no file writes). Codex returns a critique — gaps in the design, edge cases you missed, simpler alternatives. The review is written to `.volley/PLAN-REVIEW.md` and shown inline. This takes seconds, not minutes.

Read the review and revise the plan before handing off to implementation.

---

## 6. Hand implementation off to Codex

```
/volley:implement
```

This flips the STATE lock to `ACTIVE=codex` and spawns a **visible terminal tab** running `codex exec` against your plan. You can watch Codex work in real time — it streams its progress to the terminal. Claude's session is now read-only (it will refuse to write until the lock is released).

When Codex finishes, it releases the lock by setting `ACTIVE=claude` and creating a `.volley/CODEX-STARTED-<nonce>` handshake file. Claude detects this and becomes active again automatically.

You do not need to do anything while Codex is running. You can switch to the Codex terminal to watch, or do something else entirely.

---

## 7. Review what Codex wrote

Once the lock is back on Claude:

```
/volley:review-code
```

Claude reads the diff of everything Codex committed against the plan in `HANDOFF.md` and writes a structured review to `.volley/CODE-REVIEW.md`. This is Claude reviewing Codex's work — a genuinely independent perspective since Claude did not write the implementation.

If the review surfaces issues, you can ask Claude to fix them directly (it now holds the lock) or iterate with another round of `/volley:implement`.

---

## 8. Check the lock at any time

```
/volley:status
```

Status shows the current `ACTIVE` actor, the task label, how long the lock has been held, and whether the PID recorded in STATE is still alive. If the lock is older than 30 minutes and the PID is dead, it flags the lock as stale.

### Clearing a stuck lock

If the Codex terminal closed unexpectedly or you need to take back control:

```
/volley:unlock
```

Unlock asks for confirmation before clearing the lock. It is an escape hatch — use it when `/volley:status` shows a stale lock, not as a routine step.

---

## 9. Ship

Once you're satisfied with the implementation and review:

```bash
git push
gh pr create
```

The `.volley/` directory (except `HANDOFF.md`) is gitignored, so review artifacts and the STATE file don't go up with the PR.

---

## Skill reference

| Skill | When to use it |
|---|---|
| `/volley:setup` | Once per machine — install and smoke-test |
| `/volley:doctor` | Something seems broken — run this first |
| `/volley:status` | Check who holds the lock and for how long |
| `/volley:unlock` | Clear a stuck lock after confirming it's stale |
| `/volley:review-plan` | Get Codex's critique of a plan before implementing |
| `/volley:review-pr <num>` | Get Codex's review of a GitHub PR diff |
| `/volley:implement` | Hand a plan to Codex; spawns a visible terminal |
| `/volley:review-code` | Claude reviews what Codex committed against the plan |
