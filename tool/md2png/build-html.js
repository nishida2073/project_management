const fs = require('fs');
const path = require('path');
const { marked } = require('marked');

function buildHtml(mdPath) {
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
  html = html.replace(/<h([23])([^>]*)>(.*?)<\/h\1>/g, (m, level, attrs, inner) => {
    const token = `ANCHOR-${headings.length}-${Math.random().toString(36).slice(2, 8)}`;
    const text = inner.replace(/<[^>]+>/g, '').trim();
    headings.push({ level: Number(level), text, token });
    const marker = `<span style="font-size:1px;color:#ffffff;">${token}</span>`;
    // markedは見出しにid属性を付与しないため、同一ドキュメント内の[text](#見出しテキスト)形式の
    // リンクが何にもジャンプできずリンク自体が生成されない。リンク側は見出しの生テキストをそのまま
    // フラグメントに使っているため、同じテキストをidとして付与し、対応が取れるようにする
    const idAttr = ` id="${text.replace(/&/g, '&amp;').replace(/"/g, '&quot;')}"`;
    return `<h${level}${attrs}${idAttr}>${marker}${inner}</h${level}>`;
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

  // 画像などをmdPathからの相対パス（例: screenshots/foo.png）で参照しているMarkdownのために、
  // そのファイル自身のディレクトリを基準に解決されるよう<base>を注入する
  const baseDir = path.dirname(path.resolve(mdPath)).replace(/\\/g, '/');

  const page = `<!doctype html>
<html>
<head>
<meta charset="utf-8">
<base href="file:///${baseDir}/">
<title>${title.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;')}</title>
<style>
  body {
    font-family: "Hiragino Sans", "Yu Gothic UI", "Meiryo", system-ui, sans-serif;
    max-width: 900px;
    margin: 0 auto;
    padding: 40px;
    color: #1c232c;
    background: #ffffff;
    line-height: 1.8;
  }
  h1 { font-size: 2.2rem; }
  h2 { font-size: 1.8rem; margin-top: 2.5rem; border-bottom: 1px solid #d3d9df; padding-bottom: 0.3rem; break-before: page; }
  h3 { font-size: 1.45rem; margin-top: 1.8rem; color: #2b5f73; }
  h4 { font-size: 1.2rem; margin-top: 1.4rem; color: #2b5f73; }
  hr { border: none; border-top: 1px solid #d3d9df; margin: 2rem 0; }
  li { margin-bottom: 0.3rem; }
  strong { color: #2b5f73; }
  .mermaid { text-align: center; margin: 1rem 0; break-inside: avoid; }
  h2, h3, h4 { break-after: avoid; }
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
