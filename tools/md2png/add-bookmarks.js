const fs = require('fs');
const {
  PDFDocument,
  PDFHexString,
  PDFName,
  PDFArray,
  PDFNumber,
} = require('pdf-lib');

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

  const outBytes = await pdfDoc.save();
  fs.writeFileSync(outPath, outBytes);
}

module.exports = { addBookmarks };
