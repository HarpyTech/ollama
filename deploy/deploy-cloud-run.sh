#!/usr/bin/env bash
set -Eeuo pipefail

log() {
  printf '%s [deploy] %s\n' "$(date -u +'%Y-%m-%dT%H:%M:%SZ')" "$*" >&2
}

require() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

require gcloud

PROJECT_ID="${PROJECT_ID:-$(gcloud config get-value project 2>/dev/null || true)}"
REGION="${REGION:-us-central1}"
SERVICE_NAME="${SERVICE_NAME:-ollama-qwen25-7b}"
REPOSITORY="${REPOSITORY:-ollama}"
MAX_INSTANCES="${MAX_INSTANCES:-3}"
CONCURRENCY="${CONCURRENCY:-8}"
TIMEOUT_SECONDS="${TIMEOUT_SECONDS:-3600}"
ALLOW_UNAUTHENTICATED="${ALLOW_UNAUTHENTICATED:-true}"

if [[ -z "${PROJECT_ID}" ]]; then
  echo "PROJECT_ID is required. Set PROJECT_ID or run: gcloud config set project <id>" >&2
  exit 1
fi

IMAGE_URI="${REGION}-docker.pkg.dev/${PROJECT_ID}/${REPOSITORY}/${SERVICE_NAME}:latest"

log "Ensuring Artifact Registry repository exists"
if ! gcloud artifacts repositories describe "${REPOSITORY}" --location "${REGION}" >/dev/null 2>&1; then
  gcloud artifacts repositories create "${REPOSITORY}" \
    --repository-format docker \
    --location "${REGION}" \
    --description "Ollama images"
fi

log "Building image ${IMAGE_URI}"
gcloud builds submit --tag "${IMAGE_URI}" .

DEPLOY_ARGS=(
  run deploy "${SERVICE_NAME}"
  --image "${IMAGE_URI}"
  --project "${PROJECT_ID}"
  --region "${REGION}"
  --platform managed
  --execution-environment gen2
  --memory 32Gi
  --cpu 8
  --min-instances 1
  --max-instances "${MAX_INSTANCES}"
  --concurrency "${CONCURRENCY}"
  --timeout "${TIMEOUT_SECONDS}"
  --port 8080
  --cpu-boost
  --no-cpu-throttling
  --set-env-vars "PORT=8080,OLLAMA_MODEL=qwen2.5:7b"
)

if [[ "${ALLOW_UNAUTHENTICATED}" == "true" ]]; then
  DEPLOY_ARGS+=(--allow-unauthenticated)
fi

log "Deploying Cloud Run service ${SERVICE_NAME}"
gcloud "${DEPLOY_ARGS[@]}"

SERVICE_URL="$(gcloud run services describe "${SERVICE_NAME}" --project "${PROJECT_ID}" --region "${REGION}" --format='value(status.url)')"

log "Deployment complete"
log "Service URL: ${SERVICE_URL}"
log "Health check: ${SERVICE_URL}/api/tags"
