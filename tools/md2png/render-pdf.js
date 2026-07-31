const fs = require('fs');
const os = require('os');
const path = require('path');
const puppeteer = require('puppeteer');
const { buildHtml } = require('./build-html');
const { addBookmarks } = require('./add-bookmarks');

const mdPath = process.argv[2];
const outPath = process.argv[3];

const { page, headings, title } = buildHtml(mdPath);

(async () => {
  const browser = await puppeteer.launch();
  const p = await browser.newPage();
  await p.setViewport({ width: 1000, height: 800 });
  await p.setContent(page, { waitUntil: 'networkidle0' });
  await p.waitForFunction('window.__mermaidDone === true', { timeout: 60000 });
  await new Promise((r) => setTimeout(r, 300));

  const tmpPath = path.join(os.tmpdir(), `md2pdf-${Date.now()}.pdf`);
  await p.pdf({
    path: tmpPath,
    format: 'A4',
    printBackground: true,
    margin: { top: '15mm', bottom: '15mm', left: '15mm', right: '15mm' },
  });
  await browser.close();

  await addBookmarks(tmpPath, headings, outPath, title);
  fs.unlinkSync(tmpPath);

  console.log('done');
})();
