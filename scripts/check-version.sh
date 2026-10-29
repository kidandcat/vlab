#!/usr/bin/env bash
# Fail unless the Lake package version, the newest changelog heading, and the
# string the server reports are the same SemVer. `## [Unreleased]` is skipped.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"

fail() {
  echo "check-version: $*" >&2
  exit 1
}

lake=$(sed -n 's/^[[:space:]]*version := v!"\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\)".*/\1/p' lakefile.lean)
change=$(sed -n 's/^## \[\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\)\].*/\1/p' CHANGELOG.md | head -n 1)
code=$(sed -n 's/^def version : String := "\([0-9][0-9]*\.[0-9][0-9]*\.[0-9][0-9]*\)".*/\1/p' Vlab/Version.lean)

[ -n "$lake" ] || fail "lakefile.lean has no version := v!\"X.Y.Z\""
[ "$(printf '%s\n' "$lake" | wc -l)" -eq 1 ] || fail "expected one lakefile version"
lake=$(printf '%s\n' "$lake" | head -n 1)
[ -n "$change" ] || fail "CHANGELOG.md has no ## [X.Y.Z] heading"
[ -n "$code" ] || fail "Vlab/Version.lean has no def version"
[ "$(printf '%s\n' "$code" | wc -l)" -eq 1 ] || fail "expected one code version"

if [ "$lake" != "$change" ] || [ "$lake" != "$code" ]; then
  fail "mismatch lakefile=$lake changelog=$change code=$code"
fi
echo "version ok $lake"
