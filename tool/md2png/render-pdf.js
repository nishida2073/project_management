const fs = require('fs');
const os = require('os');
const path = require('path');
const puppeteer = require('puppeteer');
const { buildHtml } = require('./build-html');
const { addBookmarks } = require('./add-bookmarks');

const mdPath = process.argv[2];
const outPath = process.argv[3];

const { page, headings, title } = buildHtml(mdPath);

// page.setContent()はabout:blank起源になるため、Markdownからの相対パス（file://）で
// 参照している画像がChromiumのセキュリティ制限で読み込めない。実ファイルとして書き出し、
// file://で開くことで、その画像もmermaidと同様に正しく描画されるようにする
const tmpHtmlPath = path.join(os.tmpdir(), `md2pdf-src-${Date.now()}.html`);
fs.writeFileSync(tmpHtmlPath, page, 'utf8');

(async () => {
  const browser = await puppeteer.launch();
  const p = await browser.newPage();
  await p.setViewport({ width: 1000, height: 800 });
  await p.goto('file:///' + tmpHtmlPath.replace(/\\/g, '/'), { waitUntil: 'networkidle0' });
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
  fs.unlinkSync(tmpHtmlPath);

  console.log('done');
})();
