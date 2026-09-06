// Regenerates docs/MANUAL.pdf from docs/MANUAL.md using the shared md2png tool.
// Requires NODE_PATH to include the md2png tool's node_modules (see build_manual_pdf.bat).
//
// MANUAL.md specific pagination: a page break is inserted wherever the source
// Markdown has a <div class="pagebreak"></div> marker (placed manually before the
// relevant heading), rather than being inferred from heading position.
const fs = require('fs');
const os = require('os');
const path = require('path');
const puppeteer = require('puppeteer');

const TOOLS_DIR = 'c:/myrepo/project_management/tools/md2png';
const { buildHtml } = require(path.join(TOOLS_DIR, 'build-html'));
const { addBookmarks } = require(path.join(TOOLS_DIR, 'add-bookmarks'));

const mdPath = path.join(__dirname, 'マニュアル.md');
const outPath = path.join(__dirname, 'マニュアル.pdf');

const { page, headings, title } = buildHtml(mdPath);

const pageWithExtraStyle = page.replace(
  '</style>',
  [
    '  .pagebreak { break-before: page; }',
    '  .title-page { height: 267mm; display: flex; align-items: center; justify-content: center; text-align: center; break-after: page; }',
    '  .title-page h1 { margin: 0; }',
    '</style>',
  ].join('\n')
);

// Wrap the H1 (title) so it renders centered, both horizontally and vertically,
// on its own first page, with the rest of the document starting on page 2.
const pageWithTitle = pageWithExtraStyle.replace(
  /<h1>([\s\S]*?)<\/h1>/,
  '<div class="title-page"><h1>$1</h1></div>'
);

const tmpHtmlPath = path.join(os.tmpdir(), `manual-pdf-src-${Date.now()}.html`);
fs.writeFileSync(tmpHtmlPath, pageWithTitle, 'utf8');

(async () => {
  const browser = await puppeteer.launch();
  const p = await browser.newPage();
  await p.setViewport({ width: 1000, height: 800 });
  await p.goto('file:///' + tmpHtmlPath.replace(/\\/g, '/'), { waitUntil: 'networkidle0' });
  await p.waitForFunction('window.__mermaidDone === true', { timeout: 60000 });
  await new Promise((r) => setTimeout(r, 300));

  const tmpPdfPath = path.join(os.tmpdir(), `manual-pdf-${Date.now()}.pdf`);
  await p.pdf({
    path: tmpPdfPath,
    format: 'A4',
    printBackground: true,
    // 左右は15mmだと、横並びで置いた2枚組の画像（各300px幅）の合計が印刷可能幅にわずかに収まらず、
    // 2枚目が次の行へ折り返されてしまうため、横幅に余裕を持たせるために8mmに縮めている
    margin: { top: '15mm', bottom: '15mm', left: '8mm', right: '8mm' },
  });
  await browser.close();

  await addBookmarks(tmpPdfPath, headings, outPath, title);
  fs.unlinkSync(tmpPdfPath);
  fs.unlinkSync(tmpHtmlPath);

  console.log('done: ' + outPath);
})();
