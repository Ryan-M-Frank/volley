---
name: unlock
description: Use to force-clear the Volley STATE lock when something has gone wrong - Codex's terminal crashed, was closed, or otherwise left STATE in a bad state. Confirms with the user before clearing. The escape hatch from the concurrency model.
---

# /volley:unlock

Force-clear the lock. The escape hatch.

## Steps for Claude

1. **Read current STATE and show the user.**
   ```bash
   [ -f .volley/STATE ] || { echo "ERROR: .volley/STATE not found. Run /volley:setup first." >&2; exit 1; }
   . "${CLAUDE_PLUGIN_ROOT}/scripts/lib.sh"
   echo "Current STATE:"
   cat .volley/STATE
   echo ""
   AGE=$(volley_state_lock_age .volley/STATE 2>/dev/null) && echo "Lock age: ${AGE}s" || echo "Lock age: unknown"
   ```

2. **Confirm with the user.** Output:
   > "Force-clear this lock? STATE will be reset to ACTIVE=claude, TASK=idle, PID=0. Any work Codex was doing in a terminal tab will NOT be stopped automatically - you'll need to close that tab manually if you want Codex to stop. Confirm with 'yes' to proceed, or 'no' to abort."

   Wait for user response. Anything other than `yes` aborts.

3. **Reset STATE.**
   ```bash
   . "${CLAUDE_PLUGIN_ROOT}/scripts/lib.sh"
   volley_state_write .volley/STATE claude idle 0
   echo "Lock cleared."
   ```

4. **Print the next-step block.**
   ```bash
   . "${CLAUDE_PLUGIN_ROOT}/scripts/lib.sh"
   volley_next_step "/volley:status" "Verify the lock is clear and Claude is the active actor."
   ```
