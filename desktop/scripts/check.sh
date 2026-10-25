#!/bin/bash
set -euo pipefail
DESKTOP_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
swift run --package-path "$DESKTOP_ROOT" HowdoeyChecks
swift build --package-path "$DESKTOP_ROOT" --product Howdoey

node --test "$DESKTOP_ROOT/relay/server.test.mjs"

node --test "$DESKTOP_ROOT/relay/claude-demo.test.mjs"
