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
    $rootPath = Split-Path $scriptDir -Parent
} else {
    $rootPath = Split-Path ([System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName)
}
$scriptDir = Join-Path $rootPath "bats"

$libraryDir = Join-Path $scriptDir "library"
Get-ChildItem -Path $libraryDir -Filter *.ps1 -Recurse | ForEach-Object {
    . $_.FullName
}

$env:GUI_LOG_MODE = "1"

$createDailyReportBat = Join-Path $scriptDir "create-daily-report.bat"
$createPulseSurveyBat = Join-Path $scriptDir "create-pulse-survey.bat"
$collectAppDataBat = Join-Path $scriptDir "collect-app-data.bat"
$checkAlertBat = Join-Path $scriptDir "check-alert.bat"
$postAlertResultBat = Join-Path $scriptDir "post-alert-result.bat"
$syncKintoneToSheetBat = Join-Path $scriptDir "sync-kintone-to-sheet.bat"

$commonEnvBat = Join-Path $scriptDir "common.bat"

$clientsDir = Join-Path $rootPath "clients"

function Get-GroupNames {
    if (!(Test-Path -LiteralPath $clientsDir)) { return @() }
    $names = Get-ChildItem -LiteralPath $clientsDir -Filter "*.xlsx" -File -ErrorAction SilentlyContinue | ForEach-Object {
        [System.IO.Path]::GetFileNameWithoutExtension($_.Name)
    }
    return @($names | Select-Object -Unique | Sort-Object)
}

$blankOptions = @([PSCustomObject]@{ Text = ""; Value = "" })

$defaultTargetDate = (Get-Date).ToString("yyyy-MM-dd")
$dateAndGroupInputs = @(
    [PSCustomObject]@{ Name = "TargetDate"; Label = "対象日"; Default = $defaultTargetDate; LabelWidth = 150; InputWidth = 150 }
    [PSCustomObject]@{ Name = "TargetGroupNameFilter"; Label = "対象のグループ"; Default = ""; LabelWidth = 150; InputWidth = 150; Options = $blankOptions }
)
$categoryDefs = @(
    [PSCustomObject]@{
        Label = "アプリデータ作成"
        ButtonDefs = @(
            [PSCustomObject]@{ Label = "業務日誌"; BatchLabel = "アプリデータ作成-業務日誌"; IncludeInBatch = $true; BatchPath = $createDailyReportBat; OpenTarget = Get-ResolvedVar "OutputReportDir" $commonEnvBat; Inputs = $dateAndGroupInputs }
            [PSCustomObject]@{ Label = "パルスサーベイ"; BatchLabel = "アプリデータ作成-パルスサーベイ"; IncludeInBatch = $true; BatchPath = $createPulseSurveyBat; OpenTarget = Get-ResolvedVar "OutputReportDir" $commonEnvBat; Inputs = $dateAndGroupInputs }
        )
    }
    [PSCustomObject]@{
        Label = "アプリデータ集計"
        ButtonDefs = @(
            [PSCustomObject]@{ Label = "業務日誌・パルスサーベイ"; BatchLabel = "アプリデータ集計-業務日誌・パルスサーベイ"; IncludeInBatch = $true; BatchPath = $collectAppDataBat; OpenTarget = Get-ResolvedVar "OutputCollectDataRootDir" $commonEnvBat; Inputs = $dateAndGroupInputs }
        )
    }
    [PSCustomObject]@{
        Label = "アラート集計"
        ButtonDefs = @(
            [PSCustomObject]@{ Label = "業務日誌・パルスサーベイ"; BatchLabel = "アラート集計-業務日誌・パルスサーベイ"; IncludeInBatch = $true; BatchPath = $checkAlertBat; OpenTarget = Get-ResolvedVar "OutputAlertRootDir" $commonEnvBat; Inputs = $dateAndGroupInputs }
            [PSCustomObject]@{ Label = "投稿"; BatchLabel = "アラート集計-投稿"; IncludeInBatch = $true; BatchPath = $postAlertResultBat; OpenTarget = { param($ic) if ($ic -and $ic.ContainsKey("TargetGroupNameFilter")) { $groupValue = Get-InputValue -Control $ic["TargetGroupNameFilter"] } else { $groupValue = "" }; Get-GroupKintoneThreadUrl -GroupName $groupValue -ClientsDir $clientsDir }; Inputs = $dateAndGroupInputs }
        )
    }
)

$form = New-Form -Title "kintoneデータ集計ツール" -Width 780 -Height 560 -MinWidth 600 -MinHeight 400 -CenterScreen
$script:currentProc = $null

$tabControl = New-TabControl
$tabRun = New-TabPage -Text "実行"
$tabLogs = New-TabPage -Text "ログ"
$tabSettings = New-TabPage -Text "設定"

$tabControl.Controls.AddRange(@($tabRun, $tabLogs, $tabSettings))
$form.Controls.Add($tabControl)


$execTabControl = New-TabControl

$allButtonDefs = @()
foreach ($cd in $categoryDefs) {
    foreach ($bd in $cd.ButtonDefs) {
        if ($bd.IncludeInBatch -ne $false) { $allButtonDefs += $bd }
    }
}

$tabBatchAll = New-TabPage -Text "一括実行"
$execTabControl.Controls.Add($tabBatchAll)

$batchTab = New-BatchRunTab -TabPage $tabBatchAll -ButtonDefs $allButtonDefs `
    -Inputs @(
        [PSCustomObject]@{ Name = "TargetDate"; Label = "対象日"; Default = $defaultTargetDate; LabelWidth = 150; InputWidth = 150 }
        [PSCustomObject]@{ Name = "TargetGroupNameFilter"; Label = "対象のグループ"; Options = $blankOptions; LabelWidth = 150; InputWidth = 150 }
    ) `
    -OnOpenClick {
        param($target)
        Open-TargetOrWarn -Path $target
    } `
    -OnRunClick { Invoke-ExecuteAll }

function Set-RunButtonsEnabled {
    param([bool]$Enabled)
    Set-ButtonsEnabled -Buttons $categoryTab.RunButtons -Enabled $Enabled
    Set-ButtonsEnabled -Buttons @($batchTab.RunButton) -Enabled $Enabled
}

function Invoke-ExecuteAll {
    Invoke-BatchRunAll -ButtonDefs $allButtonDefs -CheckBoxes $batchTab.CheckBoxes `
        -StatusLabel $batchTab.StatusLabel -StatusLabels $batchTab.StatusLabels -ExtraControls @($batchTab.InputControls.Values) `
        -WriteLog { param($msg) Write-Log $msg } -SetRunButtonsEnabled { param($e) Set-RunButtonsEnabled $e } `
        -InvokeStep {
            param($bd)
            Invoke-BatchStep -ButtonDef $bd -WorkingDirectory $scriptDir -Form $form `
                -WriteLog { param($msg) Write-Log $msg } -CurrentProcessRef ([ref]$script:currentProc) `
                -GetBatArgs {
                    param($bd)
                    $batArgs = @()
                    foreach ($inputDef in $bd.Inputs) {
                        $value = Get-InputValue -Control $batchTab.InputControls[$inputDef.Name]
                        $batArgs += "-$($inputDef.Name):$value"
                    }
                    return $batArgs
                }
        }
}

