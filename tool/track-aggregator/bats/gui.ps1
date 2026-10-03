trap {
    Write-Host "エラー: $_"
    Write-Host $_.ScriptStackTrace
    Write-Host $_.Exception
}

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

$clientsDir = Join-Path $rootPath "clients"

function Get-GroupNames {
    if (!(Test-Path -LiteralPath $clientsDir)) { return @() }
    $names = Get-ChildItem -LiteralPath $clientsDir -Filter "*.xlsx" -File -ErrorAction SilentlyContinue | ForEach-Object {
        [System.IO.Path]::GetFileNameWithoutExtension($_.Name)
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
            [PSCustomObject]@{ Label = "投稿"; BatchLabel = "実施結果確認-投稿"; IncludeInBatch = $true; DefaultChecked = $false; BatchPath = (Join-Path $basePath "post-collect-results.bat"); OpenTarget = { param($ic) if ($ic -and $ic.ContainsKey("TargetGroupNameFilter")) { $groupValue = Get-InputValue -Control $ic["TargetGroupNameFilter"] } else { $groupValue = "" }; Get-GroupKintoneThreadUrl -GroupName $groupValue }; Inputs = @((New-TargetGroupInput)) }
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

New-BatchRunTab -TabPage $tabBatchAll -ButtonDefs $allButtonDefs `
    -Inputs @(
        [PSCustomObject]@{ Name = "TargetGroupNameFilter"; Label = "対象グループ"; Options = $groupOptions; LabelWidth = 90; InputWidth = 150 }
    ) `
    -OnOpenClick {
        param($target)
        Open-TargetOrWarn -Path $target
    } | Out-Null

function Start-BatchRunAll {
    Invoke-BatchRunAll -ButtonDefs $allButtonDefs -CheckBoxes $script:batchStepCheckboxes `
        -StatusLabel $script:batchStatusLabel -StatusLabels $script:batchStatusLabels `
        -WriteLog { param($msg) Write-Log $msg } -SetRunButtonsEnabled { param($e) Set-RunButtonsEnabled $e } `
        -InvokeStep {
            param($bd)
            Invoke-BatchStep -ButtonDef $bd -WorkingDirectory $basePath -Form $form `
                -WriteLog { param($msg) Write-Log $msg } -CurrentProcessRef ([ref]$script:currentProc) `
                -GetBatArgs {
                    param($bd)
                    $batArgs = @()
                    foreach ($inputDef in $bd.Inputs) {
                        $value = if ($inputDef.Name -eq "TargetGroupNameFilter") { Get-InputValue -Control $script:batchInputControls["TargetGroupNameFilter"] } else { $inputDef.Default }
                        $batArgs += "$($inputDef.Name):$value"
                    }
                    return $batArgs
                }
        }
}

$script:batchRunButton.Add_Click({ Start-BatchRunAll })


New-CategoryTabControl -TabControl $execTabControl -CategoryDefs $categoryDefs -OnRunClick {
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
} | Out-Null

$execTabControl.Height = 45 + $script:batchPanel.Height


$txtLog = New-LogTextBox

Add-StackedDockedControls -Container $tabRun -ControlsTopToBottom @($execTabControl, $txtLog)


$syncMasterButtonDef = [PSCustomObject]@{
    Label            = "マスター同期"
    BatchPath = "sync-kintone-to-sheet.bat"
}
$allButtonDefsForLog = @($categoryDefs | ForEach-Object { $_.ButtonDefs }) + @($syncMasterButtonDef)

New-LogTab -TabPage $tabLogs -ButtonDefs $allButtonDefsForLog `
    -LabelFn { param($bd) Get-BatchDisplayLabel -ButtonDef $bd } `
    -ExtraLabelText "対象グループ" -ExtraComboWidth 150 `
    -GetLogPathFn { $script:commonEnvVars["LOG_DIR"] } `
    -OnUpdateLogView { Update-LogView } | Out-Null
$script:logPath = $script:commonEnvVars["LOG_DIR"]
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

function Get-GroupXlsxPath { param([string]$GroupName) Join-Path $clientsDir "$GroupName.xlsx" }

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
            "KintoneSubdomain" = @{ Label = "サブドメイン" }
            "KintoneLoginName" = @{ Label = "ログイン名" }
            "KintonePassword"  = @{ Label = "パスワード"; Masked = $true }
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
        Label = "個別設定"
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

$settingsTrailingButtonVars = @{}

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
        $clientBatPath = Join-Path $clientsTemplateDir "client.bat"
        $script:groupTemplateDefaults = [PSCustomObject]@{
            Auth = Get-SetLineRawValues -Path $clientBatPath
            Sync = Get-SetLineRawValues -Path $clientBatPath
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

$tabSettingsMasterOps = New-Object System.Windows.Forms.TabPage
$tabSettingsMasterOps.Text = "マスター操作"
$settingsSubTabControl.Controls.Add($tabSettingsMasterOps)

$settingsToolTip = New-Object System.Windows.Forms.ToolTip

function Get-CommonSettingsFiles {
    return @(
        [PSCustomObject]@{ Path = (Join-Path $basePath "common-env.bat"); Save = { Save-CommonSettings }; Reload = {} }
    )
}

$settingsCommonTopPanel = (New-SettingsTopPanel `
    -OnSave { foreach ($f in (Get-CommonSettingsFiles)) { & $f.Save }; Update-CommonSettingsFields } `
    -OnReload { foreach ($f in (Get-CommonSettingsFiles)) { & $f.Reload }; Update-CommonSettingsFields }).Panel

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

function Get-GroupSettingsFiles {
    param([string]$GroupName)
    return @(
        [PSCustomObject]@{ Path = (Get-GroupBatPath $GroupName); Save = { Save-GroupSettings -GroupName $GroupName }.GetNewClosure(); Reload = {} }
    )
}

$settingsGroupTopPanel = (New-SettingsTopPanel `
    -ExtraControls @($lblSettingsGroupTarget, $cmbSettingsGroupTarget, $btnSettingsGroupNewGroup) `
    -OnSave {
        $target = $cmbSettingsGroupTarget.SelectedItem
        if (!$target) { return }
        foreach ($f in (Get-GroupSettingsFiles -GroupName $target)) { & $f.Save }
        Update-GroupSettingsFields
        Update-GroupDropdowns
    } `
    -OnReload {
        $target = $cmbSettingsGroupTarget.SelectedItem
        foreach ($f in (Get-GroupSettingsFiles -GroupName $target)) { & $f.Reload }
        Update-GroupSettingsFields
    }).Panel

$settingsGroupFieldPanel = New-Object System.Windows.Forms.Panel
$settingsGroupFieldPanel.Dock = [System.Windows.Forms.DockStyle]::Fill
$settingsGroupFieldPanel.AutoScroll = $true

$tabSettingsGroup.Controls.Add($settingsGroupFieldPanel)
$tabSettingsGroup.Controls.Add($settingsGroupTopPanel)

$lblSettingsMasterOpsGroupTarget = New-Object System.Windows.Forms.Label
$lblSettingsMasterOpsGroupTarget.Text = "対象グループ"

$cmbSettingsMasterOpsGroupTarget = New-Object System.Windows.Forms.ComboBox
$cmbSettingsMasterOpsGroupTarget.Size = New-Object System.Drawing.Size(260, 24)
$cmbSettingsMasterOpsGroupTarget.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$cmbSettingsMasterOpsGroupTarget.DisplayMember = "Text"

$lnkSettingsMasterOpsOpenXlsx = New-Object System.Windows.Forms.LinkLabel
$lnkSettingsMasterOpsOpenXlsx.Text = "開く"

$lblSettingsMasterOpsSaveTarget = New-Object System.Windows.Forms.Label
$lblSettingsMasterOpsSaveTarget.Text = "保存対象"
$lblSettingsMasterOpsSaveTarget.AutoSize = $true

$cmbSettingsMasterOpsSaveTarget = New-Object System.Windows.Forms.ComboBox
$cmbSettingsMasterOpsSaveTarget.Items.Add("すべて") | Out-Null
$cmbSettingsMasterOpsSaveTarget.Items.Add("テスト") | Out-Null
$cmbSettingsMasterOpsSaveTarget.Items.Add("アンケート") | Out-Null
$cmbSettingsMasterOpsSaveTarget.SelectedIndex = 0
$cmbSettingsMasterOpsSaveTarget.Size = New-Object System.Drawing.Size(120, 24)
$cmbSettingsMasterOpsSaveTarget.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList

$script:settingsMasterOpsTopPanelObj = New-SettingsTopPanel `
    -ExtraControls @($lblSettingsMasterOpsGroupTarget, $cmbSettingsMasterOpsGroupTarget, $lnkSettingsMasterOpsOpenXlsx) `
    -ButtonRowY 78 `
    -OnSave { Save-MasterOpsToExcel } `
    -OnReload {
        $target = $cmbSettingsMasterOpsGroupTarget.SelectedItem
        Read-MasterOpsExcelData -GroupName $target
    }

$settingsMasterOpsTopPanel = $script:settingsMasterOpsTopPanelObj.Panel

$lblSettingsMasterOpsSaveTarget.Location = New-Object System.Drawing.Point($lblSettingsMasterOpsGroupTarget.Location.X, 48)
$cmbSettingsMasterOpsSaveTarget.Location = New-Object System.Drawing.Point($cmbSettingsMasterOpsGroupTarget.Location.X, 46)
$settingsMasterOpsTopPanel.Controls.Add($lblSettingsMasterOpsSaveTarget)
$settingsMasterOpsTopPanel.Controls.Add($cmbSettingsMasterOpsSaveTarget)

$settingsMasterOpsPanel = New-Object System.Windows.Forms.Panel
$settingsMasterOpsPanel.Dock = [System.Windows.Forms.DockStyle]::Fill
$settingsMasterOpsPanel.AutoScroll = $true

$tabSettingsMasterOps.Controls.Add($settingsMasterOpsPanel)
$tabSettingsMasterOps.Controls.Add($settingsMasterOpsTopPanel)

$grpUserMasterSync = New-Object System.Windows.Forms.GroupBox
$grpUserMasterSync.Text = "ユーザーマスター同期"
$grpUserMasterSync.Dock = [System.Windows.Forms.DockStyle]::Top
$grpUserMasterSync.AutoSize = $true
$grpUserMasterSync.AutoSizeMode = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink
$grpUserMasterSync.Padding = New-Object System.Windows.Forms.Padding(10)

$btnMasterOpsSyncExecute = New-Object System.Windows.Forms.Button
$btnMasterOpsSyncExecute.Text = "同期実行"
$btnMasterOpsSyncExecute.Size = New-Object System.Drawing.Size(100, 24)
$btnMasterOpsSyncExecute.Location = New-Object System.Drawing.Point(20, 30)
$btnMasterOpsSyncExecute.Add_Click({
    try {
        $batchPath = Join-Path $basePath "sync-kintone-to-sheet.bat"
        $groupName = $cmbSettingsMasterOpsGroupTarget.SelectedItem
        if ([string]::IsNullOrWhiteSpace($groupName)) {
            throw "グループが選択されていません"
        }
        Invoke-ActionWithUpdateStatus -StatusLabel $lblMasterOpsStatusPlaceholder -Action {
            $script:suppressComboSync = $true
            $cmbSettingsGroupTarget.SelectedItem = $groupName
            $script:suppressComboSync = $null
            Update-GroupSettingsFields
            $syncAppId = Get-GroupSettingsFieldValue "SYNC_SyncUserMasterAppId"
            $syncSheetName = Get-GroupSettingsFieldValue "SYNC_SyncUserMasterSheetName"
            if ([string]::IsNullOrWhiteSpace($syncAppId)) {
                throw "対象アプリIDが入力されていません"
            }
            $batArgs = @("-TargetGroupNameFilter:$groupName", "-SyncUserMasterAppId:$syncAppId", "-SyncUserMasterSheetName:$syncSheetName")
            $exitCode = Invoke-BatProcess -BatPath $batchPath -WorkingDirectory $basePath -BatArgs $batArgs
            if ($exitCode -ne 0) {
                throw "同期処理に失敗しました（$($syncAppId)）"
            }
            [System.Windows.Forms.MessageBox]::Show("同期が完了しました。", "完了", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
        }
    } catch {
        [System.Windows.Forms.MessageBox]::Show("エラーが発生しました: $_", "エラー", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    }
})
$grpUserMasterSync.Controls.Add($btnMasterOpsSyncExecute)

$lblMasterOpsStatusPlaceholder = New-Object System.Windows.Forms.Label
$lblMasterOpsStatusPlaceholder.AutoSize = $false
$lblMasterOpsStatusPlaceholder.Size = New-Object System.Drawing.Size(500, 24)
$lblMasterOpsStatusPlaceholder.Location = New-Object System.Drawing.Point(130, 30)
$lblMasterOpsStatusPlaceholder.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
$grpUserMasterSync.Controls.Add($lblMasterOpsStatusPlaceholder)

$grpSurveyEdit = New-Object System.Windows.Forms.GroupBox
$grpSurveyEdit.Text = "アンケート編集"
$grpSurveyEdit.Dock = [System.Windows.Forms.DockStyle]::Top
$grpSurveyEdit.AutoSize = $true
$grpSurveyEdit.AutoSizeMode = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink
$grpSurveyEdit.Padding = New-Object System.Windows.Forms.Padding(10)

$script:surveyRows = @()
$script:surveyContentPanel = $null
$script:surveyColumns = @(
    @{ Label = "通番"; Width = 20; AutoIncrement = $true }
    @{ Label = "アンケート名"; Width = 150; Property = "SurveyName" }
    @{ Label = "TrackID"; Width = 300; Property = "TrackID";}
    @{ Label = "DL"; Width = 60; Property = "IsDownload"; IsBool = $true }
    @{ Label = "停止中"; Width = 60; Property = "IsStop"; IsBool = $true }
)

$grpTestEdit = New-Object System.Windows.Forms.GroupBox
$grpTestEdit.Text = "テスト編集"
$grpTestEdit.Dock = [System.Windows.Forms.DockStyle]::Top
$grpTestEdit.AutoSize = $true
$grpTestEdit.AutoSizeMode = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink
$grpTestEdit.Padding = New-Object System.Windows.Forms.Padding(10)

$script:testRows = @()
$script:testContentPanel = $null
$script:testColumns = @(
    @{ Label = "通番"; Width = 20; AutoIncrement = $true }
    @{ Label = "テスト名"; Width = 150; Property = "TestName" }
    @{ Label = "TrackID"; Width = 300; Property = "TrackID" }
    @{ Label = "DL"; Width = 60; Property = "IsDownload"; IsBool = $true }
    @{ Label = "停止中"; Width = 60; Property = "IsStop"; IsBool = $true }
)

$controlsToStack = @($grpUserMasterSync, (New-Panel -Height 10), $grpTestEdit, (New-Panel -Height 10), $grpSurveyEdit, (New-Panel -Height 10))
Add-StackedDockedControls -Container $settingsMasterOpsPanel -ControlsTopToBottom $controlsToStack -Spacing 0

function Update-SurveyGrid {
    $panels = New-Grid -GroupBox $grpSurveyEdit -RowDatas ([ref]$script:surveyRows) -OnDelete {
        $deleteRowNo = $this.Tag
        $updatedRows = Read-SurveyGridData
        $script:surveyRows = @($updatedRows | Where-Object { $_.No -ne $deleteRowNo })
        Update-SurveyGrid
    } -OnAdd {
        param($ContentPanel)
        $updatedRows = Read-SurveyGridData
        $script:surveyRows = $updatedRows

        $currentRows = @($script:surveyRows)
        $nextNo = if ($currentRows.Count -gt 0) { ($currentRows | Select-Object -Last 1).No + 1 } else { 1 }
        $newObj = [ordered]@{ No = $nextNo }
        foreach ($col in $script:surveyColumns | Where-Object { $_.Property }) {
            $newObj[$col.Property] = ""
        }
        $newRow = [PSCustomObject]$newObj
        $script:surveyRows = @($script:surveyRows) + @($newRow)
        Update-SurveyGrid
    } -Columns $script:surveyColumns
    $script:surveyContentPanel = $panels.ContentPanel
}

function Read-SurveyGridData {
    Read-GridData -ContentPanel $script:surveyContentPanel -Columns $script:surveyColumns
}

function Read-SurveyExcelData {
    param([string]$GroupName)

    $xlsxPath = Get-GroupXlsxPath $GroupName

    try {
        $script:surveyRows = Read-ExcelData `
            -ExcelPath $xlsxPath `
            -SheetName "アンケート" `
            -DataTransformer {
                param($Rows)
                $convertedRows = @()
                foreach ($row in $Rows) {
                    $newObj = [ordered]@{ No = @($convertedRows).Count + 1 }
                    foreach ($col in $script:surveyColumns | Where-Object { $_.Property }) {
                        $value = $row."$($col.Label)"
                        if ($col.IsBool -and $value -is [bool]) {
                            $value = if ($value) { "TRUE" } else { "FALSE" }
                        }
                        $newObj[$col.Property] = $value
                    }
                    $convertedRows += [PSCustomObject]$newObj
                }
                $convertedRows
            }
        Update-SurveyGrid
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show("アンケート読込に失敗しました: $_", "エラー", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    }
}

function Save-SurveyToExcel {
    $groupName = $cmbSettingsMasterOpsGroupTarget.SelectedItem
    $xlsxPath = Get-GroupXlsxPath $groupName
    try {
        $rowsFromUI = @(Read-SurveyGridData)
        Save-DataToExcel -ExcelPath $xlsxPath -SheetName "アンケート" -Datas $rowsFromUI -Columns $script:surveyColumns
        [System.Windows.Forms.MessageBox]::Show("アンケートを保存しました。", "完了", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show("保存に失敗しました: $_", "エラー", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    }
}

function Update-TestGrid {
    $panels = New-Grid -GroupBox $grpTestEdit -RowDatas ([ref]$script:testRows) -OnDelete {
        $deleteRowNo = $this.Tag
        $updatedRows = Read-TestGridData
        $script:testRows = @($updatedRows | Where-Object { $_.No -ne $deleteRowNo })
        Update-TestGrid
    } -OnAdd {
        param($ContentPanel)
        $updatedRows = Read-TestGridData
        $script:testRows = $updatedRows

        $currentRows = @($script:testRows)
        $nextNo = if ($currentRows.Count -gt 0) { ($currentRows | Select-Object -Last 1).No + 1 } else { 1 }
        $newObj = [ordered]@{ No = $nextNo }
        foreach ($col in $script:testColumns | Where-Object { $_.Property }) {
            $newObj[$col.Property] = ""
        }
        $newRow = [PSCustomObject]$newObj
        $script:testRows = @($script:testRows) + @($newRow)
        Update-TestGrid
    } -Columns $script:testColumns
    $script:testContentPanel = $panels.ContentPanel
}

function Read-TestGridData {
    Read-GridData -ContentPanel $script:testContentPanel -Columns $script:testColumns
}

function Read-TestExcelData {
    param([string]$GroupName)

    $xlsxPath = Get-GroupXlsxPath $GroupName

    try {
        $script:testRows = Read-ExcelData `
            -ExcelPath $xlsxPath `
            -SheetName "テスト" `
            -DataTransformer {
                param($Rows)
                $convertedRows = @()
                foreach ($row in $Rows) {
                    $newObj = [ordered]@{ No = @($convertedRows).Count + 1 }
                    foreach ($col in $script:testColumns | Where-Object { $_.Property }) {
                        $value = $row."$($col.Label)"
                        if ($col.IsBool -and $value -is [bool]) {
                            $value = if ($value) { "TRUE" } else { "FALSE" }
                        }
                        $newObj[$col.Property] = $value
                    }
                    $convertedRows += [PSCustomObject]$newObj
                }
                $convertedRows
            }
        Update-TestGrid
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show("テスト読込に失敗しました: $_", "エラー", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    }
}

function Save-MasterOpsToExcel {
    $groupName = $cmbSettingsMasterOpsGroupTarget.SelectedItem
    $xlsxPath = Get-GroupXlsxPath $groupName
    try {
        switch ($cmbSettingsMasterOpsSaveTarget.SelectedItem) {
            "すべて" {
                $surveyDatas = @(Read-SurveyGridData)
                $testDatas = @(Read-TestGridData)
                Save-DataToExcel -ExcelPath $xlsxPath -SheetDatasMap @(
                    @{ SheetName = "アンケート"; Datas = $surveyDatas; Columns = $script:surveyColumns }
                    @{ SheetName = "テスト"; Datas = $testDatas; Columns = $script:testColumns }
                )
                [System.Windows.Forms.MessageBox]::Show("すべて保存しました。", "完了", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
            }
            "テスト" {
                $testDatas = @(Read-TestGridData)
                Save-DataToExcel -ExcelPath $xlsxPath -SheetName "テスト" -Datas $testDatas -Columns $script:testColumns
                [System.Windows.Forms.MessageBox]::Show("テストを保存しました。", "完了", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
            }
            "アンケート" {
                $surveyDatas = @(Read-SurveyGridData)
                Save-DataToExcel -ExcelPath $xlsxPath -SheetName "アンケート" -Datas $surveyDatas -Columns $script:surveyColumns
                [System.Windows.Forms.MessageBox]::Show("アンケートを保存しました。", "完了", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
            }
        }
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show("保存に失敗しました: $_", "エラー", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    }
}

function Read-MasterOpsExcelData {
    param([string]$GroupName)

    $xlsxPath = Get-GroupXlsxPath $GroupName

    try {
        $surveyTransformer = {
            param($Rows)
            $convertedRows = @()
            foreach ($row in $Rows) {
                $newObj = [ordered]@{ No = @($convertedRows).Count + 1 }
                foreach ($col in $script:surveyColumns | Where-Object { $_.Property }) {
                    $value = $row."$($col.Label)"
                    if ($col.IsBool -and $value -is [bool]) {
                        $value = if ($value) { "TRUE" } else { "FALSE" }
                    }
                    $newObj[$col.Property] = $value
                }
                $convertedRows += [PSCustomObject]$newObj
            }
            $convertedRows
        }

        $testTransformer = {
            param($Rows)
            $convertedRows = @()
            foreach ($row in $Rows) {
                $newObj = [ordered]@{ No = @($convertedRows).Count + 1 }
                foreach ($col in $script:testColumns | Where-Object { $_.Property }) {
                    $value = $row."$($col.Label)"
                    if ($col.IsBool -and $value -is [bool]) {
                        $value = if ($value) { "TRUE" } else { "FALSE" }
                    }
                    $newObj[$col.Property] = $value
                }
                $convertedRows += [PSCustomObject]$newObj
            }
            $convertedRows
        }

        $results = Read-ExcelData -ExcelPath $xlsxPath -SheetTransformerMap @(
            @{ SheetName = "アンケート"; DataTransformer = $surveyTransformer }
            @{ SheetName = "テスト"; DataTransformer = $testTransformer }
        )

        $script:surveyRows = $results["アンケート"]
        $script:testRows = $results["テスト"]
        Update-SurveyGrid
        Update-TestGrid
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show("読込に失敗しました: $_", "エラー", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    }
}

function Save-TestToExcel {
    $groupName = $cmbSettingsMasterOpsGroupTarget.SelectedItem
    $xlsxPath = Get-GroupXlsxPath $groupName
    try {
        $rowsFromUI = @(Read-TestGridData)
        Save-DataToExcel -ExcelPath $xlsxPath -SheetName "テスト" -Datas $rowsFromUI -Columns $script:testColumns
        [System.Windows.Forms.MessageBox]::Show("テストを保存しました。", "完了", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show("保存に失敗しました: $_", "エラー", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    }
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

$mentionTypeOptions = @("USER", "GROUP", "ORGANIZATION")


function Update-CommonSettingsFields {
    Render-SettingsFields -Panel $settingsCommonFieldPanel -Rows (Get-CommonSettingsFieldRows) -TargetTextBoxes $script:settingsCommonFieldTextBoxes -RadioVars $radioVars `
        -GroupLabels $settingsGroupLabels -VarLabels $settingsVarLabels -ToolTip $settingsToolTip -RootPath $rootPath -EnvResolver $script:commonEnvResolver `
        -MultilineVars $settingsMultilineVars -MaskedVars $settingsMaskedVars -FolderBrowseVars $settingsFolderBrowseVars -FileBrowseVars $settingsFileBrowseVars | Out-Null
}

function Test-KintoneConnection {
    param([string]$ReportGroup, [string]$FieldName)
    $kintoneSubdomain = Get-GroupSettingsFieldValue "AUTH_KintoneSubdomain"
    $kintoneLoginName = Get-GroupSettingsFieldValue "AUTH_KintoneLoginName"
    $kintonePassword = Get-GroupSettingsFieldValue "AUTH_KintonePassword"
    $targetAppIdsValue = Get-GroupSettingsFieldValue $FieldName
    $targetAppIds = @($targetAppIdsValue -split '[,\s]+' | Where-Object { $_ })
    if ($targetAppIds.Count -eq 0) {
        throw "対象アプリIDを入力してください。"
    }
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
}

function Update-GroupSettingsFields {
    $scrollX = -$settingsGroupFieldPanel.AutoScrollPosition.X
    $scrollY = -$settingsGroupFieldPanel.AutoScrollPosition.Y

    $target = $cmbSettingsGroupTarget.SelectedItem
    $trailingButtons = $settingsTrailingButtonVars.Clone()
    $trailingButtons["CommentTextTemplate"] = { param($Panel, $Y, $Field) Add-FieldActionButton -Panel $Panel -Y $Y -Text "テスト投稿" -AddStatusLabel -OnClick {
        try {
            Invoke-ActionWithUpdateStatus -StatusLabel $Field.StatusLabel -Action {
                Sync-MentionRowsFromControls
                $spaceId = Get-GroupSettingsFieldValue "POST_SpaceId"
                $threadId = Get-GroupSettingsFieldValue "POST_ThreadId"
                $validationError = if ([string]::IsNullOrWhiteSpace($spaceId) -or [string]::IsNullOrWhiteSpace($threadId)) { "スペースIDとスレッドIDを入力してください。" } else { $null }
                if ($validationError) {
                    throw "スペースID／スレッドIDを入力してください。"
                }
                $kintoneSubdomain = Get-GroupSettingsFieldValue "AUTH_KintoneSubdomain"
                $kintoneLoginName = Get-GroupSettingsFieldValue "AUTH_KintoneLoginName"
                $kintonePassword = Get-GroupSettingsFieldValue "AUTH_KintonePassword"
                $mentions = @($script:mentionRows | Where-Object { $_.Code } | ForEach-Object { @{ code = $_.Code; type = $_.Type } })
                $baseUrl = "https://$kintoneSubdomain.cybozu.com"
                $authorization = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("${kintoneLoginName}:${kintonePassword}"))
                Add-KintoneThreadComment -SpaceId $spaceId -ThreadId $threadId -Text "【テスト投稿】track-aggregatorの設定確認用コメントです。不要であれば削除してください。" -Mentions $mentions -BaseUrl $baseUrl -Authorization $authorization | Out-Null
                [System.Windows.Forms.MessageBox]::Show("テスト投稿に成功しました。スレッドを確認し、不要であれば削除してください。", "完了", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
            }
        } catch {
            [System.Windows.Forms.MessageBox]::Show("エラーが発生しました: $_", "エラー", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        }
    }.GetNewClosure() }
    $trailingButtons["SyncUserMasterAppId"] = { param($Panel, $Y, $Field) Add-FieldActionButton -Panel $Panel -Y $Y -Text "テスト接続" -AddStatusLabel -OnClick {
        try {
            Invoke-ActionWithUpdateStatus -StatusLabel $Field.StatusLabel -Action {
                Test-KintoneConnection -ReportGroup "SYNC" -FieldName "SYNC_SyncUserMasterAppId" | Out-Null
                [System.Windows.Forms.MessageBox]::Show("テスト接続に成功しました。", "完了", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
            }
        } catch {
            [System.Windows.Forms.MessageBox]::Show("エラーが発生しました: $_", "エラー", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        }
    }.GetNewClosure() }
    Render-SettingsFields -Panel $settingsGroupFieldPanel -Rows (Get-GroupSettingsFieldRows -GroupName $target) -TargetTextBoxes $script:settingsGroupFieldTextBoxes -RadioVars $radioVars `
        -GroupLabels $settingsGroupLabels -VarLabels $settingsVarLabels -ToolTip $settingsToolTip -RootPath $rootPath -EnvResolver $script:commonEnvResolver `
        -MultilineVars $settingsMultilineVars -MaskedVars $settingsMaskedVars -FolderBrowseVars $settingsFolderBrowseVars -FileBrowseVars $settingsFileBrowseVars `
        -MentionGroupCombo $cmbSettingsGroupTarget -MentionTypeOptions $mentionTypeOptions `
        -TrailingButtonVars $trailingButtons | Out-Null

    $settingsGroupFieldPanel.AutoScrollPosition = New-Object System.Drawing.Point($scrollX, $scrollY)
}

function Save-CommonSettings {
    $path = Join-Path $basePath "common-env.bat"

    Save-EnvBatFile -Path $path -VarNames $commonSettingsVars `
        -GetValueFn { param($varName)
            Get-CommonSettingsFieldValue $varName
        } `
        -HasValueFn { param($varName)
            $true
        }
}

function Save-GroupSettings {
    param([string]$GroupName)

    $groupBatPath = Get-GroupBatPath $GroupName

    $script:saveGroupAuthVarMap = @{}
    foreach ($varName in $authVars) {
        $script:saveGroupAuthVarMap[$varName] = "AUTH_$varName"
    }

    $script:saveGroupPostVarMap = @{}
    foreach ($varName in $postVars) {
        $script:saveGroupPostVarMap[$varName] = "POST_$varName"
    }

    $script:saveGroupOverrideVarMap = @{}
    foreach ($varName in $groupOverrideVars) {
        $script:saveGroupOverrideVarMap[$varName] = "OVERRIDE_$varName"
    }

    $script:saveGroupSyncVarMap = @{}
    foreach ($varName in $syncUserMasterVars) {
        $script:saveGroupSyncVarMap[$varName] = "SYNC_$varName"
    }

    $allVars = @() + @($script:saveGroupAuthVarMap.Keys) + @("Authorization", "BaseUrl") + @($script:saveGroupPostVarMap.Keys) + @($script:saveGroupOverrideVarMap.Keys) + @($script:saveGroupSyncVarMap.Keys)

    Sync-MentionRowsFromControls

    Save-EnvBatFile -Path $groupBatPath -VarNames $allVars -RemoveUnwritten `
        -GetValueFn { param($varName)
            if ($varName -eq "Authorization") {
                $existingAuth = Get-SetLineRawValues -Path $groupBatPath
                if ($existingAuth.ContainsKey("Authorization")) { $existingAuth["Authorization"] } else { (Get-GroupTemplateDefaults).Auth["Authorization"] }
            } elseif ($varName -eq "BaseUrl") {
                "https://%KintoneSubdomain%.cybozu.com"
            } elseif ($varName -eq "MentionUserCodes") {
                ConvertTo-MentionUserCodesText -Rows $script:mentionRows
            } elseif ($script:saveGroupAuthVarMap.ContainsKey($varName)) {
                Get-GroupSettingsFieldValue $script:saveGroupAuthVarMap[$varName]
            } elseif ($script:saveGroupPostVarMap.ContainsKey($varName)) {
                $val = Get-GroupSettingsFieldValue $script:saveGroupPostVarMap[$varName]
                if ($settingsMultilineVars -contains $varName) { $val = $val -replace "`r`n", '\n' -replace "`n", '\n' }
                $val
            } elseif ($script:saveGroupOverrideVarMap.ContainsKey($varName)) {
                $val = Get-GroupSettingsFieldValue $script:saveGroupOverrideVarMap[$varName]
                if ([string]::IsNullOrWhiteSpace($val)) { "" } else { $val }
            } elseif ($script:saveGroupSyncVarMap.ContainsKey($varName)) {
                Get-GroupSettingsFieldValue $script:saveGroupSyncVarMap[$varName]
            } else {
                ""
            }
        } `
        -HasValueFn { param($varName)
            if ($varName -in $overridableVarDefs.Keys) {
                $value = Get-GroupSettingsFieldValue "OVERRIDE_$varName"
                return -not [string]::IsNullOrWhiteSpace($value)
            }
            $true
        }

    $xlsxPath = Get-GroupXlsxPath $GroupName
    if (!(Test-Path -LiteralPath $xlsxPath)) {
        $templateXlsxPath = Join-Path $clientsTemplateDir "client.xlsx"
        if (Test-Path -LiteralPath $templateXlsxPath) {
            Copy-Item -LiteralPath $templateXlsxPath -Destination $xlsxPath
        }
    }
}

function Update-GroupDropdowns {
    $groupNames = @(Get-GroupNames)

    $savedSettings = $cmbSettingsGroupTarget.SelectedItem
    $savedLog = $cmbLogGroup.SelectedItem
    $savedMaster = $cmbSettingsMasterOpsGroupTarget.SelectedItem
    $savedFilters = @{}
    foreach ($cd in $categoryDefs) {
        foreach ($bd in $cd.ButtonDefs) {
            if ($bd.InputControls -and $bd.InputControls.ContainsKey("TargetGroupNameFilter")) {
                $savedFilters[$bd.Label] = $bd.InputControls["TargetGroupNameFilter"].SelectedItem
            }
        }
    }

    if ($cmbSettingsGroupTarget) {
        $cmbSettingsGroupTarget.Items.Clear()
        foreach ($groupName in $groupNames) {
            $cmbSettingsGroupTarget.Items.Add($groupName) | Out-Null
        }
        if ($savedSettings -and $cmbSettingsGroupTarget.Items.Contains($savedSettings)) {
            $cmbSettingsGroupTarget.SelectedItem = $savedSettings
        } elseif ($cmbSettingsGroupTarget.Items.Count -gt 0) {
            $cmbSettingsGroupTarget.SelectedIndex = 0
        }
    }

    foreach ($cd in $categoryDefs) {
        foreach ($bd in $cd.ButtonDefs) {
            if ($bd.InputControls -and $bd.InputControls.ContainsKey("TargetGroupNameFilter")) {
                $cmb = $bd.InputControls["TargetGroupNameFilter"]
                if ($cmb) {
                    $cmb.Items.Clear()
                    $cmb.Items.Add("すべて") | Out-Null
                    foreach ($groupName in $groupNames) {
                        $cmb.Items.Add($groupName) | Out-Null
                    }
                    if ($savedFilters[$bd.Label] -and $cmb.Items.Contains($savedFilters[$bd.Label])) {
                        $cmb.SelectedItem = $savedFilters[$bd.Label]
                    } elseif ($cmb.Items.Count -gt 0) {
                        $cmb.SelectedIndex = 0
                    }
                }
            }
        }
    }

    if ($cmbLogGroup) {
        $cmbLogGroup.Items.Clear()
        $cmbLogGroup.Items.Add("すべて") | Out-Null
        foreach ($groupName in $groupNames) {
            $cmbLogGroup.Items.Add($groupName) | Out-Null
        }
        if ($savedLog -and $cmbLogGroup.Items.Contains($savedLog)) {
            $cmbLogGroup.SelectedItem = $savedLog
        } elseif ($cmbLogGroup.Items.Count -gt 0) {
            $cmbLogGroup.SelectedIndex = 0
        }
    }

    if ($cmbSettingsMasterOpsGroupTarget) {
        $cmbSettingsMasterOpsGroupTarget.Items.Clear()
        foreach ($groupName in $groupNames) {
            $cmbSettingsMasterOpsGroupTarget.Items.Add($groupName) | Out-Null
        }
        if ($savedMaster -and $cmbSettingsMasterOpsGroupTarget.Items.Contains($savedMaster)) {
            $cmbSettingsMasterOpsGroupTarget.SelectedItem = $savedMaster
        } elseif ($cmbSettingsMasterOpsGroupTarget.Items.Count -gt 0) {
            $cmbSettingsMasterOpsGroupTarget.SelectedIndex = 0
        }
    }
}

$btnSettingsGroupNewGroup.Add_Click({
    Add-Type -AssemblyName Microsoft.VisualBasic
    $newName = [Microsoft.VisualBasic.Interaction]::InputBox("グループ名を入力してください", "グループの新規作成", "")
    $newName = $newName.Trim()
    if (!$newName) { return }

    if ($cmbSettingsGroupTarget.Items.Contains($newName) -or (Test-Path -LiteralPath (Get-GroupXlsxPath $newName)) -or (Test-Path -LiteralPath (Get-GroupBatPath $newName))) {
        [System.Windows.Forms.MessageBox]::Show("「$newName」は既に存在します。", "グループの新規作成", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        return
    }

    $cmbSettingsGroupTarget.Items.Add($newName) | Out-Null
    $cmbSettingsGroupTarget.SelectedItem = $newName
})

$lnkSettingsMasterOpsOpenXlsx.Add_LinkClicked({
    $target = $cmbSettingsMasterOpsGroupTarget.SelectedItem
    if (!$target) {
        [System.Windows.Forms.MessageBox]::Show("対象グループが選択されていません。", "受講生データを開く", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        return
    }
    Open-TargetOrWarn -Path (Get-GroupXlsxPath $target)
})

$cmbSettingsMasterOpsGroupTarget.Add_SelectedIndexChanged({
    $target = $cmbSettingsMasterOpsGroupTarget.SelectedItem
    Read-MasterOpsExcelData -GroupName $target
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
Update-GroupDropdowns

$execTabControl.SelectedTab = $tabBatchAll
$tabControl.SelectedTab = $tabRun

$form.Add_Shown({
    Update-CommonSettingsFields
    Update-GroupSettingsFields
})

[System.Windows.Forms.Application]::Run($form)
