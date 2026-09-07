const fs = require('fs');
const {
  PDFDocument,
  PDFHexString,
  PDFName,
  PDFArray,
  PDFNumber,
  PDFDict,
} = require('pdf-lib');

function fixInternalDestLinks(pdfDoc, headingsWithPages, pages) {
  const context = pdfDoc.context;
  const byText = new Map(headingsWithPages.map((h) => [h.id, h]));

  for (const page of pdfDoc.getPages()) {
    const annotsObj = page.node.Annots();
    if (!annotsObj) continue;
    for (let i = 0; i < annotsObj.size(); i++) {
      const annotDict = context.lookup(annotsObj.get(i), PDFDict);
      if (!annotDict) continue;
      const subtype = annotDict.get(PDFName.of('Subtype'));
      if (!subtype || subtype.toString() !== '/Link') continue;
      if (annotDict.get(PDFName.of('A'))) continue;

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

function buildTree(headingsWithPages, maxLevel = 3) {
  const tree = [];
  const stack = [];
  for (const h of headingsWithPages) {
    if (h.level > maxLevel) continue;
    const node = { ...h, children: [] };
    while (stack.length && stack[stack.length - 1].level >= h.level) stack.pop();
    if (stack.length) {
      stack[stack.length - 1].node.children.push(node);
    } else {
      tree.push(node);
    }
    stack.push({ node, level: h.level });
  }
  return tree;
}

function countAll(nodes) {
  let c = 0;
  for (const n of nodes) c += 1 + countAll(n.children);
  return c;
}

async function addBookmarks(inPath, headings, outPath, title, maxLevel = 3) {
  const pdfBytes = fs.readFileSync(inPath);
  const headingsWithPages = await findHeadingPages(pdfBytes, headings);
  const tree = buildTree(headingsWithPages, maxLevel);

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
  pdfDoc.catalog.delete(PDFName.of('Dests'));

  const sortedHeadings = [...headingsWithPages].sort((a, b) =>
    a.id < b.id ? -1 : a.id > b.id ? 1 : 0
  );
  const namesArray = PDFArray.withContext(context);
  for (const h of sortedHeadings) {
    const page = pages[h.pageIndex];
    const dest = PDFArray.withContext(context);
    dest.push(page.ref);
    dest.push(PDFName.of('Fit'));
    namesArray.push(PDFHexString.fromText(h.id));
    namesArray.push(dest);
  }
  const destsNameTreeRef = context.register(context.obj({ Names: namesArray }));
  const namesDictRef = context.register(context.obj({ Dests: destsNameTreeRef }));
  pdfDoc.catalog.set(PDFName.of('Names'), namesDictRef);

  fixInternalDestLinks(pdfDoc, headingsWithPages, pages);

  const outBytes = await pdfDoc.save();
  fs.writeFileSync(outPath, outBytes);
}

module.exports = { addBookmarks, findHeadingPages, buildTree };
