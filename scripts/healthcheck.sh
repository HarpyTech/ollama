#!/usr/bin/env bash
set -Eeuo pipefail

PORT="${PORT:-8080}"
TARGET="http://127.0.0.1:${PORT}/api/tags"

if command -v curl >/dev/null 2>&1; then
  curl -fsS --max-time 5 "${TARGET}" >/dev/null
  exit 0
fi

if command -v wget >/dev/null 2>&1; then
  wget -q -T 5 -O /dev/null "${TARGET}"
  exit 0
fi

# Fallback when curl/wget are unavailable: check that the TCP port is open.
exec 3<>"/dev/tcp/127.0.0.1/${PORT}"
exec 3<&-
exec 3>&-
