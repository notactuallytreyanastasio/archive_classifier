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

echo "==> Building and deploying on remote..."

ssh "$HOST" << 'EOF'
cd /opt/blog
docker compose build classifier
docker compose up -d classifier
sleep 3
docker compose exec classifier /app/bin/migrate
docker compose exec -T caddy caddy reload --config /etc/caddy/Caddyfile
echo "==> Deploy complete!"
docker compose ps
EOF

echo ""
echo "==> archive.bobbby.online should be live!"
