#!/usr/bin/env bash
# Property (b), the cross-language check, from a clean checkout:
#
#   client/scripts/check-corpus.sh [<corpus dir>]
#
# With no argument it WRITES the corpus first (200 documents plus the end-to-end
# report document) with sbt, then installs with `npm ci`, builds, and runs the
# whole node test suite against it.  With a directory that already holds a
# manifest.json it skips the sbt half.
#
# Everything it needs beyond this repo: the ermine-writers checkout (for the
# legacy formatDisplay agreement property), found beside this one or named by
# $ERMINE_WRITERS.
set -euo pipefail
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
client="$(dirname "$here")"
repo="$(dirname "$client")"

corpus="${1:-$repo/target/widget-corpus}"
report="${ERMINE_REPORT_DOC:-$repo/target/sales-report.json}"

if [[ ! -s "$corpus/manifest.json" ]]; then
  echo "== writing the corpus with sbt into $corpus"
  ( cd "$repo" && sbt -batch \
      "core/Test/runMain com.clarifi.reporting.WidgetCorpus $corpus 200" \
      "core/Test/runMain com.clarifi.reporting.SalesReportDoc $report" )
fi

echo "== npm ci"
( cd "$client" && npm ci --no-audit --no-fund )

echo "== tsc"
( cd "$client" && npx tsc -p tsconfig.json )

echo "== node --test (corpus $corpus)"
( cd "$client" && ERMINE_CORPUS="$corpus" ERMINE_REPORT_DOC="$report" node --test "dist/test/*.test.js" )
