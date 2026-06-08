# Volley Plugin Extraction - Design

**Date:** 2026-06-01
**Status:** Revised after Codex reviews #1 + #2 (all concerns folded in); pending human review
**Owner:** Ryan Frank
**Supersedes naming:** "copair" / "DUO" -> **Volley** (see memory `naming-volley-locked`)

## Summary

Extract the in-house Claude+Codex orchestration workflow (working name "DUO") out of the
RASA repo into a standalone, public, Apache-2.0 **Claude Code plugin** named **Volley**,
distributed via a plugin marketplace. The extraction is a clean *copy + rename* of the
existing logic, plus **one intentional functional addition**: cross-platform (macOS/Linux)
terminal-spawn handlers so the public release is not Windows-only. The RASA machine keeps
running its current `duo-*` install untouched.

## Goals

1. A standalone `volley` repo that is a valid Claude Code **plugin + marketplace**, installable via `/plugin marketplace add Ryan-M-Frank/volley` then `/plugin install volley@volley`.
2. Full `duo -> volley` rename across **every** surface (skill folders, skill frontmatter `name:`, headings, descriptions, prose, user-facing messages, comments, scripts, runtime dir, function prefixes, MCP label, **and the test suite**) with zero `duo` residue.
3. Codex MCP server **bundled** in the plugin so it auto-registers on install, with documented reload/restart semantics.
4. **Cross-platform spawn**: Windows (exists) + macOS + Linux handlers, exercised by a CI matrix.
5. README de-placeholdered, LICENSE (Apache-2.0), CI runs the bash test suite + `claude plugin validate`.

## Non-Goals (explicitly out of scope)

- **Phase B / local migration.** Reinstalling the RASA machine to consume Volley (global install becomes `volley-*`, retire the `duo` working copies) is deferred. We do NOT churn the `.duo/`, `scripts/duo/`, `~/.claude/skills/duo-*/` paths while still using the tool to build the tool.
- **DUO workflow semantics are preserved** except for three deliberate deltas: (a) plugin packaging, (b) bundled-MCP activation behavior, and (c) the new macOS/Linux spawn launchers (Goal 4). Everything else is identical logic under new names.
- No npm publication. Volley ships as a plugin; npm is not a distribution channel (see `naming-volley-locked`).

## The Silent Guarantee

RASA's workflow runs off the **global install** (`~/.claude/skills/duo-*` + `~/.claude/scripts/duo/`), not the repo copy. This extraction:
- Creates a **new repo in its own directory** (`C:\git\volley`), not a worktree of RASA_DEMO.
- Does **not** modify `~/.claude/skills/duo-*` or `~/.claude/scripts/duo/`.
- Even *installing* Volley to dogfood it is non-destructive: `/volley:*` skills coexist alongside the existing `/duo-*` skills; RASA keeps using `/duo-*`.

Result: nothing RASA depends on changes. (Coexistence is an explicit acceptance test, incl. the MCP-name case below.)

## Source of Truth (what we copy from)

| Asset | Copy from | Why |
|---|---|---|
| 7 skills | `~/.claude/skills/duo-*/` (global) | Skills only exist globally; this is their only home |
| Scripts | `RASA_DEMO/scripts/duo/` (repo) | Newest copy - has the #108 spawn-codex refactor; global copy is stale |
| Tests | `RASA_DEMO/tests/duo/` (repo) | The bash suite; must be renamed too (see transforms) |
| MCP config | `RASA_DEMO-copair/.mcp.json` | `{"codex": {"command": "codex", "args": ["mcp-server"]}}` |
| README draft | `.duo/README-DRAFT.md` | Already Volley-aware; needs de-placeholdering |

## Target Repo Structure

```
volley/                              # own repo + dir (C:\git\volley)
├── .claude-plugin/
│   ├── plugin.json                  # manifest (name: volley, version, Apache-2.0, author)
│   └── marketplace.json             # lists the volley plugin with source "./"
├── skills/                          # plugin namespacing gives /volley:<name>
│   ├── setup/SKILL.md               # /volley:setup   (frontmatter name: setup)
│   ├── status/SKILL.md              # /volley:status
│   ├── unlock/SKILL.md              # /volley:unlock
│   ├── implement/SKILL.md           # /volley:implement
│   ├── review-plan/SKILL.md         # /volley:review-plan
│   ├── review-code/SKILL.md         # /volley:review-code
│   └── review-pr/SKILL.md           # /volley:review-pr
├── scripts/
│   ├── lib.sh                       # was duo-lib.sh; functions volley_*
│   ├── spawn-codex.sh               # OS dispatch -> platforms/<os>.sh
│   └── platforms/
│       ├── windows.sh               # exists (ported)
│       ├── macos.sh                 # NEW (iTerm2 / Terminal.app)
│       └── linux.sh                 # NEW (gnome-terminal / kitty / tmux fallback)
│   └── templates/
│       ├── HANDOFF.md
│       └── gitignore                # was duo-gitignore
├── .mcp.json                        # bundled Codex server -> auto-registers on install
├── tests/                           # renamed suite (see transform table)
├── .github/workflows/ci.yml         # MATRIX: windows + macos + ubuntu; runs tests + plugin validate
├── README.md                        # from draft, de-placeholdered
└── LICENSE                          # Apache-2.0 full text
```

