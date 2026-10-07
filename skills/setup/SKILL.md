---
name: setup
description: Use to initialize the Volley Claude+Codex workflow in this repo. Runs once per repo. Verifies Codex is installed and can run non-interactively, scaffolds .volley/ with HANDOFF.md template, .gitignore, and an initial STATE file. Runs a smoke test that calls Codex via `codex exec`.
---

# /volley:setup

One-time installation of the Volley workflow.

## Steps for Claude

1. **Verify Codex is installed.**
   - Run: `codex --version` — must succeed and print a version >= 0.156.
   - We do NOT run an explicit `codex login` probe here; the exact auth-status subcommand varies by Codex CLI version and a missing/wrong subcommand could falsely report "not logged in." Instead, the smoke test in step 4 will surface auth errors clearly when it calls Codex. If the smoke test fails with an auth error, instruct the user to run `codex login` and retry.

2. **Confirm Codex can run non-interactively.**
   - Run `codex exec --help` - it must succeed. Volley calls Codex through `scripts/codex-exec.sh` (`codex exec`); it no longer bundles an MCP server, because Codex 0.156 removed `codex mcp-server`.
   - If this repo has a project `.mcp.json` from an older Volley (or the user added one) that registers `codex mcp-server`, tell the user that entry is dead and can be removed. Do not edit it yourself.

3. **Scaffold `.volley/`.**
   - Create directory: `mkdir -p .volley`
   - Copy template: `cp "${CLAUDE_PLUGIN_ROOT}/scripts/templates/HANDOFF.md" .volley/HANDOFF.md` (only if `.volley/HANDOFF.md` doesn't already exist - never overwrite)
   - Copy the managed checkpoint: `cp "${CLAUDE_PLUGIN_ROOT}/scripts/templates/CHECKPOINT.md" .volley/CHECKPOINT.md` (only if it doesn't already exist - never overwrite; this is the Volley-managed cross-agent state file, distinct from the user-owned HANDOFF.md).
   - Copy the project config **only if absent** (never overwrite - the user may have customized it): `cp "${CLAUDE_PLUGIN_ROOT}/scripts/templates/config.json" .volley/config.json`. An absent `config.json` means "today's default behavior"; the scaffolded defaults (`model: inherit`, no required context files) reproduce that.
   - Copy gitignore: `cp "${CLAUDE_PLUGIN_ROOT}/scripts/templates/gitignore" .volley/.gitignore` (overwrite OK; this is internal).
   - Initialize STATE:
     ```bash
     . "${CLAUDE_PLUGIN_ROOT}/scripts/lib.sh" && volley_state_write .volley/STATE claude idle 0
     ```
   - Write machine-local state `.volley/local.json` with this repo's identity (gitignored - never committed). Derive identity with the lib helpers and write the JSON yourself (host-parsed - no jq):
     ```bash
     . "${CLAUDE_PLUGIN_ROOT}/scripts/lib.sh"
     ROOT=$(volley_repo_root); REMOTE=$(volley_repo_remote)
     echo "root=$ROOT remote=$REMOTE"
     ```
     Then create `.volley/local.json` (only if absent) as:
     ```json
     { "version": 1,
       "repository": { "canonicalRoot": "<ROOT>", "remote": "<REMOTE>" },
       "modelOverrides": { "review": null, "implementation": null },
       "roles": {} }
     ```

4. **Smoke-test Codex - and validate the configured model against the live surface.**
   - Read `.volley/config.json` (parse it yourself - it is JSON, no jq needed). Resolve the **review** role's `model` and `reasoningEffort`.
   - Run:
     ```bash
     . "${CLAUDE_PLUGIN_ROOT}/scripts/lib.sh"
     printf 'Reply with the single word: PONG\n' > .volley/smoke-prompt.md
     if bash "${CLAUDE_PLUGIN_ROOT}/scripts/codex-exec.sh" --prompt-file .volley/smoke-prompt.md --out .volley/smoke-raw.md \
          --cwd "$(volley_repo_root)" --model "<model or inherit>" --effort "<effort or inherit>"; then
       grep -q PONG .volley/smoke-raw.md && echo "[PASS] Codex replied PONG" || echo "[FAIL] Codex replied, but not with PONG"
     else
       echo "[FAIL] codex-exec.sh exited $? - read the error above"
     fi
     ```
     Do not save the smoke test's `SESSION_ID` to any role.
   - **This doubles as model validation (no hard-coded allowlist).** If Codex returns a "model not found / unavailable" style error, report it verbatim and tell the user to fix `model` in `.volley/config.json` (or `.volley/local.json` overrides) - never silently fall back to another model.
   - If the call fails with an auth error, tell the user to run `codex login` and retry.

5. **Print the next-step block.**
   - Use `volley_next_step` from the lib:
     ```bash
     . "${CLAUDE_PLUGIN_ROOT}/scripts/lib.sh"
     volley_next_step "/volley:status" "Verify the lock state and sanity-check the install."
     ```

## What to do on already-installed repos

If `.volley/STATE` exists, skip STATE re-init, but still **backfill any missing new-in-v0.2 files** (never overwrite existing ones): `.volley/config.json`, `.volley/CHECKPOINT.md`, and `.volley/local.json` (with this repo's identity). Refresh `.volley/.gitignore` from the template. Then re-run the smoke test (step 4) and print the next-step block. This is the migration path for repos set up before model selection existed - existing behavior is preserved because the scaffolded config defaults to `inherit`.

## Configuration reference

Two files, one shared and one local. Claude parses both natively (no jq).

- **`.volley/config.json` (shared, committed):** `version` (integer), a `codex` block with `review` and `implementation` roles (`model`: a concrete id or `"inherit"`; `reasoningEffort`: e.g. `high`/`xhigh` or `"inherit"`; `continuity`: `session-only` | `rehydrate` | `resume-if-safe`), and a `context` block (`required` files that must exist or setup/review fails; `optional` files reported-and-skipped if absent; `managedCheckpoint` path, default `.volley/CHECKPOINT.md`). Absent file = today's defaults. (The separate configurable-roles feature adds a `roles` block under the same `version` - leave it to that feature; don't scaffold it here.)
- **`.volley/local.json` (machine-local, gitignored):** `repository` identity (`canonicalRoot`, `remote`) used to guard against cross-project resume; `modelOverrides` for this machine; and `roles` holding exact `threadId`/`sessionId` per role. Never committed - IDs are per-user/per-machine.

**Model/effort validation:** never maintain a hard-coded model list. The step-4 smoke call *is* the validation - an unavailable model surfaces as a real Codex error. Reasoning effort rides `config.model_reasoning_effort` (there is no dedicated field).

## Failure modes

- **Codex not installed:** Tell user to install: `npm install -g @openai/codex` (or whatever their install path was).
- **Codex not logged in:** Run `codex login` (interactive — user must do this themselves).
- **Errors mentioning `codex mcp-server` or MCP:** an old Volley-era `.mcp.json` is still registered; remove that entry - Volley no longer uses MCP.
