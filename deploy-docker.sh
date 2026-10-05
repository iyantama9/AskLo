#!/bin/bash
set -e

# Configuration
SERVER="root@178.128.59.20"
SSH_KEY="$HOME/.ssh/id_ed25519"
REMOTE_DIR="/root/getai-docker"

echo "=== GetAI Docker Deployment Script ==="
echo ""

# Step 1: Create remote directory
echo "[1/7] Creating remote directory..."
ssh -i "$SSH_KEY" "$SERVER" "mkdir -p $REMOTE_DIR/{nginx,backend}"

# Step 2: Upload docker-compose and configs
echo "[2/7] Uploading Docker configuration files..."
scp -i "$SSH_KEY" docker-compose.production.yml "$SERVER:$REMOTE_DIR/docker-compose.yml"
scp -i "$SSH_KEY" .env.docker "$SERVER:$REMOTE_DIR/.env"
scp -i "$SSH_KEY" nginx/nginx.conf "$SERVER:$REMOTE_DIR/nginx/"

# Step 3: Upload backend source
echo "[3/7] Uploading backend source code..."
tar czf /tmp/backend.tar.gz -C backend --exclude=node_modules --exclude=.env --exclude=test .
scp -i "$SSH_KEY" /tmp/backend.tar.gz "$SERVER:$REMOTE_DIR/backend/"
ssh -i "$SSH_KEY" "$SERVER" "cd $REMOTE_DIR/backend && tar xzf backend.tar.gz && rm backend.tar.gz"
rm /tmp/backend.tar.gz

# Step 4: Upload frontend build
echo "[4/7] Uploading frontend build..."
tar czf /tmp/web.tar.gz -C build/web .
scp -i "$SSH_KEY" /tmp/web.tar.gz "$SERVER:$REMOTE_DIR/"
ssh -i "$SSH_KEY" "$SERVER" "cd $REMOTE_DIR && mkdir -p web && cd web && tar xzf ../web.tar.gz && rm ../web.tar.gz"
rm /tmp/web.tar.gz

# Step 5: Stop existing containers and PM2
echo "[5/7] Stopping existing services..."
ssh -i "$SSH_KEY" "$SERVER" "
  pm2 stop all 2>/dev/null || true
  pm2 delete all 2>/dev/null || true
  docker stop temp-postgres 2>/dev/null || true
  docker rm temp-postgres 2>/dev/null || true
"

# Step 6: Start Docker stack
echo "[6/7] Starting Docker stack..."
ssh -i "$SSH_KEY" "$SERVER" "
  cd $REMOTE_DIR
  docker-compose down 2>/dev/null || true
  docker-compose pull postgres minio
  docker-compose up -d postgres minio
  sleep 10
"

# Step 7: Import database
echo "[7/7] Importing database..."
DB_BACKUP=$(ssh -i "$SSH_KEY" "$SERVER" "ls -t /root/getai-database-backup-*.sql 2>/dev/null | head -1")
if [ -n "$DB_BACKUP" ]; then
  echo "Found database backup: $DB_BACKUP"
  ssh -i "$SSH_KEY" "$SERVER" "
    cd $REMOTE_DIR
    docker-compose exec -T postgres psql -U getai_user -d getai < $DB_BACKUP
  "
  echo "Database imported successfully!"
else
  echo "No database backup found, skipping import"
fi

# Start backend and frontend
echo ""
echo "Starting backend and frontend services..."
ssh -i "$SSH_KEY" "$SERVER" "
  cd $REMOTE_DIR
  docker-compose up -d backend frontend
  sleep 5
  docker-compose ps
"

echo ""
echo "=== Deployment Complete! ==="
echo ""
echo "Services:"
echo "  - Frontend: http://178.128.59.20"
echo "  - Backend API: http://178.128.59.20:4001"
echo "  - MinIO Console: http://178.128.59.20:9001"
echo ""
echo "Check logs with:"
echo "  ssh -i $SSH_KEY $SERVER 'cd $REMOTE_DIR && docker-compose logs -f'"
