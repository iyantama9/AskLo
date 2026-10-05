#!/bin/bash
# Safe Flutter Web Deployment with Cache Busting
# Usage: ./deploy_web_safe.sh

set -e

echo "🚀 Starting safe Flutter web deployment..."

# 1. Clean build
echo "📦 Building Flutter web..."
cd "$(dirname "$0")"
flutter clean
flutter build web --release --no-tree-shake-icons

# 2. Generate timestamp for cache busting
TIMESTAMP=$(date +%s)
echo "⏰ Cache buster timestamp: $TIMESTAMP"

# 3. Fix Flutter files (remove service worker registration)
echo "🔧 Fixing Flutter generated files..."

# Remove service worker registration from flutter_bootstrap.js
sed -i 's|_flutter.loader.load({[^}]*serviceWorkerSettings[^}]*});|_flutter.loader.load({});|g' build/web/flutter_bootstrap.js

# Remove reload from service worker
sed -i '/client.navigate(client.url)/d' build/web/flutter_service_worker.js

# 4. Add cache busters to index.html
echo "🔄 Adding cache busters to index.html..."
sed -i "s|flutter_bootstrap.js|flutter_bootstrap.js?v=$TIMESTAMP|g" build/web/index.html
sed -i "s|main.dart.js|main.dart.js?v=$TIMESTAMP|g" build/web/index.html

# Add no-cache meta tags if not present
if ! grep -q "Cache-Control" build/web/index.html; then
  sed -i '/<head>/a\  <meta http-equiv="Cache-Control" content="no-cache, no-store, must-revalidate">\n  <meta http-equiv="Pragma" content="no-cache">\n  <meta http-equiv="Expires" content="0">' build/web/index.html
fi

# 5. Create deployment package
echo "📦 Creating deployment package..."
cd build/web
tar -czf ../../deploy_web_${TIMESTAMP}.tar.gz .
cd ../..

echo "✅ Build complete: deploy_web_${TIMESTAMP}.tar.gz"
echo ""
echo "📤 Deploying to server..."

# 6. Upload to server
scp deploy_web_${TIMESTAMP}.tar.gz root@178.128.59.20:/tmp/

# 7. Extract and update on server
ssh root@178.128.59.20 << EOF
set -e
cd /var/www/getai-web

# Backup current version
if [ -d "backup_\$(date +%Y%m%d)" ]; then
  rm -rf backup_\$(date +%Y%m%d)
fi
mkdir -p backup_\$(date +%Y%m%d)
cp -r * backup_\$(date +%Y%m%d)/ 2>/dev/null || true

# Extract new version
tar -xzf /tmp/deploy_web_${TIMESTAMP}.tar.gz

# Clear Nginx cache
rm -rf /var/cache/nginx/*

# Reload Nginx
systemctl reload nginx

# Cleanup
rm /tmp/deploy_web_${TIMESTAMP}.tar.gz

echo "✅ Deployment complete!"
echo "🌐 Live at: https://askcore.dev"
EOF

echo ""
echo "🎉 Deployment successful!"
echo "Cache buster: v=$TIMESTAMP"
echo ""
echo "⚠️  Users may need to:"
echo "   - Hard refresh (Ctrl+Shift+R)"
echo "   - Or clear browser cache if they have old version cached"
