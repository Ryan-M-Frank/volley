# Volley continuity + model-selection change brief — review

**Reviewer:** Claude Code
**Date:** 2026-07-21
**Brief reviewed:** `VOLLEY-CONTINUITY-CHANGE-BRIEF.md`
**Repository:** `Ryan-M-Frank/volley` @ `main` (canonical root `C:/git/volley`, remote `https://github.com/Ryan-M-Frank/volley.git`)
**Codex CLI verified against:** `codex-cli 0.144.5`
**Gate honored:** This document is the only file created. No Volley source, config, skill, script, or test was modified.

---

## Verdict

**Approve pending amendments.**

The brief's owner intent is sound, the feature split (model selection ≠ thread resume ≠ project context) is correct, and every high-level assumption is either confirmed or fixable. I verified the core behaviors against the installed CLI rather than trusting the brief's examples, and the proposed direction is implementable. Approval is conditional on the amendments in the next two sections — chiefly (1) the cross-restart MCP resume story, (2) reconciling the new config with the config file the *configurable-roles* design already introduces, (3) the `managedHandoff` vs "HANDOFF is user-owned" conflict, and (4) stale model/tooling examples.

---

## What I verified live (evidence)

| Check | Command / call | Result |
|---|---|---|
| Codex version | `codex --version` | `codex-cli 0.144.5` |
| Model override on MCP tool | `mcp__codex__codex` schema | `model`, `cwd`, `config`, `sandbox`, `approval-policy`, `base-instructions` all present |
| Model override on exec | `codex exec --help` | `-m/--model`, `-C/--cd`, `-c key=value`, `--json`, `-o/--output-last-message` |
| Session resume exists | `codex exec resume --help` | takes `[SESSION_ID]` (UUID) + prompt; `--last`, `--all` (disables cwd filter), `-m` |
| **Within-process MCP continuity** | live 2-turn test | turn 1 returned `threadId 019f85ee-…`; turn 2 via `codex-reply` **recalled the token** → **works** |
| **MCP thread persists to disk** | `find ~/.codex/sessions -name '*019f85ee*'` | rollout file created: `threadId == session_id == rollout filename` |
| Default model / effort | `~/.codex/config.toml` | `model = "gpt-5.6-sol"`, `model_reasoning_effort = "xhigh"` |
| Repo identity primitives | `git remote get-url origin`, `git rev-parse --show-toplevel` | both resolve cleanly |
| `jq` present | `command -v jq` | **absent on this machine** |
| resume default cwd filter | `resume --help` | sessions are cwd-filtered unless `--all` — a natural repo guard |

---

## Corrections to the brief's assumptions

The brief's five current-behavior assumptions are **all essentially correct**. Precise corrections:

