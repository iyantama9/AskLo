#!/bin/bash
echo "=== UPTIME ==="
uptime
echo "=== MEMORY ==="
free -m
echo "=== DISK ==="
df -h /
echo "=== NGINX ==="
systemctl is-active nginx
echo "=== PM2 ==="
pm2 pid askcore-api 2>/dev/null || echo "no pm2"
echo "=== PORTS ==="
ss -tlnp | grep -E ':80|:4000|:22'
echo "=== FIX NGINX ==="
fuser -k 80/tcp 2>/dev/null
systemctl restart nginx
systemctl is-active nginx
echo "=== VERIFY ==="
curl -s -o /dev/null -w '%{http_code}' http://localhost
echo ""
echo "=== DONE ==="
