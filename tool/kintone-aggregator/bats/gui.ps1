
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
    return @(Get-ChildItem -LiteralPath $clientsDir -Filter "*.xlsx" -File -ErrorAction SilentlyContinue | Sort-Object Name | ForEach-Object { [System.IO.Path]::GetFileNameWithoutExtension($_.Name) })
}

$groupOptions = @([PSCustomObject]@{ Text = "すべて"; Value = "" })
foreach ($groupName in (Get-GroupNames)) {
    $groupOptions += [PSCustomObject]@{ Text = $groupName; Value = $groupName }
}

$defaultTargetDate = (Get-Date).ToString("yyyy-MM-dd")
$dateAndGroupInputs = @(
    [PSCustomObject]@{ Name = "TargetDate"; Label = "対象日"; Default = $defaultTargetDate; LabelWidth = 55; InputWidth = 90 }
    [PSCustomObject]@{ Name = "TargetGroupNameFilter"; Label = "対象グループ"; Default = ""; LabelWidth = 75; InputWidth = 120; Options = $groupOptions }
)
$categoryDefs = @(
    [PSCustomObject]@{
        Label = "アプリデータ作成"
        ButtonDefs = @(
            [PSCustomObject]@{ Label = "業務日誌"; BatchLabel = "アプリデータ作成-業務日誌"; IncludeInBatch = $true; BatchPath = (Join-Path $basePath "create-daily-report.bat"); OpenTarget = $script:commonEnvVars["OutputReportDir"]; Inputs = $dateAndGroupInputs }
            [PSCustomObject]@{ Label = "パルスサーベイ"; BatchLabel = "アプリデータ作成-パルスサーベイ"; IncludeInBatch = $true; BatchPath = (Join-Path $basePath "create-pulse-survey.bat"); OpenTarget = $script:commonEnvVars["OutputReportDir"]; Inputs = $dateAndGroupInputs }
        )
    }
    [PSCustomObject]@{
        Label = "アプリデータ集計"
        ButtonDefs = @(
            [PSCustomObject]@{ Label = "業務日誌・パルスサーベイ"; BatchLabel = "アプリデータ集計-業務日誌・パルスサーベイ"; IncludeInBatch = $true; BatchPath = (Join-Path $basePath "collect-app-data.bat"); OpenTarget = $script:commonEnvVars["OutputCollectDataRootDir"]; Inputs = $dateAndGroupInputs }
        )
    }
    [PSCustomObject]@{
        Label = "アラート集計"
        ButtonDefs = @(
            [PSCustomObject]@{ Label = "業務日誌・パルスサーベイ"; BatchLabel = "アラート集計-業務日誌・パルスサーベイ"; IncludeInBatch = $true; BatchPath = (Join-Path $basePath "check-alert.bat"); OpenTarget = $script:commonEnvVars["OutputAlertRootDir"]; Inputs = $dateAndGroupInputs }
            [PSCustomObject]@{ Label = "投稿"; BatchLabel = "アラート集計-投稿"; IncludeInBatch = $true; BatchPath = (Join-Path $basePath "post-alert-result.bat"); OpenTarget = { param($groupName) Get-GroupKintoneThreadUrl -GroupName $groupName }; Inputs = $dateAndGroupInputs }
        )
    }
)

$form = New-Object System.Windows.Forms.Form
$form.Text = "kintoneデータ集計ツール"
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
        [PSCustomObject]@{ Name = "TargetDate"; Label = "対象日"; Default = $defaultTargetDate; LabelWidth = 60; InputWidth = 90 }
        [PSCustomObject]@{ Name = "TargetGroupNameFilter"; Label = "対象グループ"; Options = $groupOptions; LabelWidth = 90; InputWidth = 120 }
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
$script:batchInputControls = $batchTab.InputControls
$script:batchStepCheckboxes = $batchTab.CheckBoxes
$btnRunAll = $batchTab.RunButton
$lblBatchStatus = $batchTab.StatusLabel
$script:batchRunButtons = @($btnRunAll)