## Rename Transform Table

Applies to ALL copied files (skills, scripts, tests, templates). The grep gate (AC1) is the backstop.

| # | Surface | From | To | Notes |
|---|---|---|---|---|
| 1 | Skill folders | `duo-setup/` ... (7) | `setup/` ... | Drop prefix - plugin namespace supplies `volley:` |
| 2 | Skill frontmatter `name:` | `name: duo-setup` | `name: setup` | **(Codex catch)** inside each SKILL.md |
| 3 | Headings / titles | `# /duo-setup` | `# /volley:setup` | **(Codex catch)** |
| 4 | Command refs in prose | `/duo-setup` | `/volley:setup` | Namespaced colon form |
| 5 | User-facing messages & comments | `Run /duo-setup first` etc. | `Run /volley:setup first` | **(Codex catch)** error strings, echoes, comments |
| 6 | Script references | `$HOME/.claude/scripts/duo/foo.sh` | `${CLAUDE_PLUGIN_ROOT}/scripts/foo.sh` | **Critical**; must be **quoted**: `. "${CLAUDE_PLUGIN_ROOT}/scripts/lib.sh"` |
| 7 | Runtime dir | `.duo/` | `.volley/` | Per-project working dir setup scaffolds |
| 8 | Lib functions | `duo_*` (18, incl. `duo_next_step`, `duo_state_*`) | `volley_*` | |
| 9 | Lib filename | `duo-lib.sh` | `lib.sh` | |
| 10 | Spawn/window label | `duo:codex` | `volley:codex` | Cosmetic terminal title + test default |
| 11 | Template gitignore | `duo-gitignore` | `gitignore` | |
| 12 | **Test suite** | `tests/duo/`, and inside: `scripts/duo`, `duo-lib.sh`, `duo_*`, `.duo`, `duo:codex` | `tests/`, `scripts/`, `lib.sh`, `volley_*`, `.volley`, `volley:codex` | **(Codex catch)** else CI fails |

MCP **server name** stays `codex` (what review skills call via MCP); only the cosmetic spawn label changes.

## Cross-Platform Spawn (the one new-code piece)

`spawn-codex.sh` already dispatches by OS; today only `platforms/windows.sh` exists. Add:
- **`macos.sh`** - open a new terminal running Codex via iTerm2 if present, else Terminal.app (AppleScript / `osascript`).
- **`linux.sh`** - try `gnome-terminal`, then `kitty`, then a `tmux` split as the headless/SSH fallback; clean error if none found.
- Each handler honors the same contract as `windows.sh`: receive prompt file + window label, launch Codex, and return an **informational launch identifier only**. Liveness is NOT inferred from that id (the Windows `wt` PID is already informational) - it comes from the existing `.volley/CODEX-STARTED-*` handshake file plus STATE/log checks. Handlers must preserve that handshake contract.
- **Headless/CI contract:** `VOLLEY_PLATFORM=tmux` is an explicit, tested code path (the realistic CI path, since runners lack desktop terminals). Desktop GUI launch (gnome-terminal/kitty/iTerm2/Terminal.app) is exercised manually and marked "community-tested."

**Testing reality:** the dev box is Windows, so macOS/Linux *desktop* handlers can't be fully validated locally. Mitigation: the CI matrix (windows-latest + macos-latest + ubuntu-latest) runs the test suite per-OS and the `tmux` path with a stub Codex; GUI-terminal launch paths that CI can't drive are documented "community-tested."

## Plugin Specifics

