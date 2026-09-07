// Generic Markdown -> PDF renderer built on top of the shared md2png tool, extended with:
//   - <div class="pagebreak"></div> markers in the source Markdown force a page break there
//     (in addition to the shared tool's own automatic page break before every ## heading)
//   - --title-page: centers the H1 title, both horizontally and vertically, on its own
//     first page, with the rest of the document starting on page 2
//   - --narrow-margins: uses 8mm left/right margins instead of 15mm (needed when a document
//     places two 300px-wide images side by side in a <p>, since at 15mm margins the combined
//     width barely doesn't fit the printable area and the second image wraps to the next line)
//   - --img-width=NNN: default display width (px) for any <img> that doesn't already carry
//     its own width="..." attribute, so most screenshots don't need width="NNN" repeated in
//     the Markdown; images that do specify their own width keep it
//   - --toc: inserts a table-of-contents page right after the title page (page 2 when
//     combined with --title-page, otherwise page 1), listing the same h2/h3 headings as the
//     PDF's bookmarks/outline, each with a dotted leader and page number
//   - --page-numbers: stamps a centered "N / total" footer on every page except front-matter
//     pages (the title page and, when present, the table-of-contents page), which are left
//     blank; numbering restarts at 1 on the first page after the front matter
//   - --header: shows the file name in the top-left header, on every page after the front
//     matter (the title page and, when present, the table-of-contents page)
//
// Usage: node build_pdf.js <input.md> <output.pdf> [--title-page] [--narrow-margins] [--img-width=N] [--toc] [--page-numbers] [--header]
const fs = require('fs');
const os = require('os');
const path = require('path');
const puppeteer = require('puppeteer');
const { PDFDocument, StandardFonts, rgb } = require('pdf-lib');

const { buildHtml } = require('./build-html');
const { addBookmarks, findHeadingPages, buildTree } = require('./add-bookmarks');

const styleCss = fs.readFileSync(path.join(__dirname, 'style.css'), 'utf8');

// style.css中の "セレクタ { プロパティ: 値; ... }" を素朴に読み取る。ヘッダーはブラウザで
// 描画するため style.css をそのまま<style>に埋め込めば足りるが、フッターのページ番号は
// pdf-libで直接描画しておりCSSエンジンを通らないため、color/font-sizeだけここで値を拾って使う
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

// "1px solid #d3d9df" のようなborder-topショートハンドだけ読む（他の書き方は無視＝境界線なし）
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

// 表紙（--title-page）と目次（--toc）はページ番号を振らない前付けページとして扱い、
// 本文の先頭（前付けの直後）を1ページ目として振り直す
const frontMatterPageCount = (titlePage ? 1 : 0) + (toc ? 1 : 0);

function escapeHtml(s) {
  return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

// 目次に載せる見出しは add-bookmarks.js のしおり生成と同じ h2/h3 のツリーを使う。
// pageByToken は「目次ページを挿入する前」のレンダリング結果でのページ番号（0始まり）。
// 目次は必ず1ページに収まる（.toc-page が break-after:page で1ページ分の高さに固定されている）ので、
// 挿入後は以降の全ページが一律+1ページずれる。それを踏まえて表示ページ番号を pageIndex + 2 とする
// build-html.js が各見出しに付与する id="見出しの生テキスト" と同じ規約でリンクする。
// これはadd-bookmarks.jsのfixInternalDestLinksが解決する「同一ドキュメント内リンク」の
// 仕組みそのものなので、印刷後は自動的にジャンプできるリンクアノテーションになる
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
    // Puppeteerのheader/footerテンプレートは独立したフレームで、外部stylesheet（<link>）は
    // 読み込めないため、style.cssの中身をそのまま<style>としてこのテンプレートに埋め込む。
    // 日本語ファイル名を表示する都合上、pdf-lib側のフッターページ番号（欧数字のみ）と違い
    // 標準14フォントでは描画できないため、ブラウザの印刷パイプライン自体を使う。
    // 左右の余白（--narrow-margins次第で変わる実行時の値）だけはCSSに書けないのでインラインで指定する
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

// 前付け（表紙・目次）を除いた本文ページにだけ「N / 総ページ数」をフッター中央に描画する。
// Puppeteerのheader/footerTemplateは全ページ一律にしか差し込めず、かつ番号の振り直し
// （前付け分を引いた1始まり）もできないため、印刷後にpdf-libで直接テキストを重ねる
async function addPageNumbers(pdfPath, frontCount) {
  const pdfDoc = await PDFDocument.load(fs.readFileSync(pdfPath));
  const pages = pdfDoc.getPages();
  const contentTotal = pages.length - frontCount;
  if (contentTotal <= 0) return;

  // .pdf-footerのcolor/font-size/border-topをstyle.cssから読む（pdf-libはCSS単位を解釈しない
  // ので、font-sizeの数値部分をそのままpdf-lib描画時のポイントサイズとして使う簡易対応）
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

// --header は前付け（表紙・目次）を除いた本文ページだけに出す。ヘッダー文字列は日本語の
// ファイル名なので、pdf-libの標準14フォントでは描画できずaddPageNumbersと同じ方式は使えない。
// 代わりにChromiumの印刷パイプライン自体（＝ヘッダーテンプレート）で日本語込みで描画し、
// 「ヘッダーなし」「ヘッダーあり」の2通りを印刷しておいて、前付け分だけ前者のページに差し替える
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

  // 見出し関連のCSS（.pagebreak, .title-page, .toc-page など）はすべてstyle.cssに定義済み。
  // ここではDOM側の組み立て（表紙div化・画像へのwidth属性付与・目次の挿入）だけを行う
  let styledPage = page;
  if (titlePage) {
    styledPage = styledPage.replace(/<h1>([\s\S]*?)<\/h1>/, '<div class="title-page"><h1>$1</h1></div>');
  }

  if (imgWidth) {
    // CSSのwidthだけで幅を指定すると、画像の読み込みが終わるまでブラウザが縦幅を確保できず、
    // 読み込み完了時のレイアウトのずれが原因でページ数が変わってしまうことがある（タイトル
    // ページ直後に空白ページができるなど）。width属性をHTMLに直接埋め込めば、Markdownで
    // width="300"と書いた場合と全く同じ扱いになり、読み込み前から領域が確保されるため安全
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
    // --page-numbersありなら本文側の振り直し後の番号に、なしならPDFビューア上の絶対ページ番号に合わせる
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