function Start-BatchRunAll {
    Invoke-BatchRunAll -ButtonDefs $allButtonDefs -CheckBoxes $script:batchStepCheckboxes `
        -StatusLabel $lblBatchStatus -ExtraControls @($script:batchInputControls.Values) `
        -WriteLog { param($msg) Write-Log $msg } -SetRunButtonsEnabled { param($e) Set-RunButtonsEnabled $e } `
        -InvokeStep {
            param($bd)
            Invoke-BatchStep -ButtonDef $bd -WorkingDirectory $basePath -Form $form `
                -WriteLog { param($msg) Write-Log $msg } -CurrentProcessRef ([ref]$script:currentProc) `
                -GetBatArgs {
                    param($bd)
                    $batArgs = @()
                    foreach ($inputDef in $bd.Inputs) {
                        $batArgs += Get-InputValue -Control $script:batchInputControls[$inputDef.Name]
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
                foreach ($inputDef in $bd.Inputs) {
                    $batArgs += Get-InputValue -Control $inputMap[$inputDef.Name]
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


$clientsTemplateDir = Join-Path $clientsDir "template"

function Get-GroupXlsxPath { param([string]$GroupName) Join-Path $clientsDir "$GroupName.xlsx" }

$script:commonEnvResolver = { param($name) $script:commonEnvVars[$name] }

$groupReportVars = @("TargetAppIds")
$commonReportVars = @("TargetDateCodeField", "TargetUserCodeField")
$syncUserMasterVars = @("SyncUserMasterAppId", "SyncUserMasterSheetName")

function Get-ReportTypeDefs {
    $types = @()
    foreach ($key in $script:commonEnvVars.Keys) {
        if ($key -notmatch '^SourceType(_.+)$') { continue }
        $suffix = $Matches[1]
        $types += [PSCustomObject]@{
            Prefix = $suffix.TrimStart('_')
            Suffix = $suffix
            Label  = $script:commonEnvVars[$key]
        }
    }
    return @($types | Sort-Object Prefix)
}

$settingsGroups = [ordered]@{
    "BASE" = @{
        Label = "基本設定"
        Vars = [ordered]@{
            "ClientDataRootDir"        = @{ Label = "グループデータのフォルダ"; Browse = "Folder" }
            "OutputRootDir"            = @{ Label = "出力のルートフォルダ"; Browse = "Folder" }
            "TemplateRootDir"          = @{ Label = "テンプレートのフォルダ"; Browse = "Folder" }
            "LOG_DIR"                  = @{ Label = "ログの出力先"; Browse = "Folder" }
            "OutputReportDir"          = @{ Label = "業務日誌・パルスサーベイの出力先"; Browse = "Folder" }
            "OutputCollectDataRootDir" = @{ Label = "アプリデータ集計の出力先"; Browse = "Folder" }
            "OutputAlertRootDir"       = @{ Label = "アラート検知結果の出力先"; Browse = "Folder" }
            "OutputAlertBackupDir"     = @{ Label = "アラート検知結果のバックアップ先"; Browse = "Folder" }
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
    "SYNC" = @{
        Label = "ユーザーマスター同期"
        Vars = [ordered]@{
            "SyncUserMasterAppId"   = @{ Label = "対象アプリID" }
            "SyncUserMasterSheetName" = @{ Label = "対象シート名" }
        }
    }
}

$reportTypeVarDefs = [ordered]@{
    "TargetAppIds"        = @{ Label = "対象アプリID" }
    "TargetDateCodeField" = @{ Label = "日付フィールドコード" }
    "TargetUserCodeField" = @{ Label = "受講生IDフィールドコード" }
}
foreach ($rt in (Get-ReportTypeDefs)) {
    $settingsGroups[$rt.Prefix] = @{ Label = $rt.Label; Vars = $reportTypeVarDefs }
}

$commonSettingsVars = @($settingsGroups["BASE"].Vars.Keys)
$authVars = @($settingsGroups["AUTH"].Vars.Keys)
$postVars = @($settingsGroups["POST"].Vars.Keys)

$settingsGroupLabels = @{}
$settingsVarLabels = @{}
$settingsFolderBrowseVars = @()
$settingsFileBrowseVars = @()
$settingsMaskedVars = @()
$settingsMultilineVars = @()
foreach ($groupKey in $settingsGroups.Keys) {
    $settingsGroupLabels[$groupKey] = $settingsGroups[$groupKey].Label
    foreach ($varKey in $settingsGroups[$groupKey].Vars.Keys) {
        $varDef = $settingsGroups[$groupKey].Vars[$varKey]
        $settingsVarLabels[$varKey] = $varDef.Label
        if ($varDef.Browse -eq "Folder") { $settingsFolderBrowseVars += $varKey }
        if ($varDef.Browse -eq "File") { $settingsFileBrowseVars += $varKey }
        if ($varDef.Masked) { $settingsMaskedVars += $varKey }
        if ($varDef.Multiline) { $settingsMultilineVars += $varKey }
    }
}
$settingsTrailingButtonVars = @{
    "TargetAppIds"        = { param($Panel, $Y, $Field) Add-FieldActionButton -Panel $Panel -Y $Y -Text "テスト接続" -AddStatusLabel -OnClick {
        Set-StepStatus -Label $Field.StatusLabel -Text "実行中..." -State "実行中..."
        [System.Windows.Forms.Application]::DoEvents()
        try {
            Test-KintoneConnection -ReportGroup $Field.Group -FieldName "$($Field.Group)_TargetAppIds" -ThrowOnError
            Set-StepStatus -Label $Field.StatusLabel -Text "成功" -State "成功"
        } catch {
            Set-StepStatus -Label $Field.StatusLabel -Text "失敗" -State "失敗"
        }
    }.GetNewClosure() }
    "SyncUserMasterAppId" = { param($Panel, $Y, $Field) Add-FieldActionButton -Panel $Panel -Y $Y -Text "テスト接続" -AddStatusLabel -OnClick {
        Set-StepStatus -Label $Field.StatusLabel -Text "実行中..." -State "実行中..."
        [System.Windows.Forms.Application]::DoEvents()
        try {
            Test-KintoneConnection -ReportGroup "SYNC" -FieldName "SYNC_SyncUserMasterAppId" -ThrowOnError
            Set-StepStatus -Label $Field.StatusLabel -Text "成功" -State "成功"
        } catch {
            Set-StepStatus -Label $Field.StatusLabel -Text "失敗" -State "失敗"
        }
    }.GetNewClosure() }
    "SyncUserMasterSheetName" = { param($Panel, $Y, $Field)
        Add-FieldActionButton -Panel $Panel -Y $Y -Text "同期実行" -AddStatusLabel -OnClick {
            $batchPath = Join-Path $basePath "sync-kintone-to-sheet.bat"
            if (-not (Test-Path $batchPath)) {
                [System.Windows.Forms.MessageBox]::Show("バッチファイルが見つかりません: $batchPath", "エラー", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
                return
            }
            Set-StepStatus -Label $Field.StatusLabel -Text "実行中..." -State "実行中..."
            [System.Windows.Forms.Application]::DoEvents()

            try {
                $groupName = $cmbSettingsGroupTarget.SelectedItem
                if ([string]::IsNullOrWhiteSpace($groupName)) {
                    [System.Windows.Forms.MessageBox]::Show("グループを選択してください。", "エラー", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning)
                    Set-StepStatus -Label $Field.StatusLabel -Text "失敗" -State "失敗"
                    return
                }
                $syncAppId = Get-GroupSettingsFieldValue "SYNC_SyncUserMasterAppId"
                $syncSheetName = Get-GroupSettingsFieldValue "SYNC_SyncUserMasterSheetName"
                $batArgs = @("$groupName", "-SyncUserMasterAppId:$syncAppId", "-SyncUserMasterSheetName:$syncSheetName")
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
    "CommentTextTemplate" = { param($Panel, $Y, $Field) Add-FieldActionButton -Panel $Panel -Y $Y -Text "テスト投稿" -AddStatusLabel -OnClick {
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
                    Add-KintoneThreadComment -SpaceId $spaceId -ThreadId $threadId -Text "【テスト投稿】kintoneデータ集計ツールの設定確認用コメントです。不要であれば削除してください。" -Mentions $mentions -BaseUrl $baseUrl -Authorization $authorization
                }.GetNewClosure() `
                -FormatSuccessMessage { param($response) "投稿に成功しました（コメントID: $($response.id)）。`r`nスレッドを確認し、不要であれば削除してください。" } `
                -ThrowOnError
            Set-StepStatus -Label $Field.StatusLabel -Text "成功" -State "成功"
        } catch {
            Set-StepStatus -Label $Field.StatusLabel -Text "失敗" -State "失敗"
        }
    }.GetNewClosure() }
}

function Get-SuffixedRawValues {
    param([hashtable]$RawValues, [string]$Suffix, [array]$VarNames)
    $result = @{}
    foreach ($varName in $VarNames) {
        $key = "$varName$Suffix"
        if ($RawValues.ContainsKey($key)) { $result[$varName] = $RawValues[$key] }
    }
    return $result
}

$script:groupTemplateDefaults = $null
function Get-GroupTemplateDefaults {
    if ($null -eq $script:groupTemplateDefaults) {
        $rawTemplate = Get-SetLineRawValues -Path (Join-Path $clientsTemplateDir "client.bat")
        $byType = @{}
        foreach ($rt in (Get-ReportTypeDefs)) {
            $byType[$rt.Prefix] = Get-SuffixedRawValues -RawValues $rawTemplate -Suffix $rt.Suffix -VarNames $groupReportVars
        }
        $syncValues = @{}
        foreach ($varName in $syncUserMasterVars) {
            if ($rawTemplate.ContainsKey($varName)) {
                $syncValues[$varName] = $rawTemplate[$varName]
            }
        }
        $script:groupTemplateDefaults = [PSCustomObject]@{
            Auth   = $rawTemplate
            ByType = $byType
            Sync   = $syncValues
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
        [PSCustomObject]@{ Path = $collectDataDefsPath; Save = { Save-CollectDataDefs }; Reload = { $script:collectDataDefsSections = $null } }
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
        Update-GroupDropdowns
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

function Get-CommonSettingsFieldRows {
    $raw = Get-SetLineRawValues -Path (Join-Path $basePath "common-env.bat")
    foreach ($varName in $commonSettingsVars) {
        [PSCustomObject]@{ Key = $varName; VarName = $varName; Group = "BASE"; Value = $raw[$varName] }
    }
    foreach ($rt in (Get-ReportTypeDefs)) {
        $rawForType = Get-SuffixedRawValues -RawValues $raw -Suffix $rt.Suffix -VarNames $commonReportVars
        foreach ($varName in $commonReportVars) {
            [PSCustomObject]@{ Key = "$($rt.Prefix)_$varName"; VarName = $varName; Group = $rt.Prefix; Value = $rawForType[$varName] }
        }
    }
}

function Get-GroupSettingsFieldRows {
    param([string]$GroupName)
    if (!$GroupName) { return }

    $templateDefaults = Get-GroupTemplateDefaults
    $rawGroup = Get-SetLineRawValues -Path (Get-GroupBatPath $GroupName)

    foreach ($varName in $authVars) {
        $value = if ($rawGroup.ContainsKey($varName)) { $rawGroup[$varName] } else { $templateDefaults.Auth[$varName] }
        [PSCustomObject]@{ Key = "AUTH_$varName"; VarName = $varName; Group = "AUTH"; Value = $value }
    }
    foreach ($varName in $postVars) {
        $value = if ($rawGroup.ContainsKey($varName)) { $rawGroup[$varName] } else { $templateDefaults.Auth[$varName] }
        [PSCustomObject]@{ Key = "POST_$varName"; VarName = $varName; Group = "POST"; Value = $value }
    }
    foreach ($varName in $syncUserMasterVars) {
        $value = if ($rawGroup.ContainsKey($varName)) { $rawGroup[$varName] } else { $templateDefaults.Sync[$varName] }
        [PSCustomObject]@{ Key = "SYNC_$varName"; VarName = $varName; Group = "SYNC"; Value = $value }
    }
    foreach ($rt in (Get-ReportTypeDefs)) {
        $rawForType = Get-SuffixedRawValues -RawValues $rawGroup -Suffix $rt.Suffix -VarNames $groupReportVars
        $defaultsForType = $templateDefaults.ByType[$rt.Prefix]
        foreach ($varName in $groupReportVars) {
            $value = if ($rawForType.ContainsKey($varName)) { $rawForType[$varName] } else { $defaultsForType[$varName] }
            [PSCustomObject]@{ Key = "$($rt.Prefix)_$varName"; VarName = $varName; Group = $rt.Prefix; Value = $value }
        }
    }
}

$script:settingsCommonFieldTextBoxes = @{}
$script:settingsGroupFieldTextBoxes = @{}

$mentionTypeOptions = @("USER", "GROUP", "ORGANIZATION")
$script:mentionRows = @()
$script:mentionRowsGroupName = $null
$script:mentionRowControls = @()

$collectDataDefsPath = Join-Path $basePath "collect-data-defs.txt"
$script:collectDataDefsSections = $null
$script:collectDataDefsRowControls = @()

function ConvertFrom-CollectDataDefsText {
    param([string]$Text)
    $sections = [System.Collections.Generic.List[object]]::new()
    $currentKey = $null
    $currentRows = $null
    foreach ($rawLine in ($Text -split "`r`n|`n")) {
        $trimmed = $rawLine.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmed)) { continue }
        if ($trimmed -match '^\[(.+)\]$') {
            if ($currentKey) { $sections.Add([PSCustomObject]@{ Key = $currentKey; Rows = $currentRows }) }
            $currentKey = $Matches[1]
            $currentRows = [System.Collections.Generic.List[object]]::new()
            continue
        }
        if ($null -eq $currentRows) { continue }
        $parts = $trimmed -split ',', 2
        $currentRows.Add([PSCustomObject]@{
            OrgName = $parts[0]
            NewName = if ($parts.Count -ge 2) { $parts[1] } else { "" }
        })
    }
    if ($currentKey) { $sections.Add([PSCustomObject]@{ Key = $currentKey; Rows = $currentRows }) }
    return $sections
}

function ConvertTo-CollectDataDefsText {
    param($Sections)
    $lines = @()
    foreach ($section in $Sections) {
        $lines += "[$($section.Key)]"
        foreach ($row in $section.Rows) {
            if ([string]::IsNullOrWhiteSpace($row.OrgName)) { continue }
            $lines += if ([string]::IsNullOrWhiteSpace($row.NewName)) { $row.OrgName } else { "$($row.OrgName),$($row.NewName)" }
        }
        $lines += ""
    }
    return ($lines -join "`r`n")
}

function Sync-CollectDataDefsFromControls {
    foreach ($entry in $script:collectDataDefsRowControls) {
        $entry.Row.OrgName = $entry.OrgBox.Text
        $entry.Row.NewName = $entry.NewBox.Text
    }
}

function Add-CollectDataDefsEditor {
    if ($null -eq $script:collectDataDefsSections) {
        $text = if (Test-Path -LiteralPath $collectDataDefsPath) {
            [System.IO.File]::ReadAllText($collectDataDefsPath, (New-Object System.Text.UTF8Encoding($false)))
        } else {
            ""
        }
        $script:collectDataDefsSections = ConvertFrom-CollectDataDefsText -Text $text
    }
    $script:collectDataDefsRowControls = @()

    $grp = New-Object System.Windows.Forms.GroupBox
    $grp.Text = "アプリデータ集計の列定義"
    $grp.Dock = [System.Windows.Forms.DockStyle]::Top
    $grp.AutoSize = $true
    $grp.AutoSizeMode = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink

    $y = 25
    foreach ($section in $script:collectDataDefsSections) {
        $lblFileNameCaption = New-Object System.Windows.Forms.Label
        $lblFileNameCaption.Text = "ファイル名"
        $lblFileNameCaption.AutoSize = $false
        $lblFileNameCaption.Size = New-Object System.Drawing.Size(220, 20)
        $lblFileNameCaption.Location = New-Object System.Drawing.Point(20, $y)
        $lblFileNameCaption.Font = New-Object System.Drawing.Font($lblFileNameCaption.Font.FontFamily, 9, [System.Drawing.FontStyle]::Bold)
        $grp.Controls.Add($lblFileNameCaption)

        $lblFileNameValue = New-Object System.Windows.Forms.Label
        $lblFileNameValue.Text = if ($script:commonEnvVars.ContainsKey($section.Key)) { $script:commonEnvVars[$section.Key] } else { $section.Key }
        $lblFileNameValue.AutoSize = $false
        $lblFileNameValue.Size = New-Object System.Drawing.Size(300, 20)
        $lblFileNameValue.Location = New-Object System.Drawing.Point(250, $y)
        $grp.Controls.Add($lblFileNameValue)
        $y += 26

        $lblOrgHeader = New-Object System.Windows.Forms.Label
        $lblOrgHeader.Text = "変更前"
        $lblOrgHeader.AutoSize = $false
        $lblOrgHeader.Size = New-Object System.Drawing.Size(210, 18)
        $lblOrgHeader.Location = New-Object System.Drawing.Point(20, $y)
        $grp.Controls.Add($lblOrgHeader)

        $lblNewHeader = New-Object System.Windows.Forms.Label
        $lblNewHeader.Text = "変更後"
        $lblNewHeader.AutoSize = $false
        $lblNewHeader.Size = New-Object System.Drawing.Size(210, 18)
        $lblNewHeader.Location = New-Object System.Drawing.Point(250, $y)
        $grp.Controls.Add($lblNewHeader)
        $y += 20

        foreach ($row in @($section.Rows)) {
            $txtOrg = New-Object System.Windows.Forms.TextBox
            $txtOrg.Text = "$($row.OrgName)"
            $txtOrg.Location = New-Object System.Drawing.Point(20, $y)
            $txtOrg.Size = New-Object System.Drawing.Size(210, 22)
            $grp.Controls.Add($txtOrg)

            $txtNew = New-Object System.Windows.Forms.TextBox
            $txtNew.Text = "$($row.NewName)"
            $txtNew.Location = New-Object System.Drawing.Point(250, $y)
            $txtNew.Size = New-Object System.Drawing.Size(210, 22)
            $grp.Controls.Add($txtNew)

            $btnDeleteRow = New-Object System.Windows.Forms.Button
            $btnDeleteRow.Text = "削除"
            $btnDeleteRow.Location = New-Object System.Drawing.Point(460, ($y - 1))
            $btnDeleteRow.Size = New-Object System.Drawing.Size(60, 24)
            $btnDeleteRow.Tag = [PSCustomObject]@{ Section = $section; Row = $row }
            $btnDeleteRow.Add_Click({
                Sync-CollectDataDefsFromControls
                $ctx = $this.Tag
                $ctx.Section.Rows.Remove($ctx.Row) | Out-Null
                Update-CommonSettingsFields
            })
            $grp.Controls.Add($btnDeleteRow)

            $script:collectDataDefsRowControls += [PSCustomObject]@{ Section = $section; Row = $row; OrgBox = $txtOrg; NewBox = $txtNew }
            $y += 26
        }

        $btnAddRow = New-Object System.Windows.Forms.Button
        $btnAddRow.Text = "＋ 行を追加"
        $btnAddRow.Location = New-Object System.Drawing.Point(20, $y)
        $btnAddRow.Size = New-Object System.Drawing.Size(100, 24)
        $btnAddRow.Tag = $section
        $btnAddRow.Add_Click({
            Sync-CollectDataDefsFromControls
            $this.Tag.Rows.Add([PSCustomObject]@{ OrgName = ""; NewName = "" })
            Update-CommonSettingsFields
        })
        $grp.Controls.Add($btnAddRow)
        $y += 36
    }

    $spacer = New-Object System.Windows.Forms.Panel
    $spacer.Dock = [System.Windows.Forms.DockStyle]::Top
    $spacer.Height = 10
    $settingsCommonFieldPanel.Controls.Add($grp)
    $settingsCommonFieldPanel.Controls.SetChildIndex($grp, 0)
    $settingsCommonFieldPanel.Controls.Add($spacer)
    $settingsCommonFieldPanel.Controls.SetChildIndex($spacer, 1)
}

function Save-CollectDataDefs {
    Sync-CollectDataDefsFromControls
    $text = ConvertTo-CollectDataDefsText -Sections $script:collectDataDefsSections
    [System.IO.File]::WriteAllText($collectDataDefsPath, $text, (New-Object System.Text.UTF8Encoding($false)))
}

function Update-CommonSettingsFields {
    $scrollX = -$settingsCommonFieldPanel.AutoScrollPosition.X
    $scrollY = -$settingsCommonFieldPanel.AutoScrollPosition.Y

    Render-SettingsFields -Panel $settingsCommonFieldPanel -Rows (Get-CommonSettingsFieldRows) -TextBoxes $script:settingsCommonFieldTextBoxes `
        -GroupLabels $settingsGroupLabels -VarLabels $settingsVarLabels -ToolTip $settingsToolTip -RootPath $rootPath -EnvResolver $script:commonEnvResolver `
        -MultilineVars $settingsMultilineVars -MaskedVars $settingsMaskedVars -FolderBrowseVars $settingsFolderBrowseVars -FileBrowseVars $settingsFileBrowseVars | Out-Null
    Add-CollectDataDefsEditor

    $settingsCommonFieldPanel.AutoScrollPosition = New-Object System.Drawing.Point($scrollX, $scrollY)
}

