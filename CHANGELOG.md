# Changelog

## 0.3.0 - 2026-10-06

**Why:** Codex CLI removed `codex mcp-server`, so Volley's bundled MCP bridge stopped connecting and reviews could
not reach Codex. Full write-up: [docs/incidents/2026-10-06-codex-mcp-bridge.md](docs/incidents/2026-10-06-codex-mcp-bridge.md).

- Reviews (`/volley:review-plan`, `/volley:review-pr`) and the `/volley:setup` smoke test run through
  `scripts/codex-exec.sh` (`codex exec --json`, read-only, resumable with `codex exec resume`).
- Removed `.mcp.json`. Codex floor is now 0.156.
- Security: model/effort validation now checks the whole value and rejects a leading dash. In 0.2 a multiline
  value could inject Codex arguments, including a sandbox override, into the `/volley:implement` command line.
- Review continuity follows `codex.review.continuity` (`resume-if-safe`, `session-only`, `rehydrate`).
- `.gitattributes` keeps shell scripts LF on Windows checkouts.

## 0.2.0

- Codex model selection and project continuity (#3, #4).
