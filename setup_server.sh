#!/bin/bash
set -e

echo "=== Updating packages ==="
apt-get update -y
apt-get install -y curl nginx

echo "=== Installing Node.js 22 ==="
curl -fsSL https://deb.nodesource.com/setup_22.x | bash -
apt-get install -y nodejs
npm install -g pm2

echo "=== Extracting Backend ==="
rm -rf /var/www/askcore-api/*
mkdir -p /var/www/askcore-api
tar -xzf /var/www/deploy_backend.tar.gz -C /var/www/askcore-api/
cd /var/www/askcore-api/backend
npm install

echo "=== Starting Backend with PM2 ==="
pm2 stop askcore-api || true
pm2 start src/index.js --name "askcore-api"
pm2 save
env PATH=$PATH:/usr/bin pm2 startup systemd -u root --hp /root || true

echo "=== Extracting Frontend ==="
rm -rf /var/www/askcore-web/*
mkdir -p /var/www/askcore-web
tar -xzf /var/www/deploy_web.tar.gz -C /var/www/askcore-web/

echo "=== Configuring Nginx ==="
cat > /etc/nginx/sites-available/askcore << 'EOF'
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name _;
    
    # Frontend Flutter Web
    location / {
        root /var/www/askcore-web;
        index index.html index.htm;
        try_files $uri $uri/ /index.html;
    }

    # Backend API Proxy
    location /api/ {
        proxy_pass http://localhost:4000/api/;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host $host;
        proxy_cache_bypass $http_upgrade;
    }
}
EOF

ln -sf /etc/nginx/sites-available/askcore /etc/nginx/sites-enabled/
rm -f /etc/nginx/sites-enabled/default
nginx -t
systemctl restart nginx

echo "=== Server Setup Completed Successfully ==="
