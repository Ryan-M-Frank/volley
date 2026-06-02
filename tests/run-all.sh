#!/usr/bin/env bash
# Run the full Volley test suite. Exits non-zero if any test fails.
# Globs test-*.sh (not *.sh) so it never recurses into itself.
set -u
here="$(cd "$(dirname "$0")" && pwd)"
fail=0
for t in "$here"/test-*.sh; do
  echo "== $(basename "$t") =="
  bash "$t" || fail=1
done
if [ "$fail" -eq 0 ]; then
  echo "ALL TESTS PASSED"
else
  echo "SOME TESTS FAILED" >&2
  exit 1
fi