1. **Assumption 1 (plain `codex mcp-server`, no model):** ✅ Confirmed — `.mcp.json:2-6` registers `{"command":"codex","args":["mcp-server"]}` with no model or config. (Note: this `.mcp.json` is the *plugin's bundled* server — this repo *is* the plugin, per `.claude-plugin/`. `skills/setup/SKILL.md:16-18` correctly tells consumers not to write their own; no contradiction.)

2. **Assumption 2 (reviews pass prompt/sandbox/approval but no model/effort/cwd):** ✅ Confirmed — `skills/review-plan/SKILL.md:60` and `skills/review-pr/SKILL.md:62` call `mcp__codex__codex` with only `sandbox: read-only` + `approval-policy: never`. **Correction/nuance:** the MCP server inherits Claude's process cwd, so reviews *implicitly* run in the repo root today only because Claude's cwd happens to be the root. Nothing pins the *canonical* absolute root, and there is no reasoning-effort field at all.

3. **Assumption 3 (`codex-reply` + threadId continues an exchange):** ✅ **Confirmed and demonstrated live** (recalled `VOLLEY-ALPHA-7`). `skills/review-plan/SKILL.md:60` already documents this path.

4. **Assumption 4 (implement spawns separate `codex exec` in repo root, points at plan + `.volley/HANDOFF.md`, no model, no exact resume):** ✅ Confirmed — `skills/implement/SKILL.md:97-99` spawns via `scripts/spawn-codex.sh`; every handler runs `codex exec --sandbox … -C <repo-root> -c approval_policy=never` (`windows.sh:37`, `macos.sh:20`, `linux.sh:14`, `tmux.sh:24`) with **no `-m`** and no resume. **Correction:** implementation *does* already pin cwd correctly via `-C <repo-root>`; the gap is model/effort + session capture, not cwd.

5. **Assumption 5 (model fields exist; `codex-reply` persistence/restart needs demonstration):** ✅ Confirmed the fields exist. **Correction — this is the most important finding:**
   - Within-process `codex-reply` continuity **works** (demonstrated).
   - The MCP thread **is persisted to disk** as a rollout file whose name embeds the `session_id`, and `threadId == session_id`. So the *data* survives a restart.
   - **BUT** the session-*start* tool `mcp__codex__codex` has **no `threadId`/resume parameter** (only `codex-reply` accepts `threadId`). There is therefore **no supported way to hand a saved threadId to a fresh MCP server process** and continue it over MCP. Whether `codex-reply` re-attaches to a thread the *current* server process never created is unproven and should be treated as **unsupported**.
   - The durable, transport-independent resume path is **`codex exec resume <session_id>`**, which reads the on-disk rollout and is cwd-filtered by default. Because `threadId == session_id`, even an MCP-originated thread is resumable this way — but that switches transports (MCP → terminal), which matters for the review role.

---

## Findings, ordered by severity

### F1 — HIGH: Cross-restart MCP review continuity is not achievable as the brief implies
The brief (Phase 2 §3, acceptance #3/#4) wants persisted thread IDs "when the underlying interface can resume them safely." For the **review role over MCP**, the interface *cannot* safely resume across a Claude/plugin restart: there is no resume parameter on the start tool. **Amendment:** For reviews, treat `codex-reply`+`threadId` as **within-session only** (verified working), and on any new session **fall back to file-based rehydration** (fresh `codex` call seeded from the context manifest + managed checkpoint), recording the fallback reason and telling the user. This is exactly acceptance criterion #4's fallback — make it the *default* for review across restarts, not an error path. Acceptance #3 ("a second turn reuses the thread ID") is satisfiable *within* an exchange and should be scoped to that.

### F2 — HIGH: New config duplicates a config file the roles design already introduces
`docs/design/2026-06-02-volley-configurable-roles-design.md:33-52` already specifies **`.volley/config.json`** with `{"version":1,"roles":{…}}`, parsed by a single parser, absent = current defaults. The brief proposes a *separate* file with `schemaVersion` + a `codex`/`context` shape. Shipping both creates two config authorities and two version keys. **Amendment (answers brief question 7):** **extend** `.volley/config.json` — add `codex` and `context` sections alongside `roles`, keep the existing integer `version` key (not `schemaVersion`), and keep "absent file = today's behavior." Do not introduce a second project config file.

### F3 — HIGH: `managedHandoff` conflicts with the "HANDOFF is user-owned, neither writes" invariant
`scripts/templates/HANDOFF.md:3` and `README.md:114` state Volley's `.volley/HANDOFF.md` is user-owned and **neither AI writes it**. The brief's "durable shared memory" wants Volley to *update* a managed handoff. Pointing `managedHandoff` at the root `HANDOFF.md` (the game repo's live channel) risks the exact "second conflicting authority" the brief warns about. **Amendment:** keep the user-owned `HANDOFF.md` read-only to orchestration. Introduce a **separate** Volley-managed checkpoint (default `.volley/CHECKPOINT.md`) that Volley owns and rewrites. Make its path configurable, but **default it to `.volley/CHECKPOINT.md`, never the root HANDOFF**. When an owner *does* point it at a shared file, Volley writes **only** inside sentinel markers (`<!-- volley:managed:start --> … <!-- volley:managed:end -->`) and leaves everything else byte-for-byte. This preserves the current invariant for the common case and satisfies the game repo's live-channel case safely.

### F4 — MEDIUM: Reasoning effort has no dedicated field — it rides `config`
There is no `reasoningEffort` parameter on the MCP tool or a dedicated exec flag. Reasoning effort is a **config key**: `model_reasoning_effort`. **Amendment:** pass it as `config: {"model_reasoning_effort": "<v>"}` on the MCP `codex` tool, and as `-c model_reasoning_effort=<v>` on `codex exec`. Validate the value against Codex rather than hardcoding (observed value `xhigh`); an unsupported level must produce an actionable error, never a silent drop.

### F5 — MEDIUM: Model examples and the min-version floor are stale
The brief's illustrative `gpt-5.2` and the local state example are dated; the installed default is **`gpt-5.6-sol`**. The MCP schema's own doc string still says `'gpt-5.2'`. **Amendment:** never hardcode a model allowlist (the brief already says this). Reuse the **existing PONG smoke test** (`skills/setup/SKILL.md:36`) but pass the *configured* model — an invalid model surfaces as a real Codex error at setup, with no maintained list. Separately, `skills/setup/SKILL.md:12` and `skills/diagnose/SKILL.md:12` gate on `>= 0.129`; resume-by-id and the `--json` capture below are the constraint now — bump the documented floor to the version that ships `codex exec resume` + `--json` (0.144.5 is known-good).

### F6 — MEDIUM: Implementation session capture vs the visible-terminal UX is a real trade-off
Volley's headline UX is "watch Codex work in a tab." The clean, race-free way to capture the exact `session_id` from a spawned run is `codex exec --json`, but that turns the visible tab into raw JSONL, degrading that UX. **Amendment (answers brief questions 2 & 3):**
- **Phase-1 default:** do **not** attempt implementation session-resume. Rely on durable file rehydration (context manifest + managed checkpoint). This keeps the pretty tab and ships value immediately.
- **Opt-in `implementation.continuity: "resume-if-safe"`:** capture the id via `codex exec --json | tee <log>` (structured, no filesystem timestamp race), parse `session_meta.session_id`, persist it, and resume with `codex exec resume <session_id> -C <root>` — **never `--last`**.
- **Fallback capture** (if `--json` is undesirable): after the run, select the rollout whose `session_meta.cwd == canonicalRoot` **and** whose timestamp falls in this run's NONCE window (`skills/implement/SKILL.md:30` already mints a timestamped NONCE). This is the least-fragile disk-based option and still avoids `--last`.

### F7 — MEDIUM: `jq` dependency is unmet on at least one target machine
The roles design (`…configurable-roles-design.md:35`) mandates `jq` as the single config parser and a doctor check. **`jq` is absent on this machine.** **Amendment:** because skills are Claude-driven and Claude parses JSON natively, **read/validate config in the host (Claude), not in bash**. Bash helpers should only receive already-extracted scalars (model, effort, root) via args/env. This removes a hard `jq` runtime dependency for the new config. If any pure-bash path must read JSON, add the doctor check + fail-closed install hint the roles design already specifies. (Flag as reconciliation: the roles design says "single jq parser" — the owner should decide host-parse vs jq.)

### F8 — LOW: `session_index.jsonl` is not a reliable lookup key
The freshly-created thread was **not** present in `~/.codex/session_index.jsonl` (it appears to index named threads lazily). **Amendment:** treat the **rollout file's `session_meta`** (which carries `session_id`, `cwd`, `cli_version`, `source`) as the source of truth for identity/validation, not `session_index.jsonl`.

### F9 — LOW: STATE schema will need role/assistant fields the roles design also wants
Current STATE is four keys (`scripts/lib.sh:8-18`). The roles design plans to demote STATE to metadata (`role/assistant/mode/…`). Continuity state (thread/session IDs) should **not** live in STATE (it is gitignored transient and single-slot). **Amendment:** keep continuity IDs in a dedicated local file (below), independent of STATE, so the two efforts don't collide.

---

## Recommended architecture

### Layering (answers brief questions 4 & 7)
- **Shared, committed → `.volley/config.json`** (extend the existing planned file): context manifest, role policy, and *recommended* model defaults. Team policy.
- **Local, gitignored → `.volley/local.json`**: machine/user model overrides + all thread/session IDs + repo identity. Never committed.
- **Never persisted:** auth, prompts, full transcripts, env, or absolute paths beyond the canonical root needed to prevent cross-project resume.

### Project config — extend `.volley/config.json`
```jsonc
{
  "version": 1,                      // SAME key the roles design uses — do not add schemaVersion
  "roles": { /* … existing roles-design block, untouched … */ },
  "codex": {
    "review":         { "model": "inherit", "reasoningEffort": "high", "continuity": "session-only" },
    "implementation": { "model": "inherit", "reasoningEffort": "high", "continuity": "rehydrate" }
  },
  "context": {
    "required": ["AGENTS.md"],
    "optional": ["CLAUDE.md", "planning.md", "HANDOFF.md", "CURRENT-STATE.md"],
    "managedCheckpoint": ".volley/CHECKPOINT.md"   // NOT the root HANDOFF by default (see F3)
  }
}
```
- `model: "inherit"` → omit `-m` / omit MCP `model` (uses Codex default, currently `gpt-5.6-sol`).
- `continuity` values: `session-only` (review, verified), `rehydrate` (Phase-1 implement default), `resume-if-safe` (opt-in exact-id resume, F6).
- Missing **required** context file → fail early; missing **optional** → report + skip (brief §2).

### Local state — `.volley/local.json` (gitignored)
```jsonc
{
  "version": 1,
  "repository": {
    "canonicalRoot": "C:/git/volley",
    "remote": "https://github.com/Ryan-M-Frank/volley.git"
  },
  "modelOverrides": { "review": null, "implementation": null },
  "roles": {
    "planReview":     { "threadId": "<uuid>", "model": "<resolved>", "updatedAtUtc": "<iso>" },
    "prReview":       { "threadId": "<uuid>", "model": "<resolved>", "updatedAtUtc": "<iso>" },
    "implementation": { "sessionId": "<uuid>", "model": "<resolved>", "updatedAtUtc": "<iso>" }
  }
}
```

### Repo-identity guard (answers brief question 5)
Before any resume: re-derive `git rev-parse --show-toplevel` + `git remote get-url origin`, compare to `local.json.repository`. Mismatch (copied/moved state) → **discard the stored ID, start fresh, rehydrate from files, record why**. `codex exec resume` already cwd-filters by default (an extra built-in guard); never pass `--all`, never `--last`.

### Continuity decision matrix
| Role | Transport | Within exchange | Across restart |
|---|---|---|---|
| Plan / PR review | MCP | `codex-reply`+`threadId` (verified) | **rehydrate** new `codex` session from manifest+checkpoint (F1) |
| Implementation | terminal | n/a (single run) | `rehydrate` default; `resume-if-safe` → `codex exec resume <sessionId>` (F6) |

### Status/diagnostics surface (brief §5)
`/volley:status` and `/volley:diagnose` report, without secrets: selected model + effort per role; whether the action was new / resumed / rehydrated-from-files; canonical root + which context files were found/missing; role↔thread association; and where `local.json` + the managed checkpoint live. `/volley:diagnose` adds: config parse+validate, model availability (via the reused smoke call only if the user asks for a live probe), repo-identity match, context-file presence, `local.json` integrity, MCP availability, launcher support. Diagnostics must not mutate source or spend a substantive model turn by default.

---

## File-by-file implementation plan (Phase 2, after approval, on a dedicated branch)

1. **`scripts/lib.sh`** — add pure-bash helpers that operate on *scalars only* (no JSON parsing): `volley_repo_identity` (echo root + remote), `volley_local_get/set` shims that call the host for JSON (or `jq` if the owner chooses F7), `volley_build_codex_flags <role>` → emits `-m` / `-c model_reasoning_effort=` fragments (empty when `inherit`). Keep existing STATE/lock helpers untouched.
2. **`.volley/.gitignore` + `scripts/templates/gitignore`** — add `local.json`, `codex-prompt-*.txt`, `log-*.jsonl` (already), and the JSONL capture log. Do **not** ignore `config.json` or `CHECKPOINT.md` (shareable). Confirm `CHECKPOINT.md` commit policy with owner.
3. **`skills/setup/SKILL.md`** — scaffold `.volley/config.json` (defaults = current behavior) + empty `.volley/local.json`; write `repository` identity; validate the configured model by **reusing the PONG smoke test with `model`/`config` set** (F5); create `.volley/CHECKPOINT.md` from a new template.
4. **`skills/review-plan/SKILL.md` & `skills/review-pr/SKILL.md`** — pass explicit canonical `cwd`, plus `model` and `config:{model_reasoning_effort}` from resolved config; persist returned `threadId` to `local.json`; on a new session, rehydrate from manifest+checkpoint and state the fallback (F1); use `codex-reply` only within the live exchange.
5. **`skills/implement/SKILL.md`** — resolve model/effort; pass them to the spawner via env (`VOLLEY_CODEX_MODEL`, `VOLLEY_CODEX_EFFORT`); Phase-1 default rehydrate; `resume-if-safe` path captures/persists `sessionId` and resumes by exact id. Update the managed checkpoint (only) after a successful exchange.
6. **`scripts/spawn-codex.sh` + `scripts/platforms/{windows,macos,linux,tmux}.sh`** — thread `VOLLEY_CODEX_MODEL`/`VOLLEY_CODEX_EFFORT` into the `codex exec` line as `-m` / `-c model_reasoning_effort=`, preserving existing quoting (`sed "s/'/''/g"` on Windows, `printf %q` elsewhere) — interpolate **only validated scalars**, never raw config text (brief constraint). Add optional `--json | tee` capture behind the resume flag.
7. **`skills/diagnose/SKILL.md` & `skills/status/SKILL.md`** — add the reporting surface above; add config/identity/context/local-state checks.
8. **`scripts/templates/CHECKPOINT.md`** (new) — structured: objective, accepted decisions, open questions, artifacts, verification evidence, recommended next action.
9. **`docs/`** — document the boundary loudly (brief acceptance #12): Volley resumes **Volley-created** Codex sessions and shares project files; it **cannot** inherit Claude's private chat history or attach to an unrelated Codex desktop task. Update `EXTENDING-ASSISTANTS.md` seam notes for the new flags.
10. **`README.md`** — model-selection + continuity section; correct any overclaim.

---

## Testing plan (all platforms + failure recovery)

Reuse the existing harness pattern — stub `codex` on `PATH`, drive handlers via `VOLLEY_PLATFORM`, **no live paid model calls in CI** (`tests/test-spawn-codex.sh`, `tests/test-platform-handlers.sh` already do exactly this). Answers brief question 8.

**New unit tests (pure bash, deterministic):**
- `test-config.sh` — valid/invalid `version`; unknown model field shape; absent file ⇒ current defaults; required-context-missing ⇒ fail-closed; optional-missing ⇒ report+skip.
- `test-flag-build.sh` — `volley_build_codex_flags`: `inherit` ⇒ no `-m`; concrete model ⇒ `-m <m>`; effort ⇒ `-c model_reasoning_effort=<v>`; assert **no `--last`, no `--all`** ever appear; assert a resume line uses a UUID positional.
- `test-repo-identity.sh` — match ⇒ resume allowed; moved root or changed remote ⇒ discard + fallback signalled.
- `test-quoting.sh` — model/effort values with quotes/spaces survive Windows `sed` and POSIX `printf %q` interpolation without breaking the command.
- `test-local-state.sh` — round-trip write/read; corrupt/absent `local.json` ⇒ deterministic error, no crash.
- `test-gitignore.sh` — `local.json` ignored; `config.json`/`CHECKPOINT.md` tracked.
- `test-session-capture.sh` — feed a canned `--json` stream to the parser; assert the correct `session_id` is extracted; assert the cwd+NONCE fallback selects the right rollout among decoys.
- `test-fallback.sh` — stored session absent/incompatible ⇒ new session + rehydrate + recorded reason + user-visible message.

**Integration (opt-in, not CI — needs auth + spends turns):**
- 2-turn MCP continuity (the check I ran manually) as a documented `make verify-continuity` behind an env guard.
- One real spawned `codex exec --json` capture per platform (community-tested for macOS/Linux GUI, as today).

**Failure-recovery matrix (brief acceptance #8):** unavailable model, invalid reasoning level, deleted/missing session, moved repo, missing required context, corrupt config, upgraded Codex schema — each asserted to produce a deterministic, actionable error and to fall back (where a fallback exists) rather than silently substitute.

---

## Questions requiring an owner decision

**Resolved by owner (2026-07-21):**
1. ✅ **Config parsing (F7):** **Host-parse in Claude — skip the `jq` dependency.** The new config sections are read/validated by Claude (native JSON); bash receives only extracted scalars. Reconciliation: this supersedes the roles design's "single `jq` parser" line for these sections; update that design note when the roles work lands.
2. ✅ **Managed checkpoint (F3):** **Yes to a separate `.volley/CHECKPOINT.md`.** The user-owned root `HANDOFF.md` stays read-only to orchestration; Volley writes the shared HANDOFF **only** via sentinel markers and **only** when explicitly configured.

**Still open (defaults proposed — confirm or override):**
3. **Implementation continuity UX (F6):** *Default proposed:* keep the pretty tab; Phase-1 implementation rehydrates from files, exact-session resume is opt-in (`resume-if-safe`). Avoids the JSONL-tab downgrade.
4. **Reasoning effort granularity (F4):** *Default proposed:* per-role effort (`review` vs `implementation`), matching the model split.
5. **STATE evolution (F9):** *Default proposed:* land continuity on today's four-key STATE via a **separate** `local.json`; do not block on the roles-design STATE-metadata change.
6. **Cross-restart review resume (F1):** *Default proposed:* accept file-rehydration across restarts (within-exchange thread reuse stays). This is the "nervewracking" finding — the practical impact is one line of docs, not lost functionality.

---

## Stop point

Per the brief, I stop here. No Volley source, config, skill, script, or test has been modified — only this review exists. Awaiting your acceptance of the verdict or resolution of the amendments before any implementation, which will happen on a dedicated Volley branch created after approval.
