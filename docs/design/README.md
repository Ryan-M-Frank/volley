# Design docs

Specs and implementation plans for Volley, kept for design history.

These were originally authored in the RASA project tree (where Volley was first
extracted from the in-repo "DUO" workflow) and ported here so they live with the
code they describe.

| Doc | Type | Topic |
|-----|------|-------|
| [`2026-06-01-volley-plugin-extraction-design.md`](2026-06-01-volley-plugin-extraction-design.md) | Spec | Extracting DUO into the Volley plugin |
| [`2026-06-01-volley-plugin-extraction.md`](2026-06-01-volley-plugin-extraction.md) | Plan | 18-task extraction build plan |
| [`2026-06-02-volley-configurable-roles-design.md`](2026-06-02-volley-configurable-roles-design.md) | Spec | v0.2 configurable roles / separation of duties |
| [`2026-06-02-volley-configurable-roles.md`](2026-06-02-volley-configurable-roles.md) | Plan | v0.2 6-phase / 13-task build plan |

> **Historical context.** These are point-in-time design records, not current
> docs. References to `duo`/`copair`, the RASA source repo, and absolute local
> paths (e.g. `C:\git\RASA\RASA_DEMO-copair`) describe the author's machine and
> source tree *at extraction time* - they are kept as provenance and are not
> current Volley paths or names. The only `grep`-pattern occurrences of those
> strings inside the plans are intentional (a secret/leak scanner that searches
> *for* them).
