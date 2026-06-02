# Extending Volley: swapping the second assistant

Volley pairs Claude with a second assistant that holds the implementation lock while Claude reviews. v0.1 ships with OpenAI Codex as that second assistant. The name "Volley" is deliberately backend-neutral, and the coupling to Codex is confined to three seams documented below. This is a guide for swapping Codex for another assistant - it documents the seams precisely so you can do the swap by hand. A built-in abstraction (pluggable adapters) is on the roadmap; see the North-star section at the bottom.

---

## Seam 1 - The MCP bridge

**Files involved:** `.mcp.json` (plugin root), `skills/review-plan/SKILL.md`, `skills/review-code/SKILL.md`, `skills/review-pr/SKILL.md`

The plugin's `.mcp.json` registers the Codex MCP server so Claude can call it in-session:

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

The three review skills call exactly two MCP tools from this server:

- `mcp__codex__codex` - start a new Codex session (used in `review-plan` and `review-pr`)
- `mcp__codex__codex-reply` - continue an existing session with a follow-up

`skills/review-code/SKILL.md` does not call Codex via MCP at all - it is a Claude-only inline review of the diff.

**To swap:** If your replacement assistant exposes an MCP server, register it in `.mcp.json` under a new key (e.g. `"gemini"`) and update the two tool references in `skills/review-plan/SKILL.md` and `skills/review-pr/SKILL.md` from `mcp__codex__codex` / `mcp__codex__codex-reply` to the equivalent tools your server exposes. If your assistant has no MCP server, see the fallback note under "What a second assistant must provide" below.

---

## Seam 2 - The implement spawner

**Files involved:** `scripts/spawn-codex.sh`, `scripts/platforms/windows.sh`, `scripts/platforms/macos.sh`, `scripts/platforms/linux.sh`, `scripts/platforms/tmux.sh`

`scripts/spawn-codex.sh` is the cross-platform dispatcher. It detects the OS (or reads `VOLLEY_PLATFORM` env override), sources the matching handler from `scripts/platforms/<os>.sh`, and calls `spawn_<platform>(prompt_file, title)`.

Each platform handler opens a visible terminal and streams the prompt file to `codex exec` via stdin - not argv. The stdin approach is intentional: plan files can exceed the ~32K CreateProcess argv limit on Windows, and stdin sidesteps that limit on every platform. `codex exec` reads from stdin when no positional prompt is given.

The Windows handler (`scripts/platforms/windows.sh`) builds:

```bash
Get-Content -Raw '<prompt_win_path>' | codex exec
```

and opens it in a new Windows Terminal tab.

The authoritative liveness signal is the `.volley/CODEX-STARTED-<NONCE>` handshake file. Codex's prompt instructs it to create that file as its very first action; `skills/implement/SKILL.md` polls for it before flipping the STATE lock to `ACTIVE=codex`.

**To swap:** In each platform handler, change the launched command from `codex exec` to your assistant's non-interactive "run this prompt against the working tree" CLI. Keep two things intact:

1. **Stdin streaming.** Stream the prompt via stdin (or a temp file passed by path) rather than inline argv. Example substitutions:
   - Gemini CLI: `cat '$prompt_file' | gemini`
   - Aider: `aider --message-file '$prompt_win_path'`
   - Cursor CLI (headless): `cursor --execute-file '$prompt_win_path'`

2. **The handshake.** The prompt you build (in `skills/implement/SKILL.md` step 5) instructs the assistant to create `.volley/CODEX-STARTED-<NONCE>` as its first action. That instruction travels in the prompt text itself - the spawner does not need to change for the handshake to work. Just ensure your assistant's execute mode will follow prompt instructions that include file writes.

---

## Seam 3 - Skill prose and labels

**Files involved:** `skills/setup/SKILL.md`, `skills/implement/SKILL.md`, `skills/doctor/SKILL.md`

These skills reference Codex by name in several places:

- `skills/setup/SKILL.md`: version check (`codex --version`, minimum >= 0.129), MCP smoke test (invokes `mcp__codex__codex` with `prompt: "Reply with the single word: PONG"`), install remedy (`npm install -g @openai/codex`).
- `skills/implement/SKILL.md`: the spawner call (`bash scripts/spawn-codex.sh`), the prompt it builds for Codex, and the tab title `"volley:codex"`.
- `skills/doctor/SKILL.md`: checks `codex --version` and the `mcp__codex__codex` MCP tool.

**To swap:** Update the version check command and minimum version, the MCP smoke test tool name, the install remedy, and any `"Codex"` labels in the user-facing output. The spawner call (`spawn-codex.sh`) can be renamed or left as-is - the filename is internal.

---

## What a second assistant must provide

To slot in as Volley's second assistant, a tool needs:

