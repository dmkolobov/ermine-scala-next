#!/bin/sh
# WP-33: a shim for callers that still name this script; the generator is generate.js (node, any platform).
exec node "$(dirname "$0")/generate.js" "$@"