function Update-GroupSettingsFields {
    $scrollX = -$settingsGroupFieldPanel.AutoScrollPosition.X
    $scrollY = -$settingsGroupFieldPanel.AutoScrollPosition.Y

    $target = $cmbSettingsGroupTarget.SelectedItem
    Render-SettingsFields -Panel $settingsGroupFieldPanel -Rows (Get-GroupSettingsFieldRows -GroupName $target) -TextBoxes $script:settingsGroupFieldTextBoxes -TrailingButtonVars $settingsTrailingButtonVars `
        -GroupLabels $settingsGroupLabels -VarLabels $settingsVarLabels -ToolTip $settingsToolTip -RootPath $rootPath -EnvResolver $script:commonEnvResolver `
        -MultilineVars $settingsMultilineVars -MaskedVars $settingsMaskedVars -FolderBrowseVars $settingsFolderBrowseVars -FileBrowseVars $settingsFileBrowseVars `
        -MentionGroupCombo $cmbSettingsGroupTarget -MentionTypeOptions $mentionTypeOptions | Out-Null

    $settingsGroupFieldPanel.AutoScrollPosition = New-Object System.Drawing.Point($scrollX, $scrollY)
}

function Test-KintoneConnection {
    param([string]$ReportGroup, [string]$FieldName, [switch]$ThrowOnError)

    $kintoneSubdomain = Get-GroupSettingsFieldValue "AUTH_KintoneSubdomain"
    $kintoneLoginName = Get-GroupSettingsFieldValue "AUTH_KintoneLoginName"
    $kintonePassword = Get-GroupSettingsFieldValue "AUTH_KintonePassword"
    $targetAppIdsValue = Get-GroupSettingsFieldValue $FieldName
    $targetAppIds = @($targetAppIdsValue -split '[,\s]+' | Where-Object { $_ })

    $validationError = if ($targetAppIds.Count -eq 0) { "同期対象のアプリIDが未入力です。" } else { $null }

    Invoke-TestAction -DialogTitle "テスト接続" -ValidationError $validationError `
        -Action {
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
        }.GetNewClosure() `
        -FormatSuccessMessage { param($response) $response } `
        -FormatFailureMessage { param($ErrorRecord) $ErrorRecord.Exception.Message } -ThrowOnError:$ThrowOnError
}

