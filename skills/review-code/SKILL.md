---
name: review-code
description: Use after Codex has implemented a plan. Claude reviews the diff (defaults to uncommitted changes; accepts a git revision range as argument), checks it against PLAN.md and acceptance criteria, and writes a verdict to .volley/CODE-REVIEW.md. Inline review - does not call Codex.
---

# /volley:review-code

Claude reads what Codex built and judges it.

## Steps for Claude

1. **Verify .volley/ is initialized and the lock allows Claude to act.**
   ```bash
   [ -d .volley ] || { echo "ERROR: .volley/ not found. Run /volley:setup first." >&2; exit 1; }
   [ -f .volley/STATE ] || { echo "ERROR: .volley/STATE not found. Run /volley:setup first." >&2; exit 1; }
   . "${CLAUDE_PLUGIN_ROOT}/scripts/lib.sh"
   volley_state_assert_active .volley/STATE claude || exit 1
   ```

2. **Resolve the diff to review.**
   - If user passed a range argument (e.g. `HEAD~3..HEAD`), use that.
   - Otherwise, default to uncommitted changes:
     ```bash
     git diff HEAD
     ```
   - If diff is empty, tell user "No changes to review. Did Codex finish?" and stop.

3. **Locate the plan and HANDOFF.** Same logic as `/volley:review-plan` for finding the latest PLAN.md. Read the plan and `.volley/HANDOFF.md` content.

4. **Read the diff into context.** Use Bash to capture the diff and Read tools as needed for full context on changed files.

5. **Review with these prompts in mind:**
   - Does each change implement a specific PLAN task or acceptance criterion? (Cite which.)
   - Are there changes that go beyond the plan's scope?
   - Are there gaps - acceptance criteria not addressed?
   - Are the tests covering the new code?
   - Any obvious correctness, safety, or style issues for this codebase?

6. **Write `.volley/CODE-REVIEW.md` with this structure:**

   ```markdown
   # Claude Code Review

   **Diff range:** <range used>
   **Reviewed:** <ISO timestamp>
   **Plan:** <plan path>

   ## Verdict
   SHIP | FIX | DISCUSS

   ## Coverage of acceptance criteria
   - Criterion 1: ✓ addressed in <file:line>
   - Criterion 2: ✗ not addressed
   - ...

   ## Coverage of plan tasks
   - Task N: ✓
   - Task M: partial (missing X)

   ## Issues found
   - (file:line — description)

   ## Out-of-plan changes
   - (file:line — what was changed beyond the plan, with judgement)

   ## Suggested next moves
   - (concrete actions)
   ```

7. **Surface the review inline.**

8. **Reconcile the GitHub issue (only if this repo uses the issue-tracking rule).**
   This step is conditional - skip entirely if the repo's `CLAUDE.md` does not define the "GitHub Issue Tracking Rule" or no matching issue exists.
   - Find the plan's issue: `gh issue list --state open --search "[NN-MM] in:title"` (derive `NN-MM` from the plan filename). If none, skip silently.
   - Cross-reference Codex's task log for what actually got built:
     ```bash
     cat .volley/IMPLEMENTATION-LOG.md
     ```
   - For each task marked `✓` in the **Coverage of plan tasks** table above (i.e. verified by *this* review, not merely logged by Codex), tick its checkbox in the issue body. Use `gh issue edit <n> --body-file` with the updated body, or the GraphQL `updateIssue` mutation. **Do not tick tasks marked `partial` or `✗`.**
   - Only close the issue when **all** tasks are ticked AND the verdict is `SHIP` AND `NN-MM-SUMMARY.md` exists. Prefer letting the PR close it via `Closes #N`; if committing directly, `gh issue close <n>` with a comment linking the commit.
   - On `FIX`/`DISCUSS`: tick only the verified tasks, leave the issue open, and add a brief comment noting what remains.

9. **Print the next-step block.**
   - If `SHIP`: `volley_next_step "git commit + open PR" "Code looks good. Commit (your existing flow) and open the PR."`
   - If `FIX`: `volley_next_step_options "Option A|/volley:implement|Hand back to Codex for fixes" "Option B|edit code yourself|Quick edits Claude can make directly"`
   - If `DISCUSS`: `volley_next_step_done "Open issues to talk through with the user before the next move."`
