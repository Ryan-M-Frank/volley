---
name: doctor
description: Diagnose the Volley environment in one shot - Codex CLI, the bundled MCP bridge, the platform terminal, and the per-repo lock state. Use when setup misbehaves or before starting a session in a new repo.
---

# /volley:doctor

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

6. **Summary.** Print a final `Volley doctor: N passed, M warnings, K failures` line and, for each FAIL/WARN, the one-line remedy.
