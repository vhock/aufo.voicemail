const http = require('http');
const fs = require('fs');
const fsp = fs.promises;
const path = require('path');

const HOST = '0.0.0.0';
const PORT = process.env.PORT || 3000;
const PUBLIC_DIR = __dirname;
const FEEDBACK_FILE = path.join(__dirname, 'feedback-submissions.jsonl');

const MIME_TYPES = {
  '.html': 'text/html; charset=utf-8',
  '.css': 'text/css; charset=utf-8',
  '.js': 'application/javascript; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.txt': 'text/plain; charset=utf-8',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.ico': 'image/x-icon'
};

function sendJson(res, statusCode, payload, extraHeaders = {}) {
  res.writeHead(statusCode, {
    'Content-Type': 'application/json; charset=utf-8',
    ...extraHeaders
  });
  res.end(JSON.stringify(payload));
}

function apiCorsHeaders() {
  return {
    'Access-Control-Allow-Origin': '*',
    'Access-Control-Allow-Methods': 'GET,POST,OPTIONS',
    'Access-Control-Allow-Headers': 'Content-Type'
  };
}

function safePathname(urlPath) {
  const normalized = path.normalize(urlPath).replace(/^([.][.][/\\])+/, '');
  if (normalized.startsWith('..')) return null;
  return normalized;
}

async function serveStatic(req, res) {
  const requestPath = req.url === '/' ? '/index.html' : req.url;
  const cleanPath = safePathname(decodeURIComponent(requestPath.split('?')[0]));
  if (!cleanPath) {
    res.writeHead(400);
    res.end('Bad request');
    return;
  }

  const absolutePath = path.join(PUBLIC_DIR, cleanPath);

  try {
    const stat = await fsp.stat(absolutePath);
    if (!stat.isFile()) {
      res.writeHead(404);
      res.end('Not found');
      return;
    }

    const ext = path.extname(absolutePath).toLowerCase();
    const mime = MIME_TYPES[ext] || 'application/octet-stream';
    res.writeHead(200, { 'Content-Type': mime });
    fs.createReadStream(absolutePath).pipe(res);
  } catch {
    res.writeHead(404);
    res.end('Not found');
  }
}

function readJsonBody(req, maxBytes = 100_000) {
  return new Promise((resolve, reject) => {
    let raw = '';

    req.on('data', chunk => {
      raw += chunk;
      if (raw.length > maxBytes) {
        reject(new Error('Payload too large'));
        req.destroy();
      }
    });

    req.on('end', () => {
      if (!raw) {
        resolve({});
        return;
      }
      try {
        resolve(JSON.parse(raw));
      } catch {
        reject(new Error('Invalid JSON'));
      }
    });

    req.on('error', reject);
  });
}

function validateFeedback(data) {
  const rating = Number(data.easeRating);
  const feedbackText = (data.feedbackText || '').toString().trim();

  if (!Number.isInteger(rating) || rating < 1 || rating > 5) {
    return 'easeRating must be an integer from 1 to 5';
  }

  if (!feedbackText) {
    return 'feedbackText is required';
  }

  if (feedbackText.length > 4000) {
    return 'feedbackText must be 4000 characters or fewer';
  }

  return null;
}

async function appendFeedbackRecord(record) {
  const line = JSON.stringify(record) + '\n';
  await fsp.appendFile(FEEDBACK_FILE, line, 'utf8');
}

async function readAllFeedback() {
  try {
    const text = await fsp.readFile(FEEDBACK_FILE, 'utf8');
    return text
      .split('\n')
      .filter(Boolean)
      .map(line => {
        try {
          return JSON.parse(line);
        } catch {
          return null;
        }
      })
      .filter(Boolean);
  } catch {
    return [];
  }
}

const server = http.createServer(async (req, res) => {
  const urlPath = req.url.split('?')[0];

  if (req.method === 'OPTIONS' && urlPath === '/api/feedback') {
    res.writeHead(204, apiCorsHeaders());
    res.end();
    return;
  }

  if (req.method === 'POST' && urlPath === '/api/feedback') {
    try {
      const body = await readJsonBody(req);
      const validationError = validateFeedback(body);

      if (validationError) {
        sendJson(res, 400, { ok: false, error: validationError }, apiCorsHeaders());
        return;
      }

      const record = {
        participantId: (body.participantId || '').toString().trim(),
        voicemailLanguage: (body.voicemailLanguage || '').toString().trim(),
        easeRating: Number(body.easeRating),
        feedbackText: body.feedbackText.toString().trim(),
        uiLanguage: (body.uiLanguage || '').toString().trim(),
        submittedAt: body.submittedAt || new Date().toISOString(),
        receivedAt: new Date().toISOString(),
        ip: req.socket.remoteAddress || ''
      };

      await appendFeedbackRecord(record);
      sendJson(res, 201, { ok: true }, apiCorsHeaders());
      return;
    } catch (err) {
      sendJson(res, 400, { ok: false, error: err.message || 'Bad request' }, apiCorsHeaders());
      return;
    }
  }

  if (req.method === 'GET' && urlPath === '/api/feedback') {
    const submissions = await readAllFeedback();
    sendJson(res, 200, { ok: true, count: submissions.length, submissions }, apiCorsHeaders());
    return;
  }

  await serveStatic(req, res);
});

server.listen(PORT, HOST, () => {
  console.log(`Server running on http://localhost:${PORT}`);
});
