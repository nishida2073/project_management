# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repository is

This is a documentation project (not an application). It holds Japanese-language business-flow
documentation for a training-program operation (kintone/Zoom-based operations involving 運営サポート,
運営(SO), 講師, and 受講生 roles), plus a small local tool for turning that Markdown into PDF handouts
with mermaid flowchart diagrams and PDF bookmarks. There is no git repository initialized here.

## Directory layout

- `業務フロー図の元データ/*-base.md` — raw source notes for a business process, written as plain
  nested lists (no mermaid). Structure: `# アクター` (actor list) → `## 実施タイミング` (a short bullet
  list stating when the overall flow is triggered, e.g. 事前/研修前/研修当日/研修後 — copy this bullet
  list verbatim into the diagram doc's `### 実施タイミング`, never paraphrase or invent wording for it)
  → `# <業務名>` → `## N. <サブタスク>` → `### <担当者>` → numbered steps, each with nested `- 概要` /
  `- 利用ツール` sub-bullets (the actual description/tool text is one level deeper still, under those
  two labels). Omit `利用ツール` entirely when the step uses no tool. A step may also carry an optional
  `- メモ` sub-bullet (same nesting) for a supplementary note — carry it into the diagram as a note-class
  callout verbatim, same rule: no paraphrasing, no invented category labels (see "Flowchart conventions").
- `業務フロー図/*.md` — working deliverables: the same processes redrawn as mermaid swimlane
  flowcharts (see "Flowchart conventions" below). Start a new one by copying `業務フロー図/template.md`
  and following its structure exactly. Naming: `業務フロー（<業務名>）-base.md` maps to
  `業務フロー図（<実施タイミングの値>：<業務名>）.md` — the 実施タイミング value is the doc's own
  `### 実施タイミング` bullet (copied verbatim from the source `-base.md`, see above), not a fixed label;
  e.g. `業務フロー（勤怠）-base.md` (実施タイミング: 研修当日) → `業務フロー図（研修当日：勤怠）.md`.
- `業務フロー図/template.md` — the scaffold for new diagram docs; it is the source of truth for the
  current structure (headings, mermaid skeleton, 作業 list format) — check it before relying on the
  conventions summarized below, since it is the file most likely to have been edited since.
- `PDF/` — final rendered PDFs collected for distribution, one per business process, same
  `業務フロー図（<実施タイミング>：<業務名>）.pdf` naming as the source `.md` (e.g.
  `PDF/業務フロー図（研修当日：勤怠）.pdf`), rendered from the corresponding file in `業務フロー図/`.
  `md2pdf.bat` and `render-pdf.js` write next to the input `.md` by default, so the output still needs
  to be placed/renamed into `PDF/` to match this convention.
- `tool/md2png/` — the Node.js/Puppeteer conversion tool (see below), shared with the `tool/smstokintone`
  Android app project (which uses it to render its own manual to PDF). Its `node_modules` is already
  present/committed; only run `npm install` here if dependencies are missing.
- `md2pdf.bat` — Windows entry point: drag a `.md` file onto it (or run
  `md2pdf.bat "path\to\file.md"`) to produce `path\to\file.pdf` next to it.

## Common commands

Render a Markdown file (with mermaid code blocks) to a paginated PDF with a bookmark/outline panel
generated from its `##`/`###` headings:

```
node tool/md2png/render-pdf.js "input.md" "output.pdf"
```

or via the Windows wrapper:

```
md2pdf.bat "input.md"
```

Render to a single full-page PNG screenshot instead (no bookmarks) — useful for visually sanity-checking
a diagram's layout before committing to the PDF:

```
node tool/md2png/render.js "input.md" "output.png"
```

There is no lint/test suite (`package.json`'s `test` script is an unused placeholder).

## Rendering pipeline (`tool/md2png/`)

1. **`build-html.js`** — reads the Markdown, pulls out ` ```mermaid ` blocks into placeholder tokens
   so `marked` doesn't mangle them, runs `marked.parse`, then re-inserts each block as
   `<pre class="mermaid">`. It also injects an invisible (1px, white-text) unique token span into
   every `<h2>`/`<h3>` — this is how the next step locates headings on rendered PDF pages. The
   returned HTML page loads mermaid from a CDN (`jsdelivr`) via `<script type="module">` and sets
   `window.__mermaidDone` once diagrams finish rendering — **rendering requires network access** for
   the mermaid script.
2. **`render-pdf.js`** / **`render.js`** — launch headless Puppeteer, load the page, wait on
   `window.__mermaidDone`, then either print to PDF (`render-pdf.js`) or screenshot the full page
   (`render.js`).
3. **`add-bookmarks.js`** (PDF path only) — re-opens the printed PDF with `pdfjs-dist`, searches page
   text for each heading's invisible token to find which page it landed on, builds an `h2`-parent /
   `h3`-child outline tree, and writes a PDF outline (bookmarks) into the file via `pdf-lib`, setting
   `PageMode` to `UseOutlines` so viewers open with the bookmark panel visible.

## Flowchart conventions (`業務フロー図/*.md`)

Copy `業務フロー図/template.md` for new docs and keep this structure:

- Top of file: `# <フロー名>`, then `## 概要` with a one-line summary, a bullet list of the sub-flows
  covered, a sentence noting that diagrams are split by lane/condition, a `### 実施タイミング` bullet
  list copied verbatim from the source `-base.md`'s own `## 実施タイミング` section (distinct from each
  `## N.` section's own one-line condition paragraph, which states that specific diagram's narrower
  condition — that paragraph is still your own summary wording, only `### 実施タイミング` must be
  copied as-is), and a `**凡例**` legend (lane colors, a note that the paragraph under each `##` heading
  states that diagram's triggering condition, and the yellow-dashed-note-box legend line — include it
  even in docs that end up with no notes).
- Each sub-flow/condition is one `## N. <name>` section, containing in order:
  1. A one-line paragraph stating when this diagram applies (the condition, e.g. 事前連絡あり/なし,
     到着後, 未実施者向け).
  2. A fixed `### フロー図` heading with the mermaid diagram.
  3. A fixed `### 作業` heading listing every step as a bullet, in the order it occurs in the diagram:
     ```
     1. <作業名>
       - <作業の概要>
       - <利用ツール>
       - <メモ>
     ```
     Omit the 利用ツール sub-bullet when the source step lists no tool/method. Omit the メモ sub-bullet
     entirely when the source step has no `- メモ`. Copy 作業名, 概要, 利用ツール, and メモ verbatim from
     the `-base.md` source — don't paraphrase or merge them onto one line.
  Sections/diagrams are separated by `---` horizontal rules.
- Diagrams use `flowchart LR` with one `subgraph` per actor/lane, `direction TB` for the steps inside.
  Node labels use two lines via `<br/>`: `"<作業名><br/><利用ツール>"` (drop the `<br/>` line entirely
  when there's no tool).
- When a step's source entry has a `- メモ`, add a separate node for it (`["<メモの内容>"]:::note`)
  *inside the same subgraph* as the step it annotates, linked from that step's node with a dashed line
  (`-.-`, no arrowhead) — never fold the memo text into the step's own node label. Placing the note
  node outside the actor subgraph makes mermaid route the link to the subgraph's boundary instead of
  the specific step node, which reads as "attached to the lane" rather than "attached to this step".
  To keep the note visually beside its step (rather than drifting down next to a later step, since
  dagre ranks the note one level below the step it branches from), wrap just that step's node and its
  note in their own nested `subgraph <id>_g1[" "]` with `direction LR`, and route the lane's main chain
  through that nested subgraph instead of the bare step node. Give the nested subgraph an `invisible`
  class (`fill:none,stroke:none`) so it doesn't render as a visible box.
- If the same actor's lane recurs at two non-adjacent points within a single diagram (e.g. it hands off
  to another actor and later receives a result back from them), give it a separate `subgraph` per
  occurrence instead of merging all of that actor's steps into one box — merging forces mermaid's
  layout to route the connecting edges backward across the whole diagram, producing a confusing
  loop-shaped result.
- Actor lanes use a fixed color scheme via `classDef`, applied consistently across all diagrams:
  - 運営サポート → `ops`: `fill:#4c6b8a` (blue)
  - 運営（SO） → `so`: `fill:#6b5b8a` (purple)
  - 講師 → `instr`: `fill:#4c7a5d` (green)
  - 受講生 → `student`: `fill:#a9822f` (amber)
  - Other actors outside this core cast (e.g. 構築担当者, 設営担当者) aren't covered by the four colors
    above — assign them a new muted color in the same style (similar saturation/lightness, one
    dominant channel) the first time they appear, and record the choice here so later docs reuse it
    consistently instead of picking a fresh color per file:
    - 構築担当者 → `build`: `fill:#4c8a8a` (teal)
    - 運営（SD） → `sd`: `fill:#8a4c6b` (wine)
    - システムフロンティア → `sf`: `fill:#5b6b4c` (olive)
    - 設営担当者 → `setup`: `fill:#8a5c4c` (rust/terracotta)
  - All actor `classDef`s (the four core colors and any additional muted colors above) also set
    `color:#000` — the node text must render in black rather than inheriting a light/white default,
    which is unreadable against these mid-tone fills.
  - Supplementary note callouts (dashed, linked with `-.-`) use a `note` class:
    `fill:#fff6cc,stroke:#c9a227,stroke-dasharray:4 3,color:#1c232c`. The explicit `color` is required —
    without it the note text inherits the page's default node text color, which reads as white on the
    pale yellow fill and is unreadable.
  - Actor subgraph (lane) boxes get an explicit `lane` class — `fill:#f2f2f2,stroke:#b0b0b0,color:#000` —
    applied via `class <subgraph ids> lane;` for every subgraph in the diagram. Mermaid's default cluster
    background is a pale yellow that's easy to confuse with the `note` callout color, so every diagram
    must override it explicitly rather than relying on the default; the explicit `color:#000` keeps the
    lane title text black regardless of the surrounding theme.
- Mermaid syntax rules: never use the bidirectional arrow (`<-->`), always use `-->`; represent
  cautionary/supplementary content as a dashed `note`-class box linked with `-.-`, not inline text.
