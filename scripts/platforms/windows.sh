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

  # Resolve to absolute Windows-style paths so PowerShell can read them from
  # any cwd. -wa = Windows path + absolutize (plain -w does NOT absolutize).
  local prompt_win cwd_win
  prompt_win=$(cygpath -wa "$prompt_file")
  cwd_win=$(cygpath -wa "$(pwd)")

  # Escape single quotes for safe embedding in a PowerShell single-quoted literal.
  local escaped cwd_escaped
  escaped=$(printf %s "$prompt_win" | sed "s/'/''/g")
  cwd_escaped=$(printf %s "$cwd_win" | sed "s/'/''/g")

  # Stream the file through stdin to `codex exec`.
  # -C pins Codex's cwd to the repo root (spawned terminals open in ~).
  # -c approval_policy=never prevents interactive approval prompts in a
  #    non-interactive tab from blocking forever.
  # No `;` separator — wt treats `;` as an action delimiter.
  local ps_cmd="Get-Content -Raw '${escaped}' | codex exec --sandbox ${VOLLEY_CODEX_SANDBOX:-workspace-write} -C '${cwd_escaped}' -c approval_policy=never"

  # -w 0 targets the current wt window, nt opens a new tab. -NoExit keeps the
  # tab open after Codex finishes so the user can read the final output.
  # -NoProfile speeds up launch and avoids profile side-effects.
  # Backgrounded so we can capture wt's PID via $!.
  wt -w 0 nt --title "$title" -- powershell -NoProfile -NoExit -Command "$ps_cmd" &
  echo "$!"
}
