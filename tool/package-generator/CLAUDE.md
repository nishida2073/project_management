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
`DOWNLOAD_ENABLED` / `GENERATE_ENABLED` / `UPLOAD_ENABLED` in `clients\set-env.bat`.

**`README.md` (this folder) and `config/README.md` are the source of truth** for
current behavior, env var names/defaults, and the Excel column format — this file
only covers things useful for *editing* the tool, not for *using* it. Whenever you
change a default, rename a variable/file, or change documented behavior, update
both READMEs to match (this has been a recurring source of drift — verify against
the actual `.bat`/`.ps1` content, don't assume the README is already right).

## Directory layout

- `*.bat` (root) — user-facing entry points: `all.bat`, `download-folder.bat`,
  `generate-package.bat`, `upload-folder.bat`. Kept flat in the
  root by explicit user preference (not moved into a `bats/` subfolder). Each
  does `cd /d %~dp0` then `call clients\set-env.bat` — note the `clients\`
  prefix; `set-env.bat` itself lives one level down (see next bullet), unlike
  these four which stay in the root.
- `scripts/*.ps1` — the actual implementation, one per stage, plus `common.ps1`
  (dot-sourced shared helpers: Azure CLI/Graph auth, tree-view log formatting).
  Not meant to be run directly by the user.
- `clients/` — `set-env.bat` (the real defaults file, moved here from the
  project root — see `clients/README.md` for why and the resulting
  `BASE_PATH` computation gotcha) plus one `set-env-<client name>.bat` per
  client, each overriding a subset of the same variables. See the GUI's
  設定/実行 tab notes below for how these are read/written/applied — this
  mechanism is entirely GUI-side; the `.bat`/`.ps1` entry points have no
  concept of "clients", they only ever see whatever's already in the
  environment plus whatever `clients\set-env.bat` fills in.
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
    textbox. `Update-RunCheckboxesFromClient` (via `Get-ClientAwareEnabledValue`,
    which reads the selected client's `*_ENABLED` value or falls back to
    `Get-ResolvedVar`, i.e. the *current* `set-env.bat`/env state, not a
    hardcoded default) sets the checkboxes — called once at true startup and
    again whenever the client dropdown's selection actually changes
    (`$cmbClient.Add_SelectedIndexChanged`). **It is deliberately NOT called
    just from revisiting this tab.** The `$tabControl.Add_SelectedIndexChanged`
    handler's 実行-tab branch calls only `Update-ClientList` (refreshes the
    client dropdown's *items*) — it used to also call the checkbox-sync
    function on every tab visit (via a `Sync-RunCheckboxes` wrapper, since
    removed as a no-op-adding indirection once it was trimmed down to just
    that one call), but that silently discarded any manual checkbox edit the
    moment the user switched to 設定/ログ and back, which reads as "the GUI
    checkbox isn't being respected" (confirmed by user report). The set-env.bat/
    client value is only ever a *starting point*; once the checkboxes are on
    screen, only an explicit client-dropdown switch (or restarting the app)
    reloads them from that starting point again — a manual checkbox edit
    persists across tab switches, and whatever the checkboxes show at the
    moment 実行 is clicked is what runs (matches the pre-existing
    `$clientRuntimeExcludeVars` design principle: checkboxes are the runtime
    authority — see the ログ/設定 note on `Get-ClientAwareEnabledValue` below
    for the loading side of this). Don't go back to calling the checkbox-sync
    function from the 実行-tab branch of the tab-selection handler.

    A related trap: `Update-ClientComboItems` (shared by all three client
    dropdowns) does `$ComboBox.Items.Clear()` then re-adds items and
    re-applies `.SelectedIndex` — `Clear()` resets `SelectedIndex` to `-1`
    first, so the subsequent re-assignment fires `SelectedIndexChanged` even
    when the resolved selection is the *same* client as before. Left
    unguarded, this means merely refreshing the client list (e.g. from
    `Update-ClientList` on every 実行-tab visit, or `Update-SettingsClientList`
    on every 設定-tab visit) would spuriously re-trigger whatever's wired to
    that dropdown's `SelectedIndexChanged` — silently resetting the run
    checkboxes (this exact bug), and would similarly wipe out any *unsaved*
    edits in the 設定 tab's field panel via a spurious `Update-SettingsFields`
    re-render. Fixed with a script-scoped `$script:suppressComboSync` flag,
    set `$true` for the duration of `Update-ClientComboItems`'s
    Clear/re-add/re-select and checked (skip if `$true`) at the top of all
    three dropdowns' `SelectedIndexChanged` handlers
    (`$cmbClient`/`$cmbSettingsClient`/`$cmbLogClient`). A genuine user click
    on a dropdown item never goes through `Update-ClientComboItems`, so the
    flag is always `$false` when a real selection change happens — only the
    programmatic refresh's spurious re-fire gets suppressed. Clicking
    実行 blocks tab-switching for the duration of the run (explicit user
    request: no navigating away mid-run), but **not** via
    `$tabControl.Enabled = $false` — that was the original approach and it
    broke device-code sign-in: WinForms cascades a disabled parent down to
    all descendants regardless of their own `.Enabled` value, so disabling
    `$tabControl` also disabled `$txtLog` (the log textbox, a descendant of
    the 実行 tab), making the just-printed sign-in URL/code unselectable and
    uncopyable right when the user needed to copy it into a browser. Fixed
    by leaving `$tabControl` itself always enabled and instead cancelling
    navigation via its `Selecting` event: a script-scoped `$script:isRunning`
    flag is set `$true` at the top of `Add_Click` / `$false` at the end, and
    `$tabControl.Add_Selecting({ if ($script:isRunning -and $_.TabPage -ne $tabRun) { $_.Cancel = $true } })`
    (registered once, right after the tab pages are added) blocks switching
    to ログ/設定 while running without touching any control's `Enabled`
    state — `$txtLog` stays selectable/copyable throughout. Sets
    `$env:DOWNLOAD_ENABLED` / `GENERATE_ENABLED` /
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

    **Client profile switching**: a `$cmbClient` dropdown (populated by
    `Update-ClientList`, called directly from the 実行-tab branch of the
    `$tabControl.Add_SelectedIndexChanged` handler so the *list of clients*
    refreshes whenever the 実行 tab is selected — not the checkboxes, see
    above) lists every
    `clients\set-env-*.bat` file with the `set-env-` prefix and `.bat`
    extension stripped, plus a leading `$defaultClientLabel` ("デフォルト" —
    shared across all three client dropdowns, see below). `Update-ClientList`
    and the 設定 tab's `Update-SettingsClientList` are both thin wrappers around the
    shared `Update-ClientComboItems -ComboBox ... -FixedItems @(...)` (the
    `-FixedItems` array lets a dropdown prepend more than one non-client
    entry — the ログ tab's dropdown needs both "すべて" and `$defaultClientLabel`,
    see below) — don't reintroduce a second copy of the scan/populate logic
    if a third dropdown like this ever gets added. The `set-env-` prefix itself is never
    hardcoded: `$clientFilePrefix = [System.IO.Path]::GetFileNameWithoutExtension($setEnvBat)`
    derives it from `$setEnvBat` (`clients\set-env.bat`), so renaming that
    file would (mostly) carry through automatically — see `Get-ClientBatPath`,
    the single place that builds a `clients\<prefix>-<name>.bat` path.

    This is a deliberately lightweight, session-only override mechanism —
    it does **not** touch `clients\set-env.bat`. Each
    `clients\set-env-<name>.bat` holds plain unconditional `set "VAR=value"`
    lines (see `clients/README.md` for the format), parsed by
    `Get-ClientProfileValues` with its own regex
    (`^set "(?<var>\S+?)=(?<val>.*)"$` — no `if not defined`/no backreference,
    unlike `$lineRegex`, since these lines are meant to unconditionally win)
    and each value run through the existing `Expand-VarTokens` (so
    `%BASE_PATH%` etc. still work inside a client file). `$clientOverridableVars`
    lists every variable a client file is allowed to override — everything
    in `clients\set-env.bat` *except* the four log-related ones
    (`COMMON_LOG_PATH`/`DOWNLOAD_LOG_PREFIX`/`GENERATE_LOG_PREFIX`/
    `UPLOAD_LOG_PREFIX`) — kept as an explicit list, not a
    name-pattern exclusion, per the same "extend the list, don't infer from
    the name" preference as `$enabledVars`/`$folderBrowseVars`/`$fileBrowseVars`
    above. That list includes the three `*_ENABLED` vars (so a client file
    *can* record its own preferred enabled/disabled state and the 設定 tab
    can edit it). `Get-ClientAwareEnabledValue`/`Update-RunCheckboxesFromClient`
    (wired to `$cmbClient.Add_SelectedIndexChanged`, and also called once at
    startup — see the 実行-tab note above for why it's *not* called from the
    tab-selection handler's 実行-tab branch) read the selected client's `*_ENABLED` value (via
    `Get-ClientProfileValues`, falling back to `Get-ResolvedVar` when the
    client doesn't override that var or `$defaultClientLabel` is selected)
    and set the checkboxes to match *at the moment the dropdown selection
    changes* — this is what actually makes a client's saved `*_ENABLED`
    preference visible/useful, since previously it was write-only (editable
    in 設定, never read anywhere). Despite that, `$clientRuntimeExcludeVars`
    (just those three) is still consulted when *applying* a client on
    `Add_Click` — the checkboxes are the actual authority over what runs for
    *this* click, so a client's own `*_ENABLED` value is skipped there to
    avoid silently overriding whatever the user just checked/unchecked by
    hand *after* switching clients. In other words: switching clients loads
    that client's `*_ENABLED` values into the checkboxes as a starting point,
    but whatever the checkboxes actually show at the moment 実行 is clicked
    is what wins — switching clients doesn't bypass manual checkbox edits.

    **This exclusion on the GUI side is not sufficient by itself.**
    `$env:DOWNLOAD_ENABLED`/etc. set from the checkboxes are only the
    *starting* environment for the child `all.bat` process; `all.bat` still
    calls `clients\set-env.bat` (`if not defined`, harmless — checkbox values
    survive) *and then* `clients\set-env-%CLIENT_NAME%.bat`. Client files use
    unconditional `set "VAR=value"` by design (see `clients\README.md`) so
    that a client's override always wins for every other variable — but
    `Save-ClientProfile` originally wrote the three `*_ENABLED` vars the same
    unconditional way too (needed so `Get-ClientProfileValues` could read
    them back for the checkbox-loading feature above), so a selected
    client's file, once `call`ed by `all.bat`, unconditionally overwrote
    `DOWNLOAD_ENABLED`/etc. right back to that client's own saved value,
    clobbering whatever the checkboxes had just set. Symptom (confirmed by
    user report): checkboxes were respected with デフォルト selected (no
    client file gets `call`ed) but silently ignored with any other client
    selected.

    Fixed entirely on the `gui.ps1` side, with **zero changes to any `.bat`
    file** — `Save-ClientProfile` now writes the three `*_ENABLED` lines as
    `if not defined VAR set "VAR=value"` (the same idiom `set-env.bat` itself
    uses) instead of a plain unconditional `set`, while every other
    `$clientOverridableVars` entry stays unconditional. Since `all.bat`
    always calls `clients\set-env.bat` first — which sets `DOWNLOAD_ENABLED`
    etc. from the GUI's checkbox-derived env var if already defined, or its
    own default otherwise — by the time the client file's `if not defined`
    line runs, the var is already defined either way, so that line is always
    a no-op at execution time. The client file can still carry its own saved
    `*_ENABLED` preference (read back for the checkbox-loading feature), it
    just never actually *takes effect* when the batch chain runs — consistent
    for both the GUI path and a bare `client=<name>` command-line run with no
    GUI involved. `Get-ClientProfileRawValues` falls back to matching a
    client-file line against `$lineRegex` (the same `if not defined VAR set
    "VAR=value"` pattern used to parse `set-env.bat` itself, now shared
    rather than duplicated — see `$clientLineRegex` for the plain-`set`
    pattern tried first) when `$clientLineRegex` fails to match, so it can
    still parse this `if not defined` form back out for the
    checkbox-loading feature — a
    client file is now expected to mix both line styles, which is why
    `clients\README.md` carves out this exception to its otherwise-blanket
    "use unconditional `set`" rule. Trade-off worth knowing: this only
    protects files the GUI itself writes — `clients\README.md` also
    documents hand-editing a client file with plain `set` lines, and a
    manually-added unconditional `set "DOWNLOAD_ENABLED=..."` would
    reintroduce the exact same clobbering bug for that one file. A
    `.bat`-side fix (save the three vars to `SAVED_*` right after `call
    clients\set-env.bat`, restore them right after the client-file `call`,
    in all four entry points) would have protected against that too, at the
    cost of touching every entry point instead of just `gui.ps1` — deliberately
    not chosen here; revisit if a hand-edited client file's `*_ENABLED` line
    turns out to matter in practice.
    On `Add_Click`, before applying the
    selected client's (non-excluded) values, every var name from
    `$script:lastClientVars` (whatever the *previous* run's client actually
    applied) is cleared via `[Environment]::SetEnvironmentVariable($varName, $null)`
    — skipping this step means switching from one client to `$defaultClientLabel`
    (or to a client that doesn't override the same vars) would silently leave the
    previous client's values in the process environment, since
    `[Environment]::SetEnvironmentVariable` at process scope persists for
    the GUI's lifetime, not just one run. `$cmbClient` is disabled for the
    duration of a run alongside the stage checkboxes (not via the
    `$tabControl.Enabled` mistake above — same reasoning, but this control
    lives in the always-enabled 実行 tab so it was never actually at risk;
    disabled purely to prevent switching clients mid-run).
  - **ログ (Log)**: radio buttons for the 3 stages + a single read-only
    viewer (no file picker — deliberately simplified per explicit user
    request; don't reintroduce a `ListBox` here). `Get-ResolvedVar` resolves
    a `clients\set-env.bat` variable the same way that file itself would at
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
  - **設定 (Settings)**: a generic editor for `clients\set-env.bat` (and, via
    the target dropdown described further down, for `clients\set-env-<name>.bat`
    client files too). It parses every
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
    a new variable to `clients\set-env.bat`, also add an entry to `$varLabels` (and
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

    On Save, matched lines' values are rewritten back into
    `clients\set-env.bat` byte-for-byte (verified via `Compare-Object` that
    untouched lines round-trip identically — including ones containing
    `%OTHER_VAR%` references, empty values, and backslashes). Adding a new
    variable to `clients\set-env.bat` makes it show up here automatically as
    a plain `TextBox` field — no `gui.ps1` change needed unless it should be
    one of the special field types above (though see the next paragraph —
    also add it to `$clientOverridableVars` unless it's log-related, or a
    client target's field list will silently be missing it).

    **Client profile editing** (added alongside the 実行 tab's `$cmbClient`
    dropdown — see there for the runtime-override mechanism and for
    `$clientFilePrefix`/`Get-ClientBatPath`, both defined once near the top
    of the script and reused by everything below): a `$cmbSettingsClient`
    dropdown at the top (label `$lblSettingsClient`, text "クライアント:" —
    originally "対象:"/`$lblTarget`/`$cmbSettingsTarget`, renamed so the label
    and variable names read the same across all three tabs' client dropdowns,
    see `$defaultClientLabel` below), populated by `Update-SettingsClientList`
    with `$defaultClientLabel` ("デフォルト" — a single shared constant defined
    once near the top of the script and reused by the 実行/ログ/設定 tabs'
    dropdowns, so the "no client selected" wording can't drift out of sync
    between them again) plus every `clients\set-env-*.bat` filename
    (prefix/extension stripped), sharing its scan/populate logic with the
    実行 tab's dropdown via `Update-ClientComboItems -ComboBox ... -FixedItems
    @($defaultClientLabel)` (only the fixed items and target `ComboBox`
    differ — don't duplicate the `Get-ChildItem`/`Sort-Object`/
    preserve-selection logic a third time
    if another dropdown like this gets added later). Switching
    `$cmbSettingsClient` (`Add_SelectedIndexChanged`) re-renders
    `$fieldPanel` via the same `Update-SettingsFields`, which now delegates
    the *which fields, in what order, with what starting value* decision to
    `Get-SettingsFieldSource`: `$defaultClientLabel` selected → same as
    before (every `clients\set-env.bat` line); a client selected → only
    `$clientOverridableVars` — every variable *except* the four log-related
    ones (see the 実行-tab note above for why that list is explicit, and why
    it still includes the three `*_ENABLED` vars even though applying a
    client at runtime skips them) — each value coming from that client's own
    `set "VAR=value"` line (`Get-ClientProfileRawValues` — deliberately the
    *raw*, un-`Expand-VarTokens`'d value, e.g. still `%DOWNLOAD_SITE_URL%`
    rather than its resolved URL, so the editor shows/round-trips literal
    template text the same way the default editor already does) if
    present, else `Get-SetEnvDefaults`'s raw value for that var. The rest of
    the per-field rendering body (group headers, `$varLabels`, the
    `$enabledVars`/`$folderBrowseVars`/`$fileBrowseVars` dispatch) is
    unchanged and shared regardless of which is selected — e.g. the three
    `*_ENABLED` vars still render as the same 有効/無効 `RadioButton` pair, and
    `GENERATE_CONFIG_PATH` still gets the file-browse button, when editing a
    client. Save (`$btnSave.Add_Click`) branches the same way, into
    `Save-DefaultSettings` (the original `clients\set-env.bat` rewrite,
    unchanged) or `Save-ClientProfile` — the latter always writes *every*
    `$clientOverridableVars` entry as an unconditional `set "VAR=value"`
    line (even ones left equal to the inherited default), rather than only
    the ones the user actually edited — simpler than tracking which fields
    were touched, at the cost of the saved file containing some
    redundant-with-default lines. "新規作成..." (`$btnNewClient`) prompts for
    a name via `[Microsoft.VisualBasic.Interaction]::InputBox` (needs
    `Add-Type -AssemblyName Microsoft.VisualBasic`; loaded lazily in the
    click handler, not at script startup, since nothing else needs it) and
    refuses to overwrite an existing client file (`MessageBox` warning). It
    deliberately does **not** touch disk at all — no client `.bat` is
    created until the user actually clicks 保存. An earlier version wrote an
    empty file (later, briefly, a file pre-populated with the three initial
    values below) immediately on click; both were rejected because a file
    already existed on disk before any explicit save, which reads as
    "新規作成だけでファイルが作成されてしまう" (confirmed by user report) and, for the
    pre-populated version, left a window where the on-disk content (just
    three vars) didn't match what 保存 would eventually write (every
    `$clientOverridableVars` entry) — a "中途半端" intermediate state.
    Instead, the handler adds the new name directly to
    `$cmbSettingsClient.Items` (bypassing `Update-ClientComboItems`'s
    filesystem scan entirely) and selects it, which fires the existing
    `SelectedIndexChanged` handler and renders fields the normal way —
    `Get-SettingsFieldSource` → `Get-ClientProfileRawValues` finds no file on
    disk and returns an empty map, so every field falls back to
    `Get-SetEnvDefaults`, exactly as if an empty client file existed. Three
    fields then get a friendlier starting value than the bare default,
    written directly into `$script:fieldTextBoxes[...].Text` (UI only,
    nothing round-tripped through a file) — each derived from
    `Get-SetEnvDefaults`'s *raw* value for that var plus the new client name,
    matching the "クライアント名以外は set-env.bat の値から取得" requirement:
    - `GENERATE_CONFIG_PATH`: default's trailing `.xlsx` becomes
      `_<name>.xlsx` (e.g. `...\package_definition.xlsx` →
      `...\package_definition_<name>.xlsx`)
    - `GENERATE_OUTPUT_PATH`: default with `/<name>` appended
      (`%BASE_PATH%generated` → `%BASE_PATH%generated/<name>`)
    - `UPLOAD_SITE_PATH`: default with `/<name>` appended — confirmed with
      the user that this means appending to the literal current default
      (`.../納品2`) rather than a hand-typed `.../納品` some other tool or doc
      might use, i.e. whatever set-env.bat's `UPLOAD_SITE_PATH` default
      says today is always the base, "2" included or not
    A file only comes into existence when `$btnSave.Add_Click` calls
    `Save-ClientProfile`, which was already unconditional-`WriteAllText` and
    needed no change — it works identically whether or not the target file
    previously existed. The trade-off: if the user leaves the 設定 tab (or
    otherwise triggers `Update-SettingsClientList`'s filesystem rescan)
    before saving, the pending name — never having been on disk — silently
    drops out of `$cmbSettingsClient`'s item list on the next rebuild. This
    is intentional under "unsaved = doesn't exist," not a bug to fix.
  - **ログ (Log) — client filter**: a `$cmbLogClient` dropdown (label
    `$lblLogClient`, text "クライアント:", positioned above the stage radio
    buttons, same layout convention as the 実行 tab's `$lblClient`/`$cmbClient`
    row) populated by `Update-LogClientList` — another thin wrapper around
    `Update-ClientComboItems`, but with `-FixedItems @("すべて",
    $defaultClientLabel)` instead of just `@($defaultClientLabel)`: "すべて"
    (no filtering — every log regardless of which client, if any, produced
    it) and "デフォルト" (only logs from runs where no client was selected)
    are genuinely different filters, so both are offered rather than
    collapsing to one. `Update-LogView` reads `$cmbLogClient.SelectedItem`
    and, unless it's "すべて", appends `"$logClient" + "_"` to the
    `Get-ChildItem -Filter` pattern — when `$logClient` is `$defaultClientLabel`
    ("デフォルト") this becomes the same `"デフォルト_"` segment
    `Get-ClientLogSegment` (`scripts\common.ps1`) inserts into log filenames
    for a no-client run, and when it's an actual client name it becomes that
    client's `<name>_` segment — either way `Update-LogView`'s filter and
    `Get-ClientLogSegment`'s filename segment are built from the same
    `$defaultClientLabel` string, so they can't drift out of sync. Re-scans/
    re-renders on the same triggers as the stage radios
    (`Add_SelectedIndexChanged`, and the ログ tab's `SelectedIndexChanged`
    case in the shared `$tabControl` handler calls both `Update-LogClientList`
    and `Update-LogView`). A sibling helper, `Get-ClientLogHeaderLines` (also
    `scripts\common.ps1`), returns `@("クライアント: <名前>")` when
    `$env:CLIENT_NAME` is set, or `@("クライアント: $defaultClientLabel")`
    otherwise — mirroring `Get-ClientLogSegment`'s own `$env:CLIENT_NAME`
    check (`"$($env:CLIENT_NAME)_"` or `"${defaultClientLabel}_"`) so the log
    *content* and the log *filename* always agree on which client (or
    デフォルト) actually ran, even though the two live in separate functions
    (one returns a display line, the other a filename fragment). Both read
    a `$defaultClientLabel = "デフォルト"` defined once near the top of
    `scripts\common.ps1` (right after `$cp932`) — added after "デフォルト" was
    found hardcoded independently in both functions (confirmed by user
    report: the literal was scattered across the codebase with no single
    source of truth). Note this is a **separate** constant from `gui.ps1`'s
    own `$defaultClientLabel` (see above) — the two can't share one
    PowerShell variable since `common.ps1` is dot-sourced into the
    `download-folder.ps1`/`generate-package.ps1`/`upload-folder.ps1` child
    processes `all.bat` launches, an entirely different PowerShell session
    from the GUI's, and those scripts must also work when run standalone
    without the GUI at all. Consolidation only happens *within* each file;
    keep both literals in sync by hand if "デフォルト" ever needs to change.
    Watch for `"$defaultClientLabel_"` here — PowerShell parses a trailing
    underscore as part of the variable name, silently interpolating an
    unset `$defaultClientLabel_` (empty string) instead of the intended
    variable followed by a literal `_`; use `"${defaultClientLabel}_"`.
    Each of the three stage `.ps1` scripts splices its result into
    `$logLines` right after `"# 実行情報"` and before `バッチ名:`, without
    duplicating the `if ($env:CLIENT_NAME) {...}` check a third time.

  `build-gui.bat` / `scripts/build-gui.ps1` compile `gui.ps1` into
  `コース別パッケージ生成ツール.exe` at the project root via the `ps2exe` PowerShell
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

## Critical constraint: file encoding

**`.bat` files** contain Japanese text and are saved as **Shift-JIS (CP932)**,
not UTF-8 — cmd.exe's native handling of Japanese text is far more reliable
than UTF-8, which needs `chcp 65001` and still has rough edges (BOM
misinterpreted as garbage on the first line, some built-in commands mangling
non-ASCII). **Never edit `.bat` files with the Edit/Write tools directly** —
those assume UTF-8 and will silently corrupt every multi-byte character on
save (this has happened before and is not easily noticed until the file is
reopened). Use a byte-safe read/modify/write instead:

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

**All `.ps1` files** (`common.ps1`, `download-folder.ps1`,
`generate-package.ps1`, `upload-folder.ps1`, `build-gui.ps1`, `gui.ps1`) are
saved as **UTF-8 with a BOM** — not CP932. `gui.ps1` had to be UTF-8-with-BOM
from the start: it's compiled by `ps2exe`, whose `-inputFile` reader doesn't
respect the system ANSI codepage, so a CP932 source there used to compile into
an exe with mangled Japanese string literals (confirmed empirically — string
*lengths* even changed, e.g. an 11-character title became 17 characters). The
other four `.ps1` files were migrated from CP932 to UTF-8-with-BOM afterward,
purely to remove the CP932 editing tax (byte-safe read/modify/write, no plain
Edit/Write, an actual bug introduced mid-migration from a `"$var_"` PowerShell
interpolation gotcha) that `.bat` files are stuck with for the cmd.exe reasons
above — `.ps1` has no such constraint, since Windows PowerShell 5.1 honors a
UTF-8 BOM regardless of the system codepage (`chcp`/locale don't matter),
confirmed both via `powershell.exe -File` and `ps2exe` compilation.

Because of this, **`.ps1` files can be edited with the normal Edit/Write
tools** — verified empirically that Edit preserves the BOM. After any edit,
still verify both, since a lost BOM or line-ending drift is easy to miss
silently:

```powershell
$bytes = [System.IO.File]::ReadAllBytes($path)
$hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
$content = [System.IO.File]::ReadAllText($path, [System.Text.Encoding]::UTF8)
$null = [System.Management.Automation.PSParser]::Tokenize($content, [ref]$null)  # throws on syntax error
```

After editing `gui.ps1` specifically, also rebuild with `build-gui.bat` and
actually launch the resulting `.exe` to confirm the title/labels render
correctly before considering the change done — a lost BOM is invisible in the
source file itself (which still decodes fine) and only shows up in the
compiled output.

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
- Env vars: `clients\set-env.bat` defines all defaults via `if not defined VAR set "VAR=..."`,
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
- **`clients\set-env.bat`'s `BASE_PATH` line is not a plain `%~dp0`.**
  `%~dp0` always means "the directory of the currently-executing batch
  file", so after `set-env.bat` moved from the project root into `clients\`,
  a bare `set "BASE_PATH=%~dp0"` there would silently point every default
  (`COMMON_LOG_PATH`, `DOWNLOAD_LOCAL_PATH`, `GENERATE_WORK_PATH`,
  `GENERATE_OUTPUT_PATH`, ...) one level too deep, into
  `clients\log`/`clients\download`/etc. instead of the real project root.
  Fixed with the standard batch idiom for resolving a relative `..` to a
  clean absolute path: `for %%I in ("%~dp0..") do set "BASE_PATH=%%~fI\"`
  (`%%~fI` fully-qualifies/normalizes whatever token `for` hands it — this
  works even though `%~dp0..` isn't a file, `for %%I in (...)` treats its
  argument as a literal string to transform, not a file-existence check).
  Verified empirically (see `clients/README.md` for the user-facing
  version of this warning) — don't simplify this back to `%~dp0` if
  `set-env.bat` ever moves again without re-deriving this.

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

**Device-code sign-in and the GUI can deadlock/hang if you read child-process
stdout and stderr sequentially.** `az login --use-device-code`'s own "open the
page ... and enter the code ..." prompt goes to *stderr*, not stdout. Two
places in this codebase read a child process's output and both must merge
stderr into stdout (via a `cmd.exe /c "... 2>&1"` wrapper) rather than reading
the two streams with separate loops — reading stdout to completion before
ever touching stderr means a message on stderr (like the sign-in prompt)
never surfaces while the child is still blocked waiting on it, which reads as
a frozen GUI showing only "サインインが必要です..." with no code:
- `scripts/gui.ps1`'s `$btnRun.Add_Click` (launches `all.bat`) — `$psi.FileName`
  is `cmd.exe` with `Arguments = "/c ""` + a quoted path + `" 2>&1"""` (the
  doubled outer quotes are required cmd.exe syntax when the command being
  redirected is itself a quoted, space-containing path), and only
  `StandardOutput` is read/redirected — no separate `StandardError` loop.
- `Get-GraphToken` in `scripts/common.ps1` — rather than piping `az login`'s
  output to `Out-Null` and hoping the device-code prompt appears somewhere on
  its own, it launches `az login` the same `cmd.exe /c "... 2>&1"` way,
  reads the merged stream line-by-line, and regex-matches
  `open the page (?<url>\S+)\s+and enter the code (?<code>[A-Z0-9\-]+)`
  (the stable MSAL/Azure CLI device-flow message wording) to print a
  clean `URL: ...` / `コード：...` pair instead of relying on whatever raw
  text Azure CLI happens to emit. Verified the regex against the real MSAL
  message text and the cmd.exe merge mechanics against a synthetic
  space-containing-path batch file; could not verify the live network round
  trip in this sandbox (its `az login` processes hung indefinitely with no
  response, apparently no route to Azure AD's device-code endpoint here) —
  confirmed working against a real signed-out Azure CLI on the user's actual
  machine instead.

**Merging stderr into stdout fixes the missing-message problem but not by
itself a frozen/uncopyable GUI.** Once the sign-in URL/code actually appeared
in `gui.ps1`'s log textbox, the user could still not select or copy it — the
window looked frozen. Root cause: `$btnRun.Add_Click` read output via
`while (!$proc.StandardOutput.EndOfStream) { Write-Log $proc.StandardOutput.ReadLine(); ... DoEvents() }`
— `ReadLine()` blocks until the *next* line arrives, and while the user is
off in a browser completing device-code sign-in, no next line arrives for a
long time, so `DoEvents()` simply never gets called and the WinForms message
pump stalls (already-rendered text becomes unselectable, the whole window
stops responding) even though the text was written before the block. Fixed
by switching to `Process.OutputDataReceived` (`$proc.BeginOutputReadLine()`)
feeding a `[System.Collections.Concurrent.ConcurrentQueue[string]]` via
`Register-ObjectEvent -Action {...} -MessageData $outputQueue` (the `-Action`
scriptblock runs off-thread when the event fires; the queue is the safe way
to hand data back without needing `Invoke()`), with the main loop merely
polling `TryDequeue` + `DoEvents()` + a short `Start-Sleep` — never calling a
blocking read itself. Verified via a synthetic batch file that pauses for
several seconds mid-run: the polling loop kept iterating (~50ms cadence)
throughout the pause instead of stalling. One more gotcha found through that
same test: `$proc.HasExited` can flip `true` slightly before the *last*
`OutputDataReceived` event for a just-exited process has been delivered, so
exiting the loop on `HasExited` alone drops the final line — fixed by calling
`$proc.WaitForExit()` (which per its documented contract also waits out any
in-flight redirected-stream events) followed by one more queue drain before
unregistering the event.

## No test/lint suite

There is nothing to run beyond manually invoking the `.bat` files. When
verifying changes to the PowerShell logic, prefer running the real script
(with a real Azure CLI sign-in) over guessing — this tool has previously shipped
subtle path-handling bugs (e.g. relative-path `Substring` truncation) that only
showed up against real data.