1. **A non-interactive execute mode.** The assistant must accept a prompt via stdin or a file and run it against the working tree without waiting for interactive input. This is what the spawner calls. Examples: `codex exec`, `gemini`, `aider --message-file -`.

2. **Ideally an MCP server.** The review skills (`/volley:review-plan`, `/volley:review-pr`) call the assistant in-session via MCP for fast, structured responses. Without MCP, both review paths can fall back to the spawn-a-terminal pattern used by `/volley:implement` - but that is slower and returns no structured data back to Claude in the same session.

3. **Ability to write a handshake file.** The assistant's prompt instructs it to create `.volley/CODEX-STARTED-<NONCE>` as its first action. Any assistant that can follow prompt instructions and write files satisfies this. If the assistant's execute mode is truly read-only (no file writes allowed), the handshake cannot work and the STATE lock will never flip.

---

## Worked example: adding the Gemini CLI

This is a concrete walkthrough. Gemini CLI (the `gemini` command from `@google/gemini-cli`) supports `gemini` reading from stdin.

### Step 1 - Register the MCP server (if Gemini CLI exposes one)

If a future Gemini CLI version ships an MCP server, add it to `.mcp.json`:

```json
{
  "mcpServers": {
    "gemini": {
      "command": "gemini",
      "args": ["mcp-server"]
    }
  }
}
```

If no MCP server is available yet, skip this and accept that review skills will use the spawn-terminal fallback.

### Step 2 - Update each platform handler

In `scripts/platforms/windows.sh`, change the `ps_cmd` line from:

```bash
local ps_cmd="Get-Content -Raw '${escaped}' | codex exec"
```

to:

```bash
local ps_cmd="Get-Content -Raw '${escaped}' | gemini"
```

Apply the equivalent one-line change in `scripts/platforms/macos.sh` and `scripts/platforms/linux.sh` (each has a `cat '$prompt_file' | codex exec` line).

### Step 3 - Update skill prose

In `skills/setup/SKILL.md`, change:

```
Run: `codex --version` — must succeed and print a version >= 0.129.
```

to:

```
Run: `gemini --version` — must succeed.
```

Update the install remedy from `npm install -g @openai/codex` to `npm install -g @google/gemini-cli`.

In `skills/doctor/SKILL.md`, change the two `codex --version` and `mcp__codex__codex` references to `gemini --version` and `mcp__gemini__gemini` (or omit the MCP check if no MCP server is registered).

In `skills/implement/SKILL.md`, update the tab title from `"volley:codex"` to `"volley:gemini"` (cosmetic only).

### Step 4 - Verify with /volley:doctor

After making those changes, `/volley:doctor` will check:

- `gemini --version` (step 1) - PASS if the CLI is installed
- `mcp__gemini__gemini` tool available (step 2) - PASS or WARN depending on whether you registered an MCP server
- Platform terminal binary present (step 3) - unchanged
- Plugin assets intact (step 4) - unchanged; `spawn-codex.sh` filename does not affect this check

---

## North-star: the v0.2 adapter interface

The manual steps above work but create forked copies of each platform handler. The preferred contribution target for v0.2 is a thin adapter layer that mirrors the existing `scripts/platforms/<os>.sh` pattern.

The proposed shape:

```
scripts/
  assistants/
    codex.sh      # default
    gemini.sh
    aider.sh
```

Each adapter exposes three functions:

```bash
# Open a visible terminal and stream prompt_file to the assistant.
# Returns 0 on successful launch, non-zero on failure.
assistant_spawn(prompt_file, title)

# Echo the MCP server name this assistant registers, e.g. "codex" or "gemini".
# Echo empty string if no MCP server.
assistant_mcp_server_name()

# Run the version check and print "[PASS] ..." or "[FAIL] ..." to stdout.
# Used by /volley:doctor and /volley:setup.
assistant_version_check()
```

The active adapter is selected by a `VOLLEY_ASSISTANT` env var (default: `codex`). `/volley:setup` gains a backend picker step that sets `VOLLEY_ASSISTANT` in a per-repo `.volley/CONFIG` file.

`scripts/spawn-codex.sh` becomes `scripts/spawn-assistant.sh`, sources `scripts/assistants/${VOLLEY_ASSISTANT}.sh`, and calls `assistant_spawn`. The review and setup skills read `assistant_mcp_server_name()` instead of hardcoding `mcp__codex__codex`.

**If you want to contribute a new assistant backend, target this interface.** A PR that adds `scripts/assistants/gemini.sh` implementing those three functions, plus tests in `tests/test-assistants.sh`, lands cleanly without touching the platform handlers or skill prose. PRs that patch individual platform files for a new assistant are harder to maintain and will be asked to rebase onto the adapter interface once it lands.
