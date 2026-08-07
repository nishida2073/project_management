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
- `scripts/gui.ps1` — a WinForms front-end, three tabs (`実行`/`ログ`/`設定`),
  added via a single `$tabControl.Controls.AddRange(@($tabRun, $tabLogs,
  $tabSettings))` at creation time — see the ps2exe `Insert()` quirk below for
  why this must NOT be done by adding two tabs and inserting the third later.
  `$tabControl.SelectedTab = $tabRun` is set explicitly right before
  `Application::Run` — without it, WinForms silently defaulted to showing
  `設定` on startup instead of `実行` (root cause not fully understood; fixing
  the symptom directly was more productive than chasing it further). Don't
  remove that explicit assignment.
  - **実行 (Run)**: checkboxes for the 3 stages + a Run button + a log
    textbox. `Sync-RunCheckboxes` sets each checkbox from `Get-ResolvedVar`
    (i.e. from the *current* `set-env.bat`/env state, not a hardcoded
    default) — called once at startup and again whenever this tab is
    selected (`$tabControl.Add_SelectedIndexChanged`), so edits made on the
    設定 tab are reflected without restarting the app. Don't go back to
    hardcoding `.Checked = $true/$false` on the checkbox objects. Clicking
    実行 disables `$tabControl` itself (not just the checkboxes/button) for
    the duration of the run — this blocks tab-switching too, since a
    disabled `TabControl` also refuses header clicks, not just its child
    controls (explicit user request: no navigating away mid-run). Re-enable
    it in the same place the checkboxes/button get re-enabled after
    `$proc.WaitForExit()`. Sets `$env:DOWNLOAD_ENABLED` / `GENERATE_ENABLED` /
    `UPLOAD_ENABLED` from the checkboxes, then launches `all.bat` as a
    redirected child process and streams its stdout/stderr into the textbox
    (`Write-Host` output from the underlying `.ps1`s is captured fine this
    way — confirmed empirically). The log is *appended to*, not cleared,
    across runs (a `---------------- 新しい実行 ----------------` divider is
    inserted between runs — a plain dashed rule read as ambiguous once the
    per-batch `==================================================` headers
    were added below it, so it carries a label; the `-` vs `=` distinguishes
    "new GUI-triggered run" from "a batch within that run" at a glance) —
    don't reintroduce a `$txtLog.Clear()` here, that was an explicit user
    request to preserve run history.
  - **ログ (Log)**: radio buttons for the 3 stages + a single read-only
    viewer (no file picker — deliberately simplified per explicit user
    request; don't reintroduce a `ListBox` here). `Get-ResolvedVar` resolves
    a `set-env.bat` variable the same way `set-env.bat` itself would at
    runtime — env var override first
    (`[Environment]::GetEnvironmentVariable`), else the file's own
    `if not defined` default (via `Get-SetEnvDefaults`, reusing the 設定
    tab's `$lineRegex`/`Read-SetEnvLines`) — then expands `%BASE_PATH%`
    (hardcoded to `$basePath`) and recursively expands any other `%VAR%`
    token found in the value (e.g. `UPLOAD_SITE_URL=%DOWNLOAD_SITE_URL%`).
    Selecting a stage's radio button finds every file in
    `Get-ResolvedVar COMMON_LOG_PATH` matching `"$(Get-ResolvedVar
    "<STAGE>_LOG_PREFIX")*.log"` and concatenates their raw contents
    (newest-first, no added header — each `generate-package.ps1` log
    already embeds its own sheet name via its own `# フォルダ構成` section,
    so a synthetic per-file header in the viewer would be redundant, and
    for download/upload it'd just show the meaningless local-folder-name
    part of the filename) — no stage-specific branch; download/upload just
    happen to normally have only one matching file per run, so this looks
    like "show the one log" for them, while stage 2 (individual package
    creation, one log per Excel sheet) shows every sheet's log at once
    without needing a separate file picker. Per-sheet separation *during a
    run* instead comes from `generate-package.ps1`'s own
    `Write-Host "作成開始　$sheet"` / `"作成完了　$zip"` lines, which
    surface as-is in the 実行 tab's live-streamed log. Re-scans whenever that radio
    changes or the ログ tab is selected, so it reflects the latest run
    without needing an explicit refresh button.
  - **設定 (Settings)**: a generic editor for `set-env.bat`. It parses every
    `if not defined VAR set "VAR=value"` line via the regex
    `^if not defined (?<var>\S+) set "\k<var>=(?<val>.*)"$` (backreference
    ensures the two occurrences of the var name match) and renders one
    label per variable, grouped by the prefix before the first `_`
    (`COMMON`/`DOWNLOAD`/`GENERATE`/`UPLOAD`). Both the group label and the
    field label display a Japanese description (`$groupLabels`/`$varLabels`
    lookup tables) rather than the raw env var name — falls back to the raw
    name for anything not in the table, so a newly added `set-env.bat`
    variable still shows up (untranslated) instead of silently disappearing.
    The raw variable name is preserved as a `ToolTip` on the label
    (`$settingsToolTip.SetToolTip($lbl, $varName)`) so it's still
    discoverable for cross-referencing with this file/README.md. When adding
    a new variable to `set-env.bat`, also add an entry to `$varLabels` (and
    `$groupLabels` if it introduces a new prefix) — don't leave it to fall
    back silently if a proper Japanese label is easy to write. The
    value-side control depends on the variable name, checked against three
    explicit lists
    (`$enabledVars`/`$folderBrowseVars`/`$fileBrowseVars` — extend these
    lists, don't infer field type from the name pattern, per explicit user
    preference over an earlier `.EndsWith("_ENABLED")` version):
    - `$enabledVars` (`DOWNLOAD_ENABLED`/`GENERATE_ENABLED`/`UPLOAD_ENABLED`):
      a 有効/無効 `RadioButton` pair instead of a `TextBox`. **Each pair must
      live in its own child `Panel`** — WinForms `RadioButton`s are mutually
      exclusive against every *sibling* under the same parent, so without
      separate panels, checking one field's 有効 silently unchecks another
      field's (confirmed by reproducing it: setting all three to `Checked =
      $true` in sequence left only the last one actually checked). Recorded
      per-field in `$script:fieldRadios[$varName]` (the 有効 radio); Save
      reads `.Checked` from there instead of `.Text` from
      `$script:fieldTextBoxes`.
    - `$folderBrowseVars` (`DOWNLOAD_LOCAL_PATH`/`GENERATE_OUTPUT_PATH`/
      `UPLOAD_LOCAL_PATH`) and `$fileBrowseVars` (`GENERATE_CONFIG_PATH`):
      a `TextBox` plus a "参照..." button opening a `FolderBrowserDialog` /
      `OpenFileDialog`. The button's `.Tag` is set to its own `TextBox`
      object and the click handler reads `$this.Tag` — do this, don't
      capture `$txt` directly in the `Add_Click` scriptblock, since `$txt`
      is a loop variable reassigned every iteration of the field loop and a
      closure over it would see only the *last* field's textbox by the time
      any button is actually clicked. `Resolve-BrowseStart` expands
      `%BASE_PATH%`/`%VAR%` tokens in the field's current text (reusing
      `Get-ResolvedVar`) so the dialog opens at the real resolved location.
    - Everything else: a plain `TextBox`, as before.

    **Every field control in `$fieldPanel` must use `Anchor = Top|Left`
    only — never add `Right`.** `$fieldPanel` is measured at a tiny
    placeholder size (~200x60) at control-creation time and only reaches its
    real size (~660x456) once the tab is actually shown; a `Right`-anchored
    control's width/position is recalculated against whichever size was
    current when the anchor was established, which silently produces a
    control 20-30px wider/further right than the fixed `Size`/`Location` you
    gave it — confirmed twice: once with the "参照..." buttons appearing to
    not render at all (they were pushed outside the visible/scrollable area)
    and once with a plain `TextBox` (`DOWNLOAD_SITE_URL`) whose right edge
    ended up past `fieldPanel`'s actual client width, clipped off entirely.
    Both were fixed the same way: drop `Right` from `Anchor`, keep a fixed
    `Size` comfortably inside the ~660px usable width instead of relying on
    stretch-to-fit. If a control here ever looks missing or clipped, this is
    the first thing to check — verify with an in-process trace (see the
    verification gotcha below), not by eyeballing the compiled `.exe`.

    On Save, matched lines' values are rewritten back into `set-env.bat`
    byte-for-byte (verified via `Compare-Object` that untouched lines
    round-trip identically — including ones containing `%OTHER_VAR%`
    references, empty values, and backslashes). Adding a new variable to
    `set-env.bat` makes it show up here automatically as a plain `TextBox`
    field — no `gui.ps1` change needed unless it should be one of the
    special field types above.

  `build-gui.bat` / `scripts/build-gui.ps1` compile `gui.ps1` into
  `個社別ZIP生成ツール.exe` at the project root via the `ps2exe` PowerShell
  module (auto-installed on first run, same pattern as `ImportExcel`). The
  `.exe` itself is gitignored (`*.exe`) — it's a build artifact, rebuild it
  with `build-gui.bat` whenever `gui.ps1` changes.

  **Another confirmed ps2exe-only quirk**: `$tabControl.Controls.Insert(int,
  TabPage)` threw `"指定されたメソッドはサポートされていません"`
  (`NotSupportedException`) in the compiled `.exe`, but ran fine when the
  same script was launched directly via `powershell.exe -File` — i.e. it
  reproduced only in the packaged build, same as the `$MyInvocation` issue
  below. Root cause not fully understood (unlike the encoding issue, which
  was cleanly isolated to input-file reading); the fix was simply to avoid
  `TabPageCollection.Insert` altogether and add all tabs in final order via
  a single `.AddRange()` at creation time instead of building them in one
  order and reordering later. If a future change needs to reorder or
  dynamically insert tabs, budget time to test the actual compiled `.exe`,
  not just the `.ps1` — this class of bug is invisible in the latter.

  **Verification gotcha**: `SendMessage(hwnd, BM_GETCHECK, ...)` against a
  running WinForms `CheckBox`/`RadioButton`'s native handle is **not**
  reliable for verifying checked state from outside the process (it read `0`
  in every test here even when the `.Checked` .NET property — confirmed via
  an in-process trace written to a file from a `Form.Add_Shown` handler —
  was correctly `True`). When testing this GUI from outside (no access to
  the running PowerShell session's variables), prefer writing an in-process
  debug trace (e.g. from `Add_Click`/`Add_Shown`) to a temp file over
  `user32.dll` `SendMessage`/`GetWindowText`-based black-box probing for
  anything beyond visibility and text content. Also: `EnumChildWindows`
  finds controls belonging to *every* tab regardless of which is currently
  selected (not just the visible one) — filter by `IsWindowVisible` and be
  aware that controls on different tabs can have identical `Text` (e.g. the
  実行 tab's checkboxes and the ログ tab's radio buttons are both labelled
  "1. ファイルダウンロード" etc.), so a text-only match can silently grab the
  wrong tab's control.

## Critical constraint: Shift-JIS (CP932) encoding

All `.bat` and `.ps1` files contain Japanese text and are saved as **Shift-JIS
(CP932)**, not UTF-8, **except `scripts/gui.ps1`, which must be UTF-8 with a
BOM** (see below) because it is compiled by `ps2exe`. **Never edit any of
these files with the Edit/Write tools directly** —
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

**`scripts/gui.ps1` is the one exception** — it must be saved as UTF-8 with a
BOM, not CP932. Confirmed empirically: `ps2exe`'s `-inputFile` reader does not
respect the system ANSI codepage, so a CP932-encoded source compiles into an
exe with mangled/garbled Japanese text in every string literal (window title,
labels, log messages) — the string *lengths* even change (e.g. an 11-character
title became 17 characters), which is the tell that this is happening versus a
display-only rendering issue. UTF-8-with-BOM reads correctly both ways: via
`powershell.exe -File` (BOM is honored regardless of system codepage) and via
`ps2exe` compilation. Edit it like this instead of the CP932 snippet above:

```powershell
$utf8bom = [System.Text.UTF8Encoding]::new($true)
$content = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
$content = $content.Replace($old, $new)
[System.IO.File]::WriteAllText($path, $content, $utf8bom)
```

After editing `gui.ps1`, rebuild with `build-gui.bat` and actually launch the
resulting `.exe` to confirm the title/labels render correctly before
considering the change done — this class of bug is invisible in the source
file itself (which decodes fine) and only shows up in the compiled output.

`README.md` and `config/README.md` are plain UTF-8 Markdown — normal Edit/Write
is fine for those.

Always spell the filename `README.md` (all caps) in every tool call — never
`Readme.md`. Windows' filesystem is case-insensitive but case-*preserving*, so
reading/writing the file via the wrong case actually renames it on disk to that
case, silently, even though the path still resolves. This has happened
repeatedly to both `README.md` and `config/README.md` in this project. If it
happens again, fix it with `Rename-Item` (a plain `mv`/rename to the same name
with different case is a no-op on some tools — use PowerShell's `Rename-Item`,
which handles the case-only rename correctly).

## Conventions

- File naming: kebab-case for `.bat`/`.ps1` (`download-folder.bat`, not
  `DownloadFolder.bat` or `download_folder.bat`).
- Env vars: `set-env.bat` defines all defaults via `if not defined VAR set "VAR=..."`,
  so external env vars (or values set earlier in the same file) always win.
  `%VAR%` expansion is per-line and order-sensitive — a variable referencing
  another (e.g. `GENERATE_SOURCE_PATH=%DOWNLOAD_LOCAL_PATH%`) must be defined
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
