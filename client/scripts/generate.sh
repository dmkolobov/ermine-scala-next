#!/usr/bin/env bash
# Regenerate client/src/generated/widgets.ts from the Ermine declarations: ONE
# `bin/ermine-schema --widgets` call (one JVM, about five seconds) that scans
# Layout.Widgets and every module under Layout/Widgets/ for `WidgetName T` terms
# and writes every props schema, WidgetRegistry, WidgetName, WIDGET_PROP_SCHEMAS
# and UNSUPPORTED_WIDGETS; Layout.Doc's Node and Tab ride along for the document
# parser.  Nothing in the output is edited by hand.
#
#   client/scripts/generate.sh [<output file>]
#
# Needs `java` on PATH (bin/ermine-schema execs it).
#
# The file starts with THIS script's lines: the sha256 of the generator's own
# Scala (`// generator sha256 <hex> <path from the repo root>`), which
# scripts/check-fresh.js compares, so a generator change makes the committed file
# stale even though no .e file moved; then `// body sha256: <hex>`, the hash of
# everything below it, so a hand edit of the generated text is caught too.  Below them is bin/ermine-schema's header:
# the exact command and the sha256 of every .e file the run read
# (`// sha256 <hex> <path under core/src/main/resources/modules>`), which the same
# script recomputes.  scripts/check-generated.sh regenerates and diffs (JVM).
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
client="$(dirname "$here")"
repo="$(dirname "$client")"
out="${1:-$client/src/generated/widgets.ts}"

# The generator's own sources: a change to any of these can change the output.
generator=(
  core/src/main/scala/com/clarifi/reporting/ermine/json/Schema.scala
  core/src/main/scala/com/clarifi/reporting/ermine/json/SchemaMain.scala
  core/src/main/scala/com/clarifi/reporting/ermine/json/Zod.scala
)

tmp="$(mktemp)"; body="$(mktemp)"
trap 'rm -f "$tmp" "$body"' EXIT
(cd "$repo" && bin/ermine-schema --widgets Layout.Widgets Layout.Doc:Node=DocNode Layout.Doc:Tab=DocTab) > "$body"
# keep the file newline-terminated whatever the generator printed last
[ -n "$(tail -c 1 "$body")" ] && printf '\n' >> "$body"
{
  echo "// Written by client/scripts/generate.sh -- do not edit; run it again instead."
  for f in "${generator[@]}"; do
    echo "// generator sha256 $(sha256sum "$repo/$f" | cut -d' ' -f1) $f"
  done
  # the sha256 of everything BELOW this line, as the generator printed it: a hand
  # edit anywhere in the body fails scripts/check-fresh.js (WP-32 S2 review M-1)
  echo "// body sha256: $(sha256sum "$body" | cut -d' ' -f1)"
  cat "$body"
} > "$tmp"
mkdir -p "$(dirname "$out")"
mv "$tmp" "$out"
trap - EXIT
rm -f "$body"
echo "generated $out ($(grep -c '^  [A-Za-z]*: [A-Za-z]*Props;$' "$out") widget names)"
