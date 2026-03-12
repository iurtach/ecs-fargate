#!/bin/bash
set -e

MODEL_NAME="${MODEL_NAME:-llama3.2:1b}"

echo "[entrypoint] Starting Ollama server..."
/bin/ollama serve &
OLLAMA_PID=$!

# Wait for the server to be ready
echo "[entrypoint] Waiting for Ollama to become ready..."
for i in $(seq 1 30); do
  if curl -sf http://localhost:11434/api/version > /dev/null 2>&1; then
    echo "[entrypoint] Ollama is ready."
    break
  fi
  echo "[entrypoint] Attempt $i/30 — not ready yet, retrying in 5s..."
  sleep 5
done

# Pull the model if it doesn't exist locally
if ! ollama list | grep -q "$MODEL_NAME"; then
  echo "[entrypoint] Pulling model: $MODEL_NAME"
  ollama pull "$MODEL_NAME"
  echo "[entrypoint] Model pulled successfully."
else
  echo "[entrypoint] Model $MODEL_NAME already present."
fi

echo "[entrypoint] Ollama is fully initialized."
wait $OLLAMA_PID
