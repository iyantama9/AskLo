# Flutter Web Deployment Guide - AskCore

## Masalah yang Pernah Terjadi

**Problem:** Setelah deploy, app gak render di beberapa device karena browser cache versi lama.

**Root Cause:**
1. Nginx set cache 1 tahun untuk semua .js files
2. Browser (terutama mobile) aggressive caching
3. Flutter service worker bikin reload loop
4. Main.dart.js ke-cache tanpa version number

---

## ✅ Solusi Permanent (Sudah Diterapkan)

### 1. Automatic Cache Busting
Setiap deploy, semua JS files dapat timestamp unik:
- `flutter_bootstrap.js?v=1784796296`
- `main.dart.js?v=1784796633`

### 2. No-Cache Meta Tags
```html
<meta http-equiv="Cache-Control" content="no-cache, no-store, must-revalidate">
<meta http-equiv="Pragma" content="no-cache">
<meta http-equiv="Expires" content="0">
```

### 3. Service Worker Disabled
- Tidak ada service worker registration
- Tidak ada forced reload yang bikin loop

### 4. Nginx Config
- Flutter bootstrap files: cache 5 menit
- Other static files: cache 1 tahun (normal)

---

## 🚀 Cara Deploy yang Benar

### Option 1: Pakai Script Otomatis (Recommended)

```bash
cd d:/Project/GetAI
bash deploy_web_safe.sh
```

Script ini otomatis:
- Clean build
- Fix Flutter generated files
- Add cache busters
- Upload ke server
- Clear Nginx cache
- Backup versi lama

### Option 2: Manual Deploy

```bash
# 1. Build
flutter clean
flutter build web --release --no-tree-shake-icons

# 2. Fix files
cd build/web

# Remove service worker registration.
# The generated bootstrap ends with:
#   _flutter.loader.load({ serviceWorkerSettings: { serviceWorkerVersion: "..." } });
# Patch it to a no-arg load() so the SW never registers (SW would otherwise
# trigger a reload loop on cold start). The block spans multiple lines, so
# delete everything from "_flutter.loader.load({" up to the matching ");".
python3 - <<'PY'
import re
p = "flutter_bootstrap.js"
s = open(p, encoding="utf-8").read()
s = re.sub(r"_flutter\.loader\.load\(\{[\s\S]*?\}\);", "_flutter.loader.load();", s)
open(p, "w", encoding="utf-8").write(s)
print("patched" if "_flutter.loader.load();" in s else "PATCH FAILED")
PY

# 3. Add timestamp ke index.html
TIMESTAMP=$(date +%s)
sed -i "s|flutter_bootstrap.js|flutter_bootstrap.js?v=$TIMESTAMP|g" index.html

# 4. Upload
tar -czf ../../deploy.tar.gz .
scp ../../deploy.tar.gz root@178.128.59.20:/tmp/

# 5. Extract di server
ssh root@178.128.59.20 "
  cd /var/www/getai-web
  tar -xzf /tmp/deploy.tar.gz
  rm -rf /var/cache/nginx/*
  systemctl reload nginx
"
```

---

## 📱 Kalau User Complain "App Gak Update"

### Quick Fix untuk User:

**Desktop:**
1. Hard refresh: `Ctrl + Shift + R` (Windows) atau `Cmd + Shift + R` (Mac)
2. Atau clear cache: Settings → Privacy → Clear browsing data

**Mobile (Chrome Android):**
1. Tutup app completely (swipe dari recent apps)
2. Buka lagi dan refresh
3. Kalau masih stuck: Settings → Site settings → Clear & reset

**iOS Safari:**
1. Settings → Safari → Clear History and Website Data
2. Atau long press refresh button → "Reload Without Content Blockers"

---

## 🔍 Debugging Cache Issues

### Check kalau user dapat versi lama:

```javascript
// Di browser console user
console.log(window._flutter?.buildConfig);
// Harusnya return object dengan builds array yang bener (tanpa empty {})

// Check timestamp
document.querySelector('script[src*="flutter_bootstrap"]').src
// Harusnya ada ?v=TIMESTAMP
```

### Check di server:

```bash
ssh root@178.128.59.20 "
  # Check file timestamps
  ls -la /var/www/getai-web/flutter_bootstrap.js
  ls -la /var/www/getai-web/main.dart.js
  
  # Check Nginx cache
  ls -la /var/cache/nginx/
  
  # Check index.html
  grep 'flutter_bootstrap' /var/www/getai-web/index.html
"
```

---

## ⚠️ Yang HARUS Dihindari

❌ **Jangan deploy langsung tanpa cache buster**
- User bakal stuck di versi lama

❌ **Jangan lupa clear Nginx cache**
- Server bakal serve cached version

❌ **Jangan edit production files langsung di server**
- Always build locally, deploy tarball

❌ **Jangan skip flutter clean**
- Old build artifacts bisa bikin masalah

---

## 🎯 Checklist Sebelum Deploy

- [ ] `flutter clean` done
- [ ] Build dengan `--release --no-tree-shake-icons`
- [ ] Service worker registration removed
- [ ] Cache buster timestamp added
- [ ] Backup versi sebelumnya (otomatis di script)
- [ ] Nginx cache cleared setelah deploy
- [ ] Test di incognito window setelah deploy
- [ ] Test di mobile device

---

## 📊 Version Tracking

Track setiap deploy:

```bash
# Di server, check current version
ssh root@178.128.59.20 "grep 'flutter_bootstrap.js?v=' /var/www/getai-web/index.html"

# Output: flutter_bootstrap.js?v=1784796296
# Timestamp ini = version number
```

Convert timestamp ke human readable:
```bash
date -d @1784796296
# Output: Wed Jul 23 15:44:56 WIB 2026
```

---

## 🔄 Emergency Rollback

Kalau deploy baru bermasalah:

```bash
ssh root@178.128.59.20 "
  cd /var/www/getai-web
  
  # Check available backups
  ls -la backup_*
  
  # Restore dari backup
  cp -r backup_20260723/* .
  
  # Clear cache & reload
  rm -rf /var/cache/nginx/*
  systemctl reload nginx
"
```

---

## 🎓 Lessons Learned

1. **Always use cache busting** untuk semua versioned assets
2. **Test di multiple devices** sebelum announce update
3. **Keep backups** setiap deploy
4. **Monitor user complaints** - kalau banyak yang "gak bisa akses", likely cache issue
5. **Document everything** - masalah cache susah di-debug kalau gak ada log

---

## 📞 Quick Commands

```bash
# Deploy baru
bash deploy_web_safe.sh

# Check status
ssh root@178.128.59.20 "systemctl status nginx"

# Clear cache manual
ssh root@178.128.59.20 "rm -rf /var/cache/nginx/* && systemctl reload nginx"

# View logs
ssh root@178.128.59.20 "tail -f /var/log/nginx/error.log"
```
