#!/bin/bash
set -euo pipefail
DEMO_ROOT="$(mktemp -d "${TMPDIR:-/tmp/}Howdoey-Demo.XXXXXX")"
mkdir -p "$DEMO_ROOT/Inbox" "$DEMO_ROOT/Organized/Documents"
printf 'A disposable receipt for testing Howdoey.\n' > "$DEMO_ROOT/Inbox/receipt.txt"
printf 'An existing receipt that must not be overwritten.\n' > "$DEMO_ROOT/Organized/Documents/receipt.txt"
printf 'Choose source: %s\nChoose destination: %s\n' "$DEMO_ROOT/Inbox/receipt.txt" "$DEMO_ROOT/Organized"
open "$DEMO_ROOT/Inbox"
