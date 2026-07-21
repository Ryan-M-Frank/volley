---
name: diagnose
description: Diagnose the Volley environment in one shot - Codex CLI, the bundled MCP bridge, the platform terminal, and the per-repo lock state. Use when setup misbehaves or before starting a session in a new repo.
---

# /volley:diagnose

One-shot diagnosis of whether Volley is wired up correctly here. Run each check, print a `[PASS]`/`[FAIL]`/`[WARN]` line, and end with a remediation list for anything not green.

## Steps for Claude

1. **Codex CLI present.** Run `codex --version`. PASS if it prints a version >= 0.129; FAIL otherwise (remedy: `npm install -g @openai/codex`).

2. **Bundled Codex MCP reachable.** Check whether the `mcp__codex__codex` tool is available this session. PASS if available; WARN if not (remedy: `/reload-plugins` or restart Claude Code, since the plugin's bundled server may not have loaded yet).

3. **Platform terminal available.** Detect the OS and check for a usable terminal launcher:
   ```bash
   case "$(uname -s)" in
     Darwin*) command -v osascript >/dev/null && echo "[PASS] macOS terminal (osascript)" || echo "[FAIL] osascript missing" ;;
     Linux*)  { command -v gnome-terminal || command -v kitty || command -v tmux; } >/dev/null \
                && echo "[PASS] Linux terminal (gnome-terminal/kitty/tmux)" \
                || echo "[FAIL] no gnome-terminal/kitty/tmux - install one or use VOLLEY_PLATFORM=tmux" ;;
     MINGW*|MSYS*|CYGWIN*) command -v wt >/dev/null && echo "[PASS] Windows Terminal (wt)" || echo "[FAIL] wt missing - install Windows Terminal" ;;
     *) echo "[WARN] unrecognized OS; set VOLLEY_PLATFORM=tmux for the universal fallback" ;;
   esac
   ```

4. **Plugin assets intact.** Confirm the bundled scripts resolve:
   ```bash
   for f in scripts/lib.sh scripts/spawn-codex.sh scripts/platforms/windows.sh scripts/platforms/macos.sh scripts/platforms/linux.sh scripts/platforms/tmux.sh; do
     [ -f "${CLAUDE_PLUGIN_ROOT}/$f" ] && echo "[PASS] $f" || echo "[FAIL] missing $f"
   done
   ```

5. **Per-repo lock state.** If `.volley/STATE` exists, report it and whether the named process is alive; otherwise note the repo isn't initialized:
   ```bash
   if [ -f .volley/STATE ]; then
     active=$(grep -E '^ACTIVE=' .volley/STATE | cut -d= -f2)
     task=$(grep -E '^TASK=' .volley/STATE | cut -d= -f2)
     pid=$(grep -E '^PID=' .volley/STATE | cut -d= -f2)
     echo "[INFO] lock: ACTIVE=$active TASK=$task PID=$pid"
     if [ -n "$pid" ] && [ "$pid" != "0" ]; then
       kill -0 "$pid" 2>/dev/null && echo "[INFO] named PID $pid is alive" \
         || echo "[WARN] named PID $pid is dead - lock may be stale; run /volley:unlock if it's stuck"
     fi
   else
     echo "[WARN] .volley/ not initialized here - run /volley:setup"
   fi
   ```

6. **Continuity + model config (v0.2).** Non-mutating, and **no model turn unless the user explicitly asks for a live model probe.**
   - **Config parses & validates.** Read `.volley/config.json` (parse yourself - no jq). PASS if valid JSON with a known `version`; WARN if absent (= defaults in effect); FAIL if present but malformed or unknown `version`. Report the resolved review/implementation `model` + `reasoningEffort` (show `inherit` as "Codex default"). Do **not** call a model to check availability here - note that model validity is confirmed by the `/volley:setup` smoke call (or an opt-in `--live` probe).
   - **Repository identity.** Compare `.volley/local.json` `repository` to the live repo:
     ```bash
     . "${CLAUDE_PLUGIN_ROOT}/scripts/lib.sh"
     if [ -f .volley/local.json ]; then
       # extract stored root/remote in-host (JSON), then:
       volley_repo_identity_matches "<stored_root>" "<stored_remote>" \
         && echo "[PASS] repo identity matches live checkout" \
         || echo "[WARN] repo identity mismatch - stored session IDs will be ignored (fresh session + file rehydration)"
     else
       echo "[INFO] no .volley/local.json yet - run /volley:setup"
     fi
     ```
   - **Context files.** For each `context.required` file, PASS if present / FAIL if missing (names the file). For `context.optional`, list present vs skipped.
   - **Saved-session integrity.** If `.volley/local.json` has role thread/session IDs, report them as present (never print secrets); WARN if the file is unreadable/corrupt.
   - **Managed checkpoint.** PASS if `.volley/CHECKPOINT.md` exists and still contains both `volley:managed` markers; WARN otherwise.

7. **Summary.** Print a final `Volley diagnose: N passed, M warnings, K failures` line and, for each FAIL/WARN, the one-line remedy.
