#!/bin/bash
set -euo pipefail

# Sync local dev database to production
# Usage: ./scripts/sync-db-to-prod.sh [user@host]
#
# Dumps the local dev DB, uploads to the server, and restores
# into the production database. Idempotent — safe to run repeatedly.

HOST="${1:-root@5.161.181.91}"
DUMP_FILE="/tmp/archive_classifier_dump.backup"
REMOTE_DUMP="/tmp/archive_classifier_dump.backup"
PROD_DB="archive_classifier_prod"
DB_USER="blog"

echo "==> Dumping local dev database..."
pg_dump -h localhost -U postgres -d archive_classifier_dev \
  --no-owner --no-acl -F c -f "$DUMP_FILE"
echo "  $(du -h "$DUMP_FILE" | cut -f1) dumped"

echo "==> Uploading to $HOST..."
scp "$DUMP_FILE" "$HOST:$REMOTE_DUMP"

echo "==> Restoring on production..."
ssh "$HOST" bash -s <<REMOTE
  set -euo pipefail
  cd /opt/blog

  # Ensure the database exists
  docker compose exec -T db psql -U $DB_USER -d blog_prod -c \
    "SELECT 'CREATE DATABASE $PROD_DB' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = '$PROD_DB')\\gexec" \
    2>/dev/null || true

  # Copy dump into the container
  docker compose cp "$REMOTE_DUMP" db:/tmp/dump.backup

  # Drop and restore (clean slate)
  docker compose exec -T db pg_restore -U $DB_USER -d $PROD_DB \
    --clean --if-exists --no-owner --no-acl \
    /tmp/dump.backup 2>&1 | tail -5 || true

  # Cleanup
  docker compose exec -T db rm -f /tmp/dump.backup
  rm -f "$REMOTE_DUMP"

  echo "==> Restore complete. Row counts:"
  docker compose exec -T db psql -U $DB_USER -d $PROD_DB -c \
    "SELECT 'videos' as t, count(*) FROM videos UNION ALL SELECT 'transcripts', count(*) FROM transcripts UNION ALL SELECT 'video_frames', count(*) FROM video_frames;"
REMOTE

rm -f "$DUMP_FILE"
echo "==> Done!"
