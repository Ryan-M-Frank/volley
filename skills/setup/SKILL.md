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
   - Tell the user: "Restart Claude Code now so the MCP server registration takes effect, then re-run `/volley:setup` (it will skip already-done steps and just run the smoke test). If you re-run this before restarting, you'll see an MCP-tool-not-available error - that's expected; just restart and re-run."
   - On the second invocation (after restart), check whether the `mcp__codex__codex` tool is available. The Codex MCP server exposes two tools: `mcp__codex__codex` (start a Codex session) and `mcp__codex__codex-reply` (continue an existing session). Older skill docs may reference `mcp__codex__exec` or `mcp__codex__review` - those names are wrong; only the two above are real.
   - If available, invoke `mcp__codex__codex` with: `prompt: "Reply with the single word: PONG"`, `sandbox: "read-only"`, `approval-policy: "never"`. Verify the response contains `PONG`. Read-only sandbox + no-approval policy makes the smoke test cheap and side-effect-free.
   - If not available, instruct the user to check Claude Code's MCP server status (`/mcp` slash command) and re-run after fixing.

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
