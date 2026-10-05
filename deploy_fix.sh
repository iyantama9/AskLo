#!/bin/bash
# Deploy fixed Flutter web files to resolve reload loop

echo "Deploying fixed flutter_service_worker.js and flutter_bootstrap.js..."

scp d:/Project/GetAI/build/web/flutter_bootstrap.js \
    d:/Project/GetAI/build/web/flutter_service_worker.js \
    root@178.128.59.20:/var/www/getai-web/

echo "Deployment complete. Test at https://askcore.dev"
