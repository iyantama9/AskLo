# Quick Local Deployment

## 1. Start Docker Services

```bash
# Navigate to project root
cd D:/Project/GetAI

# Start PostgreSQL + MinIO
docker-compose up -d postgres minio

# Check status
docker-compose ps
```

## 2. Setup MinIO Bucket

```bash
# Create bucket
docker-compose exec minio mc alias set local http://localhost:9000 askcore askcore_minio_password
docker-compose exec minio mc mb local/askcore-files
docker-compose exec minio mc anonymous set download local/askcore-files
```

## 3. Install Backend Dependencies

```bash
cd backend
npm install
```

## 4. Run Database Migrations

```bash
npm run migrate
```

## 5. Create Admin User

```bash
docker-compose exec postgres psql -U askcore -d askcore -c "
  INSERT INTO users (username, password_hash, role)
  VALUES ('admin', crypt('admin123', gen_salt('bf')), 'admin')
  ON CONFLICT (username) DO NOTHING;
"
```

## 6. Start Backend

```bash
# In backend directory
npm run dev
```

## 7. Start Flutter Frontend

```bash
# In new terminal, from project root
flutter run -d chrome --web-port 3000
```

## 8. Access Admin Dashboard

- **Main App**: http://localhost:3000
- **Admin Panel**: http://localhost:3000/admin
- **Backend API**: http://localhost:4001
- **MinIO Console**: http://localhost:9001

**Admin Login:**
- Username: `admin`
- Password: `admin123`

## Services Check

```bash
# Check if services are running
docker-compose ps

# View logs
docker-compose logs postgres
docker-compose logs minio

# View backend logs
cd backend && npm run dev
```

## Troubleshooting

### PostgreSQL not starting
```bash
docker-compose down
docker volume rm getai_postgres_data
docker-compose up -d postgres
```

### MinIO not accessible
```bash
docker-compose restart minio
```

### Backend errors
```bash
cd backend
rm -rf node_modules
npm install
npm run migrate
```

### Frontend issues
```bash
flutter clean
flutter pub get
flutter run -d chrome --web-port 3000
```
