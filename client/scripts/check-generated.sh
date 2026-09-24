#!/usr/bin/env bash
# The CI equality check of design note section 3.5: regenerate the zod into a temp
# file (one JVM, client/scripts/generate.sh) and diff it against the committed
# src/generated/widgets.ts.  Exits 0 when they are byte-identical, 1 with the diff
# otherwise.  scripts/check-fresh.js is the JVM-free half (hashes + exactness
# probe) that the `generated` and `client` gates run.
#
#   client/scripts/check-generated.sh
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
client="$(dirname "$here")"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

"$here/generate.sh" "$tmp/widgets.ts" > /dev/null

if diff -u "$client/src/generated/widgets.ts" "$tmp/widgets.ts"; then
  echo "check-generated: src/generated/widgets.ts is up to date"
else
  echo "check-generated: src/generated/widgets.ts is STALE -- run client/scripts/generate.sh" >&2
  exit 1
fi
