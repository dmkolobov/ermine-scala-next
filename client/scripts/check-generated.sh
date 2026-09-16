#!/usr/bin/env bash
# The CI equality check of design note section 3.5: regenerate the zod into a temp
# directory and diff it against the committed src/generated.  Exits 0 when they are
# byte-identical, 1 with the diff otherwise.
#
#   client/scripts/check-generated.sh
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
client="$(dirname "$here")"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

"$here/generate.sh" "$tmp" > /dev/null

if diff -ru "$client/src/generated" "$tmp"; then
  echo "check-generated: src/generated is up to date"
else
  echo "check-generated: src/generated is STALE -- run client/scripts/generate.sh" >&2
  exit 1
fi
