import express from 'express';
import multer from 'multer';
import { randomUUID } from 'node:crypto';
import path from 'node:path';
import fs from 'node:fs';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const UPLOADS_DIR = path.join(__dirname, 'uploads');
const PORT = process.env.PORT || 5178;
const DOCS_PORT = process.env.DOCS_PORT || 8090;
const CALLBACK_HOST = process.env.CALLBACK_HOST || 'host.docker.internal';

if (!fs.existsSync(UPLOADS_DIR)) fs.mkdirSync(UPLOADS_DIR, { recursive: true });

// In-memory store: id → { filename, ext, originalPath, editedPath, savedAt }
const sessions = new Map();

const DOCUMENT_TYPES = {
  doc: 'word', docx: 'word', odt: 'word', rtf: 'word', txt: 'word',
  xls: 'cell', xlsx: 'cell', ods: 'cell', csv: 'cell',
  ppt: 'slide', pptx: 'slide', odp: 'slide', ppsx: 'slide',
  pdf: 'pdf'
};

function docType(ext) {
  return DOCUMENT_TYPES[ext.toLowerCase()] || 'word';
}

const app = express();
app.use(express.json());
app.use((req, _res, next) => { console.log(`→ ${req.method} ${req.path}`); next(); });
app.use(express.static(path.join(__dirname, 'public')));

const upload = multer({ storage: multer.memoryStorage() });

// 1. Upload file — save to disk, create session
app.post('/api/upload', upload.single('file'), (req, res) => {
  if (!req.file) return res.status(400).json({ error: 'No file selected.' });

  const id = randomUUID();
  const ext = path.extname(req.file.originalname).slice(1).toLowerCase();
  const originalPath = path.join(UPLOADS_DIR, `${id}_original.${ext}`);

  fs.writeFileSync(originalPath, req.file.buffer);
  sessions.set(id, { filename: req.file.originalname, ext, originalPath, editedPath: null, savedAt: null });

  res.json({ id, filename: req.file.originalname, ext });
});

// 2. Serve original file — ONLYOFFICE Document Server fetches from here
app.get('/api/file/:id', (req, res) => {
  const session = sessions.get(req.params.id);
  if (!session) return res.status(404).send('Not found');
  res.sendFile(session.originalPath);
});

// 3. Callback — ONLYOFFICE posts here when user saves
// status 2 = document ready for saving, status 6 = force save
app.post('/api/callback/:id', async (req, res) => {
  const { status, url } = req.body;
  const session = sessions.get(req.params.id);

  if (!session) return res.json({ error: 0 });

  if ((status === 2 || status === 6) && url) {
    try {
      // ONLYOFFICE sends a URL pointing to its own server — rewrite to localhost
      const localUrl = url.replace(/^https?:\/\/[^/]+/, `http://localhost:${DOCS_PORT}`);
      const fileRes = await fetch(localUrl);
      if (fileRes.ok) {
        const buffer = Buffer.from(await fileRes.arrayBuffer());
        const editedPath = path.join(UPLOADS_DIR, `${req.params.id}_edited.${session.ext}`);
        fs.writeFileSync(editedPath, buffer);
        session.editedPath = editedPath;
        session.savedAt = Date.now();
        console.log(`[${req.params.id}] Saved edited file (status ${status})`);
      }
    } catch (err) {
      console.error(`[${req.params.id}] Callback download failed:`, err.message);
    }
  }

  // ONLYOFFICE expects { error: 0 } to confirm receipt
  res.json({ error: 0 });
});

// 4. Poll status — UI polls this to know when file is ready to download
app.get('/api/status/:id', (req, res) => {
  const session = sessions.get(req.params.id);
  if (!session) return res.status(404).json({ error: 'Session not found' });
  res.json({ ready: !!session.editedPath, savedAt: session.savedAt });
});

