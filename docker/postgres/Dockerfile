# pgvector/pgvector:pg15 is postgres:15 with pgvector already installed.
# No compilation needed — maintained by the pgvector team.
FROM pgvector/pgvector:pg15

# This script runs once when the database is first initialized (empty EFS).
# It enables the pgvector extension in the database.
COPY init.sql /docker-entrypoint-initdb.d/01-init.sql
