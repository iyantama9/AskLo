# Batch 1 Security Hardening Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Harden AskCore production quickly by closing direct public service exposure, adding basic anti-abuse registration, and applying safer HTTP/API defaults.

**Architecture:** Keep Nginx as the only public entry point. Backend code enforces safer auth/register/CORS defaults, while server hardening binds services to localhost and uses UFW/Fail2Ban to reduce public attack surface.

**Tech Stack:** Node.js/Express, PostgreSQL, express-rate-limit, Nginx, UFW, Fail2Ban, PM2, Flutter client.

---

## File Structure

- Modify `backend/src/index.js`: Express hardening, CORS allowlist, host binding, global/auth limiters.
- Modify `backend/src/routes/auth.js`: add `POST /register`, username/password validation, IP-based account creation cap, shared JWT helper.
- Modify `backend/src/db.js`: add `created_ip` and `last_login_at` columns if absent.
- Modify `backend/src/seed.js`: refuse production seeding unless explicitly enabled.
- Modify `nginx_optimize.conf`: security headers inside all relevant locations and safe API proxy headers.
- Use remote commands only after local code validates: backup server config, deploy backend/config, bind services, enable UFW/Fail2Ban, verify production.

---

### Task 1: Backend Express Security Defaults

**Files:**
- Modify: `backend/src/index.js`

- [ ] **Step 1: Replace Express setup with hardened defaults**

Set host binding, hide `X-Powered-By`, add CORS allowlist, and add auth limiter.

```js
const express = require('express');
const cors = require('cors');
const { initDB } = require('./db');
require('dotenv').config();

const authRoutes = require('./routes/auth');
const chatRoutes = require('./routes/chats');
const messageRoutes = require('./routes/messages');
const uploadRoutes = require('./routes/upload');
const fileRoutes = require('./routes/files');
const browseRoutes = require('./routes/browse');

const rateLimit = require('express-rate-limit');

const app = express();
const PORT = process.env.PORT || 4001;
const HOST = process.env.HOST || '127.0.0.1';
const isProduction = process.env.NODE_ENV === 'production';

const allowedOrigins = new Set([
  'https://askcore.dev',
  'https://www.askcore.dev',
]);

if (!isProduction) {
  allowedOrigins.add('http://localhost:3000');
  allowedOrigins.add('http://localhost:4001');
  allowedOrigins.add('http://127.0.0.1:4001');
}

app.disable('x-powered-by');
app.set('trust proxy', 1);

app.use(cors({
  origin(origin, callback) {
    if (!origin || allowedOrigins.has(origin)) {
      return callback(null, true);
    }
    return callback(new Error('Not allowed by CORS'));
  },
  methods: ['GET', 'POST', 'PUT', 'DELETE', 'OPTIONS'],
  allowedHeaders: ['Authorization', 'Content-Type'],
  credentials: false,
}));
app.use(express.json({ limit: '10mb' }));

const globalLimiter = rateLimit({
  windowMs: 60 * 1000,
  max: 100,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'Too many requests, please try again later.' },
});

const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 30,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'Too many auth attempts, please try again later.' },
});

const aiLimiter = rateLimit({
  windowMs: 60 * 1000,
  max: 15,
  standardHeaders: true,
  legacyHeaders: false,
  message: { error: 'Too many AI requests, please slow down.' },
});

app.use(globalLimiter);

app.use('/api/auth', authLimiter, authRoutes);
app.use('/api/chats', chatRoutes);
app.use('/api/chats', aiLimiter, messageRoutes);
app.use('/api/upload', uploadRoutes);
app.use('/api/files', fileRoutes);
app.use('/api/browse', browseRoutes);

app.get('/api/health', (_, res) => res.json({ status: 'ok' }));

async function start() {
  await initDB();
  app.listen(PORT, HOST, () => {
    console.log(`AskCore Backend running on http://${HOST}:${PORT}`);
  });
}

start().catch((err) => {
  console.error('Failed to start:', err);
  process.exit(1);
});
```

- [ ] **Step 2: Run syntax check**

Run: `rtk node --check backend/src/index.js`
Expected: no syntax errors.

---

### Task 2: Database Columns for Simple Registration Tracking

**Files:**
- Modify: `backend/src/db.js`

- [ ] **Step 1: Add idempotent user tracking columns**

After the `CREATE TABLE IF NOT EXISTS` block, add:

```js
    await client.query(`
      ALTER TABLE users ADD COLUMN IF NOT EXISTS created_ip INET;
      ALTER TABLE users ADD COLUMN IF NOT EXISTS last_login_at TIMESTAMPTZ;
    `);
```

- [ ] **Step 2: Run syntax check**

Run: `rtk node --check backend/src/db.js`
Expected: no syntax errors.

---

### Task 3: Public Register with Simple IP Anti-Abuse

**Files:**
- Modify: `backend/src/routes/auth.js`

- [ ] **Step 1: Replace auth route with login + register**

Use this implementation:

```js
const express = require('express');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const { pool } = require('../db');