$categoryTab = New-CategoryTabControl -TabControl $execTabControl -CategoryDefs $categoryDefs -OnRunClick {
    param($bd)
    Invoke-BatButton -ButtonDef $bd -WorkingDirectory $scriptDir -Form $form `
        -WriteLog { param($msg) Write-Log $msg } -SetRunButtonsEnabled { param($e) Set-RunButtonsEnabled $e } `
        -CurrentProcessRef ([ref]$script:currentProc) `
        -GetBatArgs {
            param($bd)
            $batArgs = @()
            $inputMap = $bd.InputControls
            if ($inputMap) {
                foreach ($inputDef in $bd.Inputs) {
                    $value = Get-InputValue -Control $inputMap[$inputDef.Name]
                    $batArgs += "-$($inputDef.Name):$value"
                }
            }
            return $batArgs
        }
}

$execTabControl.Height = 45 + $batchTab.Panel.Height


$txtLog = New-LogTextBox

Add-StackedDockedControls -Container $tabRun -ControlsTopToBottom @($execTabControl, $txtLog)


$syncMasterButtonDef = [PSCustomObject]@{
    Label            = "マスター同期"
    BatchPath = $syncKintoneToSheetBat
}
$allButtonDefsForLog = @($categoryDefs | ForEach-Object { $_.ButtonDefs }) + @($syncMasterButtonDef)

$logTabConditions = @(
    @{ PropertyName = "GroupCombo"; LabelText = "対象のグループ"; LabelWidth = 150; ComboWidth = 150; Options = $blankOptions }
)

$logTab = New-LogTab -TabPage $tabLogs -ButtonDefs $allButtonDefsForLog `
    -LabelFn { param($bd) Get-BatchDisplayLabel -ButtonDef $bd } `
    -Conditions $logTabConditions `
    -GetLogPathFn { Get-ResolvedVar "CommonLogPath" $commonEnvBat }

$clientsTemplateDir = Join-Path $clientsDir "template"

function Get-GroupXlsxPath { param([string]$GroupName) Join-Path $clientsDir "$GroupName.xlsx" }

$commonEnvResolver = { param($name) Get-ResolvedVar $name $commonEnvBat }

$groupReportVars = @("TargetAppIds")
$commonReportVars = @("TargetDateCodeField", "TargetUserCodeField")
$syncUserMasterVars = @("SyncUserMasterAppId", "SyncUserMasterSheetName")

function Get-ReportTypeDefs {
    $types = @()
    foreach ($key in (Get-SetEnvDefaults -Path $commonEnvBat).Keys) {
        if ($key -notmatch '^SourceType(_.+)$') { continue }
        $suffix = $Matches[1]
        $types += [PSCustomObject]@{
            Prefix = $suffix.TrimStart('_')
            Suffix = $suffix
            Label  = Get-ResolvedVar $key $commonEnvBat
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
            "CommonLogPath"                  = @{ Label = "ログの出力先"; Browse = "Folder" }
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
            "CommentTextTemplate" = @{ Label = "投稿コメント文言"; Width=400; Multiline = $true }
            "CommentSummaryTemplate" = @{ Label = "投稿集計文言"; Width=400; Multiline = $true }
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
$settingsWidthVars = @{}
foreach ($groupKey in $settingsGroups.Keys) {
    $settingsGroupLabels[$groupKey] = $settingsGroups[$groupKey].Label
    foreach ($varKey in $settingsGroups[$groupKey].Vars.Keys) {
        $varDef = $settingsGroups[$groupKey].Vars[$varKey]
        $settingsVarLabels[$varKey] = $varDef.Label
        if ($varDef.Browse -eq "Folder") { $settingsFolderBrowseVars += $varKey }
        if ($varDef.Browse -eq "File") { $settingsFileBrowseVars += $varKey }
        if ($varDef.Masked) { $settingsMaskedVars += $varKey }
        if ($varDef.Multiline) { $settingsMultilineVars += $varKey }
        if ($varDef.Width) { $settingsWidthVars[$varKey] = $varDef.Width }
    }
}
$settingsTrailingButtonVars = @{
    "TargetAppIds"        = { param($Panel, $Y, $Field) Add-FieldActionButton -Panel $Panel -Y $Y -Text "テスト接続" -AddStatusLabel -OnClick {
        Invoke-ActionWithUpdateStatus -StatusLabel $Field.StatusLabel -Action {
            Test-KintoneConnectionFromSettings -ReportGroup $Field.Group -FieldName "$($Field.Group)_TargetAppIds" | Out-Null
        }
    }.GetNewClosure() }
    "SyncUserMasterAppId" = { param($Panel, $Y, $Field) Add-FieldActionButton -Panel $Panel -Y $Y -Text "テスト接続" -AddStatusLabel -OnClick {
        Invoke-ActionWithUpdateStatus -StatusLabel $Field.StatusLabel -Action {
            Test-KintoneConnectionFromSettings -ReportGroup "SYNC" -FieldName "SYNC_SyncUserMasterAppId" | Out-Null
        }
    }.GetNewClosure() }
    "KintonePassword" = { param($Panel, $Y, $Field) Add-FieldActionButton -Panel $Panel -Y $Y -Text "テスト接続" -AddStatusLabel -OnClick {
        Invoke-ActionWithUpdateStatus -StatusLabel $Field.StatusLabel -Action {
            $kintoneSubdomain = (Get-GroupSettingsFieldValue "AUTH_KintoneSubdomain").Trim()
            $kintoneLoginName = Get-GroupSettingsFieldValue "AUTH_KintoneLoginName"
            $kintonePassword = Get-GroupSettingsFieldValue "AUTH_KintonePassword"
            if (!$kintoneSubdomain -or !$kintoneLoginName -or !$kintonePassword) {
                throw "サブドメイン・ログイン名・パスワードをすべて入力してください。"
            }
            Test-KintoneConnection -Subdomain $kintoneSubdomain -LoginName $kintoneLoginName -Password $kintonePassword
        }
    }.GetNewClosure() }
    "CommentSummaryTemplate" = { param($Panel, $Y, $Field) Add-FieldActionButton -Panel $Panel -Y $Y -Text "テスト投稿" -AddStatusLabel -OnClick {
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
            Add-KintoneThreadComment -SpaceId $spaceId -ThreadId $threadId -Text "【テスト投稿】kintoneデータ集計ツールの設定確認用コメントです。不要であれば削除してください。" -Mentions $mentions -BaseUrl $baseUrl -Authorization $authorization | Out-Null
        }
    }.GetNewClosure() -OnOpenClick {
        $subdomain = (Get-GroupSettingsFieldValue "AUTH_KintoneSubdomain").Trim()
        $spaceId = (Get-GroupSettingsFieldValue "POST_SpaceId").Trim()
        $threadId = (Get-GroupSettingsFieldValue "POST_ThreadId").Trim()
        $threadUrl = if ($subdomain -and $spaceId -and $threadId) { "https://$subdomain.cybozu.com/k/#/space/$spaceId/thread/$threadId" } else { $null }
        Open-TargetOrWarn -Path $threadUrl
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

$settingsSubTabControl = New-TabControl -Dock ([System.Windows.Forms.DockStyle]::Fill)
$tabSettings.Controls.Add($settingsSubTabControl)

$tabSettingsCommon = New-TabPage -Text "共通"
$settingsSubTabControl.Controls.Add($tabSettingsCommon)

$tabSettingsGroup = New-TabPage -Text "グループ別"
$settingsSubTabControl.Controls.Add($tabSettingsGroup)

$tabSettingsMaster = New-TabPage -Text "マスター操作"
$settingsSubTabControl.Controls.Add($tabSettingsMaster)

$settingsToolTip = New-ToolTip

function Get-CommonSettingsFiles {
    return @(
        [PSCustomObject]@{ Path = $commonEnvBat; Save = { Save-CommonSettings }; Reload = {} }
        [PSCustomObject]@{ Path = $collectDataDefsPath; Save = { Save-CollectDataDefs }; Reload = { $script:collectDataDefsItems = @() } }
    )
}

$settingsCommonTopPanel = (New-SettingsTopPanel `
    -OnSave { foreach ($f in (Get-CommonSettingsFiles)) { & $f.Save }; Update-CommonSettingsFields } `
    -OnReload { foreach ($f in (Get-CommonSettingsFiles)) { & $f.Reload }; Update-CommonSettingsFields }).Panel

$settingsCommonBottomPanel = New-Panel -Dock ([System.Windows.Forms.DockStyle]::Fill) -AutoScroll

$tabSettingsCommon.Controls.Add($settingsCommonBottomPanel)
$tabSettingsCommon.Controls.Add($settingsCommonTopPanel)

$settingsCommonFieldTextBoxes = @{}
$settingsGroupFieldTextBoxes = @{}

function Get-CommonSettingsFieldValue {
    param([string]$Key)
    if ($settingsCommonFieldTextBoxes.ContainsKey($Key)) {
        return $settingsCommonFieldTextBoxes[$Key].Text
    }
    return ""
}

function Get-GroupSettingsFieldValue {
    param([string]$Key)
    if ($settingsGroupFieldTextBoxes.ContainsKey($Key)) {
        return $settingsGroupFieldTextBoxes[$Key].Text
    }
    return ""
}

function Get-GroupSettingsFiles {
    param([string]$GroupName)
    return @(
        [PSCustomObject]@{ Path = (Get-GroupBatPath $GroupName $clientsDir); Save = { Save-GroupSettings -GroupName $GroupName }.GetNewClosure(); Reload = {} }
    )
}

$settingsGroupTop = (New-SettingsTopPanel `
    -ExtraControlDefs @(
        [PSCustomObject]@{ Name = "GroupTargetLabel"; Kind = "Label"; Text = "対象のグループ"; Width = 150 }
        [PSCustomObject]@{ Name = "GroupTarget"; Kind = "Combo"; Width = 150; OnChange = { Update-GroupSettingsFields } }
        [PSCustomObject]@{ Name = "NewGroup"; Kind = "Button"; Text = "新規作成"; Width = 140; OnClick = {
            Add-Type -AssemblyName Microsoft.VisualBasic
            $newName = [Microsoft.VisualBasic.Interaction]::InputBox("グループ名を入力してください", "グループの新規作成", "")
            $newName = $newName.Trim()
            if (!$newName) { return }

            if ($settingsGroupTop.Controls["GroupTarget"].Items.Contains($newName) -or (Test-Path -LiteralPath (Get-GroupXlsxPath $newName)) -or (Test-Path -LiteralPath (Get-GroupBatPath $newName $clientsDir))) {
                [System.Windows.Forms.MessageBox]::Show("「$newName」は既に存在します。", "グループの新規作成", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
                return
            }

            $settingsGroupTop.Controls["GroupTarget"].Items.Add([PSCustomObject]@{ Text = $newName; Value = $newName }) | Out-Null
            $settingsGroupTop.Controls["GroupTarget"].SelectedItem = $settingsGroupTop.Controls["GroupTarget"].Items[-1]
        } }
    ) `
    -OnSave {
        $target = Get-ComboBoxValue -SelectedItem $settingsGroupTop.Controls["GroupTarget"].SelectedItem
        if (!$target) { return }
        foreach ($f in (Get-GroupSettingsFiles -GroupName $target)) { & $f.Save }
        Update-GroupSettingsFields
        Update-GroupDropdowns
    } `
    -OnReload {
        $target = Get-ComboBoxValue -SelectedItem $settingsGroupTop.Controls["GroupTarget"].SelectedItem
        foreach ($f in (Get-GroupSettingsFiles -GroupName $target)) { & $f.Reload }
        Update-GroupSettingsFields
    })

$settingsGroupBottomPanel = New-Panel -Dock ([System.Windows.Forms.DockStyle]::Fill) -AutoScroll

$tabSettingsGroup.Controls.Add($settingsGroupBottomPanel)
$tabSettingsGroup.Controls.Add($settingsGroupTop.Panel)

$settingsMasterTop = (New-SettingsTopPanel `
    -ExtraControlDefs @(
        [PSCustomObject]@{ Name = "GroupTargetLabel"; Kind = "Label"; Text = "対象のグループ"; Width = 150 }
        [PSCustomObject]@{ Name = "GroupTarget"; Kind = "Combo"; Width = 150; OnChange = {
            $target = Get-ComboBoxValue -SelectedItem $settingsMasterTop.Controls["GroupTarget"].SelectedItem
            Read-ScheduleExcelData -GroupName $target
        } }
        [PSCustomObject]@{ Name = "OpenXlsx"; Kind = "Link"; Text = "開く"; OnClick = {
            $target = Get-ComboBoxValue -SelectedItem $settingsMasterTop.Controls["GroupTarget"].SelectedItem
            $xlsxPath = Get-GroupXlsxPath $target
            Open-TargetOrWarn -Path $xlsxPath
        } }
    ) `
    -OnSave { Save-ScheduleToExcel } `
    -OnReload {
        $target = Get-ComboBoxValue -SelectedItem $settingsMasterTop.Controls["GroupTarget"].SelectedItem
        Read-ScheduleExcelData -GroupName $target
    })

$settingsMasterBottomPanel = New-Panel -Dock ([System.Windows.Forms.DockStyle]::Fill) -AutoScroll

$tabSettingsMaster.Controls.Add($settingsMasterBottomPanel)
$tabSettingsMaster.Controls.Add($settingsMasterTop.Panel)

$grpUserMasterSync = New-GroupBox -Text "ユーザーマスター同期" -Dock ([System.Windows.Forms.DockStyle]::Top) -AutoSize -Padding 10

$btnMasterSyncExecute = New-Button -Text "同期実行" -X 20 -Y 30 -Width 100 -Height 24
$btnMasterSyncExecute.Add_Click({
    try {
        $batchPath = $syncKintoneToSheetBat
        $groupName = Get-ComboBoxValue -SelectedItem $settingsMasterTop.Controls["GroupTarget"].SelectedItem
        Invoke-ActionWithUpdateStatus -StatusLabel $lblMasterStatusPlaceholder -Action {
            $matchingItem = $settingsGroupTop.Controls["GroupTarget"].Items | Where-Object { (Get-ComboBoxValue -SelectedItem $_) -eq $groupName } | Select-Object -First 1
            if ($matchingItem) { $settingsGroupTop.Controls["GroupTarget"].SelectedItem = $matchingItem }
            Update-GroupSettingsFields
            $syncAppId = Get-GroupSettingsFieldValue "SYNC_SyncUserMasterAppId"
            $syncSheetName = Get-GroupSettingsFieldValue "SYNC_SyncUserMasterSheetName"
            if ([string]::IsNullOrWhiteSpace($syncAppId)) {
                throw "対象アプリIDが入力されていません"
            }
            $batArgs = @("-TargetGroupNameFilter:$groupName", "-SyncUserMasterAppId:$syncAppId", "-SyncUserMasterSheetName:$syncSheetName")
            $exitCode = Invoke-BatProcess -BatPath $batchPath -WorkingDirectory $scriptDir -BatArgs $batArgs
            if ($exitCode -ne 0) {
                throw "同期処理に失敗しました（$($syncAppId)）"
            }
        }
    } catch {
        [System.Windows.Forms.MessageBox]::Show("エラーが発生しました: $_", "エラー", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    }
})
$grpUserMasterSync.Controls.Add($btnMasterSyncExecute)

$lblMasterStatusPlaceholder = New-Label -X 130 -Y 30 -Width 500 -Height 24 -TextAlign ([System.Drawing.ContentAlignment]::MiddleLeft)
$grpUserMasterSync.Controls.Add($lblMasterStatusPlaceholder)

function Get-CommonSettingsFieldRows {
    $raw = Get-SetLineRawValues -Path $commonEnvBat
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
    $rawGroup = Get-SetLineRawValues -Path (Get-GroupBatPath $GroupName $clientsDir)

    foreach ($varName in $authVars) {
        $value = if ($rawGroup.ContainsKey($varName)) { $rawGroup[$varName] } else { $templateDefaults.Auth[$varName] }
        [PSCustomObject]@{ Key = "AUTH_$varName"; VarName = $varName; Group = "AUTH"; Value = $value }
    }
    foreach ($varName in $postVars) {
        $value = if ($rawGroup.ContainsKey($varName)) { $rawGroup[$varName] } else { $templateDefaults.Auth[$varName] }
        [PSCustomObject]@{ Key = "POST_$varName"; VarName = $varName; Group = "POST"; Value = $value }
    }
    foreach ($rt in (Get-ReportTypeDefs)) {
        $rawForType = Get-SuffixedRawValues -RawValues $rawGroup -Suffix $rt.Suffix -VarNames $groupReportVars
        $defaultsForType = $templateDefaults.ByType[$rt.Prefix]
        foreach ($varName in $groupReportVars) {
            $value = if ($rawForType.ContainsKey($varName)) { $rawForType[$varName] } else { $defaultsForType[$varName] }
            [PSCustomObject]@{ Key = "$($rt.Prefix)_$varName"; VarName = $varName; Group = $rt.Prefix; Value = $value }
        }
    }
    foreach ($varName in $syncUserMasterVars) {
        $value = if ($rawGroup.ContainsKey($varName)) { $rawGroup[$varName] } else { $templateDefaults.Sync[$varName] }
        [PSCustomObject]@{ Key = "SYNC_$varName"; VarName = $varName; Group = "SYNC"; Value = $value }
    }
}

$mentionTypeOptions = @("USER", "GROUP", "ORGANIZATION")

$collectDataDefsPath = Join-Path $scriptDir "collect-data-defs.json"
$script:collectDataDefsItems = @()
$script:collectDataDefsRowControls = @()

function Sync-CollectDataDefsFromControls {
    foreach ($entry in $script:collectDataDefsRowControls) {
        $entry.Item.orgName = $entry.OrgBox.Text
        $entry.Item.newName = $entry.NewBox.Text
        if ($entry.TypeBox) {
            $entry.Item.type = $entry.TypeBox.SelectedItem.Value
        }
    }
}

function New-CollectDataDefsEditor {
    if ($script:collectDataDefsItems.Count -eq 0) {
        if (Test-Path -LiteralPath $collectDataDefsPath) {
            $json = Get-Content -Path $collectDataDefsPath -Encoding UTF8 | ConvertFrom-Json
            $script:collectDataDefsItems = if ($json -is [array]) { $json } else { @($json) }
        }
    }
    $script:collectDataDefsRowControls = @()

    $grp = New-GroupBox -Text "アプリデータ集計の列定義" -Dock ([System.Windows.Forms.DockStyle]::Top) -AutoSize
    $typeOptions = @(Get-ReportTypeDefs | ForEach-Object { [PSCustomObject]@{ Text = $_.Label; Value = $_.Prefix; Display = $_.Label } })

    $y = 25
    $lblTypeHeader = New-Label -Text "タイプ" -X 20 -Y $y -Width 100 -Height 18
    $grp.Controls.Add($lblTypeHeader)
    $lblOrgHeader = New-Label -Text "変更前" -X 130 -Y $y -Width 140 -Height 18
    $grp.Controls.Add($lblOrgHeader)

    $lblNewHeader = New-Label -Text "変更後" -X 280 -Y $y -Width 140 -Height 18
    $grp.Controls.Add($lblNewHeader)
    $y += 20

    foreach ($item in @($script:collectDataDefsItems)) {
        $cmbType = New-ComboBox -X 20 -Y $y -Width 100 -Height 22 -Items $typeOptions
        $cmbType.SelectedItem = $cmbType.Items | Where-Object { $_.Value -eq $item.type } | Select-Object -First 1
        $grp.Controls.Add($cmbType)

        $txtOrg = New-TextBox -X 130 -Y $y -Width 140 -Height 22
        $txtOrg.Text = "$($item.orgName)"
        $grp.Controls.Add($txtOrg)

        $txtNew = New-TextBox -X 280 -Y $y -Width 140 -Height 22
        $txtNew.Text = "$($item.newName)"
        $grp.Controls.Add($txtNew)

        $btnDeleteRow = New-Button -Text "削除" -X 430 -Y ($y - 1) -Width 60 -Height 24
        $btnDeleteRow.Tag = $item
        $btnDeleteRow.Add_Click({
            Sync-CollectDataDefsFromControls
            $ctx = $this.Tag
            $script:collectDataDefsItems = @($script:collectDataDefsItems | Where-Object { $_ -ne $ctx })
            Update-CommonSettingsFields
        })
        $grp.Controls.Add($btnDeleteRow)

        $script:collectDataDefsRowControls += [PSCustomObject]@{ Item = $item; TypeBox = $cmbType; OrgBox = $txtOrg; NewBox = $txtNew }
        $y += 26
    }

    $btnAddRow = New-Button -Text "追加" -X 20 -Y $y -Width 100 -Height 24
    $btnAddRow.Add_Click({
        Sync-CollectDataDefsFromControls
        $script:collectDataDefsItems += [PSCustomObject]@{ type = ""; orgName = ""; newName = "" }
        Update-CommonSettingsFields
    })
    $grp.Controls.Add($btnAddRow)

    return $grp
}

function Save-CollectDataDefs {
    try {
        $fileStream = [System.IO.File]::Open($collectDataDefsPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite)
        $fileStream.Close()
    } catch {
        throw "ファイルが別のプロセスで開かれています：$collectDataDefsPath"
    }
    Sync-CollectDataDefsFromControls
    $json = $script:collectDataDefsItems | ConvertTo-Json
    [System.IO.File]::WriteAllText($collectDataDefsPath, $json, (New-Object System.Text.UTF8Encoding($false)))
}

function Update-CommonSettingsFields {
    $scrollX = -$settingsCommonBottomPanel.AutoScrollPosition.X
    $scrollY = -$settingsCommonBottomPanel.AutoScrollPosition.Y

    $grp = New-CollectDataDefsEditor
    $controlsToStack = @($grp)

    Render-SettingsFields -Panel $settingsCommonBottomPanel -Rows (Get-CommonSettingsFieldRows) -TargetTextBoxes $settingsCommonFieldTextBoxes `
        -GroupLabels $settingsGroupLabels -VarLabels $settingsVarLabels -ToolTip $settingsToolTip -RootPath $rootPath -EnvResolver $commonEnvResolver `
        -MultilineVars $settingsMultilineVars -MaskedVars $settingsMaskedVars -FolderBrowseVars $settingsFolderBrowseVars -FileBrowseVars $settingsFileBrowseVars -WidthVars $settingsWidthVars -LabelWidth 150 -ExtraGrps $controlsToStack | Out-Null
    $settingsCommonBottomPanel.AutoScrollPosition = New-Object System.Drawing.Point($scrollX, $scrollY)
}

function Update-GroupSettingsFields {
    $scrollX = -$settingsGroupBottomPanel.AutoScrollPosition.X
    $scrollY = -$settingsGroupBottomPanel.AutoScrollPosition.Y

    $target = Get-ComboBoxValue -SelectedItem $settingsGroupTop.Controls["GroupTarget"].SelectedItem
    Render-SettingsFields -Panel $settingsGroupBottomPanel -Rows (Get-GroupSettingsFieldRows -GroupName $target) -TargetTextBoxes $settingsGroupFieldTextBoxes -TrailingButtonVars $settingsTrailingButtonVars `
        -GroupLabels $settingsGroupLabels -VarLabels $settingsVarLabels -ToolTip $settingsToolTip -RootPath $rootPath -EnvResolver $commonEnvResolver `
        -MultilineVars $settingsMultilineVars -MaskedVars $settingsMaskedVars -FolderBrowseVars $settingsFolderBrowseVars -FileBrowseVars $settingsFileBrowseVars -WidthVars $settingsWidthVars -LabelWidth 150 `
        -MentionGroupCombo $settingsGroupTop.Controls["GroupTarget"] -MentionTypeOptions $mentionTypeOptions | Out-Null

    $settingsGroupBottomPanel.AutoScrollPosition = New-Object System.Drawing.Point($scrollX, $scrollY)

    Register-MentionEditorHandlers -OnChange { Update-GroupSettingsFields }
}

function Test-KintoneConnectionFromSettings {
    param([string]$ReportGroup, [string]$FieldName)
    $kintoneSubdomain = Get-GroupSettingsFieldValue "AUTH_KintoneSubdomain"
    $kintoneLoginName = Get-GroupSettingsFieldValue "AUTH_KintoneLoginName"
    $kintonePassword = Get-GroupSettingsFieldValue "AUTH_KintonePassword"
    $targetAppIdsValue = Get-GroupSettingsFieldValue $FieldName
    $targetAppIds = @($targetAppIdsValue -split '[,\s]+' | Where-Object { $_ })
    if ($targetAppIds.Count -eq 0) {
        throw "対象アプリIDを入力してください。"
    }
    return Test-KintoneConnectionWithAppId -Subdomain $kintoneSubdomain -LoginName $kintoneLoginName -Password $kintonePassword -AppIds $targetAppIds
}

function Save-CommonSettings {
    $saveCommonReportVarKeyMap = @{}
    foreach ($rt in (Get-ReportTypeDefs)) {
        foreach ($varName in $commonReportVars) {
            $saveCommonReportVarKeyMap["$varName$($rt.Suffix)"] = "$($rt.Prefix)_$varName"
        }
    }

    $allVars = @() + $commonSettingsVars + @($saveCommonReportVarKeyMap.Keys)
    Save-EnvBatFile -Path $commonEnvBat -VarNames $allVars `
        -GetValueFn { param($varName)
            if ($saveCommonReportVarKeyMap.ContainsKey($varName)) {
                Get-CommonSettingsFieldValue $saveCommonReportVarKeyMap[$varName]
            } else {
                Get-CommonSettingsFieldValue $varName
            }
        } `
        -HasValueFn { param($varName)
            $true
        }
}

function Save-GroupSettings {
    param([string]$GroupName)

    $groupBatPath = Get-GroupBatPath $GroupName $clientsDir

    $saveGroupAuthVarMap = @{}
    foreach ($varName in $authVars) {
        $saveGroupAuthVarMap[$varName] = "AUTH_$varName"
    }

    $saveGroupPostVarMap = @{}
    foreach ($varName in $postVars) {
        $saveGroupPostVarMap[$varName] = "POST_$varName"
    }

    $saveGroupSyncVarMap = @{}
    foreach ($varName in $syncUserMasterVars) {
        $saveGroupSyncVarMap[$varName] = "SYNC_$varName"
    }

    $saveGroupReportVarKeyMap = @{}
    foreach ($rt in (Get-ReportTypeDefs)) {
        foreach ($varName in $groupReportVars) {
            $saveGroupReportVarKeyMap["$varName$($rt.Suffix)"] = "$($rt.Prefix)_$varName"
        }
    }

    $allVars = @() + @($saveGroupAuthVarMap.Keys) + @("Authorization", "BaseUrl") + @($saveGroupPostVarMap.Keys) + @($saveGroupSyncVarMap.Keys) + @($saveGroupReportVarKeyMap.Keys)

    Sync-MentionRowsFromControls

    Save-EnvBatFile -Path $groupBatPath -VarNames $allVars `
        -GetValueFn { param($varName)
            if ($varName -eq "Authorization") {
                $existingAuth = Get-SetLineRawValues -Path $groupBatPath
                if ($existingAuth.ContainsKey("Authorization")) { $existingAuth["Authorization"] } else { (Get-GroupTemplateDefaults).Auth["Authorization"] }
            } elseif ($varName -eq "BaseUrl") {
                "https://%KintoneSubdomain%.cybozu.com"
            } elseif ($varName -eq "MentionUserCodes") {
                ConvertTo-MentionUserCodesText -Rows $script:mentionRows
            } elseif ($saveGroupAuthVarMap.ContainsKey($varName)) {
                Get-GroupSettingsFieldValue $saveGroupAuthVarMap[$varName]
            } elseif ($saveGroupPostVarMap.ContainsKey($varName)) {
                $val = Get-GroupSettingsFieldValue $saveGroupPostVarMap[$varName]
                if ($settingsMultilineVars -contains $varName) { $val = $val -replace "`r`n", '\n' -replace "`n", '\n' }
                $val
            } elseif ($saveGroupSyncVarMap.ContainsKey($varName)) {
                Get-GroupSettingsFieldValue $saveGroupSyncVarMap[$varName]
            } elseif ($saveGroupReportVarKeyMap.ContainsKey($varName)) {
                Get-GroupSettingsFieldValue $saveGroupReportVarKeyMap[$varName]
            } else {
                ""
            }
        } `
        -HasValueFn { param($varName)
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
    $allOption = [PSCustomObject]@{ Text = "すべて"; Value = "" }
    $groupNames = @(Get-GroupNames)
    $filterItems = @($allOption) + $groupNames

    $categoryDefs.ButtonDefs | Where-Object { $_.InputControls["TargetGroupNameFilter"] } | ForEach-Object {
        Update-ComboBoxItems -ComboBox $_.InputControls["TargetGroupNameFilter"] -Items $filterItems
    }

    Update-ComboBoxItems -ComboBox $logTab.InputControls["GroupCombo"] -Items $filterItems
    Update-ComboBoxItems -ComboBox $batchTab.InputControls["TargetGroupNameFilter"] -Items $filterItems
    Update-ComboBoxItems -ComboBox $settingsGroupTop.Controls["GroupTarget"] -Items $groupNames
    Update-ComboBoxItems -ComboBox $settingsMasterTop.Controls["GroupTarget"] -Items $groupNames
}

$grpScheduleEdit = New-GroupBox -Text "スケジュール編集" -Dock ([System.Windows.Forms.DockStyle]::Top) -AutoSize -Padding 10

$script:scheduleRows = @()
$script:scheduleContentPanel = $null
$scheduleSheetDef = @{
    SheetName = "スケジュール"
    Columns = @(
        @{ Label = "通番"; Width = 50; AutoIncrement = $true }
        @{ Label = "科目名"; Width = 200; Property = "Subject" }
        @{ Label = "開始日"; Width = 100; Property = "StartDate"; IsDate = $true }
        @{ Label = "終了日"; Width = 100; Property = "EndDate"; IsDate = $true }
    )
}

$controlsToStack = @($grpUserMasterSync, (New-Panel -Height 10), $grpScheduleEdit, (New-Panel -Height 10))
Add-StackedDockedControls -Container $settingsMasterBottomPanel -ControlsTopToBottom $controlsToStack -Spacing 0

function Update-ScheduleGrid {
    $panels = New-Grid -GroupBox $grpScheduleEdit -RowDatas ([ref]$script:scheduleRows) -OnDelete {
        $deleteRowNo = $this.Tag
        $updatedRows = Read-ScheduleGridData
        $script:scheduleRows = @($updatedRows | Where-Object { $_.No -ne $deleteRowNo })
        Update-ScheduleGrid
    } -OnAdd {
        param($ContentPanel)

        $updatedRows = Read-ScheduleGridData
        $script:scheduleRows = $updatedRows

        $currentRows = @($script:scheduleRows)
        $nextNo = if ($currentRows.Count -gt 0) { ($currentRows | Select-Object -Last 1).No + 1 } else { 1 }
        $newObj = [ordered]@{ No = $nextNo }
        foreach ($col in $scheduleSheetDef.Columns | Where-Object { $_.Property }) {
            $newObj[$col.Property] = ""
        }
        $newRow = [PSCustomObject]$newObj
        $script:scheduleRows = @($script:scheduleRows) + @($newRow)
        Update-ScheduleGrid
    } -Columns $scheduleSheetDef.Columns
    $script:scheduleContentPanel = $panels.ContentPanel
}

function Read-ScheduleGridData {
    Read-GridData -ContentPanel $script:scheduleContentPanel -Columns $scheduleSheetDef.Columns
}

function Read-ScheduleExcelData {
    param([string]$GroupName)

    $xlsxPath = Get-GroupXlsxPath $GroupName

    try {
        $scheduleTransformer = {
            param($Rows)
            $convertedRows = @()
            foreach ($row in $Rows) {
                $newObj = [ordered]@{ No = @($convertedRows).Count + 1 }
                foreach ($col in $scheduleSheetDef.Columns | Where-Object { $_.Property }) {
                    $value = $row."$($col.Label)"
                    if ($col.IsDate -and $value -and [double]::TryParse($value, [ref]$null)) {
                        $value = ([datetime]::FromOADate([double]$value)).ToString("yyyy-MM-dd")
                    }
                    $newObj[$col.Property] = $value
                }
                $convertedRows += [PSCustomObject]$newObj
            }
            @($convertedRows)
        }

        $script:scheduleRows = Read-ExcelData `
            -ExcelPath $xlsxPath `
            -SheetName $scheduleSheetDef.SheetName `
            -DataTransformer $scheduleTransformer
        Update-ScheduleGrid
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show("スケジュール読込に失敗しました: $_", "エラー", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    }
}

function Save-ScheduleToExcel {
    $groupName = Get-ComboBoxValue -SelectedItem $settingsMasterTop.Controls["GroupTarget"].SelectedItem
    $xlsxPath = Get-GroupXlsxPath $groupName
    try {
        $rowsFromUI = @(Read-ScheduleGridData)
        Save-DataToExcel -ExcelPath $xlsxPath -SheetDef $scheduleSheetDef -Datas $rowsFromUI
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show("保存に失敗しました: $_", "エラー", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    }
}


$settingsSubTabControl.Add_SelectedIndexChanged({
    if ($settingsSubTabControl.SelectedTab -eq $tabSettingsCommon) {
        Update-CommonSettingsFields
    } elseif ($settingsSubTabControl.SelectedTab -eq $tabSettingsGroup) {
        Update-GroupSettingsFields
    }
})

$tabControl.Add_SelectedIndexChanged({
    if ($tabControl.SelectedTab -eq $tabLogs) {
        Update-LogView -LogTab $logTab
    }
})

$execTabControl.SelectedTab = $tabBatchAll
$tabControl.SelectedTab = $tabRun

$form.Add_Shown({
    Update-CommonSettingsFields
    Update-GroupDropdowns
    Update-TabHeight -NestedTabControl $execTabControl
})

[System.Windows.Forms.Application]::Run($form)

