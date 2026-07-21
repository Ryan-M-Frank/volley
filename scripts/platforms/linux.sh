#!/usr/bin/env bash
# Linux handler for scripts/spawn-codex.sh. Sourced by the dispatcher; exposes
# spawn_linux(). Tries a desktop terminal (gnome-terminal, then kitty); if none
# is present (headless/SSH), delegates to the tmux handler.

spawn_linux() {
  local prompt_file="$1" title="$2"
  local prompt_abs repo_root
  prompt_abs=$(cd "$(dirname "$prompt_file")" && pwd)/$(basename "$prompt_file")
  repo_root=$(pwd)
  local qpath qrepo
  qpath=$(printf %q "$prompt_abs")
  qrepo=$(printf %q "$repo_root")
  # VOLLEY_CODEX_FLAGS (optional): validated `-m`/`-c model_reasoning_effort=`
  # tokens from the dispatcher. Bare identifiers only, so unquoted is safe.
  local inner="cat ${qpath} | codex exec ${VOLLEY_CODEX_FLAGS:-} --sandbox ${VOLLEY_CODEX_SANDBOX:-workspace-write} -C ${qrepo} -c approval_policy=never; exec bash"

  if command -v gnome-terminal >/dev/null; then
    gnome-terminal --title "${title}" -- bash -c "${inner}" &
    echo "linux:gnome-terminal:$!"
    return 0
  fi
  if command -v kitty >/dev/null; then
    kitty --title "${title}" bash -c "${inner}" &
    echo "linux:kitty:$!"
    return 0
  fi

  # No desktop terminal - fall back to the tmux handler (headless path).
  local here; here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  if [ -f "${here}/tmux.sh" ] && command -v tmux >/dev/null; then
    . "${here}/tmux.sh"
    spawn_tmux "$prompt_file" "$title"
    return $?
  fi

  echo "ERROR: no supported terminal (gnome-terminal/kitty) and no tmux. Install one, or set VOLLEY_PLATFORM=tmux after installing tmux." >&2
  return 127
}