const router = express.Router();

const USERNAME_PATTERN = /^[a-z0-9_]{3,30}$/;
const MIN_PASSWORD_LENGTH = 8;
const MAX_ACCOUNTS_PER_IP_PER_DAY = 3;

function normalizeUsername(username) {
  return String(username || '').toLowerCase().trim();
}

function validateUsername(username) {
  return USERNAME_PATTERN.test(username);
}

function validatePassword(password) {
  return typeof password === 'string' && password.length >= MIN_PASSWORD_LENGTH;
}

function getClientIp(req) {
  return req.ip || req.headers['x-forwarded-for']?.split(',')[0]?.trim() || req.socket.remoteAddress || null;
}

function signToken(user) {
  return jwt.sign(
    { userId: user.id, username: user.username },
    process.env.JWT_SECRET,
    { expiresIn: '7d' }
  );
}

router.post('/register', async (req, res) => {
  const username = normalizeUsername(req.body.username);
  const { password } = req.body;
  const clientIp = getClientIp(req);

  if (!validateUsername(username)) {
    return res.status(400).json({
      error: 'Username must be 3-30 characters and only use lowercase letters, numbers, or underscore',
    });
  }

  if (!validatePassword(password)) {
    return res.status(400).json({ error: 'Password must be at least 8 characters' });
  }

  try {
    if (clientIp) {
      const ipCount = await pool.query(
        `SELECT COUNT(*)::int AS count
         FROM users
         WHERE created_ip = $1::inet
           AND created_at > NOW() - INTERVAL '24 hours'`,
        [clientIp]
      );

      if ((ipCount.rows[0]?.count || 0) >= MAX_ACCOUNTS_PER_IP_PER_DAY) {
        return res.status(429).json({ error: 'Too many accounts created from this IP today' });
      }
    }

    const existing = await pool.query('SELECT id FROM users WHERE username = $1', [username]);
    if (existing.rows.length > 0) {
      return res.status(409).json({ error: 'Username already exists' });
    }

    const passwordHash = await bcrypt.hash(password, 12);
    const result = await pool.query(
      `INSERT INTO users (username, password_hash, created_ip)
       VALUES ($1, $2, $3::inet)
       RETURNING id, username`,
      [username, passwordHash, clientIp]
    );

    const user = result.rows[0];
    const token = signToken(user);

    res.status(201).json({
      token,
      user: { id: user.id, username: user.username },
    });
  } catch (err) {
    console.error('Register error:', err);
    res.status(500).json({ error: 'Server error' });
  }
});

router.post('/login', async (req, res) => {
  const username = normalizeUsername(req.body.username);
  const { password } = req.body;

  if (!username || !password) {
    return res.status(400).json({ error: 'Username and password required' });
  }

  try {
    const result = await pool.query(
      'SELECT id, username, password_hash FROM users WHERE username = $1',
      [username]
    );

    if (result.rows.length === 0) {
      return res.status(401).json({ error: 'Invalid credentials' });
    }

    const user = result.rows[0];
    const valid = await bcrypt.compare(password, user.password_hash);

    if (!valid) {
      return res.status(401).json({ error: 'Invalid credentials' });
    }

    await pool.query('UPDATE users SET last_login_at = NOW() WHERE id = $1', [user.id]);

    const token = signToken(user);

    res.json({
      token,
      user: { id: user.id, username: user.username },
    });
  } catch (err) {
    console.error('Login error:', err);
    res.status(500).json({ error: 'Server error' });
  }
});

module.exports = router;
```

- [ ] **Step 2: Run syntax check**

Run: `rtk node --check backend/src/routes/auth.js`
Expected: no syntax errors.

---

### Task 4: Disable Accidental Seed Users in Production

**Files:**
- Modify: `backend/src/seed.js`

- [ ] **Step 1: Add explicit guard at top of seed function**

At the start of `seed()`, before `await initDB();`, add:

```js
  if (process.env.ALLOW_INSECURE_SEED !== 'true') {
    console.error('Refusing to seed default users. Set ALLOW_INSECURE_SEED=true only in local/dev environments.');
    process.exit(1);
  }
```

- [ ] **Step 2: Run syntax check**

Run: `rtk node --check backend/src/seed.js`
Expected: no syntax errors.

---

### Task 5: Nginx Security Headers

**Files:**
- Modify: `nginx_optimize.conf`

- [ ] **Step 1: Add header snippet near top of HTTPS server**

Use this block in the HTTPS server and repeat key cache header behavior inside locations where needed because `add_header` inheritance can be overridden by nested locations:

```nginx
    add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header Referrer-Policy "strict-origin-when-cross-origin" always;
    add_header Permissions-Policy "camera=(), microphone=(), geolocation=(), payment=(), usb=(), fullscreen=(self)" always;
    add_header Content-Security-Policy "default-src 'self'; script-src 'self' 'wasm-unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob: https:; font-src 'self' data:; connect-src 'self' https://askcore.dev wss://askcore.dev; frame-ancestors 'self'; base-uri 'self'; form-action 'self'" always;
