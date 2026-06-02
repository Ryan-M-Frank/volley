# Volley

> Two AI coding assistants, one repository, zero deadlocks.

[![CI](https://img.shields.io/github/actions/workflow/status/Ryan-M-Frank/volley/ci.yml?branch=main)](https://github.com/Ryan-M-Frank/volley/actions)
[![License: Apache-2.0](https://img.shields.io/badge/license-Apache-2.0-blue.svg)](LICENSE)
[![Claude Code](https://img.shields.io/badge/claude--code-skills-orange)](https://docs.claude.com/claude-code)
[![Codex CLI](https://img.shields.io/badge/codex--cli-MCP-black)](https://github.com/openai/codex)

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
┌────────────────┐                ┌────────────────┐
│   You + Claude │                │     Codex      │
│                │                │                │
│  /volley:review-  │ ── via MCP ──▶ │  reads plan,   │
│  plan          │                │  returns       │
│                │ ◀── verdict ── │  critique      │
└────────────────┘                └────────────────┘

┌────────────────┐                ┌────────────────┐
│   You + Claude │                │     Codex      │
│                │                │                │
│  /volley:implement│ ─── spawns ──▶ │ writes code in │
│  (Claude reads │                │ a visible      │
│  STATE=codex,  │                │ terminal tab,  │
│  hands off)    │                │ commits        │
│                │ ◀── STATE ──── │                │
│  /volley:review-  │     released   │                │
│  code          │                │                │
└────────────────┘                └────────────────┘
```

A `.duo/STATE` file records which assistant is currently authoritative (`ACTIVE=claude` or `ACTIVE=codex`), a PID, and a timestamp. Every skill refuses to act unless the lock matches it. No race, no clobbered edits, no "wait, who wrote this?"

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
/volley:setup           # one-time: registers Codex as MCP, scaffolds .duo/
/volley:status          # sanity-check the install
```

Once installed, the skills below are available in any repo.

## Skills

| Skill | What it does | Calls Codex via |
|---|---|---|
| **`/volley:setup`** | One-time install: verifies Codex, registers MCP, scaffolds `.duo/` | (smoke test) |
| **`/volley:status`** | Inspect the lock state, lock age, stale-PID detection | (local only) |
| **`/volley:unlock`** | Force-clear a stuck STATE lock (escape hatch) | (local only) |
| **`/volley:doctor`** | Health-check: verify Codex auth, MCP registration, and STATE integrity | (local only) |
| **`/volley:review-plan`** | Hand a plan document to Codex for review; output to `.duo/PLAN-REVIEW.md` | **MCP** (fast) |
| **`/volley:review-pr <num>`** | Hand a GitHub PR diff to Codex for review; output to `.duo/PR-REVIEW-<num>.md` | **MCP** (fast) |
| **`/volley:implement`** | Hand a plan to Codex; Codex runs in a visible terminal tab while Claude waits | **Terminal spawn** (long-running) |
| **`/volley:review-code`** | Claude reviews Codex's diff against the plan; output to `.duo/CODE-REVIEW.md` | (local; no Codex call) |

Two transports for two latency profiles. Short ops (plan review, PR review) go through MCP and return in seconds. Long ops (implementation) spawn a visible Codex terminal so you can watch progress without blocking Claude's session.

## Requirements

- **[Claude Code](https://docs.claude.com/claude-code)** — the host environment
- **[Codex CLI](https://github.com/openai/codex)** >= 0.129, authenticated (`codex login`)
- **Bash** (Git Bash on Windows is fine)
- For `/volley:implement` only:
  - **macOS:** iTerm2 or Terminal.app
  - **Linux:** gnome-terminal, kitty, wezterm, or any terminal + tmux
  - **Windows:** Windows Terminal (`wt`) + Git Bash (`cygpath`)

## Platform support

| Skill | macOS | Linux | Windows |
|---|---|---|---|
| `/volley:setup` | ✅ | ✅ | ✅ |
| `/volley:status` | ✅ | ✅ | ✅ |
| `/volley:unlock` | ✅ | ✅ | ✅ |
| `/volley:doctor` | ✅ | ✅ | ✅ |
| `/volley:review-plan` | ✅ | ✅ | ✅ |
| `/volley:review-pr` | ✅ | ✅ | ✅ |
| `/volley:review-code` | ✅ | ✅ | ✅ |
| `/volley:implement` | ✅ (iTerm2 / Terminal.app) | ✅ (gnome-terminal / kitty / tmux) | ✅ (Windows Terminal) |

## How the lock works

```
.duo/
├── STATE                # ACTIVE=<actor>  TASK=<short-label>  SINCE=<iso8601>  PID=<int>
├── HANDOFF.md           # User-owned. Both AIs read; neither writes.
├── PLAN-REVIEW.md       # Codex's plan review (written by /volley:review-plan)
├── CODE-REVIEW.md       # Claude's review of Codex's code (written by /volley:review-code)
├── PR-REVIEW-<num>.md   # Codex's PR review (written by /volley:review-pr)
└── IMPLEMENTATION-LOG.md # Codex's running log during /volley:implement
```

`STATE` is atomic-written and PID-tracked. Every skill calls `duo_state_assert_active` before doing anything destructive — if the lock says it's not your turn, the skill exits with a clear message pointing you at `/volley:status` and `/volley:unlock`.

Stale-lock detection: if the lock is older than 30 minutes AND the named PID is dead, `/volley:status` flags it as stale and offers to clear via `/volley:unlock` (with confirmation).

## Configuration

`.duo/` is **per-repo** (not global). Each repo gets its own STATE, its own HANDOFF.md, its own review artifacts. This is intentional — concurrent work across repos doesn't share a lock.

Add this to your repo's `.gitignore` (or use the included `.duo/.gitignore` which excludes everything except `HANDOFF.md`):

```gitignore
.duo/STATE
.duo/*REVIEW*.md
.duo/IMPLEMENTATION-LOG.md
.duo/CODEX-STARTED-*
```

Commit `.duo/HANDOFF.md` so both AIs in a fresh clone start with the same context.

## FAQ

**Q: Can't Claude Code just do everything itself?**
Sometimes you want a fresh perspective. Codex doesn't see Claude's context window, so its review is genuinely independent. The plan/PR review skills exist for that reason. The `/volley:implement` skill exists because long implementations burn Claude's context budget unnecessarily — offloading to Codex preserves Claude's session for higher-leverage work.

**Q: Why not just run Codex in a separate terminal manually?**
You can. Volley adds (a) the hard lock so they can't both edit at once, (b) structured handoffs through `.duo/` files Claude reads automatically, and (c) the MCP pathway so short ops complete inline without a terminal swap.

**Q: Will this work with Gemini CLI / Aider / Cursor?**
Not today. Codex is the only second-assistant currently supported. The lock model is general — PRs welcome that add other transports.

**Q: My lock got stuck after closing the Codex terminal.**
Run `/volley:status` to see the lock age and PID liveness, then `/volley:unlock` to clear. The lock has a 30-minute stale threshold by default.

**Q: Does this work with Claude Code subagents?**
Subagents inherit the parent session's lock state but don't acquire their own. Don't use `/volley:implement` from inside a subagent; spawn it from the main loop.

## Roadmap

- [ ] Mac variant of `spawn-codex` (iTerm2 + Terminal.app)
- [ ] Linux variant of `spawn-codex` (gnome-terminal, kitty, wezterm, tmux fallback)
- [ ] Gemini CLI support
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
