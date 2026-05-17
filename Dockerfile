FROM ollama/ollama:latest

SHELL ["/bin/bash", "-c"]

ENV OLLAMA_MODEL="qwen2.5:7b" \
    PORT="8080" \
    OLLAMA_HOST="0.0.0.0:8080" \
    OLLAMA_KEEP_ALIVE="30m" \
    OLLAMA_NUM_PARALLEL="4" \
    OLLAMA_MAX_QUEUE="512"

COPY scripts/start.sh /usr/local/bin/start.sh
COPY scripts/healthcheck.sh /usr/local/bin/healthcheck.sh

RUN chmod +x /usr/local/bin/start.sh /usr/local/bin/healthcheck.sh

EXPOSE 8080

HEALTHCHECK --interval=30s --timeout=10s --start-period=120s --retries=6 \
  CMD /usr/local/bin/healthcheck.sh

ENTRYPOINT ["/usr/local/bin/start.sh"]
