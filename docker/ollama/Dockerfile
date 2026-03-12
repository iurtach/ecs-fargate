FROM ollama/ollama:latest

EXPOSE 11434

ENV OLLAMA_HOST=0.0.0.0
ENV OLLAMA_NUM_PARALLEL=2
ENV MODEL_NAME=llama3.2:1b

COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

HEALTHCHECK --interval=30s --timeout=10s --start-period=300s --retries=5 \
  CMD curl -f http://localhost:11434/api/version || exit 1

ENTRYPOINT ["/bin/bash", "/entrypoint.sh"]