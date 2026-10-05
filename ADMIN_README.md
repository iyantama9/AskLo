# AskCore Admin Dashboard

Simple, clean admin panel for managing AskCore models, router connections, promotions, and users.

## Features

### 1. Models Management
- Add, edit, delete AI models
- Toggle models active/inactive
- Configure capabilities (reasoning, vision, browse, image generation)
- Set cost tiers
- All models stored in database (no hardcoded arrays)

### 2. Router Configuration
- Manage multiple LLM router endpoints
- Test connection health
- Configure timeout and retry settings
- Monitor connection status

### 3. Promotions Management
- Create time-limited promotions
- Set date ranges (from X to Y)
- Unlimited quota or custom multipliers
- Assign promotions to users
- Track active promotions

### 4. Users Management
- View all users with pagination
- Search and filter by role
- View user stats (chats, promotions, usage)
- Assign promotions to users
- Change user roles (user ↔ admin)

## Quick Start

### 1. Setup Local Infrastructure

```bash
# Start PostgreSQL + MinIO
docker-compose up -d

# Wait for healthy status
docker-compose ps

# Create MinIO bucket
docker-compose exec minio mc alias set local http://localhost:9000 askcore askcore_minio_password
docker-compose exec minio mc mb local/askcore-files
docker-compose exec minio mc anonymous set public local/askcore-files
```

### 2. Run Migrations

```bash
cd backend
npm install
npm run migrate
```

### 3. Create Admin User

```bash
docker-compose exec postgres psql -U askcore -d askcore -c "
  INSERT INTO users (username, password_hash, role) 
  VALUES ('admin', crypt('admin123', gen_salt('bf')), 'admin');
"
```

### 4. Start Backend

```bash
cd backend
npm run dev
```

### 5. Start Frontend

```bash
flutter run -d chrome --web-port 3000
```

### 6. Access Admin Panel

Navigate to: http://localhost:3000/admin

**Login:**
- Username: `admin`
- Password: `admin123`

## API Endpoints

### Models Management
- `GET /api/admin/models` - List all models
- `POST /api/admin/models` - Create model
- `PUT /api/admin/models/:id` - Update model
- `DELETE /api/admin/models/:id` - Delete model
- `PATCH /api/admin/models/:id/toggle` - Toggle enabled/disabled

### Router Configuration
- `GET /api/admin/router` - List router configs
- `POST /api/admin/router` - Create config
- `PUT /api/admin/router/:id` - Update config
- `POST /api/admin/router/:id/test` - Test connection
- `PATCH /api/admin/router/:id/toggle` - Toggle active/inactive

### Promotions
- `GET /api/admin/promotions` - List promotions
- `GET /api/admin/promotions/:id` - Get promotion details
- `POST /api/admin/promotions` - Create promotion
- `PUT /api/admin/promotions/:id` - Update promotion
- `POST /api/admin/promotions/:id/assign` - Assign to users
- `DELETE /api/admin/promotions/:id/assign/:userId` - Remove from user

### Users
- `GET /api/admin/users` - List users (paginated)
- `GET /api/admin/users/:id` - Get user details
- `PATCH /api/admin/users/:id/role` - Update user role
- `GET /api/admin/users/stats/summary` - Get user statistics

## Database Schema

```sql
-- Models (replaces hardcoded modelCatalog.js)
CREATE TABLE models (
  id VARCHAR(100) PRIMARY KEY,
  display_name VARCHAR(255) NOT NULL,
  owned_by VARCHAR(100) NOT NULL,
  supports_reasoning BOOLEAN DEFAULT false,
  supports_vision BOOLEAN DEFAULT false,
  supports_image_generation BOOLEAN DEFAULT false,
  supports_browse BOOLEAN DEFAULT false,
  cost_tier VARCHAR(50) DEFAULT 'standard',
  enabled BOOLEAN DEFAULT true
);

-- Router configurations
CREATE TABLE router_configs (
  id SERIAL PRIMARY KEY,
  name VARCHAR(100) UNIQUE NOT NULL,
  base_url TEXT NOT NULL,
  api_key TEXT NOT NULL,
  is_active BOOLEAN DEFAULT true,
  timeout_ms INT DEFAULT 30000,
  max_retries INT DEFAULT 3,
  last_tested_at TIMESTAMPTZ,
  last_test_status VARCHAR(50)
);

-- Promotions
CREATE TABLE promotions (
  id SERIAL PRIMARY KEY,
  name VARCHAR(255) NOT NULL,
  description TEXT,
  start_date TIMESTAMPTZ NOT NULL,
  end_date TIMESTAMPTZ NOT NULL,
  unlimited_quota BOOLEAN DEFAULT true,
  quota_multiplier DECIMAL(10,2) DEFAULT 1.0,
  is_active BOOLEAN DEFAULT true
);

-- User promotions (many-to-many)
CREATE TABLE user_promotions (
  id SERIAL PRIMARY KEY,
  user_id INT REFERENCES users(id) ON DELETE CASCADE,
  promotion_id INT REFERENCES promotions(id) ON DELETE CASCADE,
  assigned_at TIMESTAMPTZ DEFAULT NOW(),
  UNIQUE(user_id, promotion_id)
);
```

## Promotion System

When a user has an active promotion:
- **Unlimited quota**: User bypasses all daily limits
- **Quota multiplier**: User gets N× the normal limits
- **Custom limits**: Override specific quota types

Priority: Custom limits > Unlimited > Multiplier > Default

Example:
```javascript
// User normally has 100 AI requests/day
// With 2× multiplier promotion: 200 requests/day
// With unlimited promotion: ∞ requests/day
```

## Security

All admin endpoints require:
1. Valid authentication (session token)
2. Admin role (`role = 'admin'`)

Implemented via middleware:
```javascript
router.use(authMiddleware);  // Check logged in
router.use(adminOnly);        // Check admin role
```

## Development

### Backend Structure

```
backend/
├── src/
│   ├── routes/
│   │   └── admin/
│   │       ├── models.js       # Models CRUD
│   │       ├── router.js       # Router config
│   │       ├── promotions.js   # Promotions CRUD
│   │       └── users.js        # Users management
│   ├── middleware/
│   │   └── admin.js            # Admin-only middleware
│   └── utils/
│       ├── minio.js            # MinIO storage
│       └── usage.js            # Updated with promotion support
└── migrations/
    └── 004_admin_dashboard.sql
```

### Flutter Structure

```
lib/
├── screens/
│   └── admin/
│       ├── admin_dashboard_screen.dart
│       ├── models_management_screen.dart
│       ├── router_config_screen.dart
│       ├── promotions_management_screen.dart
│       └── users_management_screen.dart
└── services/
    └── admin_service.dart
```

## Migration from Neon + R2 to Local

See [LOCAL_SETUP.md](../LOCAL_SETUP.md) for detailed migration instructions.

## Troubleshooting

### "Admin access required" error
- Ensure your user has `role = 'admin'` in database
- Check authentication token is valid

### Models not loading
- Run migrations: `npm run migrate`
- Check database connection
- Verify models table exists: `\dt models` in psql

### MinIO connection failed
- Check MinIO is running: `docker-compose ps minio`
- Verify bucket exists: `mc ls local/`
- Check endpoint in `.env`: `MINIO_ENDPOINT=localhost:9000`

### Promotion not applying
- Check promotion dates (must be between start_date and end_date)
- Verify `is_active = true`
- Ensure user is assigned: check `user_promotions` table

## Future Enhancements

- [ ] Analytics dashboard (charts, graphs)
- [ ] Bulk user operations
- [ ] Export data (CSV, JSON)
- [ ] Audit logs
- [ ] Email notifications for promotions
- [ ] Advanced role permissions (RBAC)
