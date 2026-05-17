#!/usr/bin/env bash
set -Eeuo pipefail

log() {
  printf '%s [startup] %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$*" >&2
}

PORT="${PORT:-8080}"
OLLAMA_MODEL="${OLLAMA_MODEL:-qwen2.5:7b}"
export OLLAMA_HOST="${OLLAMA_HOST:-0.0.0.0:${PORT}}"

MAX_PULL_ATTEMPTS="${MAX_PULL_ATTEMPTS:-5}"
PULL_RETRY_DELAY_SECONDS="${PULL_RETRY_DELAY_SECONDS:-15}"
HEALTH_RETRIES="${HEALTH_RETRIES:-90}"
HEALTH_RETRY_DELAY_SECONDS="${HEALTH_RETRY_DELAY_SECONDS:-2}"

shutdown() {
  log "Shutdown signal received"
  if [[ -n "${OLLAMA_PID:-}" ]] && kill -0 "${OLLAMA_PID}" >/dev/null 2>&1; then
    kill "${OLLAMA_PID}" || true
    wait "${OLLAMA_PID}" || true
  fi
}

trap shutdown SIGTERM SIGINT

wait_for_health() {
  local attempt
  for ((attempt = 1; attempt <= HEALTH_RETRIES; attempt++)); do
    if /usr/local/bin/healthcheck.sh >/dev/null 2>&1; then
      log "Ollama health check passed"
      return 0
    fi
    log "Waiting for Ollama to become healthy (${attempt}/${HEALTH_RETRIES})"
    sleep "${HEALTH_RETRY_DELAY_SECONDS}"
  done

  log "Ollama failed health check before timeout"
  return 1
}

pull_model_with_retries() {
  local attempt
  for ((attempt = 1; attempt <= MAX_PULL_ATTEMPTS; attempt++)); do
    log "Pulling model ${OLLAMA_MODEL} (attempt ${attempt}/${MAX_PULL_ATTEMPTS})"
    if ollama pull "${OLLAMA_MODEL}"; then
      log "Model ${OLLAMA_MODEL} pulled successfully"
      return 0
    fi
    log "Model pull failed, retrying in ${PULL_RETRY_DELAY_SECONDS}s"
    sleep "${PULL_RETRY_DELAY_SECONDS}"
  done

  log "Model pull failed after ${MAX_PULL_ATTEMPTS} attempts"
  return 1
}

log "Starting Ollama server on ${OLLAMA_HOST}"
ollama serve &
OLLAMA_PID="$!"

if ! wait_for_health; then
  kill "${OLLAMA_PID}" || true
  wait "${OLLAMA_PID}" || true
  exit 1
fi

if ! pull_model_with_retries; then
  kill "${OLLAMA_PID}" || true
  wait "${OLLAMA_PID}" || true
  exit 1
fi

log "Startup completed successfully"
wait "${OLLAMA_PID}"