- **`plugin.json`**: `name: "volley"`, `version: "0.1.0"` (semver; bump to release updates), `description`, `author`, `license: "Apache-2.0"`, `homepage`/`repository`.
- **Skill namespacing**: folder name = skill name; invoked `/volley:<skill>`. Frontmatter `name:` matches the de-prefixed folder.
- **`${CLAUDE_PLUGIN_ROOT}`**: resolves to the cached install dir. Used (quoted) in every script reference. Absolute `$HOME` paths forbidden.
- **Bundled MCP** (`.mcp.json` at plugin root): `{"mcpServers": {"codex": {"command": "codex", "args": ["mcp-server"]}}}`. **Reload/restart semantics (Codex catch):** a freshly installed plugin's MCP server may not be live in the current session until plugins reload or Claude Code restarts. `/volley:setup` MUST detect whether the `codex` MCP tool is reachable; if not, instruct the user to run **`/reload-plugins`** (confirm the exact command string against the installed Claude Code version at implementation time) or restart, then re-run setup - rather than failing opaquely. Setup cannot force-load the MCP into the current session; it can only detect and instruct. Setup otherwise shrinks to: verify Codex CLI installed -> confirm/await MCP reachable -> scaffold `.volley/` -> smoke test.
- **Marketplace**: single repo is both marketplace and plugin. `marketplace.json` lists volley with `"source": "./"`.

## Install / Update UX

```bash
/plugin marketplace add Ryan-M-Frank/volley
/plugin install volley@volley
# if MCP not yet reachable: /reload-plugins  (or restart Claude Code), then:
/volley:setup
```
Updates: bump `version` in `plugin.json`; users `/plugin marketplace update volley` + reinstall. Semver.

## Build Approach

One-time assembly script (auditable): copy the three sources (skills, scripts, tests) into the
target layout, apply the full transform table via systematic find-replace, then hand-add the new
`platforms/macos.sh` + `platforms/linux.sh`, `plugin.json`, `marketplace.json`, `.mcp.json`,
`README.md`, `LICENSE`, `ci.yml`. Verify locally on Windows by installing into a throwaway project
and running `/volley:setup` -> a full `/volley:implement` -> `/volley:review-code` cycle; verify
macOS/Linux via the CI matrix.

## Risks & Mitigations

| Risk | Severity | Mitigation |
|---|---|---|
| `${CLAUDE_PLUGIN_ROOT}` not resolving in SKILL.md bash | retired | Voice plugin does exactly this in production |
| Rename misses a `duo` token (frontmatter/tests/messages) | MEDIUM | Expanded transform table + `grep -riw duo` zero-gate (AC1) |
| Bundled `codex` MCP collides with a project's own `.mcp.json` `codex` | MEDIUM | Dedicated coexistence test (AC8); document scope behavior |
| Bundled MCP not live until reload/restart | MEDIUM | `/volley:setup` detects + instructs `/reload-plugins` (no opaque fail) |
| macOS/Linux handlers can't be tested on the Windows dev box | MEDIUM | CI matrix per-OS + stub Codex; mark un-CI-able paths "community-tested" |
| Stale global `scripts/duo/` drift vs repo (#108 not synced) | LOW | Copy scripts from the repo (newest), not global |

## Acceptance Criteria

1. `grep -riw "duo" volley/` (word-boundary, case-insensitive) returns **zero** matches; also explicitly check `.duo`, `duo_`, `duo-`, and `name: duo` patterns. No residue in frontmatter, headings, messages, comments, or tests.
2. `/plugin marketplace add` + `/plugin install volley@volley` succeeds in a clean project; `claude plugin validate ./` passes.
3. `/volley:setup` ensures the bundled Codex MCP is reachable - detecting its absence and instructing `/reload-plugins` or restart rather than failing opaquely - then scaffolds `.volley/` and the smoke test passes.
4. A full `/volley:implement` -> `/volley:review-code` cycle works end-to-end on Windows.
5. `tests/` pass in the CI matrix on **windows-latest, macos-latest, and ubuntu-latest**; `claude plugin validate ./` runs in CI.
6. RASA's existing `/duo-*` workflow still works unchanged (coexistence verified).
7. **Coexistence test:** in a project that already declares a `codex` server in its own `.mcp.json`, Volley installs and its `codex` MCP tool remains reachable/stable (no name-collision breakage).
8. `macos.sh` and `linux.sh` exist and implement the `windows.sh` launch contract (return informational launch id; preserve the `CODEX-STARTED-*` handshake). The `VOLLEY_PLATFORM=tmux` path passes CI smoke tests on macos + ubuntu; desktop-GUI launch paths are documented "community-tested."
9. README has no `{PLACEHOLDER}` tokens; LICENSE is full Apache-2.0 text.
