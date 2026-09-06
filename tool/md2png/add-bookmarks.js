const fs = require('fs');
const path = require('path');
const {
  PDFDocument,
  PDFHexString,
  PDFName,
  PDFArray,
  PDFNumber,
  PDFDict,
} = require('pdf-lib');

/**
 * <a href="...">がMarkdown内で他のローカルPDF（同じフォルダの他ファイル）を指している場合、
 * build-html.jsが注入する<base href="file:///...">のせいでChromiumが絶対パスのfile:// URIに
 * 解決してしまい、そのままではリンク先PDFをコピー・配布したときに壊れる（同じ絶対パスが
 * 存在する別環境でしか開けない）。同じフォルダ内の相対パスで開けるよう、そのURIリンクを
 * PDFネイティブのGoToR（他ファイルへのジャンプ）アクションへ、ファイル名だけの相対パスで
 * 書き換える。URIのフラグメント（#見出し名）はGoToRの名前付き宛先としてそのまま引き継ぐ
 */
function fixLocalPdfLinks(pdfDoc) {
  const context = pdfDoc.context;
  for (const page of pdfDoc.getPages()) {
    const annotsObj = page.node.Annots();
    if (!annotsObj) continue;
    for (let i = 0; i < annotsObj.size(); i++) {
      const annotDict = context.lookup(annotsObj.get(i), PDFDict);
      if (!annotDict) continue;
      const subtype = annotDict.get(PDFName.of('Subtype'));
      if (!subtype || subtype.toString() !== '/Link') continue;

      const actionRef = annotDict.get(PDFName.of('A'));
      const actionDict = actionRef && context.lookup(actionRef, PDFDict);
      if (!actionDict) continue;
      const actionType = actionDict.get(PDFName.of('S'));
      if (!actionType || actionType.toString() !== '/URI') continue;

      const uriObj = actionDict.get(PDFName.of('URI'));
      const uriStr = uriObj && uriObj.decodeText ? uriObj.decodeText() : null;
      if (!uriStr) continue;

      const m = /^file:\/{2,3}(.+\.pdf)(?:#(.*))?$/i.exec(uriStr);
      if (!m) continue;

      const fullPath = decodeURIComponent(m[1]);
      const fragment = m[2] ? decodeURIComponent(m[2]) : null;
      const basename = path.basename(fullPath);

      const newActionEntries = {
        S: PDFName.of('GoToR'),
        F: PDFHexString.fromText(basename),
        NewWindow: context.obj(false),
      };
      if (fragment) {
        newActionEntries.D = PDFHexString.fromText(fragment);
      }
      annotDict.set(PDFName.of('A'), context.obj(newActionEntries));
    }
  }
}

/**
 * 同一ドキュメント内の[text](#見出しテキスト)リンクは、Chromiumの印刷時にリンク先の見出しの
 * id属性を見つけて、そのリンクをLinkアノテーションの/Dest名（hrefのフラグメントをパーセント
 * エンコードした文字列）として自動生成する。この名前を解決するには本来カタログの/Dests辞書に
 * 同じキーを登録する必要があるが、見出しテキストが長いと（例：括弧書きの長い見出し）パーセント
 * エンコード後にPDFの名前オブジェクトの長さ上限（127バイト）を超えてしまい、一部のビューアで
 * PDF全体の解析が壊れる原因になっていた。
 * 辞書を経由せず、各Linkアノテーションの/Dest名を直接そのページへの宛先配列に書き換えることで、
 * 名前の長さに関わらず安全に解決できるようにする
 */
function fixInternalDestLinks(pdfDoc, headingsWithPages, pages) {
  const context = pdfDoc.context;
  const byText = new Map(headingsWithPages.map((h) => [h.text, h]));

  for (const page of pdfDoc.getPages()) {
    const annotsObj = page.node.Annots();
    if (!annotsObj) continue;
    for (let i = 0; i < annotsObj.size(); i++) {
      const annotDict = context.lookup(annotsObj.get(i), PDFDict);
      if (!annotDict) continue;
      const subtype = annotDict.get(PDFName.of('Subtype'));
      if (!subtype || subtype.toString() !== '/Link') continue;
      if (annotDict.get(PDFName.of('A'))) continue; // has its own action (e.g. our GoToR fix); leave alone

      const destNameObj = annotDict.get(PDFName.of('Dest'));
      if (!destNameObj || typeof destNameObj.decodeText !== 'function') continue;

      let headingText;
      try {
        headingText = decodeURIComponent(destNameObj.decodeText());
      } catch (e) {
        continue;
      }
      const heading = byText.get(headingText);
      if (!heading) continue;

      const destPage = pages[heading.pageIndex];
      const dest = PDFArray.withContext(context);
      dest.push(destPage.ref);
      dest.push(PDFName.of('Fit'));
      annotDict.set(PDFName.of('Dest'), dest);
    }
  }
}

async function findHeadingPages(pdfBytes, headings) {
  const pdfjsLib = await import('pdfjs-dist/legacy/build/pdf.mjs');
  const doc = await pdfjsLib.getDocument({ data: new Uint8Array(pdfBytes) }).promise;
  const pageTexts = [];
  for (let i = 1; i <= doc.numPages; i++) {
    const page = await doc.getPage(i);
    const content = await page.getTextContent();
    pageTexts.push(content.items.map((it) => it.str).join(''));
  }

  return headings.map((h) => {
    let found = 0;
    for (let i = 0; i < pageTexts.length; i++) {
      if (pageTexts[i].includes(h.token)) {
        found = i;
        break;
      }
    }
    return { ...h, pageIndex: found };
  });
}

function buildTree(headingsWithPages) {
  const tree = [];
  let currentH2 = null;
  for (const h of headingsWithPages) {
    if (h.level === 2) {
      currentH2 = { ...h, children: [] };
      tree.push(currentH2);
    } else if (currentH2) {
      currentH2.children.push({ ...h, children: [] });
    } else {
      tree.push({ ...h, children: [] });
    }
  }
  return tree;
}

function countAll(nodes) {
  let c = 0;
  for (const n of nodes) c += 1 + countAll(n.children);
  return c;
}

async function addBookmarks(inPath, headings, outPath, title) {
  const pdfBytes = fs.readFileSync(inPath);
  const headingsWithPages = await findHeadingPages(pdfBytes, headings);
  const tree = buildTree(headingsWithPages);

  const pdfDoc = await PDFDocument.load(pdfBytes);
  if (title) {
    pdfDoc.setTitle(title, { showInWindowTitleBar: true });
  }
  const context = pdfDoc.context;
  const pages = pdfDoc.getPages();

  function allocateRefs(nodes) {
    for (const node of nodes) {
      node.ref = context.nextRef();
      allocateRefs(node.children);
    }
  }
  allocateRefs(tree);

  const outlineRootRef = context.nextRef();

  function buildDicts(nodes, parentRef) {
    for (let i = 0; i < nodes.length; i++) {
      const node = nodes[i];
      const page = pages[node.pageIndex];
      const dest = PDFArray.withContext(context);
      dest.push(page.ref);
      dest.push(PDFName.of('Fit'));

      const entries = {
        Title: PDFHexString.fromText(node.text),
        Parent: parentRef,
        Dest: dest,
      };
      if (i > 0) entries.Prev = nodes[i - 1].ref;
      if (i < nodes.length - 1) entries.Next = nodes[i + 1].ref;
      if (node.children.length > 0) {
        entries.First = node.children[0].ref;
        entries.Last = node.children[node.children.length - 1].ref;
        entries.Count = PDFNumber.of(node.children.length);
      }

      const dict = context.obj(entries);
      context.assign(node.ref, dict);

      if (node.children.length > 0) {
        buildDicts(node.children, node.ref);
      }
    }
  }
  buildDicts(tree, outlineRootRef);

  const outlineRoot = context.obj({
    Type: 'Outlines',
    First: tree[0].ref,
    Last: tree[tree.length - 1].ref,
    Count: PDFNumber.of(countAll(tree)),
  });
  context.assign(outlineRootRef, outlineRoot);

  pdfDoc.catalog.set(PDFName.of('Outlines'), outlineRootRef);
  pdfDoc.catalog.set(PDFName.of('PageMode'), PDFName.of('UseOutlines'));

  // Chromiumの印刷処理自体が、同一ページ内リンクの解決用にカタログの/Dests辞書を自動生成して
  // しまう。このキーは見出しテキストをパーセントエンコードし、さらにPDF名前オブジェクトとして
  // #XXエスケープしたものになるため、見出しが少し長いだけで名前オブジェクトの長さ上限（127バイト）
  // を大きく超えてしまう（実測で151バイト超）。fixInternalDestLinksで各リンクの参照先はすでに
  // 直接の宛先配列に書き換え済みでこの辞書は不要になっているため、壊れたまま残さず削除する
  pdfDoc.catalog.delete(PDFName.of('Dests'));

  // しおり（アウトライン）に加えて、見出しのテキストをキーにした名前付き宛先（Named Destination）も
  // 登録する。他のPDFから「他のファイル.pdf#見出し名」という形でこの見出しへ直接リンクできるようにするため
  const sortedHeadings = [...headingsWithPages].sort((a, b) =>
    a.text < b.text ? -1 : a.text > b.text ? 1 : 0
  );
  const namesArray = PDFArray.withContext(context);
  for (const h of sortedHeadings) {
    const page = pages[h.pageIndex];
    const dest = PDFArray.withContext(context);
    dest.push(page.ref);
    dest.push(PDFName.of('Fit'));
    namesArray.push(PDFHexString.fromText(h.text));
    namesArray.push(dest);
  }
  const destsNameTreeRef = context.register(context.obj({ Names: namesArray }));
  const namesDictRef = context.register(context.obj({ Dests: destsNameTreeRef }));
  pdfDoc.catalog.set(PDFName.of('Names'), namesDictRef);

  fixInternalDestLinks(pdfDoc, headingsWithPages, pages);
  // fixLocalPdfLinks(pdfDoc) is intentionally NOT called: rewriting the link to a relative
  // GoToR/URI action made it stop working in the viewer actually being used to check this
  // (confirmed by the user), even though the original absolute file:// link had worked there
  // before. Left as Chromium's own absolute file:// URI, at the cost of breaking if this
  // folder is later moved or copied elsewhere.

  const outBytes = await pdfDoc.save();
  fs.writeFileSync(outPath, outBytes);
}

module.exports = { addBookmarks };
