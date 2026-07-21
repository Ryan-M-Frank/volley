<div align="center">

# 🎾 Volley

**Two AI coding assistants. One repository. Zero deadlocks.**

[![CI](https://img.shields.io/github/actions/workflow/status/Ryan-M-Frank/volley/ci.yml?branch=main)](https://github.com/Ryan-M-Frank/volley/actions)
[![License: Apache-2.0](https://img.shields.io/badge/license-Apache--2.0-blue.svg)](LICENSE)
[![Claude Code](https://img.shields.io/badge/claude--code-skills-orange)](https://docs.claude.com/claude-code)
[![Codex CLI](https://img.shields.io/badge/codex--cli-MCP-black)](https://github.com/openai/codex)

</div>

Volley is a small bundle of [Claude Code](https://docs.claude.com/claude-code) skills that lets [OpenAI Codex CLI](https://github.com/openai/codex) work alongside Claude in the same repository — planning, implementing, and reviewing each other's work — without either one trampling files the other is editing.

You stay in Claude. Codex shows up when you need it, leaves when it's done, and the two never write to the repo at the same time.

---

## Why

If you've ever:

- Wanted a **second opinion** on a plan before you commit to it
- Wanted Claude to **review a PR diff that Claude itself wrote**
- Watched Claude burn through 200K tokens on an implementation you could have offloaded to a cheaper model
- Wished you had **`git rebase --interactive` for AI sessions**

...you've hit the limits of single-assistant flows. Volley adds a second assistant with a hard lock so they collaborate instead of collide.

## The flow

```
  Plan / PR review — fast, returns in seconds (over MCP)

    You + Claude  ──/volley:review-plan──▶  Codex reads the plan
    You + Claude  ◀──────── verdict ───────  and returns a critique
                                             (→ .volley/PLAN-REVIEW.md)

  Implementation — long-running, in a visible terminal

    You + Claude  ──/volley:implement───▶  Codex writes the code in
    (hands off, waits on the lock)          its own terminal tab and
    You + Claude  ◀──── STATE released ───  logs progress as it goes
    You + Claude  ──/volley:review-code──▶  Claude reviews the diff
```

A `.volley/STATE` file records which assistant is currently authoritative (`ACTIVE=claude` or `ACTIVE=codex`), a PID, and a timestamp. Every skill refuses to act unless the lock matches it. No race, no clobbered edits, no "wait, who wrote this?"

## Quick start

```bash
# 1. Install the plugin
/plugin marketplace add Ryan-M-Frank/volley
/plugin install volley@volley
# If Codex tools aren't available yet: /reload-plugins (or restart), then:
/volley:setup

# 2. In a repo where you want to use it
cd my-project
claude  # start Claude Code

# 3. Inside Claude Code
/volley:setup           # one-time: confirms the bundled Codex MCP, scaffolds .volley/
/volley:status          # sanity-check the install
```

Once installed, the skills below are available in any repo.

## Skills

| Skill | What it does | Calls Codex via |
|---|---|---|
| **`/volley:setup`** | One-time: verifies Codex, confirms the bundled MCP is reachable, scaffolds `.volley/` | (smoke test) |
| **`/volley:status`** | Inspect the lock state, lock age, stale-PID detection | (local only) |
| **`/volley:unlock`** | Force-clear a stuck STATE lock (escape hatch) | (local only) |
| **`/volley:diagnose`** | Health-check: Codex CLI, MCP reachability, platform terminal, and lock state | (local only) |
| **`/volley:review-plan`** | Hand a plan document to Codex for review; output to `.volley/PLAN-REVIEW.md` | **MCP** (fast) |
| **`/volley:review-pr <num>`** | Hand a GitHub PR diff to Codex for review; output to `.volley/PR-REVIEW-<num>.md` | **MCP** (fast) |
| **`/volley:implement`** | Hand a plan to Codex; Codex runs in a visible terminal tab while Claude waits | **Terminal spawn** (long-running) |
| **`/volley:review-code`** | Claude reviews Codex's diff against the plan; output to `.volley/CODE-REVIEW.md` | (local; no Codex call) |

Two transports for two latency profiles. Short ops (plan review, PR review) go through MCP and return in seconds. Long ops (implementation) spawn a visible Codex terminal so you can watch progress without blocking Claude's session.

## Requirements

- **[Claude Code](https://docs.claude.com/claude-code)** — the host environment
- **[Codex CLI](https://github.com/openai/codex)** >= 0.129, authenticated (`codex login`)
- **Bash** (Git Bash on Windows is fine)
- For `/volley:implement` only:
  - **macOS:** iTerm2 or Terminal.app
  - **Linux:** gnome-terminal or kitty (desktop), or tmux (headless / SSH)
  - **Windows:** Windows Terminal (`wt`) + Git Bash (`cygpath`)

## Platform support

| Skill | macOS | Linux | Windows |
|---|---|---|---|
| `/volley:setup` | ✅ | ✅ | ✅ |
| `/volley:status` | ✅ | ✅ | ✅ |
| `/volley:unlock` | ✅ | ✅ | ✅ |
| `/volley:diagnose` | ✅ | ✅ | ✅ |
| `/volley:review-plan` | ✅ | ✅ | ✅ |
| `/volley:review-pr` | ✅ | ✅ | ✅ |
| `/volley:review-code` | ✅ | ✅ | ✅ |
| `/volley:implement` | ✅ (iTerm2 / Terminal.app) | ✅ (gnome-terminal / kitty / tmux) | ✅ (Windows Terminal) |

## How the lock works

```
.volley/
├── STATE                # ACTIVE=<actor>  TASK=<short-label>  SINCE=<iso8601>  PID=<int>
├── HANDOFF.md           # User-owned. Both AIs read; neither writes.
├── CHECKPOINT.md        # Volley-managed cross-agent state (updated inside markers only)
├── config.json          # Shared, committed: models, reasoning, context manifest
├── local.json           # Machine-local, gitignored: model overrides + exact thread/session IDs
├── PLAN-REVIEW.md       # Codex's plan review (written by /volley:review-plan)
├── CODE-REVIEW.md       # Claude's review of Codex's code (written by /volley:review-code)
├── PR-REVIEW-<num>.md   # Codex's PR review (written by /volley:review-pr)
└── IMPLEMENTATION-LOG.md # Codex's running log during /volley:implement
```

`STATE` is atomic-written and PID-tracked. Every skill calls `volley_state_assert_active` before doing anything destructive — if the lock says it's not your turn, the skill exits with a clear message pointing you at `/volley:status` and `/volley:unlock`.

Stale-lock detection: if the lock is older than 30 minutes AND the named PID is dead, `/volley:status` flags it as stale and offers to clear via `/volley:unlock` (with confirmation).

## Configuration

`.volley/` is **per-repo** (not global). Each repo gets its own STATE, its own HANDOFF.md, its own review artifacts. This is intentional — concurrent work across repos doesn't share a lock.

Add this to your repo's `.gitignore` (or use the included `.volley/.gitignore`):

```gitignore
.volley/STATE
.volley/*REVIEW*.md
.volley/IMPLEMENTATION-LOG.md
.volley/CODEX-STARTED-*
.volley/local.json        # exact thread/session IDs + machine-local model overrides
```

Commit `.volley/HANDOFF.md`, `.volley/config.json`, and `.volley/CHECKPOINT.md` so both AIs in a fresh clone start with the same context, model policy, and last-known state. **Never commit `.volley/local.json`** - its thread/session IDs are per-user/per-machine and could resume the wrong project elsewhere.

## Model selection & continuity

Volley lets you pick which Codex model answers, separately for reviews and implementation, and keeps Codex feeling like a continuing collaborator on *this* project.

- **Model choice** (`.volley/config.json`): set `codex.review.model` / `codex.implementation.model` to a concrete model id or `"inherit"` (use Codex's own default). `reasoningEffort` is separately configurable. Machine-local overrides go in `.volley/local.json`. Setup validates the model against the live Codex surface - an unavailable model errors out; Volley never silently substitutes another.
- **Project context**: every Codex session runs with the canonical Git root as its `cwd` and is pointed at the project's authority files (`config.json` `context` manifest - required files must exist, optional ones are skipped if absent).
- **Conversational continuity**: within a review exchange, follow-ups resume the exact Codex thread. Implementation can optionally resume an exact prior session by id (never `--last`), guarded by repository identity so a copied state file can't resume another project.

**The boundary (important):** Volley can resume **Volley-created** Codex conversations and share your project's committed files. It **cannot** inherit Claude's private chat history, and it **cannot** attach to an unrelated Codex desktop-app task. Across a full restart, MCP reviews rehydrate a fresh Codex session from your project files + `CHECKPOINT.md` rather than pretending a dead thread was preserved - and they tell you when that fallback happens.

## FAQ

**Q: Can't Claude Code just do everything itself?**
Sometimes you want a fresh perspective. Codex doesn't see Claude's context window, so its review is genuinely independent. The plan/PR review skills exist for that reason. The `/volley:implement` skill exists because long implementations burn Claude's context budget unnecessarily — offloading to Codex preserves Claude's session for higher-leverage work.

**Q: Why not just run Codex in a separate terminal manually?**
You can. Volley adds (a) the hard lock so they can't both edit at once, (b) structured handoffs through `.volley/` files Claude reads automatically, and (c) the MCP pathway so short ops complete inline without a terminal swap.

**Q: Will this work with Gemini CLI / Aider / Cursor?**
Not out of the box — v0.1 ships with Codex as the second assistant. But the backend is swappable: the [extension guide](docs/EXTENDING-ASSISTANTS.md) documents exactly where Codex is wired in and how to point Volley at another assistant. Pluggable adapters are on the roadmap.

**Q: My lock got stuck after closing the Codex terminal.**
Run `/volley:status` to see the lock age and PID liveness, then `/volley:unlock` to clear. The lock has a 30-minute stale threshold by default.

**Q: Does this work with Claude Code subagents?**
Subagents inherit the parent session's lock state but don't acquire their own. Don't use `/volley:implement` from inside a subagent; spawn it from the main loop.

## Roadmap

- [ ] Pluggable second-assistant adapters (Gemini, Cursor, Aider) — see [docs/EXTENDING-ASSISTANTS.md](docs/EXTENDING-ASSISTANTS.md)
- [ ] GitHub Actions workflow that runs `/volley:review-pr` automatically on new PRs
- [ ] Project-wide lock (across multiple repos in a workspace)
- [ ] Cost/token telemetry per session

v0.1 pairs Claude with OpenAI Codex; the second assistant is swappable - see [docs/EXTENDING-ASSISTANTS.md](docs/EXTENDING-ASSISTANTS.md), and pluggable adapters are on the roadmap.

See [issues](https://github.com/Ryan-M-Frank/volley/issues) for the current state.

## Contributing

PRs welcome. Run the bash test suite before submitting:

```bash
bash tests/run-all.sh
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for the full guide.

## License

Apache-2.0 © 2026 Ryan M. Frank. See [LICENSE](LICENSE).

## Acknowledgements

Built on top of [Claude Code](https://docs.claude.com/claude-code) by Anthropic and [Codex CLI](https://github.com/openai/codex) by OpenAI. Lock model inspired by the file-lock pattern in old `rcs(1)` and `git`'s own `index.lock`.

---

<sub>Made because watching one AI was getting lonely.</sub>