function Save-CommonSettings {
    $path = Join-Path $basePath "common-env.bat"

    $reportVarKeyMap = @{}
    foreach ($rt in (Get-ReportTypeDefs)) {
        foreach ($varName in $commonReportVars) {
            $reportVarKeyMap["$varName$($rt.Suffix)"] = "$($rt.Prefix)_$varName"
        }
    }

    $newLines = foreach ($line in [System.IO.File]::ReadAllLines($path, $script:cp932Encoding)) {
        $m = $script:groupBatLineRegex.Match($line.Trim())
        if ($m.Success -and ($commonSettingsVars -contains $m.Groups["var"].Value)) {
            $varName = $m.Groups["var"].Value
            $val = Get-CommonSettingsFieldValue $varName
            "set `"$varName=$val`""
        } elseif ($m.Success -and $reportVarKeyMap.ContainsKey($m.Groups["var"].Value)) {
            $rawVarName = $m.Groups["var"].Value
            $val = Get-CommonSettingsFieldValue $reportVarKeyMap[$rawVarName]
            "set `"$rawVarName=$val`""
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

    $groupLines = @("@echo off", "")
    foreach ($varName in $authVars) {
        $val = Get-GroupSettingsFieldValue "AUTH_$varName"
        $groupLines += "set `"$varName=$val`""
    }
    $groupLines += "set `"Authorization=$authorizationValue`""
    $groupLines += "set `"BaseUrl=https://%KintoneSubdomain%.cybozu.com`""
    $groupLines += ""
    Sync-MentionRowsFromControls
    foreach ($varName in $postVars) {
        $val = if ($varName -eq "MentionUserCodes") {
            ConvertTo-MentionUserCodesText -Rows $script:mentionRows
        } else {
            Get-GroupSettingsFieldValue "POST_$varName"
        }
        if ($settingsMultilineVars -contains $varName) { $val = $val -replace "`r`n", '\n' -replace "`n", '\n' }
        $groupLines += "set `"$varName=$val`""
    }
    $groupLines += ""
    foreach ($varName in $syncUserMasterVars) {
        $val = Get-GroupSettingsFieldValue "SYNC_$varName"
        $groupLines += "set `"$varName=$val`""
    }
    foreach ($rt in (Get-ReportTypeDefs)) {
        $groupLines += ""
        foreach ($varName in $groupReportVars) {
            $val = Get-GroupSettingsFieldValue "$($rt.Prefix)_$varName"
            $groupLines += "set `"$varName$($rt.Suffix)=$val`""
        }
    }
    $groupLines += ""
    [System.IO.File]::WriteAllText((Get-GroupBatPath $GroupName), (($groupLines -join "`r`n") + "`r`n"), $script:cp932Encoding)

    $xlsxPath = Get-GroupXlsxPath $GroupName
    if (!(Test-Path -LiteralPath $xlsxPath)) {
        $templateXlsxPath = Join-Path $clientsTemplateDir "client.xlsx"
        if (Test-Path -LiteralPath $templateXlsxPath) {
            Copy-Item -LiteralPath $templateXlsxPath -Destination $xlsxPath
        }
    }
}

function Update-GroupComboBoxItems {
    param([System.Windows.Forms.ComboBox]$ComboBox, [array]$Options)
    if (-not $ComboBox) { return }
    $selectedValue = if ($ComboBox.SelectedItem) { "$($ComboBox.SelectedItem.Value)" } else { "" }
    $ComboBox.Items.Clear()
    foreach ($opt in $Options) { $ComboBox.Items.Add($opt) | Out-Null }
    $matchedOption = $Options | Where-Object { "$($_.Value)" -eq $selectedValue } | Select-Object -First 1
    if ($matchedOption) {
        $ComboBox.SelectedItem = $matchedOption
    } elseif ($ComboBox.Items.Count -gt 0) {
        $ComboBox.SelectedIndex = 0
    }
}

function Update-GroupDropdowns {
    $script:groupOptions = @([PSCustomObject]@{ Text = "すべて"; Value = "" })
    foreach ($groupName in (Get-GroupNames)) {
        $script:groupOptions += [PSCustomObject]@{ Text = $groupName; Value = $groupName }
    }

    Update-GroupComboBoxItems -ComboBox $cmbBatchGroup -Options $script:groupOptions
    foreach ($cd in $categoryDefs) {
        foreach ($bd in $cd.ButtonDefs) {
            if ($bd.InputControls -and $bd.InputControls.ContainsKey("TargetGroupNameFilter")) {
                Update-GroupComboBoxItems -ComboBox $bd.InputControls["TargetGroupNameFilter"] -Options $script:groupOptions
            }
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

$lnkSettingsGroupOpenXlsx.Add_LinkClicked({
    $target = $cmbSettingsGroupTarget.SelectedItem
    if (!$target) {
        [System.Windows.Forms.MessageBox]::Show("対象グループが選択されていません。", "受講生データを開く", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        return
    }
    Open-TargetOrWarn -Path (Get-GroupXlsxPath $target)
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
