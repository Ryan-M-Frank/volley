---
name: status
description: Use to inspect the current Volley lock state. Reports who's active, what task they're on, lock age, whether the named PID is still alive, and lists the most recent .volley/ review files. Use to confirm Codex finished, to check for stale locks, or any time you're unsure whose turn it is.
---

# /volley:status

Read-only inspection of the Volley state. Never modifies anything.

## Steps for Claude

1. **Verify `.volley/` exists.** If not, tell user to run `/volley:setup` first and stop.

2. **Read STATE.** Source the lib and read all four keys. If any key read fails (missing file, missing key, or malformed STATE), report the error to the user verbatim and stop - do NOT continue with empty/default values.
   ```bash
   . "${CLAUDE_PLUGIN_ROOT}/scripts/lib.sh"
   ACTIVE=$(volley_state_get .volley/STATE ACTIVE) || exit 1
   TASK=$(volley_state_get .volley/STATE TASK) || exit 1
   SINCE=$(volley_state_get .volley/STATE SINCE) || exit 1
   PID=$(volley_state_get .volley/STATE PID) || exit 1
   AGE=$(volley_state_lock_age .volley/STATE) || exit 1
   ```

3. **Check PID liveness if ACTIVE=codex.**
   ```bash
   if [ "$ACTIVE" = "codex" ] && [ "$PID" != "0" ]; then
     if volley_state_pid_alive "$PID"; then PID_STATUS="alive"; else PID_STATUS="DEAD"; fi
   else
     PID_STATUS="n/a"
   fi
   ```

4. **List recent `.volley/` artifacts.** If no artifacts exist yet, show `(no review artifacts yet)` instead of a blank section.
   ```bash
   ARTIFACTS=$(ls -lt .volley/*.md 2>/dev/null | head -5)
   [ -z "$ARTIFACTS" ] && ARTIFACTS="(no review artifacts yet)"
   ```

5. **Read continuity config for the report (non-mutating).** If `.volley/config.json` exists, parse it (host JSON, no jq) and resolve the review/implementation `model` + `reasoningEffort` (`inherit` → show "Codex default"). If `.volley/local.json` exists, note whether repo identity matches (`volley_repo_identity_matches`) and which roles have a stored thread/session id (presence only - never print the id or any secret). Absent files → report "defaults / not initialized".

6. **Report to user.** Format like this:
   ```
   Volley Status
   ──────────
   Active actor:  <ACTIVE>
   Current task:  <TASK>
   Lock since:    <SINCE>  (<AGE>s ago)
   Recorded PID:  <PID>  (<PID_STATUS>)

   Continuity
   ──────────
   Review model:  <model / Codex default>  (effort: <effort>)
   Impl model:    <model / Codex default>  (effort: <effort>)
   Repo identity: <match | mismatch → will rehydrate | not initialized>
   Saved threads: planReview=<yes/no> prReview=<yes/no> implementation=<yes/no>
   Local state:   .volley/local.json   Checkpoint: <managedCheckpoint path>

   Recent artifacts:
   <ls output>
   ```

7. **Detect stale lock.** Stale = `ACTIVE=codex` AND one of:
   - `PID != 0` AND PID is dead, OR
   - `AGE > 1800` seconds (30 minutes).

   `PID=0` is the documented "untracked" sentinel (set by `/volley:implement` because the spawned `wt` PID is useless for liveness). When `PID=0`, fall back to age-only detection. If stale, print:
   ```
   ⚠ STALE LOCK detected. Codex's session looks abandoned (no progress for >30 min, or process ended).
     Run /volley:unlock to clear it.
   ```

8. **Print the next-step block.** Decide based on state:
   - If stale: `volley_next_step "/volley:unlock" "Clear the stale lock so Claude can resume."`
   - If `ACTIVE=codex` and alive: `volley_next_step_done "Codex is currently working. Watch the terminal tab; re-run /volley:status when it finishes."`
   - If `ACTIVE=claude` and `TASK=done`: `volley_next_step "/volley:review-code" "Codex finished. Review the diff against the plan."`
   - If `ACTIVE=claude` and `TASK=idle`: `volley_next_step "/volley:review-plan" "Ready for the next handoff. If you have a plan to review, send it to Codex."`
   - Otherwise (Claude active mid-task): `volley_next_step_done "Claude is mid-task. Continue working in this session."`
