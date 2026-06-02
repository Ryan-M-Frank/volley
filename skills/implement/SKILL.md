---
name: implement
description: Use when a plan is ready to build and you want Codex to implement it. Spawns a visible Windows Terminal tab running Codex with a pre-built prompt that points it at the plan and tells it to log progress to .volley/IMPLEMENTATION-LOG.md. Sets the STATE lock to ACTIVE=codex so Claude won't touch source files until Codex finishes. Returns control to the user with a clear "watch the tab" message.
---

# /volley:implement

Hand the keys to Codex. Watch in another tab.

## Steps for Claude

1. **Verify .volley/ is initialized and the lock allows Claude to act.**
   ```bash
   [ -d .volley ] || { echo "ERROR: .volley/ not found. Run /volley:setup first." >&2; exit 1; }
   [ -f .volley/STATE ] || { echo "ERROR: .volley/STATE not found. Run /volley:setup first." >&2; exit 1; }
   . "${CLAUDE_PLUGIN_ROOT}/scripts/lib.sh"
   volley_state_assert_active .volley/STATE claude || exit 1
   ```

2. **Resolve the plan path.**
   - If user passed an argument, use it.
   - Otherwise, find the latest PLAN.md (same logic as `/volley:review-plan`).
   - Read the plan content - we need to embed at least the path in Codex's prompt.

3. **Generate a per-run nonce and resolve absolute paths.** The nonce makes the started marker unique per invocation, so a stale Codex from a prior run cannot satisfy this run's poll. The random component pulls 8 bytes (64 bits) from `/dev/urandom`, so collision probability is effectively zero - earlier `$$ + $RANDOM` versions left a small but real collision window for invocations from the same shell process within the same second.

   Both forms of each path matter: Bash uses POSIX-style for the poll/stat side, Codex runs on Windows and needs Windows-style paths in its prompt to create / read files reliably.

   ```bash
   NONCE=$(date -u +%Y%m%dT%H%M%SZ)-$(head -c 8 /dev/urandom | od -An -tx1 | tr -d ' \n')

   # POSIX-style absolute paths - used by the orchestrator (Bash) for stat/poll.
   PLAN_PATH=$(realpath <plan>)
   HANDOFF_PATH=$(realpath .volley/HANDOFF.md)
   LOG_PATH=$(realpath .volley/IMPLEMENTATION-LOG.md)
   STATE_PATH=$(realpath .volley/STATE)
   STARTED_PATH=$(realpath .volley)/CODEX-STARTED-${NONCE}

   # Windows-style absolute paths - embedded in Codex's prompt because Codex
   # runs via `codex exec` on Windows, where Cygwin-style paths like
   # /c/git/... are not understood by native file tools.
   PLAN_PATH_WIN=$(cygpath -w "$PLAN_PATH")
   HANDOFF_PATH_WIN=$(cygpath -w "$HANDOFF_PATH")
   LOG_PATH_WIN=$(cygpath -w "$LOG_PATH")
   STATE_PATH_WIN=$(cygpath -w "$STATE_PATH")
   STARTED_PATH_WIN=$(cygpath -w "$STARTED_PATH")
   ```

4. **Create IMPLEMENTATION-LOG.md before spawning.** This avoids a race where Codex starts fast and appends to the log before Claude truncates it.

   ```bash
   echo "# Codex implementation log - $(date -u +%Y-%m-%dT%H:%M:%SZ)" > .volley/IMPLEMENTATION-LOG.md
   ```

5. **Build Codex's prompt.** First instruction is the nonced started-marker handshake: gates the STATE flip on Codex actually starting, and the unique nonce guarantees we cannot mistake a prior Codex's marker for this run's.

   Compose the prompt as a multi-line string. **Use the `_WIN` path variables for every placeholder below** - Codex runs on Windows and needs paths it can create/read with native tools.

   ```
   You are implementing the plan at <PLAN_PATH_WIN>.

   Acceptance criteria are in <HANDOFF_PATH_WIN>.

   FIRST ACTION (do this before reading the plan): create an empty file at
   exactly this path:
     <STARTED_PATH_WIN>
   This is a one-time handshake so the orchestrator knows you launched cleanly.
   The path is unique to this run - do not reuse it from any prior session.

   Workflow:
   1. Read the plan and the HANDOFF in full.
   2. Implement each task in order, following its TDD steps.
   3. Append a one-line entry to <LOG_PATH_WIN> after each task you complete:
      "<ISO timestamp>  task <N>  done"
   4. When all tasks are done OR you cannot proceed, write the file at <STATE_PATH_WIN>
      with these exact lines (overwriting whatever is there):
        ACTIVE=claude
        TASK=done
        SINCE=<current ISO UTC timestamp>
        PID=0
   5. Print a final summary to your terminal of what you completed and what (if anything)
      you skipped.

   You may run shell commands, edit files, and run tests. Stay within the repo root.
   Do NOT push to git or open PRs - the user handles that.
   ```

6. **Write the prompt to a file under `.volley/`.** The spawner pipes this file's content to `codex exec` via stdin (not argv), so size is bounded by memory rather than by the Windows command-line limit.

   ```bash
   PROMPT_FILE=".volley/codex-prompt-${NONCE}.txt"
   printf '%s\n' "$CODEX_PROMPT" > "$PROMPT_FILE"
   ```

