# Ollama on Google Cloud Run (Qwen 2.5:7b)

This repository contains a production-focused container and deployment scripts to run Ollama as a remote LLM service on Google Cloud Run, with `qwen2.5:7b` auto-pulled at startup.

## What is included

- `Dockerfile`: Uses `ollama/ollama:latest` and starts Ollama with health checks.
- `scripts/start.sh`: Boots Ollama, waits for health, auto-pulls `qwen2.5:7b`, retries on transient failures, and logs startup progress.
- `scripts/healthcheck.sh`: Health probe script used by Docker health checks.
- `deploy/deploy-cloud-run.sh`: Builds and deploys to Cloud Run with 32 GiB RAM, 8 vCPUs, and min 1 instance.
- `deploy/test-openai-api.sh`: Tests health plus OpenAI-compatible endpoints.

## Architecture Notes

- Service listens on Cloud Run port `8080`.
- `PORT` is provided by Cloud Run automatically (do not set it via `--set-env-vars`).
- Ollama defaults to `OLLAMA_NUM_PARALLEL=8` so it can use the full 8 vCPU allocation on Cloud Run.
- Model auto-pull happens on startup (`OLLAMA_MODEL=qwen2.5:7b`).
- Startup script includes retry logic and clear structured log messages.
- Container has an internal health check against `/api/tags`.

## Prerequisites

- Google Cloud project with billing enabled
- `gcloud` CLI authenticated (`gcloud auth login`)
- APIs enabled:

```bash
gcloud services enable run.googleapis.com cloudbuild.googleapis.com artifactregistry.googleapis.com
```

## Deploy to Cloud Run

Set your project first:

```bash
gcloud config set project YOUR_PROJECT_ID
```

Run the deployment script:

```bash
chmod +x deploy/deploy-cloud-run.sh
./deploy/deploy-cloud-run.sh
```

### Deploy with GitHub Actions

This repository includes an automated deployment workflow:

- Workflow file: `.github/workflows/deploy-cloud-run.yml`
- Trigger: push to `main` when deployment-related files change, plus manual `workflow_dispatch`
- Auth: Google Cloud Service Account JSON key from GitHub secret

Configure GitHub repository settings before first run:

1. Add repository secret:
	- `GCP_PROJECT_ID`: Google Cloud project ID.
	- `GCP_SA_KEY`: full JSON key for a service account with Cloud Run/Cloud Build/Artifact Registry permissions.
2. Add repository variables:
	- `GCP_REGION` (optional, default: `us-central1`)
	- `GCP_SERVICE_NAME` (optional, default: `ollama-qwen25-7b`)
	- `GCP_ARTIFACT_REGISTRY_REPOSITORY` (optional, default: `ollama`)

Recommended service account roles:

- `roles/run.admin`
- `roles/iam.serviceAccountUser`
- `roles/cloudbuild.builds.editor`
- `roles/artifactregistry.admin` (or `roles/artifactregistry.writer` if repository already exists)

Manual run from GitHub UI:

1. Open Actions.
2. Select `Deploy Ollama to Cloud Run`.
3. Click `Run workflow`.

The workflow performs config validation, authenticates to Google Cloud, runs `deploy/deploy-cloud-run.sh`, and smoke-tests `/api/tags`.

This deploys with:

- Memory: `32Gi`
- CPU: `8`
- Minimum instances: `1`
- Execution environment: `gen2`
- CPU always allocated (`--no-cpu-throttling`)

Optional environment overrides:

```bash
PROJECT_ID=YOUR_PROJECT_ID REGION=us-central1 SERVICE_NAME=ollama-qwen25-7b ./deploy/deploy-cloud-run.sh
```

### Equivalent direct Cloud Run command

