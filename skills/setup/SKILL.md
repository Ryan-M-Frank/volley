---
name: setup
description: Use to initialize the Volley Claude+Codex workflow in this repo. Runs once per repo. Verifies Codex is installed, confirms the bundled Codex MCP server is reachable, scaffolds .volley/ with HANDOFF.md template, .gitignore, and an initial STATE file. Runs a smoke test that calls Codex via MCP.
---

# /volley:setup

One-time installation of the Volley workflow.

## Steps for Claude

1. **Verify Codex is installed.**
   - Run: `codex --version` — must succeed and print a version >= 0.129.
   - We do NOT run an explicit `codex login` probe here; the exact auth-status subcommand varies by Codex CLI version and a missing/wrong subcommand could falsely report "not logged in." Instead, the MCP smoke test in step 4 will surface auth errors clearly when the bridge tries to call Codex. If the smoke test fails with an auth error, instruct the user to run `codex login` and retry.

2. **Confirm the bundled Codex MCP server is reachable.**
   - Volley bundles the Codex MCP server (see the plugin's `.mcp.json`); you do NOT write a project `.mcp.json`.
   - Check whether the `mcp__codex__codex` tool is available in this session.
   - If it is NOT available, the plugin was just installed and its MCP server has not loaded yet. Tell the user:
     "Run `/reload-plugins` (or restart Claude Code) so Volley's bundled Codex server loads, then re-run `/volley:setup`."
     (Confirm the exact reload command against this Claude Code version if `/reload-plugins` is not recognized.)
     Then STOP - do not continue until the tool is reachable.
   - If it IS available, continue.

3. **Scaffold `.volley/`.**
   - Create directory: `mkdir -p .volley`
   - Copy template: `cp "${CLAUDE_PLUGIN_ROOT}/scripts/templates/HANDOFF.md" .volley/HANDOFF.md` (only if `.volley/HANDOFF.md` doesn't already exist - never overwrite)
   - Copy gitignore: `cp "${CLAUDE_PLUGIN_ROOT}/scripts/templates/gitignore" .volley/.gitignore` (overwrite OK; this is internal)
   - Initialize STATE:
     ```bash
     . "${CLAUDE_PLUGIN_ROOT}/scripts/lib.sh" && volley_state_write .volley/STATE claude idle 0
     ```

4. **Smoke-test the MCP bridge.**
   - By this point step 2 has confirmed the `mcp__codex__codex` tool is reachable. (The Codex MCP server exposes exactly two tools: `mcp__codex__codex` to start a session and `mcp__codex__codex-reply` to continue one. Older docs mention `mcp__codex__exec`/`mcp__codex__review` - those names are wrong.)
   - Invoke `mcp__codex__codex` with: `prompt: "Reply with the single word: PONG"`, `sandbox: "read-only"`, `approval-policy: "never"`. Verify the response contains `PONG`. Read-only sandbox + no-approval policy makes the smoke test cheap and side-effect-free.
   - If the call fails with an auth error, tell the user to run `codex login` and retry. If the tool is somehow unavailable, return to step 2 (run `/reload-plugins` or restart, then re-run `/volley:setup`).

5. **Print the next-step block.**
   - Use `volley_next_step` from the lib:
     ```bash
     . "${CLAUDE_PLUGIN_ROOT}/scripts/lib.sh"
     volley_next_step "/volley:status" "Verify the lock state and sanity-check the install."
     ```

## What to do on already-installed repos

If `.volley/STATE` exists, skip scaffolding; just re-run the smoke test (step 4) and print the next-step block.

## Failure modes

- **Codex not installed:** Tell user to install: `npm install -g @openai/codex` (or whatever their install path was).
- **Codex not logged in:** Run `codex login` (interactive — user must do this themselves).
- **MCP tool missing after restart:** Check `.mcp.json` syntax; run `/mcp` to see Claude Code's view of registered servers.