7. **Spawn the Codex tab.** The spawner takes a prompt-file path and pipes it through stdin to `codex exec`.

   ```bash
   WT_PID=$(bash "${CLAUDE_PLUGIN_ROOT}/scripts/spawn-codex.sh" "$PROMPT_FILE" "volley:codex")
   ```

8. **Wait for Codex to confirm it started.** Poll for the per-run marker with a 120-second timeout. This is a bounded handshake, NOT general progress polling - we only loop until the marker appears or the timeout fires. Because the marker path includes this run's NONCE, a stale Codex from a prior session cannot satisfy the poll. (120s, not 30s: `codex exec` model spin-up can take well over 30 seconds before it reaches its first action, and a 30s cap produced false "handshake failed" results even though Codex was about to start.)

   ```bash
   for i in $(seq 1 60); do
     [ -f "$STARTED_PATH" ] && break
     sleep 2
   done
   if [ ! -f "$STARTED_PATH" ]; then
     echo "ERROR: Codex did not write $STARTED_PATH within 120s." >&2
     echo "  The tab may have opened but Codex failed to launch (check the tab for parse errors or missing binaries)." >&2
     echo "  STATE was NOT flipped - Claude is still active. You can close the tab manually and retry." >&2
     exit 1
   fi
   ```

   Note the marker proves "Codex launched and reached its first action," not "Codex is still running and healthy." Mid-run liveness still depends on lock age and IMPLEMENTATION-LOG.md mtime, which `/volley:status` checks.

9. **Flip STATE only after the handshake.**

   ```bash
   . "${CLAUDE_PLUGIN_ROOT}/scripts/lib.sh"
   volley_state_write .volley/STATE codex implement-<derive-from-plan> 0
   ```

   Where `<derive-from-plan>` is a short slug from the plan filename or path, like `implement-phase-7-2`. If derivation is hard, use `implement`.

   **About PID=0 here:** the `wt` process exits in milliseconds after spawning the tab, so its PID is useless for liveness checks. The actual long-lived processes (PowerShell + Codex inside the tab) are not directly addressable from our shell. We record `PID=0` and rely on the SINCE timestamp + IMPLEMENTATION-LOG.md mtime for stale-lock detection (`/volley:status` flags `ACTIVE=codex` with `AGE > 1800s` as stale, regardless of PID).

10. **Tell the user what just happened.**
    ```
    ✓ Codex confirmed start (handshake at <STARTED_PATH>) and is now working in a Windows Terminal tab titled "volley:codex".
      WT spawn PID: <WT_PID> (informational; not used for liveness)
      Plan: <plan path>
      Prompt: <PROMPT_FILE>
      Log: .volley/IMPLEMENTATION-LOG.md (Codex appends as it completes tasks)
      STATE: ACTIVE=codex (Claude will refuse to edit source until Codex finishes)

    Watch the tab if you like. When Codex finishes it flips STATE back to ACTIVE=claude, and the background watcher (next step) re-invokes Claude automatically to start the review - you do not need to run /volley:status by hand.
    ```

11. **Launch the background completion watcher (auto-notify).** Codex flips STATE back to `ACTIVE=claude` when it finishes (all tasks done OR it cannot proceed). Launch ONE background command that blocks until that flip and then exits - the harness re-invokes Claude the moment it exits, so neither Claude nor the user has to keep running `/volley:status`. Run it with `run_in_background: true`:

    ```bash
    for i in $(seq 1 180); do
      if grep -q '^ACTIVE=claude' .volley/STATE 2>/dev/null; then
        echo "=== CODEX FINISHED (STATE flipped to claude) ==="; cat .volley/STATE
        echo "=== implementation log ==="; cat .volley/IMPLEMENTATION-LOG.md
        exit 0
      fi
      sleep 30
    done
    echo "=== WATCH TIMEOUT (90 min) - codex still ACTIVE=codex ==="; cat .volley/STATE
    ```

    When the watcher exits, Claude is re-invoked with the final STATE + implementation log. Claude then reads the log:
    - Every planned task logged `done` -> proceed to review (`/volley:review-code`).
    - A divergence note or fewer tasks than planned -> resolve it first (correct the plan, commit any already-done work, re-spawn from the next task), then review.
    - `WATCH TIMEOUT` with `ACTIVE=codex` -> the run is slow or stuck; check the tab / `/volley:status` (the stale-lock guard applies).

    This is a single fire-once notifier, NOT per-turn polling (see the note below).

12. **Print the next-step block.**
    ```bash
    . "${CLAUDE_PLUGIN_ROOT}/scripts/lib.sh"
    volley_next_step "/volley:review-code" "Codex is building; the background watcher (step 11) will notify Claude when STATE flips back. Then review the diff against the plan."
    ```

## Important: Claude does NOT interactively poll for progress

Claude does not re-run `/volley:status` every turn or spin its own per-turn loop checking STATE. There are exactly two sanctioned waits, both of which hand control back immediately: (1) the bounded handshake in step 8, and (2) the single background completion watcher in step 11, which runs detached and fires exactly ONCE when Codex flips STATE back. The watcher is what lets the harness re-invoke Claude on completion instead of relying on the user to notice the tab finished - it is not progress-polling. If the watcher times out or was never launched, the stale-lock guard in `/volley:status` still catches an abandoned `ACTIVE=codex` session.
