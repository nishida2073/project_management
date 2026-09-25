
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

[System.Windows.Forms.Application]::EnableVisualStyles()
[System.Windows.Forms.Application]::SetCompatibleTextRenderingDefault($false)

if ($MyInvocation.MyCommand.Path) {
    $scriptDir = Split-Path $MyInvocation.MyCommand.Path
    $rootPath = Split-Path $scriptDir -Parent
} else {
    $rootPath = Split-Path ([System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName)
}
$basePath = Join-Path $rootPath "bats"

$libraryDir = Join-Path $basePath "library"
Get-ChildItem -Path $libraryDir -Filter *.ps1 -Recurse | ForEach-Object {
    . $_.FullName
}

$env:GUI_LOG_MODE = "1"

$script:commonEnvVars = Get-BatEnvVars -BatPath (Join-Path $basePath "common-env.bat")
$script:suppressComboSync = $false

$clientsDir = Join-Path $rootPath "clients"

function Get-GroupNames {
    if (!(Test-Path -LiteralPath $clientsDir)) { return @() }
    $names = Get-ChildItem -LiteralPath $clientsDir -Filter "*.xlsx" -File -ErrorAction SilentlyContinue | ForEach-Object {
        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($_.Name)
        if ($baseName -match '^(?<group>.+)-\d{4}$') { $Matches['group'] } else { $baseName }
    }
    return @($names | Select-Object -Unique | Sort-Object)
}

$groupOptions = @([PSCustomObject]@{ Text = "すべて"; Value = "" })
foreach ($groupName in (Get-GroupNames)) {
    $groupOptions += [PSCustomObject]@{ Text = $groupName; Value = $groupName }
}
function New-TargetGroupInput {
    param([bool]$NewRow = $false)
    [PSCustomObject]@{ Name = "TargetGroupNameFilter"; Label = "対象グループ"; Default = ""; LabelWidth = 75; InputWidth = 150; Options = $groupOptions; NewRow = $NewRow }
}

$categoryDefs = @(
    [PSCustomObject]@{
        Label = "実施データ取得"
        ButtonDefs = @(
            [PSCustomObject]@{ Label = "テスト・アンケート"; BatchLabel = "実施データ取得-テスト・アンケート"; IncludeInBatch = $true; BatchPath = (Join-Path $basePath "download-results.bat"); OpenTarget = $script:commonEnvVars["ClientDataRootDir"]; Inputs = @((New-TargetGroupInput)) }
            [PSCustomObject]@{ Label = "取得状況確認"; BatchLabel = "実施データ取得-取得状況確認"; IncludeInBatch = $false; BatchPath = (Join-Path $basePath "check-download-status.bat"); OpenTarget = $script:commonEnvVars["ResultRootDir"]; Inputs = @((New-TargetGroupInput)) }
        )
    }
    [PSCustomObject]@{
        Label = "実施状況確認"
        ButtonDefs = @(
            [PSCustomObject]@{ Label = "テスト・アンケート"; BatchLabel = "実施状況確認-テスト・アンケート"; IncludeInBatch = $true; BatchPath = (Join-Path $basePath "collect-combine-result.bat"); OpenTarget = $script:commonEnvVars["OutputCombineCollectDir"]; Inputs = @((New-TargetGroupInput)) }
        )
    }
    [PSCustomObject]@{
        Label = "実施結果確認"
        ButtonDefs = @(
            [PSCustomObject]@{ Label = "テスト"; BatchLabel = "実施結果確認-テスト"; IncludeInBatch = $true; BatchPath = (Join-Path $basePath "collect-test-result.bat"); OpenTarget = $script:commonEnvVars["OutputTestCollectDir"]; Inputs = @((New-TargetGroupInput)) }
            [PSCustomObject]@{ Label = "アンケート"; BatchLabel = "実施結果確認-アンケート"; IncludeInBatch = $true; BatchPath = (Join-Path $basePath "collect-survey-result.bat"); OpenTarget = $script:commonEnvVars["OutputSurveyCollectDir"]; Inputs = @((New-TargetGroupInput)) }
            [PSCustomObject]@{ Label = "投稿"; BatchLabel = "実施結果確認-投稿"; IncludeInBatch = $true; DefaultChecked = $false; BatchPath = (Join-Path $basePath "post-collect-results.bat"); OpenTarget = { param($groupName) Get-GroupKintoneThreadUrl -GroupName $groupName }; Inputs = @((New-TargetGroupInput)) }
        )
    }
    [PSCustomObject]@{
        Label = "経年比較"
        ButtonDefs = @(
            [PSCustomObject]@{
                Label = "アンケート・テスト"
                BatchLabel = "経年比較-アンケート・テスト"
                IncludeInBatch = $true
                DefaultChecked = $false
                BatchPath = (Join-Path $basePath "collect-year-comparison-result.bat")
                OpenTarget = $script:commonEnvVars["OutputYearComparisonCollectDir"]
                Inputs = @(
                    (New-TargetGroupInput)
                    [PSCustomObject]@{ Name = "TargetCompanyNames"; Label = "対象の会社名"; Default = $script:commonEnvVars["TargetCompanyNames"]; LabelWidth = 85; InputWidth = 260; NewRow = $true }
                    [PSCustomObject]@{ Name = "ComparePeriod"; Label = "比較年"; Default = $script:commonEnvVars["ComparePeriod"]; LabelWidth = 50; InputWidth = 40 }
                    [PSCustomObject]@{
                        Name = "YearOrder"; Label = "表示順"; Default = $script:commonEnvVars["YearOrder"]; LabelWidth = 55; InputWidth = 70
                        Options = @(
                            [PSCustomObject]@{ Text = "昇順"; Value = "0" }
                            [PSCustomObject]@{ Text = "降順"; Value = "1" }
                        )
                    }
                )
            }
        )
    }
)

$form = New-Object System.Windows.Forms.Form
$form.Text = "trackデータ集計ツール"
$form.Size = New-Object System.Drawing.Size(780, 560)
$form.StartPosition = "CenterScreen"
$form.MinimumSize = New-Object System.Drawing.Size(600, 400)

$script:currentProc = $null
$form.Add_FormClosing({
    if ($script:currentProc -and !$script:currentProc.HasExited) {
        & taskkill.exe /T /F /PID $script:currentProc.Id 2>&1 | Out-Null
    }
})


$tabControl = New-Object System.Windows.Forms.TabControl
$tabControl.Dock = [System.Windows.Forms.DockStyle]::Fill

$tabRun = New-Object System.Windows.Forms.TabPage
$tabRun.Text = "実行"

$tabLogs = New-Object System.Windows.Forms.TabPage
$tabLogs.Text = "ログ"

$tabSettings = New-Object System.Windows.Forms.TabPage
$tabSettings.Text = "設定"

$tabControl.Controls.AddRange(@($tabRun, $tabLogs, $tabSettings))
$form.Controls.Add($tabControl)


$execTabControl = New-Object System.Windows.Forms.TabControl

$allButtonDefs = @()
foreach ($cd in $categoryDefs) {
    foreach ($bd in $cd.ButtonDefs) {
        if ($bd.IncludeInBatch -ne $false) { $allButtonDefs += $bd }
    }
}

$tabBatchAll = New-Object System.Windows.Forms.TabPage
$tabBatchAll.Text = "一括実行"
$execTabControl.Controls.Add($tabBatchAll)

$batchTab = New-BatchRunTab -TabPage $tabBatchAll -ButtonDefs $allButtonDefs `
    -Inputs @(
        [PSCustomObject]@{ Name = "TargetGroupNameFilter"; Label = "対象グループ"; Options = $groupOptions; LabelWidth = 90; InputWidth = 150 }
    ) `
    -OnOpenClick {
        param($bd, $inputControls)
        $target = $bd.OpenTarget
        if ($target -is [scriptblock]) {
            $groupValue = Get-InputValue -Control $inputControls["TargetGroupNameFilter"]
            $target = & $target $groupValue
        }
        Open-TargetOrWarn -Path $target
    }

$batchPanel = $batchTab.Panel
$cmbBatchGroup = $batchTab.InputControls["TargetGroupNameFilter"]
$script:batchStepCheckboxes = $batchTab.CheckBoxes
$btnRunAll = $batchTab.RunButton
$lblBatchStatus = $batchTab.StatusLabel
$script:batchRunButtons = @($btnRunAll)

function Start-BatchRunAll {
    Invoke-BatchRunAll -ButtonDefs $allButtonDefs -CheckBoxes $script:batchStepCheckboxes `
        -StatusLabel $lblBatchStatus `
        -WriteLog { param($msg) Write-Log $msg } -SetRunButtonsEnabled { param($e) Set-RunButtonsEnabled $e } `
        -InvokeStep {
            param($bd)
            Invoke-BatchStep -ButtonDef $bd -WorkingDirectory $basePath -Form $form `
                -WriteLog { param($msg) Write-Log $msg } -CurrentProcessRef ([ref]$script:currentProc) `
                -GetBatArgs {
                    param($bd)
                    $batArgs = @()
                    foreach ($inputDef in $bd.Inputs) {
                        $value = if ($inputDef.Name -eq "TargetGroupNameFilter") { Get-InputValue -Control $cmbBatchGroup } else { $inputDef.Default }
                        $batArgs += "$($inputDef.Name):$value"
                    }
                    return $batArgs
                }
        }
}

$btnRunAll.Add_Click({ Start-BatchRunAll })


$tabResult = New-CategoryTabControl -TabControl $execTabControl -CategoryDefs $categoryDefs -OnRunClick {
    param($bd)
    Invoke-BatButton -ButtonDef $bd -WorkingDirectory $basePath -Form $form `
        -WriteLog { param($msg) Write-Log $msg } -SetRunButtonsEnabled { param($e) Set-RunButtonsEnabled $e } `
        -CurrentProcessRef ([ref]$script:currentProc) `
        -GetBatArgs {
            param($bd)
            $batArgs = @()
            $inputMap = $bd.InputControls
            if ($inputMap) {
                foreach ($inputName in $inputMap.Keys) {
                    $batArgs += "$($inputName):$(Get-InputValue -Control $inputMap[$inputName])"
                }
            }
            return $batArgs
        }
}
$script:runButtons = $tabResult.RunButtons

$execTabControl.Height = 45 + $batchPanel.Height


$txtLog = New-LogTextBox

Add-StackedDockedControls -Container $tabRun -ControlsTopToBottom @($execTabControl, $txtLog)

function Set-RunButtonsEnabled {
    param([bool]$Enabled)
    Set-ButtonsEnabled -Buttons $script:runButtons -Enabled $Enabled
    Set-ButtonsEnabled -Buttons $script:batchRunButtons -Enabled $Enabled
}


$allButtonDefsForLog = @($categoryDefs | ForEach-Object { $_.ButtonDefs })

$script:logTab = New-LogTab -TabPage $tabLogs -ButtonDefs $allButtonDefsForLog `
    -LabelFn { param($bd) Get-BatchDisplayLabel -ButtonDef $bd } `
    -ExtraLabelText "対象グループ" -ExtraComboWidth 150 `
    -GetLogPathFn { $script:commonEnvVars["LOG_DIR"] } `
    -OnUpdateLogView { Update-LogView }
$cmbLogGroup = $script:logTab.ExtraCombo
$cmbLogGroup.DisplayMember = "Text"
foreach ($opt in $groupOptions) { $cmbLogGroup.Items.Add($opt) | Out-Null }
if ($cmbLogGroup.Items.Count -gt 0) { $cmbLogGroup.SelectedIndex = 0 }

foreach ($radio in $script:logTab.Radios) {
    $radio.Add_CheckedChanged({ if ($this.Checked) { Update-LogView } })
}
$cmbLogGroup.Add_SelectedIndexChanged({ Update-LogView })

Update-LogView


$clientsDir = Join-Path $rootPath "clients"
$clientsTemplateDir = Join-Path $clientsDir "template"

function Get-GroupXlsxPath { param([string]$GroupName, [string]$Year) Join-Path $clientsDir "$GroupName-$Year.xlsx" }

function Get-GroupXlsxFiles {
    param([string]$GroupName)
    if (!(Test-Path -LiteralPath $clientsDir)) { return @() }
    $escaped = [regex]::Escape($GroupName)
    return @(Get-ChildItem -LiteralPath $clientsDir -Filter "*.xlsx" -File -ErrorAction SilentlyContinue | Where-Object {
        $_.BaseName -eq $GroupName -or $_.BaseName -match "^${escaped}-\d{4}$"
    })
}

function Get-TemplateXlsxPath {
    $found = Get-ChildItem -LiteralPath $clientsTemplateDir -Filter "client*.xlsx" -File -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($found) { return $found.FullName }
    return $null
}

$script:commonEnvResolver = { param($name) $script:commonEnvVars[$name] }

$overridableVarDefs = [ordered]@{
    "ComparePeriod" = @{ Label = "経年比較の比較年数" }
    "YearOrder"     = @{
        Label = "経年比較の年度表示順（0:昇順 1:降順）"
        Radio = @(
            [PSCustomObject]@{ Value = "0"; Label = "昇順(0)" }
            [PSCustomObject]@{ Value = "1"; Label = "降順(1)" }
        )
    }
    "PassScore"     = @{ Label = "合格点" }
}

$settingsGroups = [ordered]@{
    "COMMON" = @{
        Label = "共通設定"
        Vars = [ordered]@{
            "ClientDataRootDir"                    = @{ Label = "受講生データのフォルダ"; Browse = "Folder" }
            "TemplateRootDir"                      = @{ Label = "テンプレートのフォルダ"; Browse = "Folder" }
            "LOG_DIR"                               = @{ Label = "ログの出力先"; Browse = "Folder" }
            "ResultRootDir"                         = @{ Label = "実施結果の取得先（共通）"; Browse = "Folder" }
            "TestResultRootDir"                     = @{ Label = "テスト結果の取得先"; Browse = "Folder" }
            "SurveyResultRootDir"                   = @{ Label = "アンケート結果の取得先"; Browse = "Folder" }
            "OutputRootDir"                         = @{ Label = "集計結果の出力先（共通）"; Browse = "Folder" }
            "OutputTestCollectDir"                  = @{ Label = "テスト集計結果の出力先"; Browse = "Folder" }
            "OutputTestResultFileSuffix"            = @{ Label = "テスト結果ファイル名の接尾辞" }
            "OutputSurveyCollectDir"                = @{ Label = "アンケート集計結果の出力先"; Browse = "Folder" }
            "OutputSurveyResultFileSuffix"          = @{ Label = "アンケート結果ファイル名の接尾辞" }
            "OutputCombineCollectDir"               = @{ Label = "統合結果の出力先"; Browse = "Folder" }
            "OutputCombineResultFileSuffix"         = @{ Label = "統合結果ファイル名の接尾辞" }
            "OutputYearComparisonCollectDir"        = @{ Label = "経年比較結果の出力先"; Browse = "Folder" }
            "OutputYearComparisonResultFileSuffix"  = @{ Label = "経年比較結果ファイル名の接尾辞" }
            "PassScore"                             = $overridableVarDefs["PassScore"]
            "AutoHotkeyExePath"                     = @{ Label = "AutoHotkey実行ファイルのパス" }
            "AutoHotkeyScriptPath"                  = @{ Label = "ダウンロード用スクリプトのパス" }
            "TrackLoginUrl"                         = @{ Label = "trackログインURL" }
            "ComparePeriod"                         = $overridableVarDefs["ComparePeriod"]
            "CourseGroupDefs"                       = @{ Label = "コースグループ定義" }
            "YearOrder"                             = $overridableVarDefs["YearOrder"]
        }
    }
    "AUTH" = @{
        Label = "認証情報"
        Vars = [ordered]@{
            "KintoneLoginName" = @{ Label = "ログイン名" }
            "KintonePassword"  = @{ Label = "パスワード"; Masked = $true }
            "KintoneSubdomain" = @{ Label = "kintoneサブドメイン" }
        }
    }
    "POST" = @{
        Label = "投稿先"
        Vars = [ordered]@{
            "SpaceId"             = @{ Label = "投稿先スペースID" }
            "ThreadId"            = @{ Label = "投稿先スレッドID" }
            "MentionUserCodes"    = @{ Label = "メンション対象" }
            "CommentTextTemplate" = @{ Label = "投稿コメント文言"; Multiline = $true }
        }
    }
    "OVERRIDE" = @{
        Label = "個別設定（空欄の場合は共通設定の値を使用）"
        Vars = $overridableVarDefs
    }
    "SYNC" = @{
        Label = "ユーザーマスター同期"
        Vars = [ordered]@{
            "SyncUserMasterAppId"   = @{ Label = "対象アプリID" }
            "SyncUserMasterSheetName" = @{ Label = "対象シート名" }
        }
    }
}

$commonSettingsVars = @($settingsGroups["COMMON"].Vars.Keys)
$authVars = @($settingsGroups["AUTH"].Vars.Keys)
$postVars = @($settingsGroups["POST"].Vars.Keys)
$groupOverrideVars = @($settingsGroups["OVERRIDE"].Vars.Keys)
$syncUserMasterVars = @($settingsGroups["SYNC"].Vars.Keys)

$settingsTrailingButtonVars = @{
    "SyncUserMasterSheetName" = { param($Panel, $Y, $Field)
        Add-FieldActionButton -Panel $Panel -Y $Y -Text "同期実行" -AddStatusLabel -OnClick {
            $groupName = $cmbSettingsGroupTarget.SelectedItem
            if ([string]::IsNullOrWhiteSpace($groupName)) {
                [System.Windows.Forms.MessageBox]::Show("グループを選択してください。", "エラー", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
                return
            }
            $batchPath = Join-Path $basePath "sync-kintone-to-sheet.bat"
            if (-not (Test-Path $batchPath)) {
                [System.Windows.Forms.MessageBox]::Show("バッチファイルが見つかりません: $batchPath", "エラー", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
                return
            }
            Set-StepStatus -Label $Field.StatusLabel -Text "実行中..." -State "実行中..."
            [System.Windows.Forms.Application]::DoEvents()

            try {
                $syncAppId = Get-GroupSettingsFieldValue "SYNC_SyncUserMasterAppId"
                $syncSheetName = Get-GroupSettingsFieldValue "SYNC_SyncUserMasterSheetName"
                $batArgs = @("-TargetGroupNameFilter:$groupName", "-SyncUserMasterAppId:$syncAppId", "-SyncUserMasterSheetName:$syncSheetName")
                $exitCode = Invoke-BatProcess -BatPath $batchPath -WorkingDirectory $basePath -BatArgs $batArgs
                if ($exitCode -eq 0) {
                    Set-StepStatus -Label $Field.StatusLabel -Text "成功" -State "成功"
                    [System.Windows.Forms.MessageBox]::Show("同期が完了しました。", "完了", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information)
                } else {
                    Set-StepStatus -Label $Field.StatusLabel -Text "失敗" -State "失敗"
                    [System.Windows.Forms.MessageBox]::Show("同期に失敗しました。ログを確認してください。", "エラー", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
                }
            } catch {
                Set-StepStatus -Label $Field.StatusLabel -Text "失敗" -State "失敗"
                [System.Windows.Forms.MessageBox]::Show("同期処理エラー: $($_.Exception.Message)", "エラー", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
            }
        }.GetNewClosure()
    }
}

$settingsGroupLabels = @{}
$settingsVarLabels = @{}
$settingsFolderBrowseVars = @()
$settingsFileBrowseVars = @()
$settingsMaskedVars = @()
$settingsMultilineVars = @()
$radioVars = @{}
foreach ($groupKey in $settingsGroups.Keys) {
    $settingsGroupLabels[$groupKey] = $settingsGroups[$groupKey].Label
    foreach ($varKey in $settingsGroups[$groupKey].Vars.Keys) {
        $varDef = $settingsGroups[$groupKey].Vars[$varKey]
        $settingsVarLabels[$varKey] = $varDef.Label
        if ($varDef.Browse -eq "Folder") { $settingsFolderBrowseVars += $varKey }
        if ($varDef.Browse -eq "File") { $settingsFileBrowseVars += $varKey }
        if ($varDef.Masked) { $settingsMaskedVars += $varKey }
        if ($varDef.Multiline) { $settingsMultilineVars += $varKey }
        if ($varDef.Radio) { $radioVars[$varKey] = $varDef.Radio }
    }
}

$script:groupTemplateDefaults = $null
function Get-GroupTemplateDefaults {
    if ($null -eq $script:groupTemplateDefaults) {
        $script:groupTemplateDefaults = [PSCustomObject]@{
            Auth = Get-SetLineRawValues -Path (Join-Path $clientsTemplateDir "client.bat")
        }
    }
    return $script:groupTemplateDefaults
}

$settingsSubTabControl = New-Object System.Windows.Forms.TabControl
$settingsSubTabControl.Dock = [System.Windows.Forms.DockStyle]::Fill
$tabSettings.Controls.Add($settingsSubTabControl)

$tabSettingsCommon = New-Object System.Windows.Forms.TabPage
$tabSettingsCommon.Text = "共通"
$settingsSubTabControl.Controls.Add($tabSettingsCommon)

$tabSettingsGroup = New-Object System.Windows.Forms.TabPage
$tabSettingsGroup.Text = "グループ別"
$settingsSubTabControl.Controls.Add($tabSettingsGroup)

$settingsToolTip = New-Object System.Windows.Forms.ToolTip

function Get-CommonSettingsFiles {
    return @(
        [PSCustomObject]@{ Path = (Join-Path $basePath "common-env.bat"); Save = { Save-CommonSettings }; Reload = {} }
    )
}

$settingsCommonTopPanelResult = New-SettingsTopPanel `
    -OnSave { foreach ($f in (Get-CommonSettingsFiles)) { & $f.Save }; Update-CommonSettingsFields } `
    -OnReload { foreach ($f in (Get-CommonSettingsFiles)) { & $f.Reload }; Update-CommonSettingsFields }
$settingsCommonTopPanel = $settingsCommonTopPanelResult.Panel

$settingsCommonFieldPanel = New-Object System.Windows.Forms.Panel
$settingsCommonFieldPanel.Dock = [System.Windows.Forms.DockStyle]::Fill
$settingsCommonFieldPanel.AutoScroll = $true

$tabSettingsCommon.Controls.Add($settingsCommonFieldPanel)
$tabSettingsCommon.Controls.Add($settingsCommonTopPanel)

$lblSettingsGroupTarget = New-Object System.Windows.Forms.Label
$lblSettingsGroupTarget.Text = "対象グループ"

$cmbSettingsGroupTarget = New-Object System.Windows.Forms.ComboBox
$cmbSettingsGroupTarget.Size = New-Object System.Drawing.Size(260, 24)
$cmbSettingsGroupTarget.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList

$btnSettingsGroupNewGroup = New-Object System.Windows.Forms.Button
$btnSettingsGroupNewGroup.Text = "新規作成"
$btnSettingsGroupNewGroup.Size = New-Object System.Drawing.Size(140, 24)

$lnkSettingsGroupOpenXlsx = New-Object System.Windows.Forms.LinkLabel
$lnkSettingsGroupOpenXlsx.Text = "開く"

function Get-GroupSettingsFiles {
    param([string]$GroupName)
    return @(
        [PSCustomObject]@{ Path = (Get-GroupBatPath $GroupName); Save = { Save-GroupSettings -GroupName $GroupName }.GetNewClosure(); Reload = {} }
    )
}

$settingsGroupTopPanelResult = New-SettingsTopPanel `
    -ExtraControls @($lblSettingsGroupTarget, $cmbSettingsGroupTarget, $btnSettingsGroupNewGroup, $lnkSettingsGroupOpenXlsx) `
    -OnSave {
        $target = $cmbSettingsGroupTarget.SelectedItem
        if (!$target) { return }
        foreach ($f in (Get-GroupSettingsFiles -GroupName $target)) { & $f.Save }
        Update-SettingsGroupList
        Update-GroupSettingsFields
    } `
    -OnReload {
        $target = $cmbSettingsGroupTarget.SelectedItem
        foreach ($f in (Get-GroupSettingsFiles -GroupName $target)) { & $f.Reload }
        Update-GroupSettingsFields
    }
$settingsGroupTopPanel = $settingsGroupTopPanelResult.Panel

$settingsGroupFieldPanel = New-Object System.Windows.Forms.Panel
$settingsGroupFieldPanel.Dock = [System.Windows.Forms.DockStyle]::Fill
$settingsGroupFieldPanel.AutoScroll = $true

$tabSettingsGroup.Controls.Add($settingsGroupFieldPanel)
$tabSettingsGroup.Controls.Add($settingsGroupTopPanel)

function Get-GroupNames {
    if (!(Test-Path -LiteralPath $clientsDir)) { return @() }
    $names = Get-ChildItem -LiteralPath $clientsDir -Filter "*.xlsx" -File -ErrorAction SilentlyContinue | ForEach-Object {
        $baseName = [System.IO.Path]::GetFileNameWithoutExtension($_.Name)
        if ($baseName -match '^(?<group>.+)-\d{4}$') { $Matches['group'] } else { $baseName }
    }
    return @($names | Select-Object -Unique | Sort-Object)
}

function Get-CommonSettingsFieldRows {
    $raw = Get-SetLineRawValues -Path (Join-Path $basePath "common-env.bat")
    foreach ($varName in $commonSettingsVars) {
        [PSCustomObject]@{ Key = $varName; VarName = $varName; Group = "COMMON"; Value = $raw[$varName] }
    }
}

function Get-GroupSettingsFieldRows {
    param([string]$GroupName)
    if (!$GroupName) { return }

    $templateDefaults = Get-GroupTemplateDefaults
    $rawAuth = Get-SetLineRawValues -Path (Get-GroupBatPath $GroupName)
    foreach ($varName in $authVars) {
        $value = if ($rawAuth.ContainsKey($varName)) { $rawAuth[$varName] } else { $templateDefaults.Auth[$varName] }
        [PSCustomObject]@{ Key = "AUTH_$varName"; VarName = $varName; Group = "AUTH"; Value = $value }
    }
    foreach ($varName in $postVars) {
        $value = if ($rawAuth.ContainsKey($varName)) { $rawAuth[$varName] } else { $templateDefaults.Auth[$varName] }
        [PSCustomObject]@{ Key = "POST_$varName"; VarName = $varName; Group = "POST"; Value = $value }
    }
    foreach ($varName in $groupOverrideVars) {
        $value = if ($rawAuth.ContainsKey($varName)) { $rawAuth[$varName] } else { "" }
        [PSCustomObject]@{ Key = "OVERRIDE_$varName"; VarName = $varName; Group = "OVERRIDE"; Value = $value }
    }
    foreach ($varName in $syncUserMasterVars) {
        $value = if ($rawAuth.ContainsKey($varName)) { $rawAuth[$varName] } else { $templateDefaults.Sync[$varName] }
        [PSCustomObject]@{ Key = "SYNC_$varName"; VarName = $varName; Group = "SYNC"; Value = $value }
    }
}

$script:settingsCommonFieldTextBoxes = @{}
$script:settingsGroupFieldTextBoxes = @{}

$mentionTypeOptions = @("USER", "GROUP", "ORGANIZATION")
$script:mentionRows = @()
$script:mentionRowsGroupName = $null
$script:mentionRowControls = @()


function Update-CommonSettingsFields {
    Render-SettingsFields -Panel $settingsCommonFieldPanel -Rows (Get-CommonSettingsFieldRows) -TextBoxes $script:settingsCommonFieldTextBoxes -RadioVars $radioVars `
        -GroupLabels $settingsGroupLabels -VarLabels $settingsVarLabels -ToolTip $settingsToolTip -RootPath $rootPath -EnvResolver $script:commonEnvResolver `
        -MultilineVars $settingsMultilineVars -MaskedVars $settingsMaskedVars -FolderBrowseVars $settingsFolderBrowseVars -FileBrowseVars $settingsFileBrowseVars | Out-Null
}

function Test-KintoneConnection {
    param([string]$ReportGroup, [string]$FieldName, [switch]$ThrowOnError)
    $kintoneSubdomain = Get-GroupSettingsFieldValue "AUTH_KintoneSubdomain"
    $kintoneLoginName = Get-GroupSettingsFieldValue "AUTH_KintoneLoginName"
    $kintonePassword = Get-GroupSettingsFieldValue "AUTH_KintonePassword"
    $targetAppIdsValue = Get-GroupSettingsFieldValue $FieldName
    $targetAppIds = @($targetAppIdsValue -split '[,\s]+' | Where-Object { $_ })
    $validationError = if ($targetAppIds.Count -eq 0) { "同期対象のアプリIDが未入力です。" } else { $null }
    Invoke-TestAction -DialogTitle "テスト接続" -ValidationError $validationError -Action {
        $baseUrl = "https://$kintoneSubdomain.cybozu.com"
        $authorization = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("${kintoneLoginName}:${kintonePassword}"))
        $resultLines = @()
        $hasFailure = $false
        foreach ($targetAppId in $targetAppIds) {
            try {
                $fieldData = Get-CurrentAppFieldData -TargetAppId $targetAppId -BaseUrl $baseUrl -Authorization $authorization
                $fieldCodes = @($fieldData.PSObject.Properties.Name)
                $resultLines += "[成功] $targetAppId（フィールド数: $($fieldCodes.Count)）"
                $resultLines += "  $($fieldCodes -join ', ')"
            } catch {
                $hasFailure = $true
                $resultLines += "[失敗] $targetAppId： $($_.Exception.Message)"
            }
        }
        $resultText = $resultLines -join "`r`n"
        if ($hasFailure) { throw $resultText }
        return $resultText
    }.GetNewClosure() -FormatSuccessMessage { param($response) $response } -FormatFailureMessage { param($ErrorRecord) $ErrorRecord.Exception.Message } -ThrowOnError:$ThrowOnError
}

function Update-GroupSettingsFields {
    $scrollX = -$settingsGroupFieldPanel.AutoScrollPosition.X
    $scrollY = -$settingsGroupFieldPanel.AutoScrollPosition.Y

    $target = $cmbSettingsGroupTarget.SelectedItem
    $trailingButtons = $settingsTrailingButtonVars.Clone()
    $trailingButtons["CommentTextTemplate"] = { param($Panel, $Y, $Field) Add-FieldActionButton -Panel $Panel -Y $Y -Text "テスト投稿" -AddStatusLabel -OnClick {
        Sync-MentionRowsFromControls
        $spaceId = Get-GroupSettingsFieldValue "POST_SpaceId"
        $threadId = Get-GroupSettingsFieldValue "POST_ThreadId"
        $validationError = if ([string]::IsNullOrWhiteSpace($spaceId) -or [string]::IsNullOrWhiteSpace($threadId)) { "スペースIDとスレッドIDを入力してください。" } else { $null }

        Set-StepStatus -Label $Field.StatusLabel -Text "実行中..." -State "実行中..."
        [System.Windows.Forms.Application]::DoEvents()

        try {
            Invoke-TestAction -DialogTitle "テスト投稿" -ValidationError $validationError `
                -Action {
                    $kintoneSubdomain = Get-GroupSettingsFieldValue "AUTH_KintoneSubdomain"
                    $kintoneLoginName = Get-GroupSettingsFieldValue "AUTH_KintoneLoginName"
                    $kintonePassword = Get-GroupSettingsFieldValue "AUTH_KintonePassword"
                    $mentions = @($script:mentionRows | Where-Object { $_.Code } | ForEach-Object { @{ code = $_.Code; type = $_.Type } })
                    $baseUrl = "https://$kintoneSubdomain.cybozu.com"
                    $authorization = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("${kintoneLoginName}:${kintonePassword}"))
                    Add-KintoneThreadComment -SpaceId $spaceId -ThreadId $threadId -Text "【テスト投稿】track-aggregatorの設定確認用コメントです。不要であれば削除してください。" -Mentions $mentions -BaseUrl $baseUrl -Authorization $authorization
                }.GetNewClosure() `
                -FormatSuccessMessage { param($response) "投稿に成功しました（コメントID: $($response.id)）。`r`nスレッドを確認し、不要であれば削除してください。" } `
                -ThrowOnError
            Set-StepStatus -Label $Field.StatusLabel -Text "成功" -State "成功"
        } catch {
            Set-StepStatus -Label $Field.StatusLabel -Text "失敗" -State "失敗"
        }
    }.GetNewClosure() }
    $trailingButtons["SyncUserMasterAppId"] = { param($Panel, $Y, $Field) Add-FieldActionButton -Panel $Panel -Y $Y -Text "テスト接続" -AddStatusLabel -OnClick {
        Set-StepStatus -Label $Field.StatusLabel -Text "実行中..." -State "実行中..."
        [System.Windows.Forms.Application]::DoEvents()

        try {
            Test-KintoneConnection -ReportGroup "SYNC" -FieldName "SYNC_SyncUserMasterAppId" -ThrowOnError
            Set-StepStatus -Label $Field.StatusLabel -Text "成功" -State "成功"
        } catch {
            Set-StepStatus -Label $Field.StatusLabel -Text "失敗" -State "失敗"
        }
    }.GetNewClosure() }
    Render-SettingsFields -Panel $settingsGroupFieldPanel -Rows (Get-GroupSettingsFieldRows -GroupName $target) -TextBoxes $script:settingsGroupFieldTextBoxes -RadioVars $radioVars `
        -GroupLabels $settingsGroupLabels -VarLabels $settingsVarLabels -ToolTip $settingsToolTip -RootPath $rootPath -EnvResolver $script:commonEnvResolver `
        -MultilineVars $settingsMultilineVars -MaskedVars $settingsMaskedVars -FolderBrowseVars $settingsFolderBrowseVars -FileBrowseVars $settingsFileBrowseVars `
        -MentionGroupCombo $cmbSettingsGroupTarget -MentionTypeOptions $mentionTypeOptions `
        -TrailingButtonVars $trailingButtons | Out-Null

    $settingsGroupFieldPanel.AutoScrollPosition = New-Object System.Drawing.Point($scrollX, $scrollY)
}

