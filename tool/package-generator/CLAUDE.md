# CLAUDE.md

This file provides guidance to Claude Code when working in this directory
(`tool/package-generator`). It sits inside a larger documentation project; this
subtree is the one actual application/tool in the repo.

## What this tool is

A Windows batch/PowerShell tool that automates a 3-stage workflow for building
per-client delivery ZIPs from files stored on Teams/SharePoint:

1. **Download** — pull source files from a SharePoint site/folder to a local folder.
2. **Generate** — read `config/package_definition.xlsx` (one sheet = one client),
   copy the listed files/folders into a ZIP per sheet.
3. **Upload** — push the generated ZIPs back to a (different) SharePoint folder.

`all.bat` runs all three in order; each stage can be individually skipped via
`DOWNLOAD_ENABLED` / `GENERATE_ENABLED` / `UPLOAD_ENABLED` in `set-env.bat`.

**`README.md` (this folder) and `config/README.md` are the source of truth** for
current behavior, env var names/defaults, and the Excel column format — this file
only covers things useful for *editing* the tool, not for *using* it. Whenever you
change a default, rename a variable/file, or change documented behavior, update
both READMEs to match (this has been a recurring source of drift — verify against
the actual `.bat`/`.ps1` content, don't assume the README is already right).

## Directory layout

- `*.bat` (root) — user-facing entry points: `all.bat`, `download-folder.bat`,
  `generate-package.bat`, `upload-folder.bat`, `set-env.bat`. Kept flat in the
  root by explicit user preference (not moved into a `bats/` subfolder).
- `scripts/*.ps1` — the actual implementation, one per stage, plus `common.ps1`
  (dot-sourced shared helpers: Azure CLI/Graph auth, tree-view log formatting).
  Not meant to be run directly by the user.
- `config/package_definition.xlsx` + `config/README.md` — the manifest driving
  stage 2, and the guide for how to fill it in.
- `download/`, `work/`, `generated/`, `log/`, `test/` — runtime-generated folders
  (all gitignored). Safe to delete; scripts recreate what they need.

## Critical constraint: Shift-JIS (CP932) encoding

All `.bat` and `.ps1` files contain Japanese text and are saved as **Shift-JIS
(CP932)**, not UTF-8. **Never edit them with the Edit/Write tools directly** —
those assume UTF-8 and will silently corrupt every multi-byte character on save
(this has happened before and is not easily noticed until the file is reopened).

Use a byte-safe read/modify/write instead:

```powershell
$enc = [System.Text.Encoding]::GetEncoding(932)
$content = [System.IO.File]::ReadAllText($path, $enc)
$content = $content.Replace($old, $new)   # or -replace with a regex
[System.IO.File]::WriteAllText($path, $content, $enc)
```

Also preserve CRLF line endings — LF-only line endings combined with `^`
line-continuation in `.bat` files cause `cmd.exe` to misparse the file. If a
tool ever produces LF-only output, normalize with
`.Replace("\r\n","\n").Replace("\n","\r\n")` before writing.

`README.md` and `config/README.md` are plain UTF-8 Markdown — normal Edit/Write
is fine for those.

## Conventions

- File naming: kebab-case for `.bat`/`.ps1` (`download-folder.bat`, not
  `DownloadFolder.bat` or `download_folder.bat`).
- Env vars: `set-env.bat` defines all defaults via `if not defined VAR set "VAR=..."`,
  so external env vars (or values set earlier in the same file) always win.
  `%VAR%` expansion is per-line and order-sensitive — a variable referencing
  another (e.g. `GENERATE_SOURCE_BASE=%DOWNLOAD_LOCAL_DEST%`) must be defined
  after what it references.
- Each `.ps1` splits `$scriptDir` (for dot-sourcing `common.ps1`, since the
  scripts live in `scripts/`) from `$basePath` (the project root, for
  config/work/output/log path defaults):
  ```powershell
  $scriptDir = Split-Path $MyInvocation.MyCommand.Path
  $basePath = Split-Path $scriptDir -Parent
  ```
- Each `.bat` entry point does `set "EXITCODE=%ERRORLEVEL%"` immediately after
  the `powershell.exe` call (before any trailing `echo`/`timeout`, which would
  otherwise overwrite `%ERRORLEVEL%`) and `exit /b %EXITCODE%` at the end, so
  `all.bat`'s `if errorlevel 1 goto :error` chaining works correctly.

## Auth: Azure CLI + Microsoft Graph, not PnP.PowerShell

Download/upload authenticate via **Azure CLI** (`az login ... --use-device-code
--allow-no-subscriptions`) and call **Microsoft Graph** (`graph.microsoft.com`)
directly with the resulting token — see `Get-AzureCliPath` / `Get-GraphToken` in
`scripts/common.ps1`. This was a deliberate choice after PnP.PowerShell's and
Microsoft Graph PowerShell SDK's default multi-tenant apps were both blocked by
the target tenant's Conditional Access policy (`AADSTS700016`); Azure CLI's own
app was the one already consented. Raw SharePoint REST (`_api/web`) also 401s in
this tenant even with a valid token — use Graph endpoints, not REST, for any new
SharePoint operations here.

Upload of files >4MB must use a Graph resumable upload session (chunked `PUT`
with `Content-Range`); genuinely 0-byte files must instead `PUT` directly to
`.../content` since an empty `Content-Range` is rejected. Chunked `PUT`s should
go through `[System.Net.HttpWebRequest]` with `KeepAlive=$false` and a retry
loop, not `Invoke-WebRequest` — the latter intermittently drops the connection
on this endpoint.

## No test/lint suite

There is nothing to run beyond manually invoking the `.bat` files. When
verifying changes to the PowerShell logic, prefer running the real script
(with a real Azure CLI sign-in) over guessing — this tool has previously shipped
subtle path-handling bugs (e.g. relative-path `Substring` truncation) that only
showed up against real data.