// 5. Download edited file
app.get('/api/download/:id', (req, res) => {
  const session = sessions.get(req.params.id);
  if (!session || !session.editedPath) return res.status(404).json({ error: 'No saved file yet — please save in the editor first.' });
  res.download(session.editedPath, session.filename);
});

// 6. Editor config — returns the ONLYOFFICE DocsAPI config for a session
app.get('/api/editor-config/:id', (req, res) => {
  const session = sessions.get(req.params.id);
  if (!session) return res.status(404).json({ error: 'Session not found' });

  // localhost:8091 = nginx inside Docker container, serving ./uploads/ volume mount
  // avoids host.docker.internal which ONLYOFFICE docservice can't reach on macOS
  const fileUrl = `http://localhost:8091/uploads/${req.params.id}_original.${session.ext}`;
  const callbackUrl = `http://${CALLBACK_HOST}:${PORT}/api/callback/${req.params.id}`;

  res.json({
    document: {
      fileType: session.ext,
      key: req.params.id,
      title: session.filename,
      url: fileUrl,
      permissions: { edit: session.ext !== 'pdf', download: false }
    },
    documentType: docType(session.ext),
    editorConfig: {
      callbackUrl,
      user: { id: '1', name: 'Test User' },
      customization: {
        autosave: false,
        forcesave: true,
        about: false,
        feedback: false,
        help: false,
        toolbarNoTabs: true
      },
      coEditing: { mode: 'strict', change: false }
    }
  });
});

// 7. Editor-only page — loaded by iOS WKWebView (no upload/download UI, iOS handles those natively)
app.get('/editor/:id', (req, res) => {
  const session = sessions.get(req.params.id);
  if (!session) return res.status(404).send('Session not found');
  res.send(`<!doctype html>
<html>
<head>
<meta charset="utf-8"/>
<meta name="viewport" content="width=device-width, initial-scale=1, user-scalable=no"/>
<style>
  * { margin: 0; padding: 0; box-sizing: border-box; }
  html, body { width: 100%; height: 100%; overflow: hidden; background: #fff; }
  #editor { width: 100%; height: 100%; }
</style>
</head>
<body>
<div id="editor"></div>
<script>
(function () {
  var host = window.location.hostname;
  var docsOrigin = window.location.protocol + '//' + host + ':${DOCS_PORT}';
  var sessionId = '${req.params.id}';

  function postToNative(msg) {
    try { window.webkit.messageHandlers.ooEvent.postMessage(msg); } catch (_) {}
  }

  fetch('/api/editor-config/' + sessionId)
    .then(function (r) { return r.json(); })
    .then(function (config) {
      var s = document.createElement('script');
      s.src = docsOrigin + '/web-apps/apps/api/documents/api.js';
      s.onload = function () {
        new DocsAPI.DocEditor('editor', Object.assign({}, config, {
          height: '100%',
          width: '100%',
          events: {
            onDocumentStateChange: function (e) {
              postToNative({ type: 'stateChange', dirty: !!e.data });
            },
            onError: function (e) {
              postToNative({ type: 'error', data: e.data });
            }
          }
        }));
      };
      s.onerror = function () { postToNative({ type: 'loadError' }); };
      document.head.appendChild(s);
    })
    .catch(function (e) { postToNative({ type: 'configError', message: e.message }); });
})();
</script>
</body>
</html>`);
});

// Proxy healthcheck
app.get('/api/healthcheck', async (req, res) => {
  try {
    const r = await fetch(`http://localhost:${DOCS_PORT}/healthcheck`);
    const text = await r.text();
    res.status(r.ok ? 200 : 503).send(text);
  } catch {
    res.status(503).send('false');
  }
});

app.listen(PORT, () => {
  console.log(`ONLYOFFICE test harness: http://localhost:${PORT}`);
  console.log(`Document Server at: http://localhost:${DOCS_PORT}`);
  console.log(`Callback host (inside Docker): ${CALLBACK_HOST}:${PORT}`);
});
