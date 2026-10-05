# AskCore (GetAI) - Self-Hosted AI Chatbot Platform

Platform AI chatbot self-hosted dengan multi-provider LLM (DeepSeek, Gemini, Grok, Kimi, Qwen, Claude, Llama, Mistral, GLM, OpenAI), admin dashboard, dan arsitektur Docker Compose penuh (PostgreSQL + MinIO + Node.js backend + Nginx/Flutter web frontend).

## Architecture

```
Browser
   |
   v
[Nginx] Flutter Web (user chat + admin dashboard)   :8888 (host)
   |
   v
[Node.js Express Backend]                            :14001 (host)
   |                          |
   v                          v
[PostgreSQL 17]            [MinIO (S3)]
 schema + migrations        files, images, provider logos
   |
   v
[LLM Router (OpenAI-compatible)]
 DeepSeek, Gemini, Grok, Kimi, Qwen, Claude, Llama, Mistral, GLM, OpenAI
```

- **Frontend** — Flutter web (Material 3), user chat + admin dashboard di satu codebase
- **Backend** — Express.js, PostgreSQL, MinIO, streaming SSE
- **Storage** — MinIO (S3) untuk file, gambar, dan logo provider
- **Database** — PostgreSQL 17 dengan migration versioned (`backend/migrations/`)
- **Orchestration** — Docker Compose (`docker-compose.yml` / `docker-compose.production.yml`)

## Repository Layout

| Path | Isi |
|------|-----|
| `lib/` | Flutter app (screens, widgets, services) |
| `lib/assets/logos/` | Logo brand AI model (DeepSeek, Gemini, Grok, Kimi, dll) |
| `web/` | Flutter web entrypoint + PWA manifest |
| `backend/` | Express.js API (routes, utils, migrations, tests) |
| `nginx/` | Nginx config untuk serve Flutter web + proxy API |
| `docs/runbooks/` | Runbook ops (backup/restore, smoke test) |
| `docker-compose.yml` / `docker-compose.production.yml` | Orchestration |
| `DEPLOYMENT_GUIDE.md` | Cache-busting & SW fix |
| `DOCKER_DEPLOYMENT.md` | Deploy Docker |
| `LOCAL_SETUP.md` | Setup local development |
| `ADMIN_README.md` | Dokumentasi admin dashboard |
| `MIGRATION_PLAN.md` | Rencana migrasi cloud → self-hosted |

## Features

### User Chat
- Chat multi-model (deepseek/gemini/grok/kimi/qwen, dll) dengan streaming SSE
- Indikator brand model (logo asli warna, background transparan)
- Image generation, web browsing, dokumen upload/analysis, artifacts
- Response panjang **tanpa limit token** (hanya generation title yang dibatasi)
- Heartbeat SSE tiap 15 detik agar stream panjang tidak tampak "stuck"

### Admin Dashboard
- Manage model (CRUD, sort order, fitur, biaya)
- Configure router endpoint multi-provider
- Promotion & quota
- Manage user, settings
- Upload logo provider (MinIO)

## Getting Started (Local Development)

### Prerequisites
- Flutter (web support enabled)
- Node.js 18+
- Docker + Docker Compose (untuk PostgreSQL, MinIO)
- PostgreSQL migration: `backend/migrations/001..011`

### 1. Start Infrastruktur
```bash
docker compose up -d postgres minio
cp .env.docker.example .env.docker
# edit password & API key di .env.docker
```

### 2. Backend
```bash
cd backend
npm install
npm run migrate    # jalankan migration
npm run dev        # http://localhost:4001
```

### 3. Frontend (Flutter Web)
```bash
flutter pub get
flutter run -d chrome
```

### 4. Deploy Penuh (Docker)
Lihat [`DOCKER_DEPLOYMENT.md`](./DOCKER_DEPLOYMENT.md) dan [`DEPLOYMENT_GUIDE.md`](./DEPLOYMENT_GUIDE.md).

## Environment Variables

Lihat [`.env.docker.example`](./.env.docker.example) — template lengkap dengan semua variabel (Postgres, MinIO, JWT, AI API, quota).

## Testing & Quality

```bash
cd backend
npm test            # jest (routerClient, chats, artifactExtraction, dsb)
npm run check       # syntax check semua route + util
```

## Brand Logos (Dropdown Model Picker)

Logo brand AI model di dropdown disimpan di `lib/assets/logos/` sebagai PNG transparan 200x200. Widget `lib/widgets/modern_model_picker.dart` mendeteksi brand dari label display model (mis. label mengandung "kimi" → `kimi.png`). Untuk menambah logo baru:

1. Download logo resmi (warna asli, bukan monochrome)
2. Proses dengan Pillow: center-crop square, buang background (flood-fill dari edge untuk bg putih/putih, atau rounded-corner mask untuk app icon), resize ke 200x200
3. Simpan sebagai `lib/assets/logos/<brand>.png`
4. Tambahkan ke `_brandAsset()` di `modern_model_picker.dart`
5. Rebuild Flutter web + patch `flutter_bootstrap.js` (lihat DEPLOYMENT_GUIDE)

## Migration List

| File | Isi |
|------|-----|
| `001_foundation.sql` | Schema dasar: users, chats, messages, router_config |
| `002_message_attachments_and_default_model.sql` | Attachment + default model |
| `003_artifacts.sql` | Artifact extraction |
| `004_admin_dashboard.sql` | Admin roles |
| `005_qwen_image_models.sql` | Image generation models |
| `006_feedback.sql` | Feedback user |
| `007_dynamic_config.sql` | Model catalog + provider + config dinamis |
| `008_admin_settings.sql` | Settings admin |
| `009_models_sort_order.sql` | Urut tampilan model |
| `010_provider_logos.sql` | Logo per provider (MinIO) |
| `011_user_profile.sql` | Profile user |

Jalankan semua migration berurutan: `cd backend && npm run migrate`.
