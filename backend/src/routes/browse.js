const express = require('express');
const { uploadFile, getPublicUrl } = require('../utils/minio');
const authMiddleware = require('../middleware/auth');
const { validatePublicHttpUrl } = require('../utils/urlSafety');
const { sendError } = require('../utils/errors');
const { assertQuota, recordUsage } = require('../utils/usage');
const logger = require('../utils/logger');
const metrics = require('../utils/metrics');

const router = express.Router();
router.use(authMiddleware);

// Shared browser process only; page/context is isolated per request.
let browserInstance = null;
let browserIdleTimer = null;
const BROWSER_IDLE_TIMEOUT = 120000; // 2 minutes

async function getBrowser() {
  if (browserInstance) {
    resetIdleTimer();
    return browserInstance;
  }

  const puppeteer = require('puppeteer');
  browserInstance = await puppeteer.launch({
    headless: 'new',
    args: [
      '--no-sandbox',
      '--disable-setuid-sandbox',
      '--disable-dev-shm-usage',
      '--disable-gpu',
      '--single-process',
      '--no-zygote',
      '--disable-extensions',
      '--disable-background-timer-throttling',
      '--disable-renderer-backgrounding',
      '--disable-backgrounding-occluded-windows',
    ],
    executablePath: process.env.CHROME_PATH || undefined,
  });

  logger.info('browse_browser_launched');
  resetIdleTimer();
  return browserInstance;
}

async function createIsolatedContext(browser) {
  if (typeof browser.createBrowserContext === 'function') {
    return browser.createBrowserContext();
  }
  if (typeof browser.createIncognitoBrowserContext === 'function') {
    return browser.createIncognitoBrowserContext();
  }
  return browser;
}

async function closeContext(context) {
  if (context && typeof context.close === 'function') {
    await context.close().catch(() => {});
  }
}

function resetIdleTimer() {
  if (browserIdleTimer) clearTimeout(browserIdleTimer);
  browserIdleTimer = setTimeout(async () => {
    if (browserInstance) {
      try {
        await browserInstance.close();
        logger.info('browse_browser_closed', { reason: 'idle_timeout' });
      } catch (_) {}
      browserInstance = null;
    }
  }, BROWSER_IDLE_TIMEOUT);
}

// Browse endpoint: navigate, screenshot, extract text
router.post('/', async (req, res) => {
  const { url, action = 'navigate', selector, text, scroll_direction } = req.body;

  if (!url && action === 'navigate') {
    return sendError(res, req, 400, 'URL required for navigate action', null, 'URL_REQUIRED');
  }

  let context;
  try {
    await assertQuota(req.userId, 'browse_request', 1);
    const safeNavigateUrl = action === 'navigate' ? await validatePublicHttpUrl(url) : null;
    const browser = await getBrowser();
    context = await createIsolatedContext(browser);
    const page = await context.newPage();

    await page.setViewport({ width: 1280, height: 800 });

    switch (action) {
      case 'navigate': {
        await page.goto(safeNavigateUrl, { waitUntil: 'domcontentloaded', timeout: 15000 });
        await page.waitForTimeout(1000);
        break;
      }
      case 'click': {
        if (selector) {
          await page.click(selector);
          await page.waitForTimeout(1000);
        }
        break;
      }
      case 'type': {
        if (selector && text) {
          await page.type(selector, text, { delay: 50 });
          await page.waitForTimeout(500);
        }
        break;
      }
      case 'scroll': {
        const direction = scroll_direction === 'up' ? -500 : 500;
        await page.evaluate((d) => window.scrollBy(0, d), direction);
        await page.waitForTimeout(500);
        break;
      }
      case 'press_enter': {
        await page.keyboard.press('Enter');
        await page.waitForTimeout(2000);
        break;
      }
    }

    const screenshotBuffer = await page.screenshot({
      type: 'jpeg',
      quality: 60,
      fullPage: false,
    });

    const key = `browse/${req.userId}/${Date.now()}.jpg`;
    await uploadFile(key, screenshotBuffer, 'image/jpeg', {
      'Cache-Control': 'public, max-age=31536000, immutable'
    });

    const screenshotUrl = getPublicUrl(key);
    const pageTitle = await page.title();
    const currentUrl = page.url();

    const pageText = await page.evaluate(() => {
      const body = document.body;
      if (!body) return '';
      const clone = body.cloneNode(true);
      clone.querySelectorAll('script, style, noscript, svg').forEach(el => el.remove());
      return clone.innerText?.substring(0, 3000) || '';
    });

    const elements = await page.evaluate(() => {
      const items = [];
      document.querySelectorAll('a[href]').forEach((el, i) => {
        if (i < 10 && el.innerText?.trim()) {
          items.push({ type: 'link', text: el.innerText.trim().substring(0, 80), href: el.href });
        }
      });
      document.querySelectorAll('input, textarea').forEach((el, i) => {
        if (i < 5) {
          items.push({
            type: 'input',
            name: el.name || el.placeholder || el.type,
            selector: el.id ? `#${el.id}` : `input[name="${el.name}"]`,
          });
        }
      });
      document.querySelectorAll('button, [role="button"]').forEach((el, i) => {
        if (i < 5 && el.innerText?.trim()) {
          items.push({ type: 'button', text: el.innerText.trim().substring(0, 50) });
        }
      });
      return items;
    });

    await recordUsage(req.userId, 'browse_request', 1, { action, url: safeNavigateUrl });

    res.json({
      screenshot_url: screenshotUrl,
      page_title: pageTitle,
      current_url: currentUrl,
      text_content: pageText,
      elements,
    });
  } catch (err) {
    metrics.inc('browse_failures_total', { action, code: err.code || 'BROWSE_FAILED' });
    const status = /private|localhost|http\/https|resolve/i.test(err.message || '') ? 400 : 500;
    return sendError(res, req, status, 'Browse failed', err);
  } finally {
    await closeContext(context);
  }
});

// Close browser manually
router.delete('/', async (req, res) => {
  if (browserInstance) {
    await browserInstance.close();
    browserInstance = null;
    if (browserIdleTimer) clearTimeout(browserIdleTimer);
  }
  res.json({ status: 'browser closed' });
});

module.exports = router;
