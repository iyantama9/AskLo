# Docker Deployment Guide

## Overview

This guide explains how to deploy the entire AskCore application stack using Docker Compose.

## Architecture

The Docker stack consists of:
- **PostgreSQL 17**: Database
- **MinIO**: S3-compatible object storage for files and images
- **Backend**: Node.js Express API
- **Frontend**: Nginx serving Flutter web app

All services communicate via Docker network.

## Prerequisites

- Docker Engine 20.10+
- Docker Compose 2.0+
- Git

## Quick Start

### 1. Clone and Prepare

```bash
cd /path/to/GetAI
cp .env.docker.example .env
```

### 2. Configure Environment Variables

Edit `.env` file and update:
- `JWT_SECRET` - Generate with: `openssl rand -base64 32`
- `SESSION_SECRET` - Generate with: `openssl rand -base64 32`
- `AI_API_KEY` - Your AI API key
- `POSTGRES_PASSWORD` - Strong database password
- `MINIO_ROOT_PASSWORD` - Strong MinIO password

### 3. Build Flutter Web (if not already built)

```bash
flutter build web --release
```

### 4. Start Services

```bash
docker-compose up -d
```

### 5. Verify Services

```bash
# Check all containers are running
docker-compose ps

# Check backend logs
docker-compose logs -f backend

# Check MinIO bucket initialization
docker-compose logs minio-init
```

### 6. Access Application

- **Frontend**: http://localhost
- **Backend API**: http://localhost:4001
- **MinIO Console**: http://localhost:9001

## Migrating Existing Data

### From Existing PostgreSQL

```bash
# Export from existing database
docker exec getai-postgres pg_dump -U getai_user -d getai > backup.sql

# Import to new Docker container
docker-compose exec -T postgres psql -U getai_user -d getai < backup.sql
```

### From Existing MinIO

```bash
# Use MinIO client to mirror
docker exec getai-minio mc mirror old-minio/bucket-name local/askcore-files
```

## Production Deployment

### 1. Update Nginx for SSL

Replace `nginx.conf` with SSL configuration or use reverse proxy (Caddy/Traefik).

### 2. Set Production Secrets

```bash
# Generate strong secrets
export JWT_SECRET=$(openssl rand -base64 32)
export SESSION_SECRET=$(openssl rand -base64 32)
```

### 3. Configure Volumes for Backup

Update `docker-compose.yml` to use named volumes or bind mounts to host paths:

```yaml
volumes:
  postgres_data:
    driver: local
    driver_opts:
      type: none
      device: /data/postgres
      o: bind
```

### 4. Deploy

```bash
docker-compose up -d --build
```

## Maintenance

### View Logs

```bash
# All services
docker-compose logs -f

# Specific service
docker-compose logs -f backend
```

### Restart Services

```bash
# All services
docker-compose restart

# Specific service
docker-compose restart backend
```

### Update Application

```bash
# Pull latest code
git pull

# Rebuild and restart
docker-compose up -d --build
```

### Backup Database

```bash
# Create backup
docker-compose exec postgres pg_dump -U getai_user -d getai > backup-$(date +%Y%m%d).sql

# Restore backup
docker-compose exec -T postgres psql -U getai_user -d getai < backup-20260724.sql
```

### Backup MinIO Data

```bash
# Backup MinIO bucket
docker exec getai-minio mc mirror local/askcore-files /backup/minio/

# Or use volume backup
docker run --rm -v getai_minio_data:/data -v $(pwd):/backup alpine tar czf /backup/minio-backup.tar.gz /data
```

## Troubleshooting

### Backend fails to start

Check logs:
```bash
docker-compose logs backend
```

Common issues:
- Database not ready: Wait for `postgres` healthcheck
- Missing env vars: Check `.env` file
- Port conflict: Change ports in `docker-compose.yml`

### MinIO bucket not created

Check init logs:
```bash
docker-compose logs minio-init
```

Manually create:
```bash
docker exec getai-minio mc alias set local http://localhost:9000 minioadmin minioadmin123456
docker exec getai-minio mc mb local/askcore-files
docker exec getai-minio mc anonymous set download local/askcore-files
```

### Frontend cannot reach backend

- Check backend is running: `docker-compose ps backend`
- Check network: `docker network inspect getai_getai-network`
- Verify nginx proxy config in `nginx.conf`

## Scaling

### Increase Backend Replicas

```yaml
backend:
  deploy:
    replicas: 3
```

### Use External Database

Comment out `postgres` service and update `DATABASE_URL` to external DB.

### Use External Storage

Comment out `minio` service and update MinIO credentials to external S3/MinIO.

## Security Checklist

- [ ] Change default passwords in `.env`
- [ ] Generate strong JWT/SESSION secrets
- [ ] Enable SSL/TLS (use reverse proxy)
- [ ] Restrict port exposure (remove unnecessary port mappings)
- [ ] Set up firewall rules
- [ ] Regular backups enabled
- [ ] Monitor logs for security events

## Monitoring

### Resource Usage

```bash
docker stats
```

### Health Checks

```bash
# Backend health
curl http://localhost:4001/api/health

# MinIO health
curl http://localhost:9000/minio/health/live

# Database health
docker-compose exec postgres pg_isready
```

## Migration from PM2 Deployment

1. **Backup current data** (already done)
2. **Stop PM2 services**: `pm2 stop all`
3. **Update code**: Pull latest with Docker support
4. **Configure `.env`**: Copy credentials from old `.env`
5. **Import database**: Use backup created earlier
6. **Start Docker stack**: `docker-compose up -d`
7. **Verify**: Test all features
8. **Update DNS/proxy**: Point to new Docker stack
9. **Remove old PM2 setup**: `pm2 delete all`

## Performance Tuning

### PostgreSQL

```yaml
environment:
  POSTGRES_SHARED_BUFFERS: 256MB
  POSTGRES_WORK_MEM: 16MB
  POSTGRES_MAX_CONNECTIONS: 100
```

### MinIO

```yaml
environment:
  MINIO_API_REQUESTS_MAX: 1600
```

### Backend

```yaml
environment:
  NODE_OPTIONS: --max-old-space-size=2048
```

## Support

For issues, check:
1. Docker logs: `docker-compose logs`
2. Service status: `docker-compose ps`
3. Network connectivity: `docker network inspect getai_getai-network`
