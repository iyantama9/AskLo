#!/bin/bash
set -e

echo "🚀 Deploying AskCore Flutter Web with Admin Panel..."

SERVER="root@178.128.59.20"
BUILD_DIR="build/web"
TARGET_DIR="/var/www/getai-web"

# Check if build exists
if [ ! -d "$BUILD_DIR" ]; then
  echo "❌ Build directory not found. Run 'flutter build web' first."
  exit 1
fi

echo "📦 Creating backup..."
ssh $SERVER "cd $TARGET_DIR && tar -czf ../getai-web.backup.\$(date +%Y%m%d-%H%M%S).tar.gz ."

echo "📤 Uploading Flutter web build..."
rsync -avz --delete \
  --exclude='.git' \
  --exclude='*.map' \
  $BUILD_DIR/ $SERVER:$TARGET_DIR/

echo "🗑️  Removing old standalone admin.html..."
ssh $SERVER "rm -f $TARGET_DIR/admin.html"

echo "🔧 Setting permissions..."
ssh $SERVER "chown -R www-data:www-data $TARGET_DIR && chmod -R 755 $TARGET_DIR"

echo "✅ Deployment complete!"
echo ""
echo "🌐 Test URLs:"
echo "   Main app: https://askcore.dev"
echo "   Admin:    https://askcore.dev/admin"
echo ""
echo "💡 Admin credentials:"
echo "   Username: admin"
echo "   Password: admin123"
