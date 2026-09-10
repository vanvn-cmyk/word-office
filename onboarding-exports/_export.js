const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

const MAIN = '/Users/admin/Desktop/Word Edit/Word Office/Word Office/Onboarding-Draft.html';
const OUT_DIR = '/Users/admin/Desktop/Word Edit/Word Office/Word Office/onboarding-exports';
const CHROME = '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';

const html = fs.readFileSync(MAIN, 'utf-8');

const styleMatch = html.match(/<style>([\s\S]*?)<\/style>/);
if (!styleMatch) throw new Error('No <style> block found');
const styles = styleMatch[1];

function extractFrame(marker) {
  const idx = html.indexOf(marker);
  if (idx === -1) throw new Error(`Marker not found: ${marker}`);
  const frameStart = html.indexOf('<div class="frame">', idx);
  const captionIdx = html.indexOf('<div class="caption">', frameStart);
  const captionEnd = html.indexOf('</div>', captionIdx) + '</div>'.length;
  const frameEnd = html.indexOf('</div>', captionEnd) + '</div>'.length;
  return html.substring(frameStart, frameEnd);
}

const s1 = extractFrame('<!-- MVP S1 : EDIT OFFICE');
const s2 = extractFrame('<!-- MVP S2 : TOOLS BUILT-IN');
const s3 = extractFrame('<!-- MVP S3 : NEVER LOSE TRACK');
const s4 = extractFrame('<!-- MVP S4 : FOLDER + READY MERGED');

const template = (frame, title) => `<!DOCTYPE html>
<html lang="en" data-theme="dark">
<head>
<meta charset="UTF-8">
<title>${title}</title>
<style>${styles}

/* Export overrides */
html, body {
  margin: 0 !important;
  padding: 0 !important;
  background: #0B0B10 !important;
  min-height: 100vh;
}
body {
  display: flex !important;
  align-items: center !important;
  justify-content: center !important;
  padding: 32px 0 !important;
}
.caption { display: none !important; }
.frame { margin: 0 auto !important; }
</style>
</head>
<body>
${frame}
</body>
</html>`;

const screens = [
  { name: 'S1-EditOffice', title: 'Edit Office · Onboarding S1', html: s1 },
  { name: 'S2-Tools', title: 'Tools built-in · Onboarding S2', html: s2 },
  { name: 'S3-NeverLoseTrack', title: 'Never lose track · Onboarding S3', html: s3 },
  { name: 'S4-FolderReady', title: 'Folder + Ready · Onboarding S4', html: s4 },
];

for (const s of screens) {
  const htmlPath = path.join(OUT_DIR, `${s.name}.html`);
  const pngPath = path.join(OUT_DIR, `${s.name}.png`);
  fs.writeFileSync(htmlPath, template(s.html, s.title));
  console.log(`[html] ${s.name}.html`);

  const cmd = `"${CHROME}" --headless=new --disable-gpu --hide-scrollbars --window-size=400,760 --force-device-scale-factor=2 --screenshot="${pngPath}" "file://${htmlPath}" 2>&1`;
  try {
    execSync(cmd, { stdio: 'pipe' });
    const stats = fs.statSync(pngPath);
    console.log(`[png ] ${s.name}.png (${(stats.size / 1024).toFixed(1)} KB)`);
  } catch (e) {
    console.error(`[fail] ${s.name}: ${e.message}`);
  }
}

console.log('\nExport dir:', OUT_DIR);
