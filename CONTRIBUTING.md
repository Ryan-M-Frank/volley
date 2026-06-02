# Contributing to Volley

Thanks for taking the time. Volley is intentionally small — the goal is to keep it that way while making it correct on every platform.

---

## Repo layout

```
.claude-plugin/         Claude Code plugin manifest (plugin.json, marketplace.json)
skills/<name>/
  SKILL.md              The skill definition Claude Code reads and executes
scripts/
  lib.sh                Shared bash helpers (state read/write, lock assert, next-step renderers)
  spawn-codex.sh        Cross-platform dispatcher — detects platform, sources the handler, calls spawn_<platform>()
  platforms/
    windows.sh          Windows Terminal (wt) + PowerShell handler
    macos.sh            iTerm2 / Terminal.app handler (community-tested)
    linux.sh            gnome-terminal / kitty / wezterm / tmux handler (community-tested)
    tmux.sh             Universal tmux fallback (CI-tested on ubuntu/macos)
  templates/
    gitignore           Template .gitignore dropped into .volley/ by /volley:setup
    HANDOFF.md          Starter HANDOFF.md scaffolded by /volley:setup
tests/
  test-lib.sh           Unit tests for scripts/lib.sh helpers
  test-spawn-codex.sh   Tests for the dispatcher (platform detection, error paths)
  test-platform-handlers.sh  Tests for each handler's argument validation
  test-setup.sh         Tests for /volley:setup idempotence and scaffold output
  test-concurrency.sh   Lock-contention and simultaneous-write tests
  test-stale-lock.sh    Stale-lock detection and auto-clear threshold tests
  test-extras.sh        Edge cases and regression guards
```

---

## Adding or fixing a platform handler

Each platform handler is a sourced bash file that exposes exactly one function: `spawn_<platform>(prompt_file, title)`. The dispatcher (`scripts/spawn-codex.sh`) sources the file and calls the function.

### What the function must do

1. **Validate prerequisites** — check that the required terminal binary is in `PATH`. Echo a clear `ERROR:` message to stderr and `return 127` if not.
2. **Open a visible terminal** running `codex exec` with the prompt content streamed via stdin:
   ```bash
   # The prompt is streamed through stdin — NOT passed as an argv argument.
   # Plan files can exceed the OS CreateProcess argv limit (~32K on Windows),
   # and stdin sidesteps that limit on every platform.
   some-terminal-launcher -- bash -c "cat '$prompt_file' | codex exec"
   ```
3. **Echo an informational launch identifier** (PID, session name, or window ID) to stdout. This value is **informational only** — callers may log it, but must not rely on it for liveness. The authoritative liveness signal is the `.volley/CODEX-STARTED-<NONCE>` handshake file that Codex creates as its first action; `/volley:implement` polls for that file before flipping the STATE lock.
4. **Return 0** on successful launch, non-zero on failure.

### Adding the dispatch case

Open `scripts/spawn-codex.sh`. The handler is sourced automatically via the `HANDLER_FILE` pattern — no switch statement to update. The dispatcher computes:

```bash
HANDLER_FILE="${DUO_DIR}/platforms/${PLATFORM}.sh"
. "$HANDLER_FILE"
"spawn_${PLATFORM}" "$PROMPT_FILE" "$TITLE"
```

So creating `scripts/platforms/myplatform.sh` with `spawn_myplatform()` is sufficient. The only thing to add to `spawn-codex.sh` is a new detection branch in `detect_platform()` if the new platform isn't already caught by the `uname -s` cases.

### Testing your handler locally

Set `VOLLEY_PLATFORM=<name>` to force the dispatcher to use your handler without changing the detection logic:

```bash
VOLLEY_PLATFORM=myplatform bash scripts/spawn-codex.sh /tmp/test-prompt.txt "test title"
```

This is also how tests stub the platform — they export `VOLLEY_PLATFORM` before calling the dispatcher.

### macOS and Linux desktop handlers

The macOS and Linux desktop handlers (`scripts/platforms/macos.sh`, `scripts/platforms/linux.sh`) are **community-tested** — the primary developer builds and tests on Windows; the tmux handler is what CI exercises on ubuntu/macos runners. If you have a real macOS or Linux desktop and can confirm a handler works (or fix one that doesn't), that PR is especially welcome. Please note in the PR description which terminal application you tested against and the OS version.

---

## Running the test suite

All tests are plain bash scripts that write their own temp dirs and clean up after themselves. Run the full suite:

```bash
for t in tests/*.sh; do bash "$t"; done
```

Every test script must exit 0 and print `FAIL=0` at the end. If any script exits non-zero, the CI `test` job fails.

To run a single test file during development:

```bash
bash tests/test-lib.sh
bash tests/test-platform-handlers.sh
```

---

## CI requirements

Every PR must be green across all three CI jobs before merging:

| Job | What it checks |
|---|---|
| `test` | Full bash test suite on `ubuntu-latest`, `macos-latest`, `windows-latest` |
| `shellcheck` | `shellcheck -S warning scripts/*.sh scripts/platforms/*.sh tests/*.sh` — no warnings allowed |
| `leak-scan` | No forbidden strings (personal path bleed-through, API keys, private key headers, AWS key patterns) |
| `validate` | All JSON manifests parse cleanly |

Run shellcheck locally before pushing:

```bash
shellcheck -S warning scripts/*.sh scripts/platforms/*.sh tests/*.sh
```

Fix every warning — shellcheck is run at the `warning` severity level, which catches undefined variable references, unquoted expansions, and other real bugs, not just style.

---

## Commit and PR conventions

- **Small, focused commits.** One logical change per commit. If you're adding a platform handler and adding tests for it, those can be one commit; refactoring `lib.sh` and adding the handler should be two.
- **Conventional-commit-ish messages.** Prefix with a type: `feat:`, `fix:`, `docs:`, `test:`, `refactor:`, `chore:`. Examples:
  - `feat: add spawn_myplatform handler for Kitty terminal`
  - `fix: escape single quotes in macos prompt path`
  - `test: cover stale-lock PID=0 edge case`
- **Fill out the PR template.** Explain what changed and why, which platform(s) you tested on, and confirm the test suite passed locally.
- **One platform handler per PR** if you're adding desktop support — easier to review and revert if something breaks on a platform the maintainer can't reproduce.

---

## Code style

- Bash only (no Python, no Node, no dependencies beyond `bash`, `git`, and the terminal binary being spawned).
- `set -euo pipefail` at the top of every script.
- Quote every variable expansion. Shellcheck will remind you.
- Use the helpers in `scripts/lib.sh` for reading/writing STATE — don't parse STATE files ad-hoc in skill scripts.
- Keep functions short. If a function is getting long, it's probably doing two things.

---

## Licensing

By submitting a PR you agree that your contribution will be licensed under the same [Apache-2.0](LICENSE) license as the rest of the project.

Questions? Open an issue or email frank.ryanm@gmail.com.
