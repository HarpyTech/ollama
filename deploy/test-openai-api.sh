#!/usr/bin/env bash
set -Eeuo pipefail

if [[ $# -lt 1 ]]; then
  echo "Usage: $0 <SERVICE_URL> [API_KEY]" >&2
  echo "Example: $0 https://ollama-qwen25-7b-xxxxx-uc.a.run.app dummy-key" >&2
  exit 1
fi

SERVICE_URL="${1%/}"
API_KEY="${2:-dummy-key}"
MODEL="${MODEL:-qwen2.5:7b}"

log() {
  printf '%s [test] %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$*" >&2
}

log "Checking health endpoint"
curl -fsS "${SERVICE_URL}/api/tags" | sed -e 's/{/\n{/g' | head -n 20

log "Listing OpenAI-compatible models"
curl -fsS "${SERVICE_URL}/v1/models" \
  -H "Authorization: Bearer ${API_KEY}" \
  -H "Content-Type: application/json" | head -c 1200 && echo

log "Sending OpenAI-compatible chat completion request"
curl -fsS "${SERVICE_URL}/v1/chat/completions" \
  -H "Authorization: Bearer ${API_KEY}" \
  -H "Content-Type: application/json" \
  -d "{\"model\":\"${MODEL}\",\"messages\":[{\"role\":\"system\",\"content\":\"You are concise.\"},{\"role\":\"user\",\"content\":\"Reply with: Cloud Run OK\"}],\"temperature\":0}" | head -c 2000 && echo
