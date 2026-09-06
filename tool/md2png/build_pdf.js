// Generic Markdown -> PDF renderer built on top of the shared md2png tool, extended with:
//   - <div class="pagebreak"></div> markers in the source Markdown force a page break there
//     (in addition to the shared tool's own automatic page break before every ## heading)
//   - --title-page: centers the H1 title, both horizontally and vertically, on its own
//     first page, with the rest of the document starting on page 2
//   - --narrow-margins: uses 8mm left/right margins instead of 15mm (needed when a document
//     places two 300px-wide images side by side in a <p>, since at 15mm margins the combined
//     width barely doesn't fit the printable area and the second image wraps to the next line)
//
// Usage: node build_pdf.js <input.md> <output.pdf> [--title-page] [--narrow-margins]
const fs = require('fs');
const os = require('os');
const path = require('path');
const puppeteer = require('puppeteer');

const { buildHtml } = require('./build-html');
const { addBookmarks } = require('./add-bookmarks');

const args = process.argv.slice(2).filter((a) => !a.startsWith('--'));
const flags = new Set(process.argv.slice(2).filter((a) => a.startsWith('--')));
const [mdPath, outPath] = args;
const titlePage = flags.has('--title-page');
const narrowMargins = flags.has('--narrow-margins');

if (!mdPath || !outPath) {
  console.error('Usage: node build_manual_pdf.js <input.md> <output.pdf> [--title-page] [--narrow-margins]');
  process.exit(1);
}

(async () => {
  const { page, headings, title } = buildHtml(mdPath);

  let styledPage = page;
  if (titlePage) {
    styledPage = styledPage.replace(
      '</style>',
      [
        '  .pagebreak { break-before: page; }',
        '  .title-page { height: 267mm; display: flex; align-items: center; justify-content: center; text-align: center; break-after: page; }',
        '  .title-page h1 { margin: 0; }',
        '</style>',
      ].join('\n')
    );
    styledPage = styledPage.replace(/<h1>([\s\S]*?)<\/h1>/, '<div class="title-page"><h1>$1</h1></div>');
  } else {
    styledPage = styledPage.replace('</style>', '  .pagebreak { break-before: page; }\n</style>');
  }

  const tmpHtmlPath = path.join(os.tmpdir(), `md2pdf-src-${Date.now()}.html`);
  fs.writeFileSync(tmpHtmlPath, styledPage, 'utf8');

  const browser = await puppeteer.launch();
  const p = await browser.newPage();
  await p.setViewport({ width: 1000, height: 800 });
  await p.goto('file:///' + tmpHtmlPath.replace(/\\/g, '/'), { waitUntil: 'networkidle0' });
  await p.waitForFunction('window.__mermaidDone === true', { timeout: 60000 });
  await new Promise((r) => setTimeout(r, 300));

  const tmpPdfPath = path.join(os.tmpdir(), `md2pdf-${Date.now()}.pdf`);
  await p.pdf({
    path: tmpPdfPath,
    format: 'A4',
    printBackground: true,
    margin: narrowMargins
      ? { top: '15mm', bottom: '15mm', left: '8mm', right: '8mm' }
      : { top: '15mm', bottom: '15mm', left: '15mm', right: '15mm' },
  });
  await browser.close();

  await addBookmarks(tmpPdfPath, headings, outPath, title);
  fs.unlinkSync(tmpPdfPath);
  fs.unlinkSync(tmpHtmlPath);

  console.log('done: ' + outPath);
})();
