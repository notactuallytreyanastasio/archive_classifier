#!/bin/bash
set -euo pipefail

# Deploy archive_classifier to Hetzner VPS
# Adds itself as a sidecar to the blog docker-compose stack
#
# Usage: ./deploy.sh [user@host]
#
# Prerequisites:
# 1. SSH access to the server
# 2. ARCHIVE_CLASSIFIER_SECRET_KEY_BASE set in /opt/blog/.env on server
# 3. DNS: archive.bobbby.online → 5.161.181.91

HOST="${1:-root@5.161.181.91}"
REMOTE_DIR="/opt/archive_classifier"
BLOG_DIR="/opt/blog"

echo "==> Syncing archive_classifier to $HOST:$REMOTE_DIR..."

rsync -avz --delete \
  --exclude '_build' \
  --exclude 'deps' \
  --exclude 'node_modules' \
  --exclude '.env' \
  --exclude '.git' \
  --exclude '.elixir_ls' \
  --exclude '.deciduous' \
  --exclude '.claude' \
  "$PWD/" "$HOST:$REMOTE_DIR/"

echo "==> Patching blog docker-compose and Caddyfile on remote..."

ssh "$HOST" bash -s <<'REMOTE'
  set -euo pipefail

  # --- Ensure init-db.sh creates our database ---
  INIT_DB="/opt/blog/init-db.sh"
  if ! grep -q "archive_classifier_prod" "$INIT_DB"; then
    cat >> "$INIT_DB" <<'INITEOF'

# Create archive_classifier database
psql -v ON_ERROR_STOP=1 --username "$POSTGRES_USER" --dbname "$POSTGRES_DB" <<-EOSQL
    SELECT 'CREATE DATABASE archive_classifier_prod'
    WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'archive_classifier_prod')\gexec
EOSQL
INITEOF
    echo "  Added archive_classifier_prod to init-db.sh"
  fi

  # --- Create database now if Postgres is already running ---
  cd /opt/blog
  docker compose exec -T db psql -U blog -d blog_prod -c \
    "SELECT 'CREATE DATABASE archive_classifier_prod' WHERE NOT EXISTS (SELECT FROM pg_database WHERE datname = 'archive_classifier_prod')\gexec" \
    2>/dev/null || echo "  (DB will be created on next Postgres init)"

  # --- Add classifier service to docker-compose if not present ---
  COMPOSE="/opt/blog/docker-compose.yml"
  if ! grep -q "classifier:" "$COMPOSE"; then
    # Insert before the caddy service
    sed -i '/^  caddy:/i\
  classifier:\
    build:\
      context: /opt/archive_classifier\
    restart: always\
    depends_on:\
      db:\
        condition: service_healthy\
    environment:\
      DATABASE_URL: ecto://blog:${DB_PASSWORD}@db/archive_classifier_prod\
      SECRET_KEY_BASE: ${ARCHIVE_CLASSIFIER_SECRET_KEY_BASE}\
      PHX_HOST: archive.bobbby.online\
      PORT: "4002"\
      POOL_SIZE: "10"\
      PHX_SERVER: "true"\
    # Not exposed to host - Caddy proxies via Docker network\
' "$COMPOSE"
    echo "  Added classifier service to docker-compose.yml"
  fi

  # --- Add Caddyfile entry if not present ---
  CADDYFILE="/opt/blog/Caddyfile"
  if ! grep -q "archive.bobbby.online" "$CADDYFILE"; then
    cat >> "$CADDYFILE" <<'CADDYEOF'

archive.bobbby.online {
	reverse_proxy classifier:4002

	encode gzip zstd

	header {
		X-Forwarded-Proto {scheme}
	}
}
CADDYEOF
    echo "  Added archive.bobbby.online to Caddyfile"
  fi

  # --- Build and deploy ---
  cd /opt/blog
  docker compose build classifier
  docker compose up -d

  # Run migrations
  docker compose exec classifier /app/bin/migrate

  # Reload Caddy config
  docker compose exec -T caddy caddy reload --config /etc/caddy/Caddyfile

  echo "==> Deploy complete!"
  docker compose ps
REMOTE

echo ""
echo "==> archive.bobbby.online should be live!"
echo "    (Make sure DNS points archive.bobbby.online to 5.161.181.91)"