```

- [ ] **Step 2: Ensure static and index locations include security headers**

Inside `location ~* ...`, `location = /index.html`, and `location /api/`, include at least:

```nginx
        add_header X-Content-Type-Options "nosniff" always;
        add_header Referrer-Policy "strict-origin-when-cross-origin" always;
```

For `location /api/`, include:

```nginx
        proxy_hide_header X-Powered-By;
        add_header Strict-Transport-Security "max-age=31536000; includeSubDomains" always;
        add_header X-Frame-Options "SAMEORIGIN" always;
        add_header X-Content-Type-Options "nosniff" always;
        add_header Referrer-Policy "strict-origin-when-cross-origin" always;
        add_header Permissions-Policy "camera=(), microphone=(), geolocation=(), payment=(), usb=(), fullscreen=(self)" always;
```

---

### Task 6: Deploy Backend and Nginx Safely

**Files:**
- Deploy: `backend/`
- Deploy: `nginx_optimize.conf`

- [ ] **Step 1: Build backend tarball**

Run: `tar -czf deploy_backend.tar.gz --exclude=node_modules --exclude=.env -C backend .`
Expected: tarball created.

- [ ] **Step 2: Upload and extract backend**

Use Python/Paramiko to upload `deploy_backend.tar.gz` to `/tmp/deploy_backend.tar.gz`, extract into `/var/www/getai-api`, and run `npm install --production`.

- [ ] **Step 3: Upload Nginx config backup + replacement**

Backup remote `/etc/nginx/sites-available/getai-ssl` to `/root/getai-ssl.backup.<timestamp>` before replacing it with `nginx_optimize.conf`.

- [ ] **Step 4: Test Nginx**

Run remote: `nginx -t`
Expected: syntax OK.

- [ ] **Step 5: Restart backend and reload Nginx**

Run remote:

```bash
pm2 restart getai-api --update-env
systemctl reload nginx
```

- [ ] **Step 6: Verify public app and API**

Run local:

```bash
rtk curl -sI https://askcore.dev
rtk curl -s https://askcore.dev/api/health
```

Expected: root returns 200 and health returns `{"status":"ok"}`.

---

### Task 7: Server Firewall and Fail2Ban

**Files:**
- Remote server config only.

- [ ] **Step 1: Install and enable Fail2Ban**

Run remote:

```bash
apt-get update
apt-get install -y fail2ban ufw
systemctl enable --now fail2ban
```

- [ ] **Step 2: Configure UFW safely**

Run remote:

```bash
ufw default deny incoming
ufw default allow outgoing
ufw allow OpenSSH
ufw allow 80/tcp
ufw allow 443/tcp
ufw deny 4000/tcp
ufw deny 4001/tcp
ufw --force enable
```

- [ ] **Step 3: Verify firewall and direct port closure**

Run local:

```bash
rtk curl -s -o /dev/null -w "%{http_code}\n" http://YOUR_SERVER_IP:4001/api/health
rtk curl -s -o /dev/null -w "%{http_code}\n" http://YOUR_SERVER_IP:4000/api/health
```

Expected: timeout/connection failure or non-200 through public IP. `https://askcore.dev/api/health` remains 200.

---

### Task 8: Register Endpoint Smoke Test

**Files:**
- Remote backend/API.

- [ ] **Step 1: Test invalid username**

Run:

```bash
rtk curl -s -X POST https://askcore.dev/api/auth/register -H "Content-Type: application/json" -d '{"username":"!!","password":"password123"}'
```

Expected: 400 with username validation error.

- [ ] **Step 2: Test valid registration with unique throwaway username**

Run with a unique username:

```bash
rtk curl -s -X POST https://askcore.dev/api/auth/register -H "Content-Type: application/json" -d '{"username":"testuser_<unique>","password":"password123"}'
```

Expected: 201 with token and user object.

- [ ] **Step 3: Test duplicate username**

Repeat Step 2 with same username.
Expected: 409 username already exists.

---

## Self-Review

Spec coverage:

- Backend binding: Task 1 and Task 6.
- CORS restriction: Task 1.
- Hide X-Powered-By: Task 1 and Task 5 proxy hide.
- Register simple anti-abuse: Task 2 and Task 3.
- Seed disable: Task 4.
- Nginx headers: Task 5.
- Deploy and verify: Task 6.
- UFW and Fail2Ban: Task 7.
- Register smoke test: Task 8.

Placeholder scan: no TBD/TODO implementation placeholders remain.

Type consistency: `created_ip`, `last_login_at`, `HOST`, `PORT`, auth routes, and limiter names are consistent across tasks.
