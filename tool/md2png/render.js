const fs = require('fs');
const os = require('os');
const path = require('path');
const puppeteer = require('puppeteer');
const { buildHtml } = require('./build-html');

const mdPath = process.argv[2];
const outPath = process.argv[3];

const { page } = buildHtml(mdPath);

// page.setContent()はabout:blank起源になるため、Markdownからの相対パス（file://）で
// 参照している画像がChromiumのセキュリティ制限で読み込めない。実ファイルとして書き出し、
// file://で開くことで、その画像もmermaidと同様に正しく描画されるようにする
const tmpHtmlPath = path.join(os.tmpdir(), `md2png-src-${Date.now()}.html`);
fs.writeFileSync(tmpHtmlPath, page, 'utf8');

(async () => {
  const browser = await puppeteer.launch();
  const p = await browser.newPage();
  await p.setViewport({ width: 1000, height: 800 });
  await p.goto('file:///' + tmpHtmlPath.replace(/\\/g, '/'), { waitUntil: 'networkidle0' });
  await p.waitForFunction('window.__mermaidDone === true', { timeout: 60000 });
  await new Promise(r => setTimeout(r, 300));
  await p.screenshot({ path: outPath, fullPage: true });
  await browser.close();
  fs.unlinkSync(tmpHtmlPath);
  console.log('done');
})();
