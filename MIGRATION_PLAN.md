# Migration Plan: Cloud to Self-Hosted Docker

## Current Architecture
- **Storage**: Cloudflare R2 (partially migrated to MinIO)
- **Database**: Neon PostgreSQL (cloud)
- **Backend**: PM2 process on VPS
- **Frontend**: Static Flutter web on nginx

## Target Architecture (Full Docker)
- **Storage**: MinIO (Docker container)
- **Database**: PostgreSQL 17 (Docker container)
- **Backend**: Node.js Express (Docker container)
- **Frontend**: Nginx serving Flutter web (Docker container)
- **Orchestration**: Docker Compose

## Migration Steps

### Phase 1: Data Migration Assessment
- [ ] Check R2 data exists and size
- [ ] Export Neon database schema + data
- [ ] Verify MinIO bucket ready
- [ ] Verify local PostgreSQL container ready

### Phase 2: Data Migration Execution
- [ ] Migrate R2 files to MinIO (if any exist)
- [ ] Import Neon database to local PostgreSQL
- [ ] Verify data integrity

### Phase 3: Dockerization
- [ ] Create Dockerfile for backend
- [ ] Create Dockerfile for frontend (nginx + Flutter web)
- [ ] Create docker-compose.yml for all services
- [ ] Create .env files for Docker environment

### Phase 4: Testing & Deployment
- [ ] Test local Docker stack
- [ ] Deploy to server
- [ ] Smoke test all features
- [ ] Update DNS/configs

## Services in Docker Compose
1. **postgres** - PostgreSQL 17
2. **minio** - MinIO S3-compatible storage
3. **backend** - Node.js Express API
4. **frontend** - Nginx serving Flutter web
5. **minio-mc** - MinIO client for initial setup

