---
name: review-plan
description: Use to send a plan document to Codex for review via `codex exec`. Defaults to the most recently modified PLAN.md under .planning/, or accept an explicit path argument. Codex's review is written to .volley/PLAN-REVIEW.md and surfaced inline. A high-effort review usually takes a few minutes.
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

   Write this prompt to `.volley/plan-review-prompt.md` (gitignored; `scripts/codex-exec.sh` sends it to Codex on stdin):

   ```
   You are reviewing an implementation plan. Be specific and concrete.

   PROJECT CONTEXT: before reviewing, read these files in the repo (read-only): <list every context.required file, every context.optional file that exists, and the managedCheckpoint (default .volley/CHECKPOINT.md) if it exists>.

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

5. **Resolve the review role's model/effort/context from config.** Read `.volley/config.json` (parse it yourself; absent = defaults). Take `codex.review.model`, `codex.review.reasoningEffort`, and apply any `.volley/local.json` `modelOverrides.review`. Check `context.required` files all exist - if any is missing, stop with a clear error naming the file (fail early). Note which `context.optional` files exist; missing optional files are reported and skipped.

6. **Invoke Codex via `scripts/codex-exec.sh`.** (Codex 0.156 removed `codex mcp-server`, so Volley no longer uses an MCP bridge; reviews run through `codex exec`.)
   - **Resume or fresh** - follow `codex.review.continuity` (absent = `session-only`), and only ever resume when `.volley/local.json` has `roles.planReview.threadId` **and** the stored `repository` matches the live checkout (`volley_repo_identity_matches "<canonicalRoot>" "<remote>"`):
     - `resume-if-safe`: pass `--resume <threadId>`.
     - `session-only` (the default): pass `--resume <threadId>` only if that id was saved by a review earlier **in this same Claude conversation** (a follow-up round). A fresh conversation or a restart starts a new Codex session.
     - `rehydrate`: never pass `--resume`; every review starts fresh from the context files.
   - Run it with a long timeout (high-effort reviews take minutes; prefer running it in the background):
     ```bash
     . "${CLAUDE_PLUGIN_ROOT}/scripts/lib.sh"
     bash "${CLAUDE_PLUGIN_ROOT}/scripts/codex-exec.sh" \
       --prompt-file .volley/plan-review-prompt.md --out .volley/plan-review-raw.md \
       --cwd "$(volley_repo_root)" --model "<resolved model or inherit>" --effort "<resolved effort or inherit>" \
       [--resume "<threadId>"]
     ```
     The script always runs Codex **read-only** (`--sandbox read-only`; on resume `-c sandbox_mode="read-only"`), validates the model/effort tokens, and prints `SESSION_ID=<id>` and `CONTINUITY=<fresh|resumed|fallback:...>` as its last lines.
   - **Continuity:** save `SESSION_ID` to `.volley/local.json` under `roles.planReview` (`threadId`, `updatedAtUtc`). If `CONTINUITY` starts with `fallback:`, tell the user the saved session could not be resumed (give the reason after the colon) and that this review started fresh from the files.
   - **Errors:** exit 2 = bad config (e.g. an unsafe model token) - surface it and stop; exit 3 = Codex wrote no review; any other non-zero exit = show Codex's stderr verbatim. An unavailable model or bad reasoning level is surfaced as-is - never silently substitute another model. An auth error means the user should run `codex login`.

7. **Write the review to `.volley/PLAN-REVIEW.md`.** Prepend a small header with the plan path and timestamp, then Codex's response:

   ```markdown
   # Codex Plan Review

   **Plan:** <plan path>
   **Reviewed:** <ISO timestamp>

   ---

   <Codex's response verbatim, i.e. the contents of .volley/plan-review-raw.md>
   ```

8. **Surface the review inline.** Print the file content (or a clean summary if it's long) so the user reads it without opening another editor.

9. **Print the next-step block.** Decide based on Codex's verdict:
   - If `APPROVE`: `volley_next_step "/volley:implement" "Plan approved by Codex. Open Codex in a new terminal tab to build."`
   - If `CONCERNS`: `volley_next_step_options "Option A|/volley:implement|Accept review and proceed anyway" "Option B|edit PLAN.md|Address concerns then re-run /volley:review-plan"`
   - If `REJECT`: `volley_next_step "edit PLAN.md" "Address Codex's concerns and re-run /volley:review-plan."`
