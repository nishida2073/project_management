import fs from 'fs';
const pdfjsLib = await import('pdfjs-dist/legacy/build/pdf.mjs');
for (const n of [80,40,20,10]) {
  try {
    const data = new Uint8Array(fs.readFileSync(`/tmp/mdtest2/x_${n}.pdf`));
  } catch(e) {}
}
