# AskCore Local Setup Guide

## Overview

Full local development setup for AskCore with PostgreSQL, MinIO (S3-compatible), and admin dashboard.

## Architecture

```
┌─────────────────┐
│  Flutter Web    │ ← User Interface + Admin Dashboard
│  (Port 80/443)  │
└────────┬────────┘
         │
         ▼
┌─────────────────┐
│  Backend API    │ ← Express.js
│  (Port 4001)    │
└────────┬────────┘
         │
         ├─────────► PostgreSQL (Port 5432)
         │
         └─────────► MinIO S3 (Port 9000/9001)
```

## Prerequisites

- Docker & Docker Compose
- Node.js 18+ (for backend development)
- Flutter 3.x (for frontend development)

## Quick Start

### 1. Clone & Setup Environment

```bash
# Copy environment file
cp backend/.env.local backend/.env

# Generate secrets (Linux/Mac)
export JWT_SECRET=$(openssl rand -base64 32)
export SESSION_SECRET=$(openssl rand -base64 32)
export POSTGRES_PASSWORD=$(openssl rand -base64 24)
export MINIO_PASSWORD=$(openssl rand -base64 24)

# Update .env with generated secrets
```

### 2. Start Infrastructure

```bash
# Start PostgreSQL + MinIO
docker-compose up -d postgres minio

# Wait for services to be healthy
docker-compose ps

# Create MinIO bucket
docker-compose exec minio mc alias set local http://localhost:9000 askcore askcore_minio_password
docker-compose exec minio mc mb local/askcore-files
docker-compose exec minio mc anonymous set public local/askcore-files
```

### 3. Run Migrations

```bash
cd backend
npm install
npm run migrate
```

### 4. Create Admin User

```bash
# Connect to PostgreSQL
docker-compose exec postgres psql -U askcore -d askcore

# Create admin user
INSERT INTO users (username, password_hash, role) 
VALUES (
  'admin', 
  crypt('admin123', gen_salt('bf')), 
  'admin'
);
```

### 5. Start Backend

```bash
cd backend
npm run dev
```

### 6. Start Frontend

```bash
cd ..
flutter run -d chrome --web-port 3000
```

### 7. Access Admin Dashboard

- Web App: http://localhost:3000
- Admin Dashboard: http://localhost:3000/admin
- MinIO Console: http://localhost:9001
- Backend API: http://localhost:4001

**Login Credentials:**
- Username: `admin`
- Password: `admin123`

## Admin Dashboard Features

### 1. Models Management (`/admin/models`)
- Add/edit/delete AI models
- Toggle active/inactive
- Configure model capabilities:
  - Reasoning support
  - Vision support
  - Image generation
  - Web browsing
- Cost tier management

### 2. Router Configuration (`/admin/router`)
- Manage multiple LLM router endpoints
- Test connections
- Configure timeouts and retries
- Monitor connection health

### 3. Promotions Management (`/admin/promotions`)
- Create time-limited promotions
- Set date ranges (from X to Y)
- Unlimited quota or multiplier
- Assign to specific users
- Track active promotions

### 4. Users Management (`/admin/users`)
- View all users
- Search and filter
- Assign promotions
- View usage stats
- Change user roles

## Database Schema

### New Admin Tables

```sql
-- Models (replaces hardcoded array)
models (id, display_name, owned_by, capabilities, enabled)

-- Router configurations
router_configs (id, name, base_url, api_key, is_active)

-- Promotions
promotions (id, name, start_date, end_date, unlimited_quota)

-- User promotions (many-to-many)
user_promotions (user_id, promotion_id, assigned_at)
```

## Migration from Neon to Local

### Export from Neon

```bash
# Export schema + data
pg_dump $NEON_DATABASE_URL -Fc -f neon_backup.dump

# Or just data
pg_dump $NEON_DATABASE_URL --data-only -f neon_data.sql
```

### Import to Local

```bash
# Restore full dump
pg_restore -U askcore -d askcore -c neon_backup.dump

# Or restore data only
docker-compose exec -T postgres psql -U askcore -d askcore < neon_data.sql
```

### Migrate Files from R2 to MinIO

```bash
# Install rclone
curl https://rclone.org/install.sh | sudo bash

# Configure R2
rclone config create r2 s3 \
  provider Cloudflare \
  access_key_id $R2_ACCESS_KEY_ID \
  secret_access_key $R2_SECRET_ACCESS_KEY \
  endpoint https://$R2_ACCOUNT_ID.r2.cloudflarestorage.com

# Configure MinIO
rclone config create minio s3 \
  provider Minio \
  access_key_id askcore \
  secret_access_key askcore_minio_password \
  endpoint http://localhost:9000

# Sync files
rclone sync r2:askcore-bucket minio:askcore-files --progress
```

## Development

### Backend Development

```bash
cd backend
npm run dev          # Start with nodemon
npm run migrate      # Run migrations
npm test            # Run tests
```

### Frontend Development

```bash
flutter run -d chrome
flutter build web --release
```

## Production Deployment

### 1. Update Environment

```env
NODE_ENV=production
DATABASE_URL=postgresql://askcore:$PASSWORD@postgres:5432/askcore
MINIO_ENDPOINT=minio:9000
```

### 2. Build & Deploy

```bash
# Build backend
cd backend
npm ci --production

# Build frontend
cd ..
flutter build web --release

# Start with Docker Compose
docker-compose up -d
```

### 3. Nginx Configuration

```nginx
server {
    listen 80;
    server_name askcore.dev;

    # Frontend
    location / {
        root /var/www/askcore-web;
        try_files $uri $uri/ /index.html;
    }

    # Backend API
    location /api/ {
        proxy_pass http://localhost:4001;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
    }

    # MinIO files
    location /files/ {
        proxy_pass http://localhost:9000/askcore-files/;
    }
}
```

## Troubleshooting

### Database Connection Failed

```bash
# Check if PostgreSQL is running
docker-compose ps postgres

# View logs
docker-compose logs postgres

# Restart
docker-compose restart postgres
```

### MinIO Connection Failed

```bash
# Check MinIO status
docker-compose ps minio

# Access MinIO console
open http://localhost:9001
```

### Models Not Loading

```bash
# Check if migration ran
docker-compose exec postgres psql -U askcore -d askcore -c "SELECT COUNT(*) FROM models;"

# Re-run migration
cd backend && npm run migrate
```

## Security Notes

- Change default passwords in production
- Use strong JWT/Session secrets
- Enable HTTPS for production
- Restrict MinIO bucket access
- Use environment variables for secrets
- Never commit `.env` files

## Support

- Backend API: http://localhost:4001/api
- Admin Dashboard: http://localhost:3000/admin
- MinIO Console: http://localhost:9001
