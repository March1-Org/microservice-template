#!/bin/bash

# Load environment variables
if [ -f .env ]; then
  source .env
else
  echo "Error: .env file not found."
  exit 1
fi

# Generate init.sql from the template
.test/utils/generate-init.sh

# Create Docker volume for PostgreSQL data
docker volume create postgres_data

# Start the PostgreSQL container
DB_CONTAINER_ID=$(docker run -d \
  -e POSTGRES_USER="$POSTGRES_USER" \
  -e POSTGRES_PASSWORD="$POSTGRES_PASSWORD" \
  -e POSTGRES_DB="$POSTGRES_DB" \
  -p 5432:5432 \
  -v postgres_data:/var/lib/postgresql/data \
  -v $(pwd)/init.sql:/docker-entrypoint-initdb.d/init.sql \
  postgres:latest)

if [ -z "$DB_CONTAINER_ID" ]; then
  echo "Failed to start the database container."
  exit 1
fi

echo $DB_CONTAINER_ID

# Start the Redis container
CACHE_CONTAINER_ID=$(docker run -d \
  -e REDIS_PASSWORD="$REDIS_PASSWORD" \
  -p 6379:6379 \
  bitnami/redis:latest)

if [ -z "$CACHE_CONTAINER_ID" ]; then
  echo "Failed to start the cache container."
  exit 1
fi

echo $CACHE_CONTAINER_ID

# Wait for the database to start
echo "Waiting for the database to start..."
for i in {1..30}; do
  if docker exec $DB_CONTAINER_ID pg_isready -U $POSTGRES_USER -d $POSTGRES_DB; then
    echo "Database is ready!"
    break
  fi
  sleep 1
done


# Migrate SQL files from ./drizzle folder
echo "Migrating SQL files from ./drizzle folder..."
for sql_file in ./drizzle/*.sql; do
  if [ -f "$sql_file" ]; then
    echo "Executing $sql_file..."
    docker exec -i $DB_CONTAINER_ID psql -U $POSTGRES_USER -d $POSTGRES_DB -f - < "$sql_file"
    if [ $? -eq 0 ]; then
      echo "$sql_file migrated successfully."
    else
      echo "Failed to migrate $sql_file."
      exit 1
    fi
  else
    echo "No SQL files found in ./drizzle folder."
    exit 1
  fi
done


# Run tests
echo "Running tests..."
export PATH="$HOME/.bun/bin:$PATH" # Ensure Bun is in PATH
bun test

# Stop and remove containers
echo "Stopping and removing containers..."
docker stop $DB_CONTAINER_ID
docker rm $DB_CONTAINER_ID
docker stop $CACHE_CONTAINER_ID
docker rm $CACHE_CONTAINER_ID