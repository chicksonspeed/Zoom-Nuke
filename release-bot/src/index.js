'use strict';

const http = require('http');
const crypto = require('crypto');
const https = require('https');
const fs = require('fs');
const path = require('path');

// ---------------------------------------------------------------------------
// Load .env in development (ignored if the file doesn't exist in production)
// ---------------------------------------------------------------------------
try {
  require('dotenv').config();
} catch {
  // dotenv not installed or .env missing — rely on real env vars
}

// ---------------------------------------------------------------------------
// Environment validation
// ---------------------------------------------------------------------------
const REQUIRED_ENV = [
  'TELEGRAM_BOT_TOKEN',
  'TELEGRAM_CHAT_ID',
  'GITHUB_WEBHOOK_SECRET',
];

for (const key of REQUIRED_ENV) {
  if (!process.env[key]) {
    console.error(`[FATAL] Missing required environment variable: ${key}`);
    process.exit(1);
  }
}

const {
  TELEGRAM_BOT_TOKEN,
  TELEGRAM_CHAT_ID,
  GITHUB_WEBHOOK_SECRET,
  PORT = '3000',
} = process.env;

// ---------------------------------------------------------------------------
// Duplicate-prevention state  (persisted to disk)
// ---------------------------------------------------------------------------
const STATE_FILE = path.join(__dirname, '..', 'posted-releases.json');

function loadState() {
  try {
    if (fs.existsSync(STATE_FILE)) {
      const raw = fs.readFileSync(STATE_FILE, 'utf8');
      return JSON.parse(raw);
    }
  } catch (err) {
    console.warn('[WARN] Could not read state file, starting fresh:', err.message);
  }
  return { postedTags: [] };
}

function saveState(state) {
  try {
    fs.writeFileSync(STATE_FILE, JSON.stringify(state, null, 2), 'utf8');
  } catch (err) {
    console.error('[ERROR] Could not write state file:', err.message);
  }
}

// ---------------------------------------------------------------------------
// GitHub signature verification
// ---------------------------------------------------------------------------
function verifySignature(rawBody, signatureHeader) {
  if (!signatureHeader || !signatureHeader.startsWith('sha256=')) {
    return false;
  }
  const hmac = crypto.createHmac('sha256', GITHUB_WEBHOOK_SECRET);
  hmac.update(rawBody);
  const expected = Buffer.from('sha256=' + hmac.digest('hex'));
  const received = Buffer.from(signatureHeader);

  if (expected.length !== received.length) return false;
  try {
    return crypto.timingSafeEqual(expected, received);
  } catch {
    return false;
  }
}

// ---------------------------------------------------------------------------
// Telegram
// ---------------------------------------------------------------------------
function sendTelegramMessage(text) {
  return new Promise((resolve, reject) => {
    const body = JSON.stringify({
      chat_id: TELEGRAM_CHAT_ID,
      text,
      parse_mode: 'HTML',
      disable_web_page_preview: false,
    });

    const options = {
      hostname: 'api.telegram.org',
      path: `/bot${TELEGRAM_BOT_TOKEN}/sendMessage`,
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Content-Length': Buffer.byteLength(body),
      },
    };

    const req = https.request(options, (res) => {
      let data = '';
      res.on('data', (chunk) => (data += chunk));
      res.on('end', () => {
        let parsed;
        try {
          parsed = JSON.parse(data);
        } catch {
          return reject(new Error('Telegram returned non-JSON response'));
        }
        if (parsed.ok) {
          resolve(parsed);
        } else {
          reject(new Error(`Telegram API error: ${parsed.description}`));
        }
      });
    });

    req.on('error', reject);
    req.write(body);
    req.end();
  });
}

// ---------------------------------------------------------------------------
// Message formatter
// ---------------------------------------------------------------------------
function formatReleaseMessage(release) {
  const { tag_name, name, body, html_url } = release;

  // Strip markdown-ish headers (#, ##) and truncate long release notes
  let summary = (body || '').trim();
  summary = summary.replace(/^#{1,4}\s.+$/gm, '').replace(/\n{3,}/g, '\n\n').trim();
  if (summary.length > 350) {
    summary = summary.slice(0, 347) + '…';
  }
  if (!summary) summary = '(No release notes provided)';

  const title = name && name !== tag_name ? name : tag_name;

  return (
    `🚨 <b>Zoom-Nuke release published</b>\n\n` +
    `<b>Version:</b> ${escapeHtml(tag_name)}\n` +
    `<b>Title:</b> ${escapeHtml(title)}\n\n` +
    `${escapeHtml(summary)}\n\n` +
    `<b>Download:</b>\n${html_url}`
  );
}

function escapeHtml(str) {
  return String(str)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;');
}

// ---------------------------------------------------------------------------
// HTTP server
// ---------------------------------------------------------------------------
const server = http.createServer((req, res) => {
  // ------ Health check ------
  if (req.method === 'GET' && req.url === '/health') {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ status: 'ok', timestamp: new Date().toISOString() }));
    return;
  }

  // ------ GitHub webhook ------
  if (req.method === 'POST' && req.url === '/webhook') {
    let rawBody = '';

    req.on('data', (chunk) => (rawBody += chunk));

    req.on('end', async () => {
      // 1. Verify signature
      const sigHeader = req.headers['x-hub-signature-256'] || '';
      if (!verifySignature(rawBody, sigHeader)) {
        console.warn('[WARN] Rejected request: invalid or missing webhook signature');
        res.writeHead(401, { 'Content-Type': 'text/plain' });
        res.end('Unauthorized');
        return;
      }

      // 2. Check event type — only care about "release"
      const event = req.headers['x-github-event'];
      if (event !== 'release') {
        console.log(`[INFO] Ignored event type: "${event}"`);
        res.writeHead(200);
        res.end('OK');
        return;
      }

      // 3. Parse payload
      let payload;
      try {
        payload = JSON.parse(rawBody);
      } catch (err) {
        console.error('[ERROR] Failed to parse webhook payload:', err.message);
        res.writeHead(400, { 'Content-Type': 'text/plain' });
        res.end('Bad Request');
        return;
      }

      const { action, release } = payload;

      // 4. Only react to "published"
      if (action !== 'published') {
        console.log(`[INFO] Ignored release action: "${action}"`);
        res.writeHead(200);
        res.end('OK');
        return;
      }

      // 5. Validate release data
      if (!release || !release.tag_name || !release.html_url) {
        console.error('[ERROR] Payload is missing required release fields (tag_name, html_url)');
        res.writeHead(400, { 'Content-Type': 'text/plain' });
        res.end('Missing release data');
        return;
      }

      const { tag_name } = release;

      // 6. Skip drafts
      if (release.draft) {
        console.log(`[INFO] Skipped draft release: ${tag_name}`);
        res.writeHead(200);
        res.end('OK');
        return;
      }

      // 7. Duplicate guard
      const state = loadState();
      if (state.postedTags.includes(tag_name)) {
        console.log(`[INFO] Duplicate event — already posted release: ${tag_name}`);
        res.writeHead(200);
        res.end('OK');
        return;
      }

      // 8. Send to Telegram
      const message = formatReleaseMessage(release);
      console.log(`[INFO] Sending Telegram announcement for release: ${tag_name}`);

      try {
        await sendTelegramMessage(message);
        // Persist so we never re-post this tag
        state.postedTags.push(tag_name);
        saveState(state);
        console.log(`[INFO] ✅ Posted release ${tag_name} to Telegram`);
        res.writeHead(200);
        res.end('OK');
      } catch (err) {
        console.error(`[ERROR] Telegram send failed for ${tag_name}:`, err.message);
        res.writeHead(500, { 'Content-Type': 'text/plain' });
        res.end('Telegram delivery failed');
      }
    });

    req.on('error', (err) => {
      console.error('[ERROR] Request stream error:', err.message);
    });

    return;
  }

  // ------ 404 fallback ------
  res.writeHead(404);
  res.end('Not Found');
});

server.listen(parseInt(PORT, 10), () => {
  console.log(`[INFO] Zoom-Nuke release bot started on port ${PORT}`);
  console.log(`[INFO]   POST /webhook  — GitHub release events`);
  console.log(`[INFO]   GET  /health   — health check`);
});

server.on('error', (err) => {
  console.error('[FATAL] Server error:', err.message);
  process.exit(1);
});
