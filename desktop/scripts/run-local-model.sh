#!/bin/bash
set -euo pipefail
# Start the installed Ollama server for Howdoey's on-device testing.
# Download a model separately with: ollama pull qwen3.5:4b
if ! command -v ollama >/dev/null 2>&1; then
    printf 'Install Ollama from https://ollama.com/download/mac first.\n' >&2
    exit 1
fi
if curl --fail --silent --max-time 2 http://127.0.0.1:11434/api/version >/dev/null; then
    printf 'Ollama is already running on localhost:11434.\n'
    exit 0
fi
export OLLAMA_HOST=127.0.0.1:11434
export OLLAMA_CONTEXT_LENGTH=8192
export OLLAMA_NO_CLOUD=true
export OLLAMA_DEBUG_LOG_REQUESTS=false
exec ollama serve
