# Volley — Configurable Roles (Separation of Duties) — Design

**Date:** 2026-06-02
**Status:** Revised after Codex reviews #1 + #2 (all concerns addressed); ready for implementation plan
**Target:** Volley v0.2 (the `github.com/Ryan-M-Frank/volley` plugin)
**Depends on / relates to:** the assistant-adapter direction in `docs/EXTENDING-ASSISTANTS.md`

## The core principle (the headline)

**Separation of duties between AI agents: every step is produced by one agent and *reviewed by a different one* — and the workflow will not advance until that independent review is recorded.**

This is two clauses, both enforced:
1. **No self-review** — a reviewer is never the same agent that produced the artifact. (config invariant)
2. **Review is mandatory, not optional** — a produced artifact (plan, code, PR) cannot be marked complete / advanced until a *different* agent records a verdict. (workflow invariant)

Clause 2 is the one that makes the principle real (Codex review #1: a config-only invariant is hollow if the review can be skipped). It is a hard, fail-closed property and the product's thesis — stated loudly in README + SECURITY, framed as the audit-grade principle it is.

## What this feature does

Make **who performs each role configurable** — planner, implementer, plan-reviewer, code-reviewer, **pr-reviewer** — assignable to any registered assistant, subject to separation of duties. Today these are hardcoded. v0.2 makes them configurable while making self-review impossible *and* review mandatory.

## Goals
1. A per-repo config assigning roles to assistants; absent = today's exact behavior.
2. Separation of duties enforced as fail-closed invariants (both clauses) at config load and at workflow transitions.
3. Skills resolve roles dynamically (never hardcode).
4. Backward compatible; purely additive externally.
5. Data model future-proof for N≥3 (build/test N=2 now).

## Non-Goals
- 3rd-assistant machinery before a 3rd adapter exists (model allows it; ship Claude + Codex).
- Rewriting the workflow engine — we add a review-gate + a real lock primitive, not a new orchestrator.

## Config: `.volley/config.json` (per-repo)

JSON, parsed by **`jq`** — a single parser path, NOT "jq else python" (two implementations risk validation drift — Codex review #2), and NOT hand-rolled bash. `/volley:doctor` checks `jq` is present and fails closed with a clear install hint if it isn't. Absent file = current hardcoded defaults.

```json
{
  "version": 1,
  "roles": {
    "planner":       "claude",
    "implementer":   "codex",
    "plan_reviewer": "auto",
    "code_reviewer": "auto",
    "pr_reviewer":   "auto"
  }
}
```

- **`roles`**: producers (`planner`, `implementer`) explicit; reviewers default `"auto"` (= a *different* assistant than the producer) or pinned to an assistant id (validated ≠ producer). `auto` is **only valid at N=2**; with N≥3 a reviewer must be pinned (object order is not a stable tie-break — Codex review #1).
- **No user-declared `can`.** Capabilities are **declared by each assistant's adapter** (immutable), not asserted in user config (Codex review #1 — config must not grant a capability the tool lacks). The registry of assistants + their real capabilities comes from installed adapters (the `EXTENDING-ASSISTANTS` contract), not this file.
- **Defaults (no file):** reproduce v0.1 — `planner=claude, implementer=codex`, reviewers `auto` → plan/pr-review=codex, code-review=claude.

## Assistant registry (from adapters, not config)

Each installed adapter declares, immutably: `id`, `kind` (`host | mcp | terminal | mcp+terminal`), and the roles it can actually fulfill (derived from its real transports — e.g. an MCP-only backend can review but cannot `implement`). `claude` is always `kind: host`, runs roles **inline**. The resolver reads this registry; config may only *assign* roles to assistants that genuinely support them.

## Enforcement

**At config load (fail closed, before touching the repo):** a `volley-config` resolver validates and, if invalid, prints a clear error and touches nothing — even if a skill is invoked directly. Checks:
```
- version known; JSON valid (via jq/python)
- every role's assistant exists in the adapter registry AND its adapter supports that role
- reviewer(x) != producer(x) for plan, code, pr           # SoD clause 1
- auto only at N==2; N>=3 reviewers must be pinned
- claude.kind == host   (claude need NOT hold an artifact role; it always orchestrates)
```

**At workflow transitions (the new gate — SoD clause 2):** each produced artifact is tracked with `produced_by`, `review_required=true`, `reviewed_by`. Volley **refuses to advance/complete** the step until `reviewed_by` is set AND `reviewed_by != produced_by`. (It refuses *advancement within Volley* — it cannot stop a user abandoning a run or editing outside the tool; Codex review #2.) For the **PR artifact, `produced_by` = the `implementer`** (the agent that authored the change), not whoever typed the PR body — so `pr_reviewer != implementer` is the meaningful constraint (Codex review #2).

## Lock — real acquisition primitive (fixes a v0.1 race)

**Codex review #1 caught a latent bug in today's lock:** the STATE file is written atomically (`mv`), but two commands can both observe `idle` then both write `busy` (TOCTOU). v0.2 replaces *acquisition* with an atomic primitive:
- **Acquire** = `mkdir .volley/lock.d` (atomic; fails if held). **Release is owner-token-safe** — the acquirer records an owner token; a release/stale-clear only removes the lock when the token matches, so it can never delete a different, freshly-acquired lock (Codex review #2). *(Shipped in v0.1.1 as `volley_lock_acquire`/`volley_lock_release`; wiring into the implement handoff lands with this v0.2 work.)*
- **STATE becomes metadata** (not the lock itself): `status, role, assistant, mode, pid, since`, e.g. `busy role=implementer assistant=codex mode=terminal pid=12345`.
- This race fix is worth backporting to v0.1 as its own small patch.

**Reviews need a precisely-defined stable snapshot, not just "skip the lock"** (Codex reviews #1, #2): a read-only review of `git diff` while an implementer is still editing reviews a moving tree. Review skills either require **no active writer**, or **pin an explicit snapshot**. The snapshot must be defined precisely — a bare "tree hash" misses staged/untracked/binary changes (Codex review #2). Capture: `git stash create` (a real commit object capturing tracked working-tree + index changes) **plus** a content hash of untracked files (`git ls-files --others --exclude-standard`). Verify the same snapshot id after the review; if it moved, invalidate and re-run.

## Skills + transport resolution

Skills read the resolver, never hardcode. `claude`→inline; `codex` review→MCP; `codex` implement→terminal spawn; a backend that can't fulfill a role's transport is rejected at load.

- `/volley:implement` → `implementer`: spawn-capable backend → spawn (today's path); **`claude` → first-class INLINE mode** (Codex review #1): acquires the lock, writes `busy role=implementer assistant=claude mode=inline pid=$$`, makes the changes in-session, then transitions to "awaiting review". No PID-liveness promise; explicit completion marker; interruption/stale-recovery is tested.
- `/volley:review-code` / `review-plan` / `review-pr` → the configured reviewer: `claude` → local; backend → snapshot diff over MCP, verdict back; records `reviewed_by` (satisfying the SoD gate).
- `/volley:status` + `/volley:doctor` print the live role matrix + the review-gate state.

## N≥3 future (designed-for, not built)
Add an adapter → it self-declares capabilities → assign roles to it. No role names, skills, or lock semantics change. Reviewers must be pinned (no `auto`) at N≥3. Ship Claude + Codex; no rotation/tie-break policy until a 3rd adapter lands.

## Risks
| Risk | Mitigation |
|---|---|
| `claude`-as-implementer is a distinct code path (no child process/handshake) | first-class inline mode: explicit busy state, completion transition, interruption tests — not "STATE stays claude" |
| Capability drift — valid config, bad workflow | capabilities are adapter-declared (not user `can`); recommended configs documented; doctor surfaces the matrix |
| Review races a still-editing writer | snapshot + tree-hash pin; reviews require no active writer or invalidate-on-change |
| Lock double-acquire (pre-existing) | atomic `mkdir`/noclobber acquisition; STATE demoted to metadata |
| Config silently degrades workflow | fail-closed validation + review-gate + status/doctor surfacing |

## Acceptance criteria
1. **Absent config → external behavior identical to v0.1.** (STATE gains fields additively; "byte-for-byte" means workflow/behavior, not the STATE file bytes — Codex review #1 clarification.)
2. A config that violates SoD clause 1 (reviewer == producer) **fails closed**, touching nothing, even if a skill is invoked directly.
3. **SoD clause 2:** a produced artifact cannot be completed/advanced until a *different* assistant records a verdict; implement-then-stop is refused.
4. planner/implementer/plan_reviewer/code_reviewer/**pr_reviewer** each assignable to either assistant (subject to SoD + adapter capability); a full non-default matrix runs E2E.
5. `claude`-as-implementer runs as first-class inline mode and is reviewed by the configured different assistant.
6. `codex`-as-code-reviewer works (snapshot diff over MCP, verdict back).
7. **Lock:** concurrent acquire attempts — exactly one wins (race test); STATE records role+assistant+mode.
8. **Review snapshot:** a review whose tree changes mid-review is invalidated/re-run (test).
9. Config parsed by a real parser; invalid version/role/assistant/capability/`auto`-at-N≥3 all fail closed with clear errors; doctor checks the parser is present.
10. Adding a hypothetical 3rd adapter + assigning a role needs no skill/lock changes (config-only fixture test).
11. CI matrix green; zero `duo`/`copair` residue.
