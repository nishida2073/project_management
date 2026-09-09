# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

This is not a software codebase — there is no source code, build system, linter, or test suite. The folder contains Japanese-language meeting notes and derived summary documents about an operational review (業務日誌 / パルスサーベイ / 勤怠 processes for a training program run with kintone).

## Files

This folder is a 3-stage pipeline, each stage derived from the previous one:

1. `議事録.txt` — the source meeting notes (raw transcript, multiple sessions, written by different people, with overlapping/duplicate content across sessions). This is the single source of truth; all other files are derived from it. Do not edit it to remove duplication — that's what `議事録（整理後）.txt` is for.
2. `議事録（整理後）.txt` — `議事録.txt` with duplicate content across sessions merged, organized by topic (業務日誌 / パルスサーベイ / 勤怠（出欠）).
3. `問題点・要望一覧.csv` — `議事録（整理後）.txt` reorganized into a table split by 業務 (topic) and カテゴリ (問題点・要望・その他). This is now the editable source of truth for the table directly — there is no separate `.md` staging file (removed; edit the `.csv` in place). Columns: `No, 業務, カテゴリ, 内容`.
   - **Encoded in Shift-JIS (CP932), not UTF-8** — for Excel compatibility. The `Write` tool always writes UTF-8, so after editing this file's content, re-encode it (e.g. via PowerShell `[System.IO.File]::WriteAllText(path, content, [System.Text.Encoding]::GetEncoding(932))`). To read its current content correctly, decode as CP932 too (don't rely on the default `Read` tool, which assumes UTF-8 and will show mojibake).
   - If the write fails with a file-in-use error, this CSV is very likely open in Excel — ask the user to close it (including quitting the Excel process, not just the window) before retrying, since Excel holds an exclusive OS-level lock.
   - `No` is a sequential row number starting at 1 with no gaps — renumber it whenever rows are added/removed/reordered.

## Working conventions established in this folder

- When asked to summarize or extract from `議事録.txt` (or `議事録（整理後）.txt`), always diff the result back against the full source text before calling it complete — prior passes have missed items (e.g., action items without an explicit "問題" label, or "特になし" notes for a subsection).
- "現状のフローの説明" (plain descriptions of the current process) are explicitly excluded from 問題点/要望 extraction unless asked otherwise.
- The カテゴリ column (problem/request type) supports three values: 問題点, 要望, その他 — その他 is for ambiguous/uncertain items (e.g. phrased with a question mark, or "no problem" statements) that aren't a clear problem or a clear request.
- 業務 values used: 全体 (cross-cutting items, e.g. involving SF/kintone account requests), 業務日誌, パルスサーベイ, 勤怠 — not その他, which is reserved for the カテゴリ column.
- Current sort order in `問題点・要望一覧.csv`: 業務 grouped with 全体 first, then remaining topics; within each 業務 group, rows ordered 問題点 → 要望 → その他. Preserve this ordering when adding rows, unless told otherwise.
- When editing this table, rewrite the whole file (via `Write`, to a scratch path, then re-encode to CP932 over the real path) rather than partial edits, since row order/grouping/numbering changes frequently.
