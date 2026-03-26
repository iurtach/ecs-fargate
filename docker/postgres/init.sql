-- Runs once on first startup (when EFS data directory is empty).
-- Enables the pgvector extension so the web service can store embeddings.
CREATE EXTENSION IF NOT EXISTS vector;