function Save-CommonSettings {
    $path = Join-Path $basePath "common-env.bat"
    $newLines = foreach ($line in [System.IO.File]::ReadAllLines($path, $script:cp932Encoding)) {
        $m = $script:groupBatLineRegex.Match($line.Trim())
        if ($m.Success -and ($commonSettingsVars -contains $m.Groups["var"].Value)) {
            $varName = $m.Groups["var"].Value
            $val = Get-CommonSettingsFieldValue $varName
            "set `"$varName=$val`""
        } else {
            $line
        }
    }
    $content = ($newLines -join "`r`n") + "`r`n"
    [System.IO.File]::WriteAllText($path, $content, $script:cp932Encoding)
}

function Save-GroupSettings {
    param([string]$GroupName)

    $existingAuth = Get-SetLineRawValues -Path (Get-GroupBatPath $GroupName)
    $authorizationValue = if ($existingAuth.ContainsKey("Authorization")) { $existingAuth["Authorization"] } else { (Get-GroupTemplateDefaults).Auth["Authorization"] }

    $authLines = @("@echo off", "")
    foreach ($varName in $authVars) {
        $val = Get-GroupSettingsFieldValue "AUTH_$varName"
        $authLines += "set `"$varName=$val`""
    }
    $authLines += "set `"Authorization=$authorizationValue`""
    $authLines += "set `"BaseUrl=https://%KintoneSubdomain%.cybozu.com`""
    $authLines += ""

    Sync-MentionRowsFromControls
    foreach ($varName in $postVars) {
        $val = if ($varName -eq "MentionUserCodes") {
            ConvertTo-MentionUserCodesText -Rows $script:mentionRows
        } else {
            Get-GroupSettingsFieldValue "POST_$varName"
        }
        if ($settingsMultilineVars -contains $varName) { $val = $val -replace "`r`n", '\n' -replace "`n", '\n' }
        $authLines += "set `"$varName=$val`""
    }
    $authLines += ""

    foreach ($varName in $groupOverrideVars) {
        $val = Get-GroupSettingsFieldValue "OVERRIDE_$varName"
        if ($val -ne "") { $authLines += "set `"$varName=$val`"" }
    }
    $authLines += ""
    foreach ($varName in $syncUserMasterVars) {
        $val = Get-GroupSettingsFieldValue "SYNC_$varName"
        $authLines += "set `"$varName=$val`""
    }
    $authLines += ""
    [System.IO.File]::WriteAllText((Get-GroupBatPath $GroupName), (($authLines -join "`r`n") + "`r`n"), $script:cp932Encoding)

    if ((Get-GroupXlsxFiles -GroupName $GroupName).Count -eq 0) {
        $currentYear = $script:commonEnvVars["TargetYear"]
        $templateXlsxPath = Get-TemplateXlsxPath
        if ($currentYear -and $templateXlsxPath) {
            Copy-Item -LiteralPath $templateXlsxPath -Destination (Get-GroupXlsxPath $GroupName $currentYear)
        }
    }
}

$btnSettingsGroupNewGroup.Add_Click({
    Add-Type -AssemblyName Microsoft.VisualBasic
    $newName = [Microsoft.VisualBasic.Interaction]::InputBox("グループ名を入力してください", "グループの新規作成", "")
    $newName = $newName.Trim()
    if (!$newName) { return }

    if ($cmbSettingsGroupTarget.Items.Contains($newName) -or (Get-GroupXlsxFiles -GroupName $newName).Count -gt 0 -or (Test-Path -LiteralPath (Get-GroupBatPath $newName))) {
        [System.Windows.Forms.MessageBox]::Show("「$newName」は既に存在します。", "グループの新規作成", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        return
    }

    $cmbSettingsGroupTarget.Items.Add($newName) | Out-Null
    $cmbSettingsGroupTarget.SelectedItem = $newName
})

$lnkSettingsGroupOpenXlsx.Add_LinkClicked({
    $target = $cmbSettingsGroupTarget.SelectedItem
    if (!$target) {
        [System.Windows.Forms.MessageBox]::Show("対象グループが選択されていません。", "受講生データを開く", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        return
    }
    $currentYear = $script:commonEnvVars["TargetYear"]
    $openPath = $null
    if ($currentYear) {
        $currentYearPath = Get-GroupXlsxPath $target $currentYear
        if (Test-Path -LiteralPath $currentYearPath) { $openPath = $currentYearPath }
    }
    if (!$openPath) {
        $latest = Get-GroupXlsxFiles -GroupName $target | Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($latest) { $openPath = $latest.FullName }
    }
    if (!$openPath) { $openPath = Get-GroupXlsxPath $target $currentYear }
    Open-TargetOrWarn -Path $openPath
})

$cmbSettingsGroupTarget.Add_SelectedIndexChanged({
    if (!$script:suppressComboSync) { Update-GroupSettingsFields }
})

$tabControl.Add_SelectedIndexChanged({
    if ($tabControl.SelectedTab -eq $tabSettings) {
        Update-SettingsGroupList
    } elseif ($tabControl.SelectedTab -eq $tabLogs) {
        Update-LogView
    }
})

Update-SettingsGroupList
Update-CommonSettingsFields
Update-GroupSettingsFields

$execTabControl.SelectedTab = $tabBatchAll
$tabControl.SelectedTab = $tabRun

$form.Add_Shown({
    Update-CommonSettingsFields
    Update-GroupSettingsFields
})

[System.Windows.Forms.Application]::Run($form)
