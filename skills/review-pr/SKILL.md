---
name: review-pr
description: Use to send a GitHub PR's diff to Codex for review via MCP. Required argument is the PR number. Output written to .volley/PR-REVIEW-<num>.md and shown inline. Asks for explicit user opt-in before posting as a PR comment.
---

# /volley:review-pr

Codex reviews a PR. You decide whether to post the review as a comment.

## Steps for Claude

1. **Validate input.** PR number is required. If missing, tell user "Pass a PR number, e.g. /volley:review-pr 123" and stop.

2. **Verify .volley/ is initialized and the lock allows Claude to act.**
   ```bash
   [ -d .volley ] || { echo "ERROR: .volley/ not found. Run /volley:setup first." >&2; exit 1; }
   [ -f .volley/STATE ] || { echo "ERROR: .volley/STATE not found. Run /volley:setup first." >&2; exit 1; }
   . "${CLAUDE_PLUGIN_ROOT}/scripts/lib.sh"
   volley_state_assert_active .volley/STATE claude || exit 1
   ```

3. **Fetch PR metadata and diff via gh.** Write into `.volley/` (transient, gitignored, no `/tmp/` collision risk):
   ```bash
   PR_NUM=<n>
   gh pr view "$PR_NUM" --json title,body,baseRefName,headRefName > ".volley/pr-${PR_NUM}-meta.json"
   gh pr diff "$PR_NUM" > ".volley/pr-${PR_NUM}-diff.patch"
   ```
   If `gh` is not authenticated or PR doesn't exist, surface the error and stop.

4. **Build the review prompt for Codex.**
   ```
   You are reviewing a GitHub pull request. Be specific. Cite file paths
   and line numbers from the diff.

   PR TITLE: <title>
   PR DESCRIPTION:
   <body>

   DIFF:
   <full diff content>

   Provide your review in this format:

   ## Verdict
   APPROVE | REQUEST_CHANGES | COMMENT

   ## Summary
   (2-3 sentences on what this PR does)

   ## Issues
   - (file:line — issue description)

   ## Nits
   - (file:line — minor suggestions)

   ## Suggestions for follow-up
   - (out-of-scope improvements not blocking this PR)

   Keep it under 800 words.
   ```

5. **Invoke Codex via MCP.** Same tool as `/volley:review-plan`. Handle errors the same way.

6. **Write to `.volley/PR-REVIEW-<num>.md`.**
   ```markdown
   # Codex PR Review

   **PR:** #<num> — <title>
   **Reviewed:** <ISO timestamp>

   ---

   <Codex's response verbatim>
   ```

7. **Surface the review inline.**

8. **Ask user about posting as PR comment.** Output:
   > "Post this review as a comment on PR #<num>? (y/n)"

   If `y` (and ONLY if y - never auto-post):
   ```bash
   gh pr comment "$PR_NUM" --body-file ".volley/PR-REVIEW-${PR_NUM}.md"
   ```

9. **Print the next-step block.**
   - If verdict is APPROVE and user is the PR author: `volley_next_step "merge the PR" "Codex approved; merge when CI is green."`
   - Otherwise: `volley_next_step_done "Review complete. Address any issues in follow-up commits if applicable."`
