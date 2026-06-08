# Volley Plugin Extraction Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a standalone, public, cross-platform Claude Code **plugin** named **Volley** (the DUO Claude+Codex workflow, renamed) in its own repo, installable via a plugin marketplace, without touching RASA's working `duo-*` install.

**Architecture:** A new git repo at `C:\git\volley` laid out as a Claude Code plugin (`.claude-plugin/plugin.json` + top-level `skills/`, `scripts/`, `.mcp.json`). The 7 skills, the bash library, the spawn dispatcher, and the test suite are **copied** from their current homes (skills from `~/.claude/skills/duo-*`, scripts/tests from the #108 branch which has the refactored dispatcher) and put through a mechanical `duo→volley` + `copair→volley` rename. Three new platform handlers (`macos.sh`, `linux.sh`, `tmux.sh`) are written test-first to satisfy the existing dispatcher contract. The Codex MCP server is bundled so it auto-registers on install.

**Tech Stack:** Bash (scripts, handlers, tests), Markdown (skills), JSON (plugin/marketplace/MCP manifests), GitHub Actions (CI matrix: windows/macos/ubuntu), Claude Code plugin system (`${CLAUDE_PLUGIN_ROOT}`, `/plugin`, `/reload-plugins`).

**Source refs (read these exact versions):**
- Skills: `~/.claude/skills/duo-{setup,status,unlock,implement,review-plan,review-code,review-pr}/SKILL.md`
- Scripts + tests (REFRACTORED): the `feature/copair-spawn-codex-refactor` branch in `C:\git\RASA\RASA_DEMO-copair` (read via `git show feature/copair-spawn-codex-refactor:<path>`). Do NOT use the `master`/origin working-tree copies - they predate the #108 dispatcher refactor.
- README draft: `.duo/README-DRAFT.md` (in RASA_DEMO-copair)

**Two naming families to eliminate (AC1 gate):** both `duo`/`DUO`/`.duo`/`duo_`/`duo-` AND `copair`/`COPAIR` (the dispatcher uses `COPAIR_PLATFORM`). The grep gate checks both.

**Namespacing rule:** plugin skills are invoked `/<plugin>:<skill>`. The plugin is `volley`, so skill folders DROP the prefix: `duo-setup/` → `setup/` (invoked `/volley:setup`). Do NOT name them `volley-setup/` (that yields `/volley:volley-setup`).

---

## File Structure

```
C:\git\volley\
├── .claude-plugin/
│   ├── plugin.json              # manifest: name volley, version 0.1.0, Apache-2.0
│   └── marketplace.json         # lists volley, source "./"
├── skills/                      # 7 skills, prefix dropped
│   ├── setup/SKILL.md
│   ├── status/SKILL.md
│   ├── unlock/SKILL.md
│   ├── implement/SKILL.md
│   ├── review-plan/SKILL.md
│   ├── review-code/SKILL.md
│   └── review-pr/SKILL.md
├── scripts/
│   ├── lib.sh                   # was duo-lib.sh; volley_* functions
│   ├── spawn-codex.sh           # dispatcher; VOLLEY_PLATFORM override
│   ├── platforms/
│   │   ├── windows.sh           # ported
│   │   ├── macos.sh             # NEW (TDD)
│   │   ├── linux.sh             # NEW (TDD)
│   │   └── tmux.sh              # NEW (TDD, CI-tested)
│   └── templates/
│       ├── HANDOFF.md
│       └── gitignore            # was duo-gitignore
├── .mcp.json                    # bundled Codex server
├── tests/
│   ├── test-lib.sh
│   ├── test-setup.sh
│   ├── test-concurrency.sh
│   ├── test-stale-lock.sh
│   ├── test-spawn-codex.sh
│   └── test-platform-handlers.sh   # NEW
├── .github/workflows/ci.yml     # matrix win+macos+ubuntu
├── README.md
└── LICENSE                      # Apache-2.0
```

**Responsibilities:** `scripts/lib.sh` = state lock + next-step helpers (no I/O beyond STATE file). `scripts/spawn-codex.sh` = OS detection + handler dispatch only. `scripts/platforms/*.sh` = one terminal-launcher each, all exposing `spawn_<platform>(prompt_file, title)`. `skills/*` = the user-facing workflow steps. Tests mirror each unit.

---

## Task 1: Scaffold the Volley repo + plugin manifest

**Files:**
- Create: `C:\git\volley\.claude-plugin\plugin.json`
- Create: `C:\git\volley\.claude-plugin\marketplace.json`
- Create: `C:\git\volley\LICENSE`
- Create: `C:\git\volley\.gitignore`

- [ ] **Step 1: Create the repo and directory skeleton**

Run (PowerShell):
```powershell
New-Item -ItemType Directory -Force C:\git\volley | Out-Null
cd C:\git\volley
git init
New-Item -ItemType Directory -Force .claude-plugin, skills, scripts\platforms, scripts\templates, tests, .github\workflows | Out-Null
```

- [ ] **Step 2: Write `.claude-plugin/plugin.json`**

```json
{
  "name": "volley",
  "version": "0.1.0",
  "description": "Two AI coding assistants in one repo, behind a hard lock. Claude and OpenAI Codex plan, implement, and review each other's work without colliding.",
  "author": { "name": "Ryan Frank", "email": "frank.ryanm@gmail.com" },
  "homepage": "https://github.com/Ryan-M-Frank/volley",
  "repository": "https://github.com/Ryan-M-Frank/volley",
  "license": "Apache-2.0",
  "keywords": ["claude-code", "codex", "pair-programming", "code-review", "workflow"]
}
```

- [ ] **Step 3: Write `.claude-plugin/marketplace.json`**

```json
{
  "name": "volley",
  "owner": { "name": "Ryan Frank" },
  "plugins": [
    {
      "name": "volley",
      "source": "./",
      "description": "Two AI coding assistants in one repo, behind a hard lock."
    }
  ]
}
```

- [ ] **Step 4: Add LICENSE (full Apache-2.0 text) and a repo `.gitignore`**

Fetch the canonical text:
```powershell
Invoke-WebRequest https://www.apache.org/licenses/LICENSE-2.0.txt -OutFile LICENSE
```
`.gitignore` (repo-level; the per-project `.volley/` runtime dir is ignored by the consuming repo, not here):
```
*.log
.DS_Store
```

- [ ] **Step 5: Validate the plugin skeleton**

Run: `claude plugin validate ./`
Expected: PASS (manifest valid). If the exact CLI subcommand differs in the installed version, confirm with `claude plugin --help` and use the validation command it lists. Record the working command for the CI task.

- [ ] **Step 6: Commit**

```bash
git add -A
git commit -m "chore: scaffold volley plugin repo + Apache-2.0 license"
```

---

## Task 2: Port the bash library (`duo-lib.sh` → `scripts/lib.sh`)

**Files:**
- Create: `C:\git\volley\scripts\lib.sh` (from `git show feature/copair-spawn-codex-refactor:scripts/duo/duo-lib.sh`)

- [ ] **Step 1: Copy the source verbatim**

From the RASA_DEMO-copair repo:
```bash
git show feature/copair-spawn-codex-refactor:scripts/duo/duo-lib.sh > /c/git/volley/scripts/lib.sh
```

- [ ] **Step 2: Apply the rename transforms (in `C:\git\volley`)**

Run exactly (GNU sed; on Windows use Git Bash):
```bash
cd /c/git/volley
sed -i \
  -e 's/duo_/volley_/g' \
  -e 's/\.duo\//.volley\//g' \
  -e 's/\.duo\b/.volley/g' \
  -e 's/\bCOPAIR_/VOLLEY_/g' \
  -e 's/\bcopair\b/volley/g' \
  -e 's#/duo-\([a-z-]*\)#/volley:\1#g' \
  -e 's/duo:codex/volley:codex/g' \
  scripts/lib.sh
```
Note: the `/duo-<x>` → `/volley:<x>` rule converts any user-facing command references in messages. Function names use `volley_` (underscore), command refs use `volley:` (colon).

- [ ] **Step 3: Verify no residue in this file**

Run: `grep -niwE 'duo|copair' scripts/lib.sh ; grep -nE 'duo_|\.duo|duo-|COPAIR' scripts/lib.sh`
Expected: no output (exit 1 from grep). If anything prints, hand-fix it.

- [ ] **Step 4: Smoke-check the lib loads and a core function works**

```bash
bash -c '. /c/git/volley/scripts/lib.sh && volley_state_write /tmp/STATE claude idle 0 && cat /tmp/STATE'
```
Expected: prints a STATE file with `ACTIVE=claude`, `TASK=idle`. (Confirms `duo_state_write`→`volley_state_write` renamed consistently, including internal references.)

- [ ] **Step 5: Commit**

```bash
git add scripts/lib.sh && git commit -m "feat: port duo-lib as volley lib (volley_* functions)"
```

---

## Task 3: Port the spawn dispatcher + windows handler + its test

**Files:**
- Create: `C:\git\volley\scripts\spawn-codex.sh`
- Create: `C:\git\volley\scripts\platforms\windows.sh`
- Create: `C:\git\volley\tests\test-spawn-codex.sh`

- [ ] **Step 1: Copy the three sources from the #108 branch**

```bash
R=feature/copair-spawn-codex-refactor
git show $R:scripts/duo/spawn-codex.sh        > /c/git/volley/scripts/spawn-codex.sh
git show $R:scripts/duo/platforms/windows.sh  > /c/git/volley/scripts/platforms/windows.sh
git show $R:tests/duo/test-spawn-codex.sh     > /c/git/volley/tests/test-spawn-codex.sh
```

- [ ] **Step 2: Apply transforms to all three**

```bash
cd /c/git/volley
sed -i \
  -e 's/\bCOPAIR_PLATFORM\b/VOLLEY_PLATFORM/g' \
  -e 's/\bCOPAIR_/VOLLEY_/g' \
  -e 's/duo:codex/volley:codex/g' \
  -e 's#/duo-\([a-z-]*\)#/volley:\1#g' \
  -e 's/\.duo\//.volley\//g' \
  -e 's/\bcopair\b/volley/g' \
  scripts/spawn-codex.sh scripts/platforms/windows.sh tests/test-spawn-codex.sh
```
Also fix the test's path roots: the test computes `SCRIPT="${ROOT}/scripts/duo/spawn-codex.sh"` - update to `scripts/spawn-codex.sh`:
```bash
sed -i 's#scripts/duo/spawn-codex.sh#scripts/spawn-codex.sh#g' tests/test-spawn-codex.sh
```

- [ ] **Step 3: Verify residue gone + test paths correct**

Run: `grep -nwE 'duo|copair|COPAIR' scripts/spawn-codex.sh scripts/platforms/windows.sh tests/test-spawn-codex.sh`
Expected: no output. (The default title is now `volley:codex`; test 7 asserts that.)

- [ ] **Step 4: Run the dispatcher test (it stubs handlers, no real terminal)**

Run: `bash tests/test-spawn-codex.sh`
Expected: `PASS=8 FAIL=0`, exit 0. The test stubs windows/macos/linux/tmux handlers, so it passes before those real handlers exist.

- [ ] **Step 5: Commit**

```bash
git add scripts/spawn-codex.sh scripts/platforms/windows.sh tests/test-spawn-codex.sh
git commit -m "feat: port cross-platform spawn dispatcher + windows handler (VOLLEY_PLATFORM)"
```

---

## Task 4: NEW - `tmux.sh` handler (TDD; the CI-tested universal path)

**Files:**
- Create: `C:\git\volley\tests\test-platform-handlers.sh`
- Create: `C:\git\volley\scripts\platforms\tmux.sh`

- [ ] **Step 1: Write the failing test for `spawn_tmux`**

Create `tests/test-platform-handlers.sh`:
```bash
#!/usr/bin/env bash
# Tests for the platform handlers. The tmux handler is fully exercised (CI can
# run a headless tmux server). macos/linux desktop handlers are smoke-checked
# for "errors cleanly when no terminal is available" only - real GUI launch is
# community-tested.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMPDIR=$(mktemp -d); trap 'rm -rf "$TMPDIR"' EXIT
PASS=0; FAIL=0
fail() { echo "FAIL: $1"; FAIL=$((FAIL+1)); }
pass() { echo "PASS: $1"; PASS=$((PASS+1)); }

PROMPT="$TMPDIR/prompt.txt"; echo "hello from plan" > "$PROMPT"

# --- tmux handler ---
if command -v tmux >/dev/null 2>&1; then
  # Stub `codex` on PATH so the session runs something deterministic that
  # writes a marker file, proving the prompt was streamed to it via stdin.
  BIN="$TMPDIR/bin"; mkdir -p "$BIN"
  cat > "$BIN/codex" <<EOF
#!/usr/bin/env bash
# stub: 'codex exec' reads prompt on stdin; record it
cat > "$TMPDIR/codex-received.txt"
EOF
  chmod +x "$BIN/codex"

  ( . "$ROOT/scripts/platforms/tmux.sh"
    PATH="$BIN:$PATH" spawn_tmux "$PROMPT" "volley:codex" >/dev/null )
  # Give the detached session a moment to consume stdin.
  for _ in 1 2 3 4 5 6 7 8 9 10; do [ -s "$TMPDIR/codex-received.txt" ] && break; sleep 0.3; done
  grep -q "hello from plan" "$TMPDIR/codex-received.txt" 2>/dev/null \
    && pass "spawn_tmux streams the prompt file to codex via stdin" \
    || fail "spawn_tmux did not stream prompt (got: $(cat "$TMPDIR/codex-received.txt" 2>/dev/null))"
else
  echo "SKIP: tmux not installed - tmux handler test skipped"
fi

# --- missing-terminal clean error (run handlers with an empty PATH) ---
# Guarded so the suite passes incrementally as each handler lands (Tasks 4-6).
for h in macos linux tmux; do
  [ -f "$ROOT/scripts/platforms/$h.sh" ] || { echo "SKIP: $h.sh not present yet"; continue; }
  ( . "$ROOT/scripts/platforms/$h.sh"
    PATH="/nonexistent" "spawn_$h" "$PROMPT" "t" ) >/dev/null 2>&1
  rc=$?
  [ "$rc" -ne 0 ] && pass "spawn_$h returns non-zero when its terminal is absent" \
                  || fail "spawn_$h should fail when terminal absent (rc=$rc)"
done

echo ""; echo "PASS=$PASS FAIL=$FAIL"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
```

- [ ] **Step 2: Run it to confirm it fails (handler files don't exist yet)**

Run: `bash tests/test-platform-handlers.sh`
Expected: FAIL - sourcing `scripts/platforms/tmux.sh` errors ("No such file"). Confirms the test drives the code.

- [ ] **Step 3: Write `scripts/platforms/tmux.sh`**

```bash
#!/usr/bin/env bash
# tmux handler for scripts/spawn-codex.sh - the universal/headless fallback.
# Sourced by the dispatcher; exposes spawn_tmux(). Runs `codex exec` inside a
# detached tmux session with the prompt streamed via stdin (same argv-avoiding
# rationale as the other handlers). Liveness is the CODEX-STARTED handshake,
# not the session name echoed here.

spawn_tmux() {
  local prompt_file="$1" title="$2"

  command -v tmux >/dev/null || {
    echo "ERROR: tmux not found in PATH. Install tmux, or set VOLLEY_PLATFORM to a desktop handler (windows/macos/linux)." >&2
    return 127
  }

  # Sanitize the title into a valid tmux session name.
  local session="volley_${title//[^a-zA-Z0-9_-]/_}"

  # Run codex with the prompt on stdin. `exec bash` keeps the pane open after
  # Codex exits so the user can read the final output. printf %q safely quotes
  # the path for the shell tmux spawns.
  local qpath; qpath=$(printf %q "$prompt_file")
  tmux new-session -d -s "$session" "cat ${qpath} | codex exec; exec bash"

  # Informational identifier only.
  echo "tmux:${session}"
}
```

- [ ] **Step 4: Run the test to verify it passes**

Run: `bash tests/test-platform-handlers.sh`
Expected (on a box/CI with tmux): `PASS: spawn_tmux streams the prompt file to codex via stdin` and the tmux missing-terminal case passes; `FAIL=0`. On the Windows dev box without tmux, the tmux stream test prints `SKIP` - that's expected; CI (ubuntu/macos) covers it.

- [ ] **Step 5: Commit**

```bash
git add scripts/platforms/tmux.sh tests/test-platform-handlers.sh
git commit -m "feat: tmux spawn handler (universal headless path) + handler tests"
```

---

## Task 5: NEW - `macos.sh` handler

**Files:**
- Create: `C:\git\volley\scripts\platforms\macos.sh`

- [ ] **Step 1: Write `scripts/platforms/macos.sh`**

```bash
#!/usr/bin/env bash
# macOS handler for scripts/spawn-codex.sh. Sourced by the dispatcher; exposes
# spawn_macos(). Opens a new terminal window (iTerm2 if running/installed, else
# Terminal.app) running `codex exec` with the prompt streamed via stdin.

spawn_macos() {
  local prompt_file="$1" title="$2"

  command -v osascript >/dev/null || {
    echo "ERROR: osascript not found - spawn_macos requires macOS. Set VOLLEY_PLATFORM=tmux for the universal fallback." >&2
    return 127
  }

  local qpath; qpath=$(printf %q "$prompt_file")
  # The command the new terminal will run. `cat | codex exec` avoids argv limits.
  local inner="cat ${qpath} | codex exec"

  if osascript -e 'tell application "System Events" to (name of processes) contains "iTerm2"' 2>/dev/null | grep -qi true \
     || [ -d "/Applications/iTerm.app" ]; then
    osascript >/dev/null 2>&1 <<OSA || { echo "ERROR: failed to launch iTerm2" >&2; return 1; }
tell application "iTerm"
  set newWindow to (create window with default profile)
  tell current session of newWindow
    set name to "${title}"
    write text "${inner}"
  end tell
end tell
OSA
  else
    osascript >/dev/null 2>&1 <<OSA || { echo "ERROR: failed to launch Terminal.app" >&2; return 1; }
tell application "Terminal"
  do script "${inner}"
  activate
end tell
OSA
  fi

  echo "macos:${title}"
}
```

- [ ] **Step 2: Syntax-check the handler (cannot launch a GUI on the Windows dev box)**

Run: `bash -n scripts/platforms/macos.sh && echo OK`
Expected: `OK` (parses). Full launch is verified on macOS CI / community-tested per the spec.

- [ ] **Step 3: Verify the missing-terminal path via the handler test**

Run: `bash tests/test-platform-handlers.sh`
Expected: `PASS: spawn_macos returns non-zero when its terminal is absent` (osascript absent on non-mac → returns 127).

- [ ] **Step 4: Commit**

```bash
git add scripts/platforms/macos.sh
git commit -m "feat: macOS spawn handler (iTerm2 / Terminal.app via osascript)"
```

---

## Task 6: NEW - `linux.sh` handler

**Files:**
- Create: `C:\git\volley\scripts\platforms\linux.sh`

- [ ] **Step 1: Write `scripts/platforms/linux.sh`**

```bash
#!/usr/bin/env bash
# Linux handler for scripts/spawn-codex.sh. Sourced by the dispatcher; exposes
# spawn_linux(). Tries a desktop terminal (gnome-terminal, then kitty); if none
# is present (headless/SSH), delegates to the tmux handler.

spawn_linux() {
  local prompt_file="$1" title="$2"
  local qpath; qpath=$(printf %q "$prompt_file")
  local inner="cat ${qpath} | codex exec; exec bash"

  if command -v gnome-terminal >/dev/null; then
    gnome-terminal --title "${title}" -- bash -c "${inner}" &
    echo "linux:gnome-terminal:$!"
    return 0
  fi
  if command -v kitty >/dev/null; then
    kitty --title "${title}" bash -c "${inner}" &
    echo "linux:kitty:$!"
    return 0
  fi

  # No desktop terminal - fall back to the tmux handler (headless path).
  local here; here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  if [ -f "${here}/tmux.sh" ] && command -v tmux >/dev/null; then
    . "${here}/tmux.sh"
    spawn_tmux "$prompt_file" "$title"
    return $?
  fi

  echo "ERROR: no supported terminal (gnome-terminal/kitty) and no tmux. Install one, or set VOLLEY_PLATFORM=tmux after installing tmux." >&2
  return 127
}
```

- [ ] **Step 2: Syntax-check**

Run: `bash -n scripts/platforms/linux.sh && echo OK`
Expected: `OK`.

- [ ] **Step 3: Verify the handler test's missing-terminal case for linux**

Run: `bash tests/test-platform-handlers.sh`
Expected: `PASS: spawn_linux returns non-zero when its terminal is absent` (empty PATH → no gnome-terminal/kitty/tmux → returns 127). On ubuntu CI with tmux installed, the delegation path is exercised by the tmux test indirectly.

- [ ] **Step 4: Commit**

```bash
git add scripts/platforms/linux.sh
git commit -m "feat: Linux spawn handler (gnome-terminal/kitty, tmux fallback)"
```

---

## Task 7: Port templates

**Files:**
- Create: `C:\git\volley\scripts\templates\HANDOFF.md`
- Create: `C:\git\volley\scripts\templates\gitignore`

- [ ] **Step 1: Copy from the #108 branch and rename the gitignore template**

```bash
R=feature/copair-spawn-codex-refactor
git show $R:scripts/duo/templates/HANDOFF.md      > /c/git/volley/scripts/templates/HANDOFF.md
git show $R:scripts/duo/templates/duo-gitignore   > /c/git/volley/scripts/templates/gitignore
```

- [ ] **Step 2: Transform any duo/copair references inside the templates**

```bash
cd /c/git/volley
sed -i -e 's/\.duo\//.volley\//g' -e 's#/duo-\([a-z-]*\)#/volley:\1#g' \
       -e 's/\bcopair\b/volley/g' -e 's/\bDUO\b/Volley/g' \
       scripts/templates/HANDOFF.md scripts/templates/gitignore
```

- [ ] **Step 3: Verify**

Run: `grep -niwE 'duo|copair' scripts/templates/*`
Expected: no output.

- [ ] **Step 4: Commit**

```bash
git add scripts/templates && git commit -m "feat: port HANDOFF + gitignore templates"
```

---

## Task 8: Port the 7 skills (rename + de-prefix + ${CLAUDE_PLUGIN_ROOT} rewire)

**Files:**
- Create: `C:\git\volley\skills\{setup,status,unlock,implement,review-plan,review-code,review-pr}\SKILL.md`

This task ports six skills mechanically; `setup` gets extra changes in Task 9 (MCP bundling). Do all seven here first, then specialize `setup`.

- [ ] **Step 1: Copy each skill, dropping the `duo-` folder prefix**

```bash
cd /c/git/volley
for s in setup status unlock implement review-plan review-code review-pr; do
  mkdir -p "skills/$s"
  cp "$HOME/.claude/skills/duo-$s/SKILL.md" "skills/$s/SKILL.md"
done
```

- [ ] **Step 2: Apply the rename transforms to every skill body**

Order matters: rewrite script paths BEFORE the generic `duo` rules so the `$HOME/.claude/scripts/duo/` prefix is captured as a unit.
```bash
cd /c/git/volley
for s in setup status unlock implement review-plan review-code review-pr; do
  f="skills/$s/SKILL.md"
  sed -i \
    -e 's#\$HOME/\.claude/scripts/duo/duo-lib\.sh#${CLAUDE_PLUGIN_ROOT}/scripts/lib.sh#g' \
    -e 's#\$HOME/\.claude/scripts/duo/spawn-codex\.sh#${CLAUDE_PLUGIN_ROOT}/scripts/spawn-codex.sh#g' \
    -e 's#\$HOME/\.claude/scripts/duo/templates/duo-gitignore#${CLAUDE_PLUGIN_ROOT}/scripts/templates/gitignore#g' \
    -e 's#\$HOME/\.claude/scripts/duo/templates/#${CLAUDE_PLUGIN_ROOT}/scripts/templates/#g' \
    -e 's#\$HOME/\.claude/scripts/duo/#${CLAUDE_PLUGIN_ROOT}/scripts/#g' \
    -e 's/duo_/volley_/g' \
    -e 's/\.duo\//.volley\//g' \
    -e 's/duo:codex/volley:codex/g' \
    -e 's#/duo-\([a-z-]*\)#/volley:\1#g' \
    -e 's/\bCOPAIR_/VOLLEY_/g' \
    -e 's/\bcopair\b/volley/g' \
    "$f"
done
```

- [ ] **Step 3: Fix the frontmatter `name:` (drop prefix) and the H1 heading**

The `s#/duo-<x>#/volley:<x>#` rule already converted `# /duo-setup` → `# /volley:setup`. Now fix the YAML `name:` to the bare skill name (namespacing supplies `volley:`):
```bash
cd /c/git/volley
for s in setup status unlock implement review-plan review-code review-pr; do
  sed -i "s/^name: duo-$s\$/name: $s/" "skills/$s/SKILL.md"
done
```

- [ ] **Step 4: Quote the `${CLAUDE_PLUGIN_ROOT}` source lines**

`${CLAUDE_PLUGIN_ROOT}` can contain spaces (e.g. `C:\Users\Ryan Frank\...`). Any line that sources or runs a script must quote it. Convert `. ${CLAUDE_PLUGIN_ROOT}/scripts/lib.sh` → `. "${CLAUDE_PLUGIN_ROOT}/scripts/lib.sh"` and `bash ${CLAUDE_PLUGIN_ROOT}/...` → `bash "${CLAUDE_PLUGIN_ROOT}/..."`:
```bash
cd /c/git/volley
for s in setup status unlock implement review-plan review-code review-pr; do
  f="skills/$s/SKILL.md"
  sed -i -E 's#(\. )(\$\{CLAUDE_PLUGIN_ROOT\}/scripts/[^ ]*\.sh)#\1"\2"#g' "$f"
  sed -i -E 's#(bash )(\$\{CLAUDE_PLUGIN_ROOT\}/scripts/[^ ]*\.sh)#\1"\2"#g' "$f"
done
```

- [ ] **Step 5: Verify residue gone across all skills**

Run:
```bash
grep -rniwE 'duo|copair' skills/ ; grep -rnE 'duo_|\.duo|duo-|COPAIR|\$HOME/\.claude/scripts' skills/
```
Expected: no output. Then confirm every script reference is quoted:
```bash
grep -rnE '(\.|bash) \$\{CLAUDE_PLUGIN_ROOT\}' skills/ | grep -v '"' || echo "all quoted"
```
Expected: `all quoted`.

- [ ] **Step 6: Commit**

```bash
git add skills/ && git commit -m "feat: port 7 skills - de-prefixed, CLAUDE_PLUGIN_ROOT paths"
```

---

## Task 9: Specialize the `setup` skill for bundled MCP + reachability detection

**Files:**
- Modify: `C:\git\volley\skills\setup\SKILL.md`
- Create: `C:\git\volley\.mcp.json`

Because the plugin bundles the Codex MCP server, `/volley:setup` no longer writes a project `.mcp.json`. It must instead detect whether the bundled server is live and instruct a reload if not.

- [ ] **Step 1: Create the bundled `.mcp.json` at the plugin root**

```json
{
  "mcpServers": {
    "codex": {
      "command": "codex",
      "args": ["mcp-server"]
    }
  }
}
```

- [ ] **Step 2: Replace setup Step 2 ("Register Codex MCP") with a reachability gate**

In `skills/setup/SKILL.md`, replace the entire "2. **Register Codex as a project-scoped MCP server.**" section (the JSON block and Edit/Write instruction) with:
```markdown
2. **Confirm the bundled Codex MCP server is reachable.**
   - Volley bundles the Codex MCP server (see the plugin's `.mcp.json`); you do NOT write a project `.mcp.json`.
   - Check whether the `mcp__codex__codex` tool is available in this session.
   - If it is NOT available, the plugin was just installed and its MCP server has not loaded yet. Tell the user:
     "Run `/reload-plugins` (or restart Claude Code) so Volley's bundled Codex server loads, then re-run `/volley:setup`."
     (Confirm the exact reload command against this Claude Code version if `/reload-plugins` is not recognized.)
     Then STOP - do not continue until the tool is reachable.
   - If it IS available, continue.
```

- [ ] **Step 3: Update setup Step 3 (scaffold) - drop the gitignore prefix, keep template paths**

The template copy lines were already rewired to `${CLAUDE_PLUGIN_ROOT}/scripts/templates/` in Task 8. Confirm the gitignore line reads:
`cp "${CLAUDE_PLUGIN_ROOT}/scripts/templates/gitignore" .volley/.gitignore`
and the HANDOFF line reads:
`cp "${CLAUDE_PLUGIN_ROOT}/scripts/templates/HANDOFF.md" .volley/HANDOFF.md`
Fix by hand if Task 8's sed left `duo-gitignore` anywhere:
```bash
sed -i 's#templates/duo-gitignore#templates/gitignore#g' /c/git/volley/skills/setup/SKILL.md
```

- [ ] **Step 4: Update the setup `description:` and "already-installed" check**

The "already-installed" section checks `.mcp.json` for the codex entry - that no longer applies. Replace its condition with: "If `.volley/STATE` exists, skip scaffolding; just re-run the smoke test (step 4) and print the next-step block." Update the frontmatter `description:` to drop "registers Codex as an MCP server in .mcp.json" and say "confirms the bundled Codex MCP server is reachable".

- [ ] **Step 5: Verify the setup skill**

Run:
```bash
grep -niwE 'duo|copair' /c/git/volley/skills/setup/SKILL.md
grep -n 'reload-plugins\|CLAUDE_PLUGIN_ROOT\|mcp__codex__codex' /c/git/volley/skills/setup/SKILL.md
```
Expected: first grep empty; second shows the reload instruction, the quoted template paths, and the tool-reachability check.

- [ ] **Step 6: Commit**

```bash
cd /c/git/volley
git add skills/setup/SKILL.md .mcp.json
git commit -m "feat: bundle Codex MCP; setup detects reachability + instructs /reload-plugins"
```

---

## Task 10: Port the remaining tests + adapt path roots

**Files:**
- Create: `C:\git\volley\tests\{test-lib,test-setup,test-concurrency,test-stale-lock}.sh`

- [ ] **Step 1: Copy the remaining test files from the #108 branch**

```bash
R=feature/copair-spawn-codex-refactor
for t in test-lib test-setup test-concurrency test-stale-lock; do
  git show $R:tests/duo/$t.sh > /c/git/volley/tests/$t.sh
done
```

- [ ] **Step 2: Transform names AND path roots**

The tests reference `scripts/duo/`, `duo-lib.sh`, `tests/duo`, `duo_*`, `.duo`, `COPAIR_PLATFORM`, `duo:codex`. Rewrite:
```bash
cd /c/git/volley
for t in test-lib test-setup test-concurrency test-stale-lock; do
  f="tests/$t.sh"
  sed -i \
    -e 's#scripts/duo/duo-lib\.sh#scripts/lib.sh#g' \
    -e 's#scripts/duo/#scripts/#g' \
    -e 's#tests/duo/#tests/#g' \
    -e 's#templates/duo-gitignore#templates/gitignore#g' \
    -e 's/duo_/volley_/g' \
    -e 's/\.duo\b/.volley/g' \
    -e 's/\bCOPAIR_/VOLLEY_/g' \
    -e 's/duo:codex/volley:codex/g' \
    -e 's#/duo-\([a-z-]*\)#/volley:\1#g' \
    -e 's/\bcopair\b/volley/g' \
    -e 's#dirname "$0")/../..#dirname "$0")/..#g' \
    "$f"
done
```
**ROOT depth (critical - this exact bug broke test-spawn-codex.sh in Task 3):** these tests lived at `tests/duo/` and compute their repo root as `$(dirname "$0")/../..`. Now that they live directly in `tests/`, `../..` climbs ONE LEVEL TOO HIGH and every `${ROOT}/scripts/...` path misses. The `dirname "$0")/../.. -> /..` sed line above fixes it. After transform, OPEN each test and confirm `ROOT` resolves to the repo root, then RUN it (next step) - a wrong ROOT shows up as "No such file or directory" failures, not a clean error.

- [ ] **Step 3: Verify residue + run the full suite locally**

```bash
cd /c/git/volley
grep -rnwE 'duo|copair|COPAIR' tests/ || echo "tests clean"
for t in tests/*.sh; do echo "== $t =="; bash "$t" || echo "  (see failures above)"; done
```
Expected: `tests clean`; `test-lib`, `test-setup`, `test-concurrency`, `test-stale-lock`, `test-spawn-codex` pass on the Windows dev box. `test-platform-handlers` tmux-stream case prints SKIP without tmux (covered by CI). Investigate any real failure before continuing (do not rationalize a red as environmental without proof).

- [ ] **Step 4: Commit**

```bash
git add tests/ && git commit -m "feat: port test suite, adapt path roots to flat scripts/ + tests/"
```

---

## Task 11: CI matrix workflow

**Files:**
- Create: `C:\git\volley\.github\workflows\ci.yml`

- [ ] **Step 1: Write the workflow**

```yaml
name: ci
on:
  push:
  pull_request:
jobs:
  test:
    strategy:
      fail-fast: false
      matrix:
        os: [ubuntu-latest, macos-latest, windows-latest]
    runs-on: ${{ matrix.os }}
    steps:
      - uses: actions/checkout@v4
      - name: Install tmux (linux/macos)
        if: runner.os != 'Windows'
        shell: bash
        run: |
          if [ "$RUNNER_OS" = "Linux" ]; then sudo apt-get update && sudo apt-get install -y tmux; fi
          if [ "$RUNNER_OS" = "macOS" ]; then brew install tmux || true; fi
      - name: Run bash test suite
        shell: bash
        run: |
          fail=0
          for t in tests/*.sh; do
            echo "== $t =="
            bash "$t" || fail=1
          done
          exit $fail
  validate:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Validate plugin manifest
        run: |
          # Use the plugin validation command confirmed in Task 1, Step 5.
          # If the Claude CLI is unavailable on CI, fall back to JSON lint:
          python3 -c "import json,sys; json.load(open('.claude-plugin/plugin.json')); json.load(open('.claude-plugin/marketplace.json')); json.load(open('.mcp.json')); print('manifests valid JSON')"
```

- [ ] **Step 2: Validate the YAML locally**

Run: `python3 -c "import yaml,sys; yaml.safe_load(open('.github/workflows/ci.yml')); print('yaml ok')"` (or any YAML linter available).
Expected: `yaml ok`.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/ci.yml && git commit -m "ci: matrix (ubuntu/macos/windows) test suite + manifest validation"
```

---

## Task 12: De-placeholder the README

**Files:**
- Create: `C:\git\volley\README.md` (from `.duo/README-DRAFT.md` in RASA_DEMO-copair)

- [ ] **Step 1: Copy the draft and strip the HTML build-note comment**

```bash
cp "/c/git/RASA/RASA_DEMO-copair/.duo/README-DRAFT.md" /c/git/volley/README.md
```
Delete the leading `<!-- ... -->` placeholder-list comment block at the top of the file.

- [ ] **Step 2: Resolve every placeholder token**

Replace throughout `README.md`:
- `{ORG}/{REPO}` → `Ryan-M-Frank/volley`
- `{YEAR}` → `2026`
- the badge `License: Apache-2.0` URL/label → keep Apache-2.0 (already chosen)
- `{DEMO_GIF}` → remove the image line for v0.1 (no asset yet); leave a `<!-- demo gif: add at first release -->` HTML comment placeholder is NOT allowed by AC9 - instead delete the line entirely.
- The install block's `# TODO: lock final install method` → replace with the real commands:
  ```bash
  /plugin marketplace add Ryan-M-Frank/volley
  /plugin install volley@volley
  # If Codex tools aren't available yet: /reload-plugins (or restart), then:
  /volley:setup
  ```
- All `/copair-*` / `copair` command references → `/volley:<skill>` and "Volley".

- [ ] **Step 3: Verify no placeholders or stale names remain**

Run:
```bash
cd /c/git/volley
grep -nE '\{[A-Z_]+\}|TODO|TBD|copair|/duo-|DUO' README.md || echo "README clean"
```
Expected: `README clean`.

- [ ] **Step 4: Commit**

```bash
git add README.md && git commit -m "docs: de-placeholdered README for Volley v0.1"
```

---

## Task 13: Final acceptance gate

**Files:** none created; this task verifies the whole repo against the spec's acceptance criteria.

- [ ] **Step 1: Zero-residue gate (AC1) across the entire repo**

```bash
cd /c/git/volley
echo "--- word-boundary duo/copair ---"
grep -rniwE 'duo|copair' . --exclude-dir=.git
echo "--- token patterns ---"
grep -rnE '\.duo|duo_|duo-|COPAIR|DUO' . --exclude-dir=.git
```
Expected: BOTH empty. Any hit must be fixed and re-committed before proceeding.

- [ ] **Step 2: Manifest validation (AC2)**

Run the plugin-validate command confirmed in Task 1 Step 5 (e.g. `claude plugin validate ./`).
Expected: PASS.

- [ ] **Step 3: Full local test suite (AC5, Windows portion)**

```bash
cd /c/git/volley
fail=0; for t in tests/*.sh; do echo "== $t =="; bash "$t" || fail=1; done; echo "FAIL=$fail"
```
Expected: `FAIL=0` (tmux-stream case may SKIP on Windows; CI covers ubuntu/macos).

- [ ] **Step 4: Push and confirm CI matrix is green (AC5, all OS)**

```bash
cd /c/git/volley
git branch -M main
# Create the GitHub repo (personal namespace) and push:
gh repo create Ryan-M-Frank/volley --public --source=. --remote=origin --push
```
Then watch the Actions run: `gh run watch` (or `gh run list`). Expected: all three matrix legs + validate pass.

- [ ] **Step 5: Live install + setup smoke (AC2, AC3) in a throwaway project**

In a fresh empty dir (a real git repo), in Claude Code:
```
/plugin marketplace add Ryan-M-Frank/volley
/plugin install volley@volley
/reload-plugins        # if the codex MCP tool isn't immediately available
/volley:setup
```
Expected: setup detects the bundled `codex` MCP (instructing reload first if needed, not failing opaquely), scaffolds `.volley/`, smoke test returns PONG.

- [ ] **Step 6: Full cycle (AC4) + coexistence (AC6, AC7)**

- Run a `/volley:implement` → `/volley:review-code` cycle on a trivial change in the throwaway project; confirm Codex spawns and the lock flips. (Windows handler.)
- **Coexistence:** in a project that already has its own `.mcp.json` declaring a `codex` server, install Volley and confirm `mcp__codex__codex` is still reachable and the existing `/duo-*` skills still run. Document the observed behavior.

- [ ] **Step 7: Tag v0.1.0**

```bash
cd /c/git/volley
git tag v0.1.0 && git push origin v0.1.0
```

---

## Notes for the executor

- **Work happens in `C:\git\volley`**, a brand-new repo - NOT in RASA_DEMO. The only reads from RASA_DEMO are `git show feature/copair-spawn-codex-refactor:<path>` (scripts/tests) and the README draft. Never modify `~/.claude/skills/duo-*` or `~/.claude/scripts/duo/` - that would break RASA's live workflow (the Silent Guarantee).
- **The sed transforms are the real artifact** for the rename tasks; run them exactly, then trust the grep gate + the ported test suite to catch misses. If a grep gate fails, fix by hand and re-run the gate before committing.
- **macOS/Linux desktop launch can't be validated on the Windows dev box.** Their tasks verify parse-correctness + the missing-terminal error path locally; real GUI launch is proven by CI (tmux path) and marked community-tested otherwise. Do not claim they "work" beyond what was actually run.
- After all tasks: update memory `naming-volley-locked` / `project_worktree_split` if the repo location or install commands changed from what's recorded.

---

# ADDENDUM: Approved enhancements (2026-06-02)

Eight user-approved additions (4 verifications + 4 features). **Execution order:** run Task 14 right after Task 9 (it's another skill); Task 15 right after Task 10 (more tests); fold Task 16 into Task 11 (CI); run Task 17 right after Task 12 (docs); apply the Task 13 modifications at the gate. All new shell files must also pass the Task 16 shellcheck job.

## Task 14: NEW `/volley:doctor` health-check skill

**Files:** Create `C:\git\volley\skills\doctor\SKILL.md`

- [ ] **Step 1: Write `skills/doctor/SKILL.md`**

```markdown
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
   . "${CLAUDE_PLUGIN_ROOT}/scripts/lib.sh"
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

5. **Per-repo lock state.** If `.volley/STATE` exists, report it; otherwise note the repo isn't initialized:
   ```bash
   if [ -f .volley/STATE ]; then
     . "${CLAUDE_PLUGIN_ROOT}/scripts/lib.sh"
     volley_state_describe .volley/STATE   # prints ACTIVE, TASK, age, and PID-liveness
   else
     echo "[WARN] .volley/ not initialized here - run /volley:setup"
   fi
   ```
   (If `volley_state_describe` does not exist in the ported lib, read `.volley/STATE` and print `ACTIVE`/`TASK`/`SINCE`, and check whether the recorded `PID` is alive with `kill -0`.)

6. **Summary.** Print a final `Volley doctor: N passed, M warnings, K failures` line and, for each FAIL/WARN, the one-line remedy.
```

- [ ] **Step 2: Validate** - `grep -niwE 'duo|copair|rasa' skills/doctor/SKILL.md` returns nothing; the only script paths use `${CLAUDE_PLUGIN_ROOT}` (quoted). Run `claude plugin validate ./` (still PASS).
- [ ] **Step 3: Commit** - `git add skills/doctor/SKILL.md && git commit -m "feat: /volley:doctor environment health-check skill"`

## Task 15: Extra verification tests (path-with-spaces, frontmatter, idempotent setup)

**Files:** Create `C:\git\volley\tests\test-extras.sh`

- [ ] **Step 1: Write `tests/test-extras.sh`**

```bash
#!/usr/bin/env bash
# Extra guards: (1) sourcing works from a path containing a space (the real
# ${CLAUDE_PLUGIN_ROOT} lives under "C:\Users\Ryan Frank\..."); (2) every skill
# has valid name+description frontmatter; (3) STATE writes are idempotent and
# never clobber an existing HANDOFF.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0
pass(){ echo "PASS: $1"; PASS=$((PASS+1)); }
fail(){ echo "FAIL: $1"; FAIL=$((FAIL+1)); }

# (1) path-with-spaces: copy lib into "a dir/with space" and source via that path
SPACED="$TMP/a dir/with space"
mkdir -p "$SPACED/scripts"
cp "$ROOT/scripts/lib.sh" "$SPACED/scripts/lib.sh"
if ( . "$SPACED/scripts/lib.sh" && volley_state_write "$TMP/STATE" claude idle 0 ) >/dev/null 2>&1 \
   && grep -q 'ACTIVE=claude' "$TMP/STATE"; then
  pass "lib.sh sources and runs from a path containing spaces"
else
  fail "lib.sh broke when sourced from a spaced path"
fi

# (2) skill frontmatter: each SKILL.md opens with --- and has name: + description:
for d in "$ROOT"/skills/*/; do
  s="$d/SKILL.md"; name=$(basename "$d")
  head -1 "$s" | grep -q '^---$' || { fail "$name: no frontmatter fence"; continue; }
  awk '/^---$/{n++; next} n==1{print} n>=2{exit}' "$s" | grep -q '^name:' \
    && awk '/^---$/{n++; next} n==1{print} n>=2{exit}' "$s" | grep -q '^description:' \
    && pass "$name: frontmatter has name + description" \
    || fail "$name: frontmatter missing name or description"
done

# (3) idempotent STATE write: writing twice yields identical content
. "$ROOT/scripts/lib.sh"
volley_state_write "$TMP/S2" claude idle 0; a=$(cat "$TMP/S2")
volley_state_write "$TMP/S2" claude idle 0; b=$(cat "$TMP/S2")
[ "$a" = "$b" ] && pass "volley_state_write is idempotent" || fail "volley_state_write not idempotent"

echo ""; echo "PASS=$PASS FAIL=$FAIL"; [ "$FAIL" -eq 0 ] && exit 0 || exit 1
```

- [ ] **Step 2: Run it** - `bash tests/test-extras.sh`. Expected `FAIL=0`. (If `volley_state_write` signature differs from `(file actor task pid)`, adjust the calls to match the ported lib - check `scripts/lib.sh`.)
- [ ] **Step 3: Commit** - `git add tests/test-extras.sh && git commit -m "test: path-with-spaces, skill frontmatter, idempotent STATE guards"`

## Task 16: CI additions - ShellCheck + RASA-leak scan (extends Task 11)

**Files:** Modify `C:\git\volley\.github\workflows\ci.yml`

- [ ] **Step 1: Add two jobs to `ci.yml`**

```yaml
  shellcheck:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: Install shellcheck
        run: sudo apt-get update && sudo apt-get install -y shellcheck
      - name: Lint all bash
        run: |
          shellcheck -S warning scripts/*.sh scripts/platforms/*.sh tests/*.sh

  leak-scan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - name: No RASA / secret bleed-through
        run: |
          # Author email is intentional; everything else internal must be absent.
          if grep -rniE 'rasa|RASA_DEMO|/c/git/RASA|C:\\\\git\\\\RASA|api[_-]?key|secret[_-]?key|ghp_[A-Za-z0-9]{20}|AKIA[0-9A-Z]{16}|BEGIN [A-Z ]*PRIVATE KEY' . \
               --exclude-dir=.git | grep -viE 'frank\.ryanm@gmail\.com'; then
            echo "::error::Potential RASA/secret bleed-through found above - must be zero before publish."
            exit 1
          fi
          echo "leak scan clean"
```
(If `shellcheck -S warning` surfaces pre-existing issues in the ported scripts, fix them in the relevant file and re-commit - do not lower the severity to hide them.)

- [ ] **Step 2: Run both gates locally before pushing**
```bash
cd /c/git/volley
command -v shellcheck >/dev/null && shellcheck -S warning scripts/*.sh scripts/platforms/*.sh tests/*.sh || echo "shellcheck not local; CI will run it"
grep -rniE 'rasa|RASA_DEMO|api[_-]?key|secret[_-]?key|ghp_[A-Za-z0-9]{20}|BEGIN [A-Z ]*PRIVATE KEY' . --exclude-dir=.git | grep -viE 'frank\.ryanm@gmail\.com' && echo "REVIEW THESE" || echo "leak scan clean"
```
Expected: `leak scan clean`; shellcheck clean (fix any findings).

- [ ] **Step 3: Commit** - `git add .github/workflows/ci.yml && git commit -m "ci: shellcheck lint + RASA/secret leak-scan gates"`

## Task 17: OSS docs - CONTRIBUTING, SECURITY, templates, quickstart (after Task 12)

**Files:** Create `CONTRIBUTING.md`, `SECURITY.md`, `.github/ISSUE_TEMPLATE/bug_report.md`, `.github/ISSUE_TEMPLATE/feature_request.md`, `.github/PULL_REQUEST_TEMPLATE.md`, `docs/QUICKSTART.md`

- [ ] **Step 1: `CONTRIBUTING.md`** - cover: how the plugin is laid out; how to add/fix a platform handler (implement `spawn_<platform>(prompt_file, title)` in `scripts/platforms/<platform>.sh`, honor the informational-id + `CODEX-STARTED` handshake contract, add a dispatch case); running the test suite (`bash tests/*.sh`); that macOS/Linux desktop handlers are **community-tested** and PRs confirming them on real desktops are especially welcome; the commit/PR conventions; that CI must be green (matrix + shellcheck + leak-scan).

- [ ] **Step 2: `SECURITY.md`** - the trust model: the lock is **cooperative** (a STATE file preventing Claude and Codex from writing concurrently) - it is tamper-*evident-by-convention*, not a security boundary; Codex runs under the sandbox/approval policy passed by the skills (reviews use `read-only` + `never`); the plugin bundles an MCP server that runs the user's local `codex` binary - no remote calls beyond what Codex itself makes; how to report a vulnerability (email). State plainly what Volley does NOT guarantee (it does not sandbox Claude, does not encrypt the lock, does not prevent a determined local user from editing STATE).

- [ ] **Step 3: Issue + PR templates** - `bug_report.md` (OS, Codex version, `/volley:doctor` output, repro), `feature_request.md` (problem/proposal), `PULL_REQUEST_TEMPLATE.md` (what/why, tests run, CI green, platform tested on).

- [ ] **Step 4: `docs/QUICKSTART.md`** - a worked example: install via `/plugin`, `/reload-plugins`, `/volley:setup`, write a HANDOFF, `/volley:review-plan`, `/volley:implement`, `/volley:review-code`, ship. Include the `/volley:doctor` step for troubleshooting.

- [ ] **Step 5: Verify + commit** - `grep -rniwE 'duo|copair|rasa' CONTRIBUTING.md SECURITY.md docs/ .github/ISSUE_TEMPLATE .github/PULL_REQUEST_TEMPLATE.md` returns nothing (except intended). `git add` the docs + `git commit -m "docs: CONTRIBUTING, SECURITY, issue/PR templates, quickstart"`.

## Task 13 modifications (apply at the publish gate)

- [ ] **New AC0 (runs FIRST, before anything else in Task 13): RASA / secret leak gate.**
```bash
cd /c/git/volley
grep -rniE 'rasa|RASA_DEMO|/c/git/RASA|C:\\\\git\\\\RASA|api[_-]?key|secret[_-]?key|ghp_[A-Za-z0-9]{20}|AKIA[0-9A-Z]{16}|BEGIN [A-Z ]*PRIVATE KEY' . --exclude-dir=.git | grep -viE 'frank\.ryanm@gmail\.com'
```
Expected: NO output. Any hit is a publish blocker - investigate and remove before proceeding. This gate is mandatory and runs before the zero-`duo` gate.
- [ ] **Doctor in acceptance:** after `/volley:setup`, run `/volley:doctor` in the throwaway project and confirm an all-green (or only-expected-WARN) report.
- [ ] **Demo capture:** during the live `/volley:implement` → `/volley:review-code` cycle (Task 13 Step 6), record an asciinema/terminal cast, export a GIF, commit it to the repo (e.g. `docs/demo.gif`), and replace the README demo line with it. (This is the one artifact that needs the interactive live session.)
- [ ] **Updated acceptance set:** all original ACs 1-9 PLUS: leak gate zero (AC0), shellcheck green, `test-extras.sh` green, `/volley:doctor` green, CONTRIBUTING/SECURITY/templates/quickstart present, demo committed + linked, and the assistant-extension guide present (Task 18).

## Task 18: Assistant-extension guide (swap Codex for Cursor/Gemini/etc.)

**Premise:** Volley pairs Claude with a *second assistant*. v0.1 ships **OpenAI Codex** as that backend, but the name is deliberately backend-neutral and the coupling is confined to a few seams. This guide documents those seams and the recipe to swap the backend, and proposes the adapter interface as the v0.2 contribution target. It is a **guide only** - no backend abstraction is built in v0.1.

**Files:** Create `C:\git\volley\docs\EXTENDING-ASSISTANTS.md`; add a short pointer in `CONTRIBUTING.md` and a one-line roadmap note in `README.md`.

- [ ] **Step 1: Write `docs/EXTENDING-ASSISTANTS.md`** covering, concretely:

  1. **The three seams where Codex is wired in** (give exact file references):
     - **MCP bridge** - `.mcp.json` registers the `codex` MCP server (`codex` / `["mcp-server"]`). The in-session review skills call `mcp__codex__codex` / `mcp__codex__codex-reply`. *To swap:* register your assistant's MCP server under a server name and update those tool references in `skills/review-plan`, `skills/review-code`, `skills/review-pr`.
     - **Implement spawner** - `scripts/spawn-codex.sh` dispatches to `scripts/platforms/<os>.sh`, each of which launches a visible terminal running `codex exec` with the prompt streamed via stdin. *To swap:* change the launched command to your assistant's non-interactive "run this prompt against the repo" CLI (e.g. `gemini`, `cursor`, `aider --message-file -`). The stdin-streaming + `CODEX-STARTED-*` handshake contract stays the same.
     - **Skill prose/labels** - `skills/setup` (Codex version check, MCP smoke test) and `skills/implement` reference Codex by name. *To swap:* update those references and the smoke-test prompt.

  2. **What a second assistant must provide to qualify:**
     - A **non-interactive execute mode** (run a prompt against the working tree) for `/volley:implement` - streamed via stdin or a file (plans are large; avoid argv limits).
     - Ideally an **MCP server** for the in-session `/volley:review-*` calls. Without MCP, the review path can fall back to the spawn-a-terminal pattern (slower, no structured return).
     - A way to report it started (the handshake file) so the lock can flip safely.

  3. **A worked mini-example** - adding the **Gemini CLI** as the backend: the `.mcp.json` entry (or the spawn command), the two or three skill edits, and how `/volley:doctor` would check for it. Keep it concrete enough to copy.

  4. **North-star (v0.2 roadmap) - the adapter interface:** propose factoring an `assistants/<name>.sh` adapter (mirroring the existing `platforms/<os>.sh` pattern) that exposes a small contract - e.g. `assistant_spawn(prompt_file,title)`, `assistant_mcp_server_name()`, `assistant_version_check()` - selected by a `VOLLEY_ASSISTANT` env var and a `/volley:setup` backend picker. Frame this as the preferred contribution target so PRs converge instead of forking.

- [ ] **Step 2: Cross-link** - add to `CONTRIBUTING.md` a line: "Want Volley to drive a different second assistant (Cursor, Gemini, Aider...)? See `docs/EXTENDING-ASSISTANTS.md`." Add to `README.md` a one-line roadmap note: "v0.1 pairs Claude with OpenAI Codex; the backend is swappable - see the extension guide, and pluggable adapters are on the roadmap."

- [ ] **Step 3: Verify + commit** - `grep -niwE 'duo|copair|rasa' docs/EXTENDING-ASSISTANTS.md` returns nothing. `git add docs/EXTENDING-ASSISTANTS.md CONTRIBUTING.md README.md && git commit -m "docs: guide for swapping the second assistant (Codex -> Cursor/Gemini/etc.)"`

**Execution order:** run Task 18 right after Task 17 (it edits the same CONTRIBUTING.md/README.md). Add "assistant-extension guide present" to the Task 13 acceptance set.
