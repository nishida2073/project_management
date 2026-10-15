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

$downloadResultsBat = Join-Path $scriptDir "download-results.bat"
$checkDownloadStatusBat = Join-Path $scriptDir "check-download-status.bat"
$collectCombineResultBat = Join-Path $scriptDir "collect-combine-result.bat"
$collectTestResultBat = Join-Path $scriptDir "collect-test-result.bat"
$collectSurveyResultBat = Join-Path $scriptDir "collect-survey-result.bat"
$postCollectResultsBat = Join-Path $scriptDir "post-collect-results.bat"
$collectYearComparisonResultBat = Join-Path $scriptDir "collect-year-comparison-result.bat"
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

function New-TargetGroupInput {
    param([bool]$NewRow = $false)
    [PSCustomObject]@{ Name = "TargetGroupNameFilter"; Label = "対象のグループ"; Default = ""; LabelWidth = 150; InputWidth = 150; Options = $blankOptions; NewRow = $NewRow }
}

$categoryDefs = @(
    [PSCustomObject]@{
        Label = "実施データ取得"
        ButtonDefs = @(
            [PSCustomObject]@{ Label = "テスト・アンケート"; BatchLabel = "実施データ取得-テスト・アンケート"; IncludeInBatch = $true; BatchPath = $downloadResultsBat; OpenTarget = Get-ResolvedVar "ResultRootDir" $commonEnvBat; Inputs = @((New-TargetGroupInput)) }
            [PSCustomObject]@{ Label = "取得状況確認"; BatchLabel = "実施データ取得-取得状況確認"; IncludeInBatch = $false; BatchPath = $checkDownloadStatusBat; OpenTarget = Get-ResolvedVar "ResultRootDir" $commonEnvBat; Inputs = @((New-TargetGroupInput)) }
        )
    }
    [PSCustomObject]@{
        Label = "実施状況確認"
        ButtonDefs = @(
            [PSCustomObject]@{ Label = "テスト・アンケート"; BatchLabel = "実施状況確認-テスト・アンケート"; IncludeInBatch = $true; BatchPath = $collectCombineResultBat; OpenTarget = Get-ResolvedVar "OutputCombineCollectDir" $commonEnvBat; Inputs = @((New-TargetGroupInput)) }
        )
    }
    [PSCustomObject]@{
        Label = "実施結果確認"
        ButtonDefs = @(
            [PSCustomObject]@{ Label = "テスト"; BatchLabel = "実施結果確認-テスト"; IncludeInBatch = $true; BatchPath = $collectTestResultBat; OpenTarget = Get-ResolvedVar "OutputTestCollectDir" $commonEnvBat; Inputs = @((New-TargetGroupInput)) }
            [PSCustomObject]@{ Label = "アンケート"; BatchLabel = "実施結果確認-アンケート"; IncludeInBatch = $true; BatchPath = $collectSurveyResultBat; OpenTarget = Get-ResolvedVar "OutputSurveyCollectDir" $commonEnvBat; Inputs = @((New-TargetGroupInput)) }
            [PSCustomObject]@{ Label = "投稿"; BatchLabel = "実施結果確認-投稿"; IncludeInBatch = $true; DefaultChecked = $false; BatchPath = $postCollectResultsBat; OpenTarget = { param($ic) if ($ic -and $ic.ContainsKey("TargetGroupNameFilter")) { $groupValue = Get-InputValue -Control $ic["TargetGroupNameFilter"] } else { $groupValue = "" }; Get-GroupKintoneThreadUrl -GroupName $groupValue -ClientsDir $clientsDir }; Inputs = @((New-TargetGroupInput)) }
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
                BatchPath = $collectYearComparisonResultBat
                OpenTarget = Get-ResolvedVar "OutputYearComparisonCollectDir" $commonEnvBat
                Inputs = @(
                    (New-TargetGroupInput)
                    [PSCustomObject]@{ Name = "TargetCompanyNames"; Label = "対象の会社名"; Default = Get-ResolvedVar "TargetCompanyNames" $commonEnvBat; LabelWidth = 150; InputWidth = 150; NewRow = $true }
                    [PSCustomObject]@{ Name = "ComparePeriod"; Label = "比較年"; Default = Get-ResolvedVar "ComparePeriod" $commonEnvBat; LabelWidth = 50; InputWidth = 40 }
                    [PSCustomObject]@{
                        Name = "YearOrder"; Label = "表示順"; Default = Get-ResolvedVar "YearOrder" $commonEnvBat; LabelWidth = 55; InputWidth = 70
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

$script:currentProc = $null
$form = New-Form -Title "trackデータ集計ツール" -Width 900 -Height 560 -MinWidth 600 -MinHeight 400 -CenterScreen

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
        -StatusLabel $batchTab.StatusLabel -StatusLabels $batchTab.StatusLabels `
        -WriteLog { param($msg) Write-Log $msg } -SetRunButtonsEnabled { param($e) Set-RunButtonsEnabled $e } `
        -InvokeStep {
            param($bd)
            Invoke-BatchStep -ButtonDef $bd -WorkingDirectory $scriptDir -Form $form `
                -WriteLog { param($msg) Write-Log $msg } -CurrentProcessRef ([ref]$script:currentProc) `
                -GetBatArgs {
                    param($bd)
                    $batArgs = @()
                    foreach ($inputDef in $bd.Inputs) {
                        $value = if ($inputDef.Name -eq "TargetGroupNameFilter") { Get-InputValue -Control $batchTab.InputControls["TargetGroupNameFilter"] } else { $inputDef.Default }
                        $batArgs += "$($inputDef.Name):$value"
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
                foreach ($inputName in $inputMap.Keys) {
                    $batArgs += "$($inputName):$(Get-InputValue -Control $inputMap[$inputName])"
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
    -GetLogPathFn { Get-ResolvedVar "LOG_DIR" $commonEnvBat }


$clientsDir = Join-Path $rootPath "clients"
$clientsTemplateDir = Join-Path $clientsDir "template"

function Get-GroupXlsxPath { param([string]$GroupName) Join-Path $clientsDir "$GroupName.xlsx" }

$commonEnvResolver = { param($name) Get-ResolvedVar $name $commonEnvBat }

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
            "OutputTestResultFileSuffix"            = @{ Label = "テスト結果ファイル名の接尾語" }
            "OutputSurveyCollectDir"                = @{ Label = "アンケート集計結果の出力先"; Browse = "Folder" }
            "OutputSurveyResultFileSuffix"          = @{ Label = "アンケート結果ファイル名の接尾語" }
            "OutputCombineCollectDir"               = @{ Label = "統合結果の出力先"; Browse = "Folder" }
            "OutputCombineResultFileSuffix"         = @{ Label = "統合結果ファイル名の接尾語" }
            "OutputYearComparisonCollectDir"        = @{ Label = "経年比較結果の出力先"; Browse = "Folder" }
            "OutputYearComparisonResultFileSuffix"  = @{ Label = "経年比較結果ファイル名の接尾語" }
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
            "CommentTextTemplate" = @{ Label = "投稿コメント文言"; Width=400; Multiline = $true }
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
$settingsWidthVars = @{}
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
        if ($varDef.Width) { $settingsWidthVars[$varKey] = $varDef.Width }
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
        [PSCustomObject]@{ Path = (Join-Path $scriptDir "common.bat"); Save = { Save-CommonSettings }; Reload = {} }
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

            if ((Test-Path -LiteralPath (Get-GroupXlsxPath $newName)) -or (Test-Path -LiteralPath (Get-GroupBatPath $newName $clientsDir))) {
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
            Read-MasterExcelData -GroupName $target
        } }
        [PSCustomObject]@{ Name = "OpenXlsx"; Kind = "Link"; Text = "開く"; OnClick = {
            $target = Get-ComboBoxValue -SelectedItem $settingsMasterTop.Controls["GroupTarget"].SelectedItem
            Open-TargetOrWarn -Path (Get-GroupXlsxPath $target)
        } }
        [PSCustomObject]@{ Name = "SaveTargetLabel"; Kind = "Label"; Text = "保存対象"; Width = 120 }
        [PSCustomObject]@{ Name = "SaveTarget"; Kind = "Combo"; Width = 120
            Items = @(
                [PSCustomObject]@{ Text = "すべて"; Value = "すべて" }
                [PSCustomObject]@{ Text = "テスト"; Value = "テスト" }
                [PSCustomObject]@{ Text = "アンケート"; Value = "アンケート" }
            )
            SelectedItem = [PSCustomObject]@{ Text = "すべて"; Value = "すべて" } }
    ) `
    -OnSave { Save-MasterToExcel } `
    -OnReload {
        $target = Get-ComboBoxValue -SelectedItem $settingsMasterTop.Controls["GroupTarget"].SelectedItem
        Read-MasterExcelData -GroupName $target
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

$grpSurveyEdit = New-GroupBox -Text "アンケート編集" -Dock ([System.Windows.Forms.DockStyle]::Top) -AutoSize -Padding 10

$script:surveyRows = @()
$script:surveyContentPanel = $null
$surveySheetDef = @{
    SheetName = "アンケート"
    Columns = @(
        @{ Label = "通番"; Width = 40; AutoIncrement = $true }
        @{ Label = "アンケート名"; Width = 150; Property = "SurveyName" }
        @{ Label = "TrackId"; Width = 400; Property = "TrackID";}
        @{ Label = "DL"; Width = 60; Property = "IsDownload"; IsBool = $true; Default = "FALSE" }
        @{ Label = "停止中"; Width = 60; Property = "IsStop"; IsBool = $true; Default = "TRUE" }
    )
}

$grpTestEdit = New-GroupBox -Text "テスト編集" -Dock ([System.Windows.Forms.DockStyle]::Top) -AutoSize -Padding 10

$script:testRows = @()
$script:testContentPanel = $null
$testSheetDef = @{
    SheetName = "テスト"
    Columns = @(
        @{ Label = "通番"; Width = 40; AutoIncrement = $true }
        @{ Label = "テスト名"; Width = 150; Property = "TestName"; }
        @{ Label = "TrackId"; Width = 400; Property = "TrackID" }
        @{ Label = "DL"; Width = 60; Property = "IsDownload"; IsBool = $true; Default = "FALSE" }
        @{ Label = "停止中"; Width = 60; Property = "IsStop"; IsBool = $true; Default = "TRUE" }
    )
}

$controlsToStack = @($grpUserMasterSync, (New-Panel -Height 10), $grpTestEdit, (New-Panel -Height 10), $grpSurveyEdit, (New-Panel -Height 10))
Add-StackedDockedControls -Container $settingsMasterBottomPanel -ControlsTopToBottom $controlsToStack -Spacing 0

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
        foreach ($col in $surveySheetDef.Columns | Where-Object { $_.Property }) {
            $newObj[$col.Property] = ""
        }
        $newRow = [PSCustomObject]$newObj
        $script:surveyRows = @($script:surveyRows) + @($newRow)
        Update-SurveyGrid
    } -Columns $surveySheetDef.Columns
    $script:surveyContentPanel = $panels.ContentPanel
}

function Read-SurveyGridData {
    Read-GridData -ContentPanel $script:surveyContentPanel -Columns $surveySheetDef.Columns
}

function Read-SurveyExcelData {
    param([string]$GroupName)

    $xlsxPath = Get-GroupXlsxPath $GroupName

    try {
        $surveyTransformer = {
            param($Rows)
            $convertedRows = @()
            foreach ($row in $Rows) {
                $newObj = [ordered]@{ No = @($convertedRows).Count + 1 }
                foreach ($col in $surveySheetDef.Columns | Where-Object { $_.Property }) {
                    $value = $row."$($col.Label)"
                    if ($col.IsBool -and $value -is [bool]) {
                        $value = if ($value) { "TRUE" } else { "FALSE" }
                    }
                    $newObj[$col.Property] = $value
                }
                $convertedRows += [PSCustomObject]$newObj
            }
            @($convertedRows)
        }

        $script:surveyRows = Read-ExcelData `
            -ExcelPath $xlsxPath `
            -SheetName $surveySheetDef.SheetName `
            -DataTransformer $surveyTransformer
        Update-SurveyGrid
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show("アンケート読込に失敗しました: $_", "エラー", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    }
}

function Save-SurveyToExcel {
    $groupName = Get-ComboBoxValue -SelectedItem $settingsMasterTop.Controls["GroupTarget"].SelectedItem
    $xlsxPath = Get-GroupXlsxPath $groupName
    try {
        $rowsFromUI = @(Read-SurveyGridData)
        Save-DataToExcel -ExcelPath $xlsxPath -SheetDef $surveySheetDef -Datas $rowsFromUI
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
        foreach ($col in $testSheetDef.Columns | Where-Object { $_.Property }) {
            $newObj[$col.Property] = ""
        }
        $newRow = [PSCustomObject]$newObj
        $script:testRows = @($script:testRows) + @($newRow)
        Update-TestGrid
    } -Columns $testSheetDef.Columns
    $script:testContentPanel = $panels.ContentPanel
}

function Read-TestGridData {
    Read-GridData -ContentPanel $script:testContentPanel -Columns $testSheetDef.Columns
}

function Read-TestExcelData {
    param([string]$GroupName)

    $xlsxPath = Get-GroupXlsxPath $GroupName

    try {
        $testTransformer = {
            param($Rows)
            $convertedRows = @()
            foreach ($row in $Rows) {
                $newObj = [ordered]@{ No = @($convertedRows).Count + 1 }
                foreach ($col in $testSheetDef.Columns | Where-Object { $_.Property }) {
                    $value = $row."$($col.Label)"
                    if ($col.IsBool -and $value -is [bool]) {
                        $value = if ($value) { "TRUE" } else { "FALSE" }
                    }
                    $newObj[$col.Property] = $value
                }
                $convertedRows += [PSCustomObject]$newObj
            }
            @($convertedRows)
        }

        $script:testRows = Read-ExcelData `
            -ExcelPath $xlsxPath `
            -SheetName $testSheetDef.SheetName `
            -DataTransformer $testTransformer
        Update-TestGrid
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show("テスト読込に失敗しました: $_", "エラー", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    }
}

function Save-MasterToExcel {
    $groupName = Get-ComboBoxValue -SelectedItem $settingsMasterTop.Controls["GroupTarget"].SelectedItem
    $xlsxPath = Get-GroupXlsxPath $groupName
    try {
        $saveTarget = Get-ComboBoxValue -SelectedItem $settingsMasterTop.Controls["SaveTarget"].SelectedItem
        switch ($saveTarget) {
            "すべて" {
                $surveyDatas = @(Read-SurveyGridData)
                $testDatas = @(Read-TestGridData)
                Save-DataToExcel -ExcelPath $xlsxPath -SheetDefDatasMap @(
                    @{ SheetDef = $surveySheetDef; Datas = $surveyDatas }
                    @{ SheetDef = $testSheetDef; Datas = $testDatas }
                )
            }
            "テスト" {
                $testDatas = @(Read-TestGridData)
                Save-DataToExcel -ExcelPath $xlsxPath -SheetDef $testSheetDef -Datas $testDatas
            }
            "アンケート" {
                $surveyDatas = @(Read-SurveyGridData)
                Save-DataToExcel -ExcelPath $xlsxPath -SheetDef $surveySheetDef -Datas $surveyDatas
            }
        }
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show("保存に失敗しました: $_", "エラー", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    }
}

function Read-MasterExcelData {
    param([string]$GroupName)

    $xlsxPath = Get-GroupXlsxPath $GroupName

    try {

        $surveyTransformer = {
            param($Rows)
            $convertedRows = @()
            foreach ($row in $Rows) {
                $newObj = [ordered]@{ No = @($convertedRows).Count + 1 }
                foreach ($col in $surveySheetDef.Columns | Where-Object { $_.Property }) {
                    $value = $row."$($col.Label)"
                    if ($col.IsBool -and $value -is [bool]) {
                        $value = if ($value) { "TRUE" } else { "FALSE" }
                    }
                    $newObj[$col.Property] = $value
                }
                $convertedRows += [PSCustomObject]$newObj
            }
            @($convertedRows)
        }

        $testTransformer = {
            param($Rows)
            $convertedRows = @()
            foreach ($row in $Rows) {
                $newObj = [ordered]@{ No = @($convertedRows).Count + 1 }
                foreach ($col in $testSheetDef.Columns | Where-Object { $_.Property }) {
                    $value = $row."$($col.Label)"
                    if ($col.IsBool -and $value -is [bool]) {
                        $value = if ($value) { "TRUE" } else { "FALSE" }
                    }
                    $newObj[$col.Property] = $value
                }
                $convertedRows += [PSCustomObject]$newObj
            }
            @($convertedRows)
        }

        $results = Read-ExcelData -ExcelPath $xlsxPath -SheetTransformerMap @(
            @{ SheetName = $surveySheetDef.SheetName; DataTransformer = $surveyTransformer }
            @{ SheetName = $testSheetDef.SheetName; DataTransformer = $testTransformer }
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
    $groupName = Get-ComboBoxValue -SelectedItem $settingsMasterTop.Controls["GroupTarget"].SelectedItem
    $xlsxPath = Get-GroupXlsxPath $groupName
    try {
        $rowsFromUI = @(Read-TestGridData)
        Save-DataToExcel -ExcelPath $xlsxPath -SheetDef $testSheetDef -Datas $rowsFromUI
    }
    catch {
        [System.Windows.Forms.MessageBox]::Show("保存に失敗しました: $_", "エラー", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
    }
}

function Get-CommonSettingsFieldRows {
    $raw = Get-SetLineRawValues -Path (Join-Path $scriptDir "common.bat")
    foreach ($varName in $commonSettingsVars) {
        [PSCustomObject]@{ Key = $varName; VarName = $varName; Group = "COMMON"; Value = $raw[$varName] }
    }
}

function Get-GroupSettingsFieldRows {
    param([string]$GroupName)
    if (!$GroupName) { return }

    $templateDefaults = Get-GroupTemplateDefaults
    $rawAuth = Get-SetLineRawValues -Path (Get-GroupBatPath $GroupName $clientsDir)
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
    Render-SettingsFields -Panel $settingsCommonBottomPanel -Rows (Get-CommonSettingsFieldRows) -TargetTextBoxes $settingsCommonFieldTextBoxes -RadioVars $radioVars `
        -GroupLabels $settingsGroupLabels -VarLabels $settingsVarLabels -ToolTip $settingsToolTip -RootPath $rootPath -EnvResolver $commonEnvResolver `
        -MultilineVars $settingsMultilineVars -MaskedVars $settingsMaskedVars -FolderBrowseVars $settingsFolderBrowseVars -FileBrowseVars $settingsFileBrowseVars -WidthVars $settingsWidthVars -LabelWidth 150 | Out-Null
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

function Update-GroupSettingsFields {
    $scrollX = -$settingsGroupBottomPanel.AutoScrollPosition.X
    $scrollY = -$settingsGroupBottomPanel.AutoScrollPosition.Y

    $target = Get-ComboBoxValue -SelectedItem $settingsGroupTop.Controls["GroupTarget"].SelectedItem
    $trailingButtons = $settingsTrailingButtonVars.Clone()
    $trailingButtons["CommentTextTemplate"] = { param($Panel, $Y, $Field) Add-FieldActionButton -Panel $Panel -Y $Y -Text "テスト投稿" -AddStatusLabel -OnClick {
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
        }
    }.GetNewClosure() -OnOpenClick {
        $subdomain = (Get-GroupSettingsFieldValue "AUTH_KintoneSubdomain").Trim()
        $spaceId = (Get-GroupSettingsFieldValue "POST_SpaceId").Trim()
        $threadId = (Get-GroupSettingsFieldValue "POST_ThreadId").Trim()
        $threadUrl = if ($subdomain -and $spaceId -and $threadId) { "https://$subdomain.cybozu.com/k/#/space/$spaceId/thread/$threadId" } else { $null }
        Open-TargetOrWarn -Path $threadUrl
    }.GetNewClosure() }
    $trailingButtons["SyncUserMasterAppId"] = { param($Panel, $Y, $Field) Add-FieldActionButton -Panel $Panel -Y $Y -Text "テスト接続" -AddStatusLabel -OnClick {
        Invoke-ActionWithUpdateStatus -StatusLabel $Field.StatusLabel -Action {
            Test-KintoneConnectionFromSettings -ReportGroup "SYNC" -FieldName "SYNC_SyncUserMasterAppId" | Out-Null
        }
    }.GetNewClosure() }
    $trailingButtons["KintonePassword"] = { param($Panel, $Y, $Field) Add-FieldActionButton -Panel $Panel -Y $Y -Text "テスト接続" -AddStatusLabel -OnClick {
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
    Render-SettingsFields -Panel $settingsGroupBottomPanel -Rows (Get-GroupSettingsFieldRows -GroupName $target) -TargetTextBoxes $settingsGroupFieldTextBoxes -RadioVars $radioVars `
        -GroupLabels $settingsGroupLabels -VarLabels $settingsVarLabels -ToolTip $settingsToolTip -RootPath $rootPath -EnvResolver $commonEnvResolver `
        -MultilineVars $settingsMultilineVars -MaskedVars $settingsMaskedVars -FolderBrowseVars $settingsFolderBrowseVars -FileBrowseVars $settingsFileBrowseVars -WidthVars $settingsWidthVars -LabelWidth 150 `
        -MentionGroupCombo $settingsGroupTop.Controls["GroupTarget"] -MentionTypeOptions $mentionTypeOptions `
        -TrailingButtonVars $trailingButtons | Out-Null

    $settingsGroupBottomPanel.AutoScrollPosition = New-Object System.Drawing.Point($scrollX, $scrollY)

    Register-MentionEditorHandlers -OnChange { Update-GroupSettingsFields }
}

function Save-CommonSettings {
    $path = Join-Path $scriptDir "common.bat"

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

    $groupBatPath = Get-GroupBatPath $GroupName $clientsDir

    $saveGroupAuthVarMap = @{}
    foreach ($varName in $authVars) {
        $saveGroupAuthVarMap[$varName] = "AUTH_$varName"
    }

    $saveGroupPostVarMap = @{}
    foreach ($varName in $postVars) {
        $saveGroupPostVarMap[$varName] = "POST_$varName"
    }

    $saveGroupOverrideVarMap = @{}
    foreach ($varName in $groupOverrideVars) {
        $saveGroupOverrideVarMap[$varName] = "OVERRIDE_$varName"
    }

    $saveGroupSyncVarMap = @{}
    foreach ($varName in $syncUserMasterVars) {
        $saveGroupSyncVarMap[$varName] = "SYNC_$varName"
    }

    $allVars = @() + @($saveGroupAuthVarMap.Keys) + @("Authorization", "BaseUrl") + @($saveGroupPostVarMap.Keys) + @($saveGroupOverrideVarMap.Keys) + @($saveGroupSyncVarMap.Keys)

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
            } elseif ($saveGroupAuthVarMap.ContainsKey($varName)) {
                Get-GroupSettingsFieldValue $saveGroupAuthVarMap[$varName]
            } elseif ($saveGroupPostVarMap.ContainsKey($varName)) {
                $val = Get-GroupSettingsFieldValue $saveGroupPostVarMap[$varName]
                if ($settingsMultilineVars -contains $varName) { $val = $val -replace "`r`n", '\n' -replace "`n", '\n' }
                $val
            } elseif ($saveGroupOverrideVarMap.ContainsKey($varName)) {
                $val = Get-GroupSettingsFieldValue $saveGroupOverrideVarMap[$varName]
                if ([string]::IsNullOrWhiteSpace($val)) { "" } else { $val }
            } elseif ($saveGroupSyncVarMap.ContainsKey($varName)) {
                Get-GroupSettingsFieldValue $saveGroupSyncVarMap[$varName]
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


