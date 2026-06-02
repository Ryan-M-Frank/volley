# Security Policy

## The honest trust model

### The lock is cooperative, not enforced

Volley's concurrency control is a `.volley/STATE` file containing four keys (`ACTIVE`, `TASK`, `SINCE`, `PID`). Every skill checks this file before acting and refuses if the lock doesn't belong to it.

This is a **coordination convention, not a security boundary.** A determined local user can open `.volley/STATE` in a text editor, change `ACTIVE=codex` to `ACTIVE=claude`, and proceed. The lock exists to prevent accidental concurrent writes from two AI sessions running in the same repo — it does not protect against a local user who deliberately circumvents it. If you need hard enforcement, the right tool is OS-level file locking or branch protection, not a text file.

### Codex sandbox and approval policy

Volley passes explicit sandbox and approval settings when calling Codex through MCP:

- **Review operations** (`/volley:review-plan`, `/volley:review-pr`) run Codex with `sandbox: read-only` and `approval-policy: never`. Codex reads files and returns a critique; it does not write anything.
- **Implementation** (`/volley:implement`) spawns Codex in a **visible terminal tab** under whatever sandbox policy your local Codex configuration applies. The user can watch every action Codex takes in real time. Volley does not override or weaken your Codex approval settings for the implementation path.

### The bundled MCP server

Volley ships a `.mcp.json` that registers an MCP server pointing at your **local `codex` binary**. Volley itself makes no network calls — it is a collection of bash scripts and skill definitions. Any network traffic originates from Codex (connecting to the OpenAI API) under the authentication credentials you established with `codex login`.

The `.mcp.json` entry tells Claude Code where to find Codex on your machine. It does not transmit your credentials or any repo content to a Volley-controlled server — there is no such server.

### What Volley does NOT do

- It does not sandbox Claude Code or restrict what Claude can read or write.
- It does not encrypt, sign, or cryptographically verify the STATE lock file.
- It does not prevent a local user from editing STATE, HANDOFF.md, or any other `.volley/` file directly.
- It does not audit or log which assistant wrote which files.
- It does not prevent Codex from making network calls to the OpenAI API (that is governed by your Codex configuration and OpenAI account settings).

### Threat model summary

Volley is designed to prevent **accidental** concurrent writes between two cooperating AI assistants in a local development environment. It is not designed to prevent **intentional** tampering by anyone with local filesystem access. If your threat model includes malicious local actors, Volley's lock provides no protection against that.

---

## Reporting a vulnerability

If you find a security issue — for example, a shell injection vector in one of the spawn handlers, a way for a malformed STATE file to execute arbitrary code, or a credential leak path — please **do not open a public GitHub issue**.

Email: **frank.ryanm@gmail.com**

Include:
- A description of the vulnerability and what an attacker could achieve
- Steps to reproduce (the simpler the better)
- Which file(s) are involved and the relevant line numbers if known

You will receive an acknowledgement within 72 hours. Once a fix is confirmed, the vulnerability will be disclosed publicly in the release notes with credit to the reporter (unless you prefer to remain anonymous).