```bash
gcloud run deploy ollama-qwen25-7b \
	--image REGION-docker.pkg.dev/PROJECT_ID/ollama/ollama-qwen25-7b:latest \
	--region REGION \
	--platform managed \
	--execution-environment gen2 \
	--memory 32Gi \
	--cpu 8 \
	--min-instances 1 \
	--max-instances 3 \
	--concurrency 8 \
	--timeout 3600 \
	--port 8080 \
	--cpu-boost \
	--no-cpu-throttling \
	--set-env-vars OLLAMA_MODEL=qwen2.5:7b \
	--allow-unauthenticated
```

## Health checks and logs

- Health endpoint: `GET /api/tags`
- OpenAI-compatible model listing: `GET /v1/models`
- Cloud logs:

```bash
gcloud run services logs read ollama-qwen25-7b --region REGION --limit 200
```

## OpenAI-compatible API testing examples

Assume:

- `SERVICE_URL=https://YOUR_SERVICE_URL`
- `API_KEY=dummy-key` (Ollama does not require a real key by default)

### Quick script

```bash
chmod +x deploy/test-openai-api.sh
./deploy/test-openai-api.sh "$SERVICE_URL" "$API_KEY"
```

### cURL: list models

```bash
curl -sS "$SERVICE_URL/v1/models" \
	-H "Authorization: Bearer $API_KEY" \
	-H "Content-Type: application/json"
```

### cURL: chat completions

```bash
curl -sS "$SERVICE_URL/v1/chat/completions" \
	-H "Authorization: Bearer $API_KEY" \
	-H "Content-Type: application/json" \
	-d '{
		"model": "qwen2.5:7b",
		"messages": [
			{"role": "system", "content": "You are concise."},
			{"role": "user", "content": "Say hello from Cloud Run."}
		],
		"temperature": 0.2
	}'
```

## FastAPI client integration

You can connect a FastAPI service to this Cloud Run-hosted Ollama instance using the OpenAI Python client with a custom `base_url`.

Install dependencies:

```bash
pip install fastapi uvicorn openai httpx
```

Example `fastapi_client.py`:

```python
import logging
import os

from fastapi import FastAPI, HTTPException
from openai import OpenAI

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("fastapi-ollama-client")

OLLAMA_BASE_URL = os.getenv("OLLAMA_BASE_URL", "https://YOUR_SERVICE_URL/v1")
OLLAMA_API_KEY = os.getenv("OLLAMA_API_KEY", "dummy-key")
MODEL_NAME = os.getenv("MODEL_NAME", "qwen2.5:7b")

client = OpenAI(base_url=OLLAMA_BASE_URL, api_key=OLLAMA_API_KEY)
app = FastAPI()


@app.get("/healthz")
def healthz() -> dict:
		try:
				models = client.models.list()
				return {"ok": True, "model_count": len(models.data)}
		except Exception as exc:
				logger.exception("Health check to Ollama failed")
				raise HTTPException(status_code=503, detail=f"Upstream unavailable: {exc}")


@app.post("/ask")
def ask(prompt: str) -> dict:
		try:
				resp = client.chat.completions.create(
						model=MODEL_NAME,
						messages=[{"role": "user", "content": prompt}],
						temperature=0.2,
				)
				answer = resp.choices[0].message.content if resp.choices else ""
				return {"answer": answer}
		except Exception as exc:
				logger.exception("Chat completion request failed")
				raise HTTPException(status_code=502, detail=f"Ollama request failed: {exc}")
```

Run locally:

```bash
export OLLAMA_BASE_URL="https://YOUR_SERVICE_URL/v1"
export OLLAMA_API_KEY="dummy-key"
uvicorn fastapi_client:app --host 0.0.0.0 --port 8000
```

## Operational recommendations

- Restrict access using IAM (`--no-allow-unauthenticated`) for private deployments.
- Put Cloud Run behind API Gateway or Load Balancer if you need auth, quotas, or WAF.
- Monitor p95/p99 latency and memory usage; increase max instances for burst traffic.
- Keep model warm by using min instances (`1` configured by default).