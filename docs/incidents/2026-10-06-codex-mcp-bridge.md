# Incident: Codex review bridge stopped connecting (fixed in 0.3.0)

**Status:** resolved by [PR #5](https://github.com/Ryan-M-Frank/volley/pull/5) (0.3.0, merged 2026-10-06 22:23 US Central).
**Impact:** `/volley:review-plan`, `/volley:review-pr` and the `/volley:setup` smoke test could not reach Codex.
`/volley:implement` was unaffected (it opens Codex in a terminal tab). Reviews had to be run with `codex exec` by hand.

## Timeline (US Central)

| When | What | Evidence |
|---|---|---|
| 2026-09-21 14:46 | Earliest `plugin:volley:codex (CONNECTION_CLOSED)` found in the maintainer's Claude Code session logs. | Local session transcripts on the maintainer's desktop. |
| 2026-09-24 16:50 | codex-cli 0.156.1 installed (the current version). The same error appears in sessions across several projects afterwards. | `package.json` timestamp of the global npm install; session transcripts. |
| 2026-10-06 evening | Diagnosed: `codex mcp-server` does not exist in 0.156.1. Fix written, reviewed and tested. | `codex --help`; running the bridge command by hand. |
| 2026-10-06 22:23 | PR #5 merged (0.3.0). | GitHub. |

**What is verified and what is not:** the removal of `mcp-server` is verified in the installed 0.156.1. The
earlier errors from 2026-09-21 are consistent with the same cause, but which Codex release first removed the
command, and whether those earlier errors had exactly this cause, is not confirmed.

## Why it broke

Volley 0.2 talked to Codex through an MCP server it registered in its own `.mcp.json`:

```json
{ "mcpServers": { "codex": { "command": "codex", "args": ["mcp-server"] } } }
```

In codex-cli 0.156.1 the `mcp-server` subcommand is gone from `codex --help`, and no feature flag brings it back.
The Codex CLI treats an unknown first word as a **prompt**, so `codex mcp-server` started the interactive terminal
UI instead of a server. With no terminal attached it exited at once with `Error: stdin is not a terminal`, and
Claude Code reported the plugin's server as `CONNECTION_CLOSED`. Nothing in Volley changed; an external command it
depended on disappeared underneath it.

## Why it was not caught

- **No recurring check against a real Codex.** The `/volley:setup` smoke test did call the real bridge, but only
  once, at setup time. CI and the test suite are offline by design, so nothing re-checked the bridge after Codex
  was upgraded.
- **`/volley:diagnose` only checked that the MCP tool was present,** and only told the user to reload plugins when
  it was missing. It could not tell "not loaded yet" from "the server cannot start".
- **The version floor was a minimum only** (`>= 0.129`). It said nothing about newer releases removing commands.
- **Codex can be upgraded independently of Volley,** so the breaking change arrived without any Volley release.

## The fix (0.3.0)

- Reviews and the setup smoke test now go through `scripts/codex-exec.sh`, which runs `codex exec --json`, the
  documented non-interactive mode of the Codex CLI.
  - **Fresh review:** `codex exec --sandbox read-only -C <repo root> --json -o <scratch file> -` with the prompt on
    stdin.
  - **Resumed review:** `codex exec resume <id>`. In 0.156.1 `exec resume` accepts neither `--sandbox` nor `-C`, so
    the script enforces read-only with `-c 'sandbox_mode="read-only"'` and runs from the repo root (Codex also uses
    the current directory to find the saved session). A live check confirmed a resumed session could not write a
    file.
  - **When it resumes:** only if `codex.review.continuity` allows it (`resume-if-safe`, or `session-only` for a
    follow-up round in the same Claude conversation) and the stored repository identity matches. An invalid
    session id or a failed resume falls back to a fresh session, and the script reports that.
- `.mcp.json` is removed. Setup and diagnose check `codex exec` instead of an MCP tool, and diagnose warns if a
  `.mcp.json` in the repository still registers `codex mcp-server`.

## Found along the way

The two-reviewer process on PR #5 (Codex gpt-6-astra, then a Claude Fable review) turned up two more problems:

- **Argument injection through model/effort values.** `volley_validate_token` matched line by line, so a multiline
  model or effort value in `.volley/config.json` passed validation, and its extra lines became extra Codex
  arguments (for example `--config sandbox_mode=...` or `--dangerously-bypass-approvals-and-sandbox`).
  - **Released 0.2:** affected the `/volley:implement` spawner, which builds its Codex command line from those
    values. 0.2 reviews were not affected, because they passed model and effort to the MCP tool as structured
    parameters.
  - **This PR:** the new exec-based review path was exposed during development, before merge.
  - **Fixed:** validation now checks the whole value and rejects a leading dash, and the review script passes model
    and effort as separate array elements.
- **macOS bash 3.2.** A revision during PR #5 (commit `a6a8560`) switched the script to an argument array. bash 3.2
  treats an empty array as unbound under `set -u`, so on macOS the script failed whenever **both** model and
  effort were `inherit`. CI's macOS job caught it before merge.

## Follow-ups

- An opt-in live check that runs the real `codex exec` (PONG plus one resume) when Codex is installed and logged in,
  so a removed or renamed command shows up the next time the check runs. Tracked with the review nits in
  [issue #6](https://github.com/Ryan-M-Frank/volley/issues/6).
- After upgrading Codex, run `/volley:setup`'s smoke test (or one review) before relying on reviews.
  `/volley:diagnose` only checks that `codex exec` runs, not authentication or resume.
