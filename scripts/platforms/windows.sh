#!/usr/bin/env bash
# Windows handler for scripts/spawn-codex.sh.
#
# Sourced by the dispatcher; exposes one function: spawn_windows().
# Opens a Windows Terminal tab running `codex exec` with the prompt streamed
# in via stdin. See ../spawn-codex.sh for cross-platform rationale and the
# stdin-vs-argv justification.

spawn_windows() {
  local prompt_file="$1" title="$2"

  command -v wt >/dev/null || {
    echo "ERROR: wt (Windows Terminal) not found in PATH. Install Windows Terminal to use /volley:implement on Windows." >&2
    return 127
  }
  command -v cygpath >/dev/null || {
    echo "ERROR: cygpath not found. /volley:implement runs from Git Bash on Windows; cygpath ships with Git for Windows." >&2
    return 127
  }

  # Resolve to a Windows-style path so PowerShell can read it from any cwd.
  local prompt_win
  prompt_win=$(cygpath -w "$prompt_file")

  # Escape single quotes for safe embedding in a PowerShell single-quoted literal.
  local escaped
  escaped=$(printf %s "$prompt_win" | sed "s/'/''/g")

  # Stream the file through stdin to `codex exec`. Only this short literal
  # command line is constructed by CreateProcess; the prompt content itself
  # is read by Get-Content and piped, so no argv length limit applies.
  local ps_cmd="Get-Content -Raw '${escaped}' | codex exec"

  # -w 0 targets the current wt window, nt opens a new tab. -NoExit keeps the
  # tab open after Codex finishes so the user can read the final output.
  # Backgrounded so we can capture wt's PID via $!.
  wt -w 0 nt --title "$title" -- powershell -NoExit -Command "$ps_cmd" &
  echo "$!"
}
