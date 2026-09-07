const fs = require('fs');
const path = require('path');
const { marked } = require('marked');

const defaultStyle = fs.readFileSync(path.join(__dirname, 'style.css'), 'utf8');

function buildHtml(mdPath, anchorLevels = [2, 3, 5], styleCss = defaultStyle) {
  const title = path.basename(mdPath, path.extname(mdPath));
  let md = fs.readFileSync(mdPath, 'utf8');

  const mermaidBlocks = [];
  md = md.replace(/```mermaid\n([\s\S]*?)```/g, (m, code) => {
    const token = `@@MERMAID_${mermaidBlocks.length}@@`;
    mermaidBlocks.push(code);
    return token;
  });

  let html = marked.parse(md);

  const headings = [];
  const headingRe = new RegExp(`<h([${anchorLevels.join('')}])([^>]*)>(.*?)</h\\1>`, 'g');
  html = html.replace(headingRe, (m, level, attrs, inner) => {
    const rawText = inner.replace(/<[^>]+>/g, '').trim();
    const idMatch = rawText.match(/^(.*?)\s*\{#([^}]+)\}$/);
    const text = idMatch ? idMatch[1] : rawText;
    const id = idMatch ? idMatch[2] : rawText;
    const displayInner = idMatch ? inner.replace(/\s*\{#[^}]+\}\s*$/, '') : inner;
    const token = `ANCHOR-${headings.length}-${Math.random().toString(36).slice(2, 8)}`;
    headings.push({ level: Number(level), text, id, token });
    const marker = `<span style="font-size:1px;color:#ffffff;position:absolute;">${token}</span>`;
    const idAttr = ` id="${id.replace(/&/g, '&amp;').replace(/"/g, '&quot;')}"`;
    return `<h${level}${attrs}${idAttr}>${marker}${displayInner}</h${level}>`;
  });

  mermaidBlocks.forEach((code, i) => {
    const token = `@@MERMAID_${i}@@`;
    const re = new RegExp(`<p>\\s*${token}\\s*</p>`);
    const replacement = `<pre class="mermaid">${code}</pre>`;
    if (re.test(html)) {
      html = html.replace(re, replacement);
    } else {
      html = html.replace(token, replacement);
    }
  });

  const baseDir = path.dirname(path.resolve(mdPath)).replace(/\\/g, '/');

  const page = `<!doctype html>
<html>
<head>
<meta charset="utf-8">
<base href="file:///${baseDir}/">
<title>${title.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')}</title>
<style>
${styleCss}
</style>
</head>
<body>
${html}
<script type="module">
  import mermaid from "https://cdn.jsdelivr.net/npm/mermaid@11/dist/mermaid.esm.min.mjs";
  mermaid.initialize({ startOnLoad: true, theme: "default" });
  window.__mermaidDone = false;
  mermaid.run().then(() => { window.__mermaidDone = true; });
</script>
</body>
</html>`;

  return { page, headings, title };
}

module.exports = { buildHtml };
