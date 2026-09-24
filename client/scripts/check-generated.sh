#!/bin/sh
# WP-33: a shim for callers that still name this script; the check is check-generated.js (node, any platform).
exec node "$(dirname "$0")/check-generated.js" "$@"
