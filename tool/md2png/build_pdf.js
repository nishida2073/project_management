const fs = require('fs');
const os = require('os');
const path = require('path');
const puppeteer = require('puppeteer');
const { PDFDocument, StandardFonts, rgb } = require('pdf-lib');

const { buildHtml } = require('./build-html');
const { addBookmarks, findHeadingPages, buildTree } = require('./add-bookmarks');

const styleCss = fs.readFileSync(path.join(__dirname, 'style.css'), 'utf8');

function escapeHtml(s) {
  return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

function readCssRule(cssText, selector) {
  const re = new RegExp(selector.replace(/[.#]/g, '\\$&') + '\\s*\\{([^}]*)\\}');
  const body = cssText.match(re)?.[1] ?? '';
  const props = {};
  for (const decl of body.split(';')) {
    const idx = decl.indexOf(':');
    if (idx === -1) continue;
    props[decl.slice(0, idx).trim()] = decl.slice(idx + 1).trim();
  }
  return props;
}

function hexToRgb01(hex) {
  const m = /^#([0-9a-f]{6})$/i.exec((hex || '').trim());
  if (!m) return null;
  const n = parseInt(m[1], 16);
  return rgb(((n >> 16) & 255) / 255, ((n >> 8) & 255) / 255, (n & 255) / 255);
}

function parseBorderTop(value) {
  const m = /^([\d.]+)px\s+(solid|dashed|dotted)\s+(#[0-9a-f]{6})$/i.exec((value || '').trim());
  if (!m) return null;
  const [, widthStr, style, hex] = m;
  const dashArray = style === 'dashed' ? [4, 2] : style === 'dotted' ? [1, 2] : undefined;
  return { width: parseFloat(widthStr), color: hexToRgb01(hex), dashArray };
}

function mmToPt(mmStr) {
  return (parseFloat(mmStr) * 72) / 25.4;
}

const args = process.argv.slice(2).filter((a) => !a.startsWith('--'));
const flags = process.argv.slice(2).filter((a) => a.startsWith('--'));
const [mdPath, outPath] = args;
const titlePage = flags.includes('--title-page');
const narrowMargins = flags.includes('--narrow-margins');
const toc = flags.includes('--toc');
const pageNumbers = flags.includes('--page-numbers');
const header = flags.includes('--header');
const imgWidthFlag = flags.find((f) => f.startsWith('--img-width='));
const imgWidth = imgWidthFlag ? Number(imgWidthFlag.slice('--img-width='.length)) : null;

if (!mdPath || !outPath) {
  console.error('Usage: node build_pdf.js <input.md> <output.pdf> [--title-page] [--narrow-margins] [--img-width=N] [--toc] [--page-numbers] [--header]');
  process.exit(1);
}

const pdfMargin = narrowMargins
  ? { top: '15mm', bottom: '15mm', left: '8mm', right: '8mm' }
  : { top: '15mm', bottom: '15mm', left: '15mm', right: '15mm' };

const frontMatterPageCount = (titlePage ? 1 : 0) + (toc ? 1 : 0);

function tocRow(h, className, displayPage) {
  const href = `#${encodeURIComponent(h.text)}`;
  return `<a class="toc-item ${className}" href="${href}"><span class="toc-text">${escapeHtml(h.text)}</span><span class="toc-dots"></span><span class="toc-page-num">${displayPage(h.token)}</span></a>`;
}

function buildTocHtml(tree, pageByToken, displayOffset) {
  const displayPage = (token) => pageByToken.get(token) + 2 - displayOffset;
  const rows = [];
  for (const h2 of tree) {
    rows.push(tocRow(h2, 'toc-h2', displayPage));
    for (const h3 of h2.children) {
      rows.push(tocRow(h3, 'toc-h3', displayPage));
    }
  }
  return `<div class="toc-page"><h2 class="toc-title">目次</h2>${rows.join('\n')}</div>`;
}

async function renderPdf(browser, htmlPage, headerText) {
  const tmpHtmlPath = path.join(os.tmpdir(), `md2pdf-src-${Date.now()}-${Math.random().toString(36).slice(2, 8)}.html`);
  fs.writeFileSync(tmpHtmlPath, htmlPage, 'utf8');

  const p = await browser.newPage();
  await p.setViewport({ width: 1000, height: 800 });
  await p.goto('file:///' + tmpHtmlPath.replace(/\\/g, '/'), { waitUntil: 'networkidle0' });
  await p.waitForFunction('window.__mermaidDone === true', { timeout: 60000 });
  await new Promise((r) => setTimeout(r, 300));

  const tmpPdfPath = path.join(os.tmpdir(), `md2pdf-${Date.now()}-${Math.random().toString(36).slice(2, 8)}.pdf`);
  const pdfOptions = { path: tmpPdfPath, format: 'A4', printBackground: true, margin: pdfMargin };
  if (headerText) {
    pdfOptions.displayHeaderFooter = true;
    pdfOptions.footerTemplate = '<div></div>';
    pdfOptions.headerTemplate = `
      <style>${styleCss}</style>
      <div class="pdf-header" style="width:100%; box-sizing:border-box; padding:0 ${pdfMargin.right} 0 ${pdfMargin.left};">
        ${escapeHtml(headerText)}
      </div>`;
  }
  await p.pdf(pdfOptions);
  await p.close();
  fs.unlinkSync(tmpHtmlPath);

  return tmpPdfPath;
}

async function addPageNumbers(pdfPath, frontCount) {
  const pdfDoc = await PDFDocument.load(fs.readFileSync(pdfPath));
  const pages = pdfDoc.getPages();
  const contentTotal = pages.length - frontCount;
  if (contentTotal <= 0) return;

  const footerRule = readCssRule(styleCss, '.pdf-footer');
  const font = await pdfDoc.embedFont(StandardFonts.Helvetica);
  const fontSize = parseFloat(footerRule['font-size']) || 9;
  const color = hexToRgb01(footerRule.color) || rgb(0.54, 0.57, 0.61);
  const border = parseBorderTop(footerRule['border-top']);
  const lineY = 30;
  const marginLeft = mmToPt(pdfMargin.left);
  const marginRight = mmToPt(pdfMargin.right);

  for (let i = frontCount; i < pages.length; i++) {
    const pageObj = pages[i];
    const { width } = pageObj.getSize();
    const label = `${i - frontCount + 1} / ${contentTotal}`;
    const textWidth = font.widthOfTextAtSize(label, fontSize);
    pageObj.drawText(label, {
      x: (width - textWidth) / 2,
      y: 18,
      size: fontSize,
      font,
      color,
    });
    if (border) {
      pageObj.drawLine({
        start: { x: marginLeft, y: lineY },
        end: { x: width - marginRight, y: lineY },
        thickness: border.width,
        color: border.color,
        dashArray: border.dashArray,
      });
    }
  }

  fs.writeFileSync(pdfPath, await pdfDoc.save());
}

async function mergeFrontMatter(frontPath, restPath, frontCount, outFile) {
  const frontDoc = await PDFDocument.load(fs.readFileSync(frontPath));
  const restDoc = await PDFDocument.load(fs.readFileSync(restPath));
  const total = frontDoc.getPageCount();
  const splitAt = Math.min(frontCount, total);

  const outDoc = await PDFDocument.create();
  const frontIdx = Array.from({ length: splitAt }, (_, i) => i);
  const restIdx = Array.from({ length: total - splitAt }, (_, i) => i + splitAt);

  const frontPages = await outDoc.copyPages(frontDoc, frontIdx);
  frontPages.forEach((pg) => outDoc.addPage(pg));
  const restPages = await outDoc.copyPages(restDoc, restIdx);
  restPages.forEach((pg) => outDoc.addPage(pg));

  fs.writeFileSync(outFile, await outDoc.save());
  return outFile;
}

(async () => {
  const { page, headings, title } = buildHtml(mdPath);

  let styledPage = page;
  if (titlePage) {
    styledPage = styledPage.replace(/<h1>([\s\S]*?)<\/h1>/, '<div class="title-page"><h1>$1</h1></div>');
  }

  if (imgWidth) {
    styledPage = styledPage.replace(/<img\s+([^>]*?)>/g, (m, attrs) => {
      if (/\bwidth\s*=/.test(attrs)) return m;
      return `<img ${attrs} width="${imgWidth}">`;
    });
  }

  const browser = await puppeteer.launch();

  let finalPage = styledPage;
  if (toc) {
    const draftPdfPath = await renderPdf(browser, styledPage);
    const headingsWithPages = await findHeadingPages(fs.readFileSync(draftPdfPath), headings);
    fs.unlinkSync(draftPdfPath);

    const pageByToken = new Map(headingsWithPages.map((h) => [h.token, h.pageIndex]));
    const tree = buildTree(headingsWithPages);
    const tocDisplayOffset = pageNumbers ? frontMatterPageCount : 0;
    const tocHtml = buildTocHtml(tree, pageByToken, tocDisplayOffset);

    finalPage = titlePage
      ? finalPage.replace(/(<div class="title-page">[\s\S]*?<\/div>)/, `$1\n${tocHtml}`)
      : finalPage.replace('<body>\n', `<body>\n${tocHtml}\n`);
  }

  let tmpPdfPath;
  if (header && frontMatterPageCount > 0) {
    const noHeaderPath = await renderPdf(browser, finalPage, null);
    const withHeaderPath = await renderPdf(browser, finalPage, title);
    tmpPdfPath = path.join(os.tmpdir(), `md2pdf-merged-${Date.now()}-${Math.random().toString(36).slice(2, 8)}.pdf`);
    await mergeFrontMatter(noHeaderPath, withHeaderPath, frontMatterPageCount, tmpPdfPath);
    fs.unlinkSync(noHeaderPath);
    fs.unlinkSync(withHeaderPath);
  } else {
    tmpPdfPath = await renderPdf(browser, finalPage, header ? title : null);
  }
  await browser.close();

  await addBookmarks(tmpPdfPath, headings, outPath, title);
  fs.unlinkSync(tmpPdfPath);

  if (pageNumbers) {
    await addPageNumbers(outPath, frontMatterPageCount);
  }

  console.log('done: ' + outPath);
})();
