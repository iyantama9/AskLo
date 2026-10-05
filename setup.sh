#!/bin/bash
set -e

echo "🚀 AskCore Local Setup Script"
echo "=============================="
echo ""

# Check prerequisites
command -v docker >/dev/null 2>&1 || { echo "❌ Docker is required but not installed. Aborting." >&2; exit 1; }
command -v docker-compose >/dev/null 2>&1 || { echo "❌ Docker Compose is required but not installed. Aborting." >&2; exit 1; }
command -v node >/dev/null 2>&1 || { echo "❌ Node.js is required but not installed. Aborting." >&2; exit 1; }

echo "✅ Prerequisites check passed"
echo ""

# Generate environment file if not exists
if [ ! -f backend/.env ]; then
    echo "📝 Creating backend/.env file..."
    cp backend/.env.local backend/.env

    # Generate secrets (if openssl available)
    if command -v openssl >/dev/null 2>&1; then
        JWT_SECRET=$(openssl rand -base64 32)
        SESSION_SECRET=$(openssl rand -base64 32)
        sed -i "s/local_jwt_secret_change_this/$JWT_SECRET/g" backend/.env
        sed -i "s/local_session_secret_change_this/$SESSION_SECRET/g" backend/.env
        echo "✅ Generated secure secrets"
    else
        echo "⚠️  OpenSSL not found, using default secrets (not secure for production)"
    fi
fi

echo ""
echo "🐳 Starting Docker services..."
docker-compose up -d postgres minio

echo ""
echo "⏳ Waiting for services to be healthy..."
sleep 5

# Check service health
echo "Checking PostgreSQL..."
docker-compose exec -T postgres pg_isready -U askcore || { echo "❌ PostgreSQL not ready"; exit 1; }
echo "✅ PostgreSQL is ready"

echo ""
echo "📦 Setting up MinIO bucket..."
docker-compose exec -T minio sh -c "
    mc alias set local http://localhost:9000 askcore askcore_minio_password --api s3v4 2>/dev/null || true
    mc mb local/askcore-files 2>/dev/null || true
    mc anonymous set download local/askcore-files 2>/dev/null || true
" && echo "✅ MinIO bucket configured"

echo ""
echo "📚 Installing backend dependencies..."
cd backend
npm install
echo "✅ Dependencies installed"

echo ""
echo "🔄 Running database migrations..."
npm run migrate
echo "✅ Migrations complete"

echo ""
echo "👤 Creating admin user..."
docker-compose exec -T postgres psql -U askcore -d askcore -c "
    INSERT INTO users (username, password_hash, role, created_at)
    VALUES ('admin', crypt('admin123', gen_salt('bf')), 'admin', NOW())
    ON CONFLICT (username) DO NOTHING;
" && echo "✅ Admin user created (username: admin, password: admin123)"

echo ""
echo "=============================="
echo "✅ Setup complete!"
echo "=============================="
echo ""
echo "Next steps:"
echo "  1. Start backend: cd backend && npm run dev"
echo "  2. Start frontend: flutter run -d chrome --web-port 3000"
echo "  3. Access admin: http://localhost:3000/admin"
echo ""
echo "Credentials:"
echo "  Username: admin"
echo "  Password: admin123"
echo ""
echo "Services:"
echo "  - Backend API: http://localhost:4001"
echo "  - MinIO Console: http://localhost:9001"
echo "  - PostgreSQL: localhost:5432"
echo ""
