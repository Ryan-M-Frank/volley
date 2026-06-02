---
name: review-plan
description: Use to send a plan document to Codex for review via MCP. Defaults to the most recently modified PLAN.md under .planning/, or accept an explicit path argument. Codex's review is written to .volley/PLAN-REVIEW.md and surfaced inline. Fast - completes in seconds.
---

# /volley:review-plan

Hand a plan to Codex. Get back a review. Write it to disk, show it inline.

## Steps for Claude

1. **Verify .volley/ is initialized and the lock allows Claude to act.**
   ```bash
   [ -d .volley ] || { echo "ERROR: .volley/ not found. Run /volley:setup first." >&2; exit 1; }
   [ -f .volley/STATE ] || { echo "ERROR: .volley/STATE not found. Run /volley:setup first." >&2; exit 1; }
   . "${CLAUDE_PLUGIN_ROOT}/scripts/lib.sh"
   volley_state_assert_active .volley/STATE claude || exit 1
   ```
   If the assert fails, the helper already printed a refusal message. Stop.

2. **Resolve the plan path.**
   - If user passed a path argument, use it.
   - Otherwise: `ls -t .planning/**/PLAN.md 2>/dev/null | head -1` (or use Glob tool with pattern `.planning/**/PLAN.md` and take the most recent by mtime).
   - If no plan found, tell user "No PLAN.md found under .planning/. Pass an explicit path, or check that you've run /gsd:plan-phase to create one." and stop.

3. **Read the plan and HANDOFF.**
   - Read the plan file's full content.
   - Read `.volley/HANDOFF.md` for acceptance criteria.

4. **Build the review prompt for Codex.**

   The prompt to send via `mcp__codex__codex` (the only Codex session-start tool the MCP server exposes; older docs may say `mcp__codex__review` or `mcp__codex__exec` - those names are wrong):

   ```
   You are reviewing an implementation plan. Be specific and concrete.

   ACCEPTANCE CRITERIA (from HANDOFF.md):
   <paste HANDOFF.md content>

   PLAN TO REVIEW:
   <paste plan content>

   Provide your review in this format:

   ## Verdict
   APPROVE | CONCERNS | REJECT

   ## Strengths
   - (specific things the plan gets right)

   ## Concerns
   - (specific issues, with file/line refs from the plan if applicable)

   ## Suggested changes
   - (concrete edits, not vague advice)

   Keep it under 500 words. Skip filler.
   ```

5. **Invoke Codex via MCP.** Call `mcp__codex__codex` with the review prompt, `sandbox: "read-only"` (reviews are non-mutating), and `approval-policy: "never"` (no interactive prompts). If a follow-up question is needed, use `mcp__codex__codex-reply` with the returned thread ID to continue the session. If an error indicates the MCP server isn't reachable, tell the user to restart Claude Code and re-run `/volley:setup` to verify the registration is intact.

6. **Write the review to `.volley/PLAN-REVIEW.md`.** Prepend a small header with the plan path and timestamp, then Codex's response:

   ```markdown
   # Codex Plan Review

   **Plan:** <plan path>
   **Reviewed:** <ISO timestamp>

   ---

   <Codex's response verbatim>
   ```

7. **Surface the review inline.** Print the file content (or a clean summary if it's long) so the user reads it without opening another editor.

8. **Print the next-step block.** Decide based on Codex's verdict:
   - If `APPROVE`: `volley_next_step "/volley:implement" "Plan approved by Codex. Open Codex in a new terminal tab to build."`
   - If `CONCERNS`: `volley_next_step_options "Option A|/volley:implement|Accept review and proceed anyway" "Option B|edit PLAN.md|Address concerns then re-run /volley:review-plan"`
   - If `REJECT`: `volley_next_step "edit PLAN.md" "Address Codex's concerns and re-run /volley:review-plan."`
