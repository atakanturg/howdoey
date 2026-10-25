#!/bin/bash
set -euo pipefail
DESKTOP_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [ ! -d "$DESKTOP_ROOT/dist/Howdoey.app" ]; then "$DESKTOP_ROOT/scripts/package.sh"; fi
open "$DESKTOP_ROOT/dist/Howdoey.app"
