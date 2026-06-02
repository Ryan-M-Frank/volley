## What and why

<!-- Describe the change and the reason for it. Link any related issue (e.g. "Fixes #42"). -->

## Tests run locally

<!-- Confirm the full suite passed: -->
```
for t in tests/*.sh; do bash "$t"; done
```
- [ ] All test scripts exited 0 and printed `FAIL=0`

## CI

- [ ] All CI jobs are green (test matrix, shellcheck, leak-scan, validate)

## Platform(s) tested on

<!-- Check every platform you actually ran /volley:implement on. For changes that only affect MCP-based skills or lock logic, checking "not applicable" is fine. -->

- [ ] Windows (Windows Terminal + Git Bash)
- [ ] macOS (specify terminal: iTerm2 / Terminal.app / other: _____)
- [ ] Linux desktop (specify terminal: gnome-terminal / kitty / wezterm / other: _____)
- [ ] tmux (specify OS: _____)
- [ ] Not applicable (change does not touch spawn or platform handlers)

## Docs updated

- [ ] CONTRIBUTING.md updated if I changed how platform handlers work or how tests are run
- [ ] README.md updated if I changed the skill list, requirements, or platform support table
- [ ] Not needed
