# AskCore Logo/Render Issue - Root Cause and Fix

## Problem
The logo was not appearing because **the entire app was not rendering**. Only a blank screen with an "Enable accessibility" button was visible.

## Root Cause
**Service Worker Reload Loop**

Flutter's generated `flutter_service_worker.js` creates an infinite reload loop:

1. Bootstrap loads and tries to register `flutter_service_worker.js`
2. The service worker immediately unregisters itself (Flutter's deprecation pattern)
3. During unregistration, it calls `client.navigate(client.url)` which **force-reloads the page**
4. The page reloads and bootstrap tries to register the service worker again
5. Loop repeats infinitely - Flutter never completes initialization

Evidence:
- Console showed "Injecting <script> tag" 4 times (multiple initialization attempts)
- No canvas elements created (rendering never started)
- No scene host created (app never mounted)
- `engineInitialized: false` despite all assets loading successfully

## Secondary Issue
**Malformed Build Config**

`flutter_bootstrap.js` contained:
```javascript
_flutter.buildConfig = {
  "builds": [
    {"compileTarget":"dart2js","renderer":"canvaskit","mainJsPath":"main.dart.js"},
    {}  // ← Empty object breaks build selection
  ]
}
```

## Fix Applied

### 1. Remove forced reload from service worker
**File:** `build/web/flutter_service_worker.js`

Changed:
```javascript
// OLD - forces page reload
clients.forEach((client) => {
  if (client.url && 'navigate' in client) {
    client.navigate(client.url);
  }
});
```

To:
```javascript
// NEW - no reload needed
// Service worker unregistered successfully, no need to reload clients
```

### 2. Fix malformed build config
**File:** `build/web/flutter_bootstrap.js`

Changed:
```javascript
// OLD
"builds":[{"compileTarget":"dart2js","renderer":"canvaskit","mainJsPath":"main.dart.js"},{}]

// NEW
"builds":[{"compileTarget":"dart2js","renderer":"canvaskit","mainJsPath":"main.dart.js"}]
```

## Deployment

Run the deployment script:
```bash
bash d:/Project/GetAI/deploy_fix.sh
```

Or deploy manually:
```bash
scp d:/Project/GetAI/build/web/flutter_bootstrap.js \
    d:/Project/GetAI/build/web/flutter_service_worker.js \
    root@178.128.59.20:/var/www/getai-web/
```

## Verification

After deployment:
1. Open https://askcore.dev in a fresh incognito window
2. The login screen should render immediately with the logo visible
3. Console should show only 1 "Injecting <script> tag" message (not 3-4)
4. No page reloads should occur during initialization

## Why This Wasn't Caught Earlier

The issue only manifests in the deployed environment because:
- Local Flutter development uses hot reload, not service workers
- The service worker deprecation pattern (auto-unregister) is new in recent Flutter versions
- The forced reload happens after initialization starts, so there's no error message
- Browser caches can mask the issue until a hard refresh occurs

## Logo Files Status
All logo files are valid and deployed correctly:
- `assets/logo.png` - 1180536 bytes, valid PNG
- Successfully loading from https://askcore.dev/assets/assets/logo.png
- The logo issue was never about the logo files - it was about the app not rendering at all
