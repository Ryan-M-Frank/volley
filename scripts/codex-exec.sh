#!/usr/bin/env bash
# Run one read-only Codex review turn via `codex exec` and capture its session id.
#
# Why this exists: Codex 0.156 removed `codex mcp-server`, which Volley's bundled MCP bridge used.
# Every review (/volley:review-plan, /volley:review-pr, the /volley:setup smoke test) now goes through
# this script instead. It keeps the v0.2 guarantees: read-only sandbox, validated model/effort tokens,
# repo-rooted cwd, and continuity through a saved session id (`codex exec resume <id>`).
#
# Usage:
#   bash scripts/codex-exec.sh --prompt-file <file> --out <file> [--cwd <repo root>]
#                              [--model <m|inherit>] [--effort <e|inherit>] [--resume <session-id>]
#
# Prints, as its last lines:
#   SESSION_ID=<uuid>            (empty if Codex reported none)
#   CONTINUITY=fresh | resumed | fallback:resume-failed | fallback:invalid-session-id
# The full --json event stream is saved to "<out>.events.jsonl".
#
# Exit codes: 0 ok; 2 usage/config error (Codex not called); 3 Codex succeeded but wrote no review;
# otherwise Codex's own exit code. VOLLEY_CODEX_BIN overrides the codex binary (tests use a fake).

set -u
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib.sh
. "$here/lib.sh"

prompt="" out="" cwd="" model="" effort="" resume=""
while [ $# -gt 0 ]; do
  case "$1" in
    --prompt-file) prompt="${2:-}"; shift 2 ;;
    --out)         out="${2:-}";    shift 2 ;;
    --cwd)         cwd="${2:-}";    shift 2 ;;
    --model)       model="${2:-}";  shift 2 ;;
    --effort)      effort="${2:-}"; shift 2 ;;
    --resume)      resume="${2:-}"; shift 2 ;;
    *) echo "ERROR: unknown argument: $1" >&2; exit 2 ;;
  esac
done

[ -n "$prompt" ] && [ -f "$prompt" ] || { echo "ERROR: --prompt-file missing or not found: ${prompt:-<none>}" >&2; exit 2; }
[ -n "$out" ] || { echo "ERROR: --out is required" >&2; exit 2; }
if [ -z "$cwd" ]; then cwd=$(volley_repo_root) || true; fi
[ -n "$cwd" ] && [ -d "$cwd" ] || { echo "ERROR: --cwd missing and not inside a git repo" >&2; exit 2; }

flags=$(volley_codex_flags "$model" "$effort") || exit 2
bin="${VOLLEY_CODEX_BIN:-codex}"
events="${out}.events.jsonl"
mkdir -p "$(dirname "$out")"
rm -f "$out"

# $flags holds only validated bare tokens (see volley_codex_flags), so word-splitting it is safe.
run_fresh() {
  # shellcheck disable=SC2086
  "$bin" exec $flags --sandbox read-only -C "$cwd" --json -o "$out" - < "$prompt" > "$events"
}
run_resume() {
  # `exec resume` accepts neither --sandbox nor -C: enforce read-only through config and run from the repo.
  # shellcheck disable=SC2086
  ( cd "$cwd" && "$bin" exec resume $flags -c 'sandbox_mode="read-only"' --json -o "$out" "$resume" - < "$prompt" > "$events" )
}

continuity="fresh"
if [ -n "$resume" ]; then
  if printf '%s' "$resume" | grep -Eq '^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$'; then
    if run_resume; then
      continuity="resumed"
    else
      echo "WARN: resuming session $resume failed; starting a fresh session (context comes from files)." >&2
      continuity="fallback:resume-failed"
      run_fresh; rc=$?
      [ "$rc" -eq 0 ] || { echo "ERROR: codex exec failed (exit $rc)" >&2; exit "$rc"; }
    fi
  else
    echo "WARN: saved session id is not a UUID; ignoring it and starting fresh." >&2
    continuity="fallback:invalid-session-id"
    run_fresh; rc=$?
    [ "$rc" -eq 0 ] || { echo "ERROR: codex exec failed (exit $rc)" >&2; exit "$rc"; }
  fi
else
  run_fresh; rc=$?
  [ "$rc" -eq 0 ] || { echo "ERROR: codex exec failed (exit $rc)" >&2; exit "$rc"; }
fi

[ -s "$out" ] || { echo "ERROR: Codex finished but wrote no review to $out" >&2; exit 3; }

sid=$(volley_session_id_from_jsonl "$events" 2>/dev/null) || sid=""
[ -n "$sid" ] || echo "WARN: no session id in Codex output; the next review will start fresh." >&2
echo "SESSION_ID=$sid"
echo "CONTINUITY=$continuity"
