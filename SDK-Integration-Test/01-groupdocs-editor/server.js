import 'dotenv/config';
import express from 'express';
import multer from 'multer';
import path from 'node:path';

const API_BASE = 'https://api.groupdocs.cloud';
const CLIENT_ID = process.env.GROUPDOCS_CLIENT_ID;
const CLIENT_SECRET = process.env.GROUPDOCS_CLIENT_SECRET;
const PORT = process.env.PORT || 5177;

if (!CLIENT_ID || !CLIENT_SECRET) {
  console.error('Thiếu GROUPDOCS_CLIENT_ID / GROUPDOCS_CLIENT_SECRET — copy .env.example thành .env và điền vào.');
  process.exit(1);
}

class StageError extends Error {
  constructor(stage, detail) {
    super(detail);
    this.stage = stage;
    this.detail = detail;
  }
}

const FRIENDLY_MESSAGES = {
  token: "Couldn't connect to the editing service. Please try again in a moment.",
  upload: "Couldn't upload your file for processing. Your original file was not changed.",
  load: "This Excel file couldn't be opened — it may contain features like Data Bars or pivot tables that aren't supported yet. Try removing conditional formatting in Excel first, then re-upload.",
  save: "Couldn't save your changes. Your original file was not changed.",
  download: "Couldn't download the result. Please try again."
};

function friendlyError(err) {
  const stage = err instanceof StageError ? err.stage : 'unknown';
  return {
    error: FRIENDLY_MESSAGES[stage] || 'Có lỗi xảy ra, vui lòng thử lại.',
    detail: err.detail || err.message
  };
}

let cachedToken = null;
let tokenExpiresAt = 0;

async function getAccessToken() {
  if (cachedToken && Date.now() < tokenExpiresAt) return cachedToken;

  const res = await fetch(`${API_BASE}/connect/token`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
    body: new URLSearchParams({
      grant_type: 'client_credentials',
      client_id: CLIENT_ID,
      client_secret: CLIENT_SECRET
    })
  });

  const text = await res.text();
  if (!res.ok) throw new StageError('token', `Lấy token thất bại (${res.status}): ${text}`);

  const data = JSON.parse(text);
  cachedToken = data.access_token;
  tokenExpiresAt = Date.now() + (Number(data.expires_in ?? 3600) - 60) * 1000;
  return cachedToken;
}

async function groupdocsFetch(pathname, options = {}) {
  const token = await getAccessToken();
  return fetch(`${API_BASE}${pathname}`, {
    ...options,
    headers: { Authorization: `Bearer ${token}`, ...options.headers }
  });
}

async function uploadToStorage(remotePath, buffer, stage = 'upload') {
  const form = new FormData();
  form.append('File', new Blob([buffer]), path.basename(remotePath));

  const res = await groupdocsFetch(`/v1.0/editor/storage/file/${encodeURI(remotePath)}`, {
    method: 'PUT',
    body: form
  });
  const text = await res.text();
  if (!res.ok) throw new StageError(stage, `Upload lên storage thất bại (${res.status}): ${text}`);
}

async function downloadFromStorage(remotePath, stage = 'download') {
  const res = await groupdocsFetch(`/v1.0/editor/storage/file/${encodeURI(remotePath)}`, { method: 'GET' });
  if (!res.ok) {
    const text = await res.text();
    throw new StageError(stage, `Download từ storage thất bại (${res.status}): ${text}`);
  }
  return Buffer.from(await res.arrayBuffer());
}

function docTypeParams(ext) {
  const lower = ext.toLowerCase();
  if (['.xlsx', '.xls', '.ods', '.csv'].includes(lower)) return { WorksheetIndex: 0 };
  if (['.pptx', '.ppt', '.odp', '.ppsx'].includes(lower)) return { SlideNumber: 0 };
  return {};
}

const MIME_TYPES = {
  '.png': 'image/png', '.jpg': 'image/jpeg', '.jpeg': 'image/jpeg',
  '.gif': 'image/gif', '.svg': 'image/svg+xml', '.css': 'text/css',
  '.woff': 'font/woff', '.woff2': 'font/woff2'
};

const app = express();
app.use(express.json({ limit: '50mb' }));
app.use(express.static(path.join(process.cwd(), 'public')));

const upload = multer({ storage: multer.memoryStorage() });

app.post('/api/load', upload.single('file'), async (req, res) => {
  try {
    if (!req.file) return res.status(400).json({ error: 'No file selected.' });

    const ext = path.extname(req.file.originalname);
    const remotePath = `sdk-test/${req.file.originalname}`;
    const outputFolder = 'sdk-test/output';

    await uploadToStorage(remotePath, req.file.buffer, 'upload');

    const loadRes = await groupdocsFetch('/v1.0/editor/load', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        FileInfo: { FilePath: remotePath },
        OutputPath: outputFolder,
        ...docTypeParams(ext)
      })
    });
    const loadText = await loadRes.text();
    if (!loadRes.ok) throw new StageError('load', `editor/load thất bại (${loadRes.status}): ${loadText}`);
    const { htmlPath, resourcesPath } = JSON.parse(loadText);

    const htmlBuffer = await downloadFromStorage(htmlPath, 'load');

    res.json({
      html: htmlBuffer.toString('utf-8'),
      remotePath,
      htmlPath,
      resourcesPath,
      resourceBase: `/api/resource/${resourcesPath}/`
    });
  } catch (err) {
    console.error(err);
    res.status(500).json(friendlyError(err));
  }
});

app.get('/api/resource/*', async (req, res) => {
  try {
    const remotePath = req.params[0];
    const buffer = await downloadFromStorage(remotePath);
    res.setHeader('Content-Type', MIME_TYPES[path.extname(remotePath).toLowerCase()] || 'application/octet-stream');
    res.send(buffer);
  } catch (err) {
    res.status(404).send('');
  }
});

app.post('/api/save', async (req, res) => {
  try {
    const { html, remotePath, htmlPath, resourcesPath } = req.body;
    if (!html || !remotePath || !htmlPath || !resourcesPath) {
      return res.status(400).json({ error: 'Something is missing — please reload the file and try again.' });
    }

    await uploadToStorage(htmlPath, Buffer.from(html, 'utf-8'), 'save');

    const ext = path.extname(remotePath);
    const outputPath = remotePath.slice(0, -ext.length) + '.edited' + ext;

    const saveRes = await groupdocsFetch('/v1.0/editor/save', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        FileInfo: { FilePath: remotePath },
        OutputPath: outputPath,
        HtmlPath: htmlPath,
        ResourcesPath: resourcesPath
      })
    });
    const saveText = await saveRes.text();
    if (!saveRes.ok) throw new StageError('save', `editor/save thất bại (${saveRes.status}): ${saveText}`);
    const { path: resultPath } = JSON.parse(saveText);

    const fileBuffer = await downloadFromStorage(resultPath, 'download');
    res.setHeader('Content-Disposition', `attachment; filename="${path.basename(resultPath)}"`);
    res.setHeader('Content-Type', 'application/octet-stream');
    res.send(fileBuffer);
  } catch (err) {
    console.error(err);
    res.status(500).json(friendlyError(err));
  }
});

app.listen(PORT, () => {
  console.log(`GroupDocs.Editor test harness: http://localhost:${PORT}`);
});
