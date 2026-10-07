# Incident: Codex review bridge stopped connecting (fixed in 0.3.0)

**Status:** resolved by [PR #5](https://github.com/Ryan-M-Frank/volley/pull/5) (0.3.0, merged 2026-10-07).
**Impact:** `/volley:review-plan`, `/volley:review-pr` and the `/volley:setup` smoke test could not reach Codex.
`/volley:implement` was unaffected (it opens Codex in a terminal tab). Reviews fell back to running `codex exec`
by hand.

## Timeline

| When (UTC) | What |
|---|---|
| 2026-09-21 19:46 | First recorded `plugin:volley:codex (CONNECTION_CLOSED)` in a Claude Code session. |
| 2026-09-24 | codex-cli 0.156.1 installed (current version). The failure is present in every session from here on. |
| 2026-10-06 | Diagnosed: `codex mcp-server` no longer exists. Fix written, reviewed and tested. |
| 2026-10-07 03:23 | PR #5 merged (0.3.0). |

The exact Codex release that removed the command is not confirmed: the failure predates 0.156.1, so an earlier
release around 2026-09-21 dropped it.

## Why it broke

Volley 0.2 talked to Codex through an MCP server it registered in its own `.mcp.json`:

```json
{ "mcpServers": { "codex": { "command": "codex", "args": ["mcp-server"] } } }
```

Codex CLI removed the `mcp-server` subcommand. It is gone from `codex --help`, and there is no feature flag that
brings it back. The Codex CLI treats an unknown first word as a **prompt**, so `codex mcp-server` started the
interactive terminal UI instead of a server. With no terminal attached it exited at once with
`Error: stdin is not a terminal`, and Claude Code reported the plugin's server as `CONNECTION_CLOSED`. Nothing in
Volley changed; an external command it depended on disappeared underneath it.

## Why it was not caught

- **No check against a real Codex.** CI and the test suite are offline by design, so nothing exercised the bridge
  against an installed Codex.
- **`/volley:diagnose` only checked that the MCP tool was present,** and only told the user to reload plugins when
  it was missing. It could not tell "not loaded yet" from "the server cannot start".
- **The version floor was a minimum only** (`>= 0.129`). It said nothing about newer releases removing commands.
- **Codex updates itself independently of Volley,** so the breaking change arrived without any Volley release.

## The fix (0.3.0)

- Reviews and the setup smoke test now go through `scripts/codex-exec.sh`, which runs `codex exec --json`
  read-only and keeps continuity with `codex exec resume <id>`. `codex exec` is Codex's documented
  non-interactive interface, so it is a more stable thing to depend on than the MCP server was.
- `.mcp.json` is removed. Setup and diagnose check `codex exec` instead of an MCP tool, and diagnose warns if an
  old `mcp-server` entry is still registered.

## Found along the way

The two-reviewer process on PR #5 (Codex gpt-6-astra, then a Claude Fable review) turned up issues beyond the
original break:

- **A sandbox bypass that had existed since 0.2:** `volley_validate_token` matched line by line, so a multiline
  model or effort value in `.volley/config.json` could add arbitrary Codex arguments, including
  `--config sandbox_mode=...` or `--dangerously-bypass-approvals-and-sandbox`. It affected the implement spawner
  too. It is now a whole-string check that also rejects a leading dash.
- **macOS bash 3.2** treats an empty array as unbound under `set -u`. CI's macOS job caught that the first version
  of the new script failed whenever the model was `inherit`.

## Follow-ups

- Opt-in live check: a test that runs the real `codex exec` (PONG plus one resume) when Codex is installed and
  logged in, so a removed command is caught the day it happens. Tracked with the review nits in
  [issue #6](https://github.com/Ryan-M-Frank/volley/issues/6).
- When Codex updates, run `/volley:diagnose` before relying on reviews.
