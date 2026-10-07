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

$setEnvBat = Join-Path $basePath "common-env.bat"
$script:commonEnvVars = Get-BatEnvVars -BatPath $setEnvBat

$clientsDir = Join-Path $rootPath "clients"

function Get-ClientNames {
    if (!(Test-Path -LiteralPath $clientsDir)) { return @() }
    $names = Get-ChildItem -LiteralPath $clientsDir -Filter "*.bat" -File -ErrorAction SilentlyContinue | ForEach-Object {
        [System.IO.Path]::GetFileNameWithoutExtension($_.Name)
    }
    return @($names | Select-Object -Unique | Sort-Object)
}

$allGroupsOption = [PSCustomObject]@{ Text = "すべて"; Value = "" }
$clientOptions = @()
foreach ($clientName in (Get-ClientNames)) {
    $clientOptions += [PSCustomObject]@{ Text = $clientName; Value = $clientName }
}
function New-ClientInput {
    param([bool]$NewRow = $false)
    [PSCustomObject]@{ Name = "ClientName"; Label = "対象グループ"; Default = ""; LabelWidth = 75; InputWidth = 150; Options = $clientOptions; NewRow = $NewRow }
}

function Get-NewClientInitialValues {
    param([string]$ClientName)
    $templateBatPath = Join-Path $clientsTemplateDir "client.bat"
    if (!(Test-Path -LiteralPath $templateBatPath)) { return @{} }

    $templateValues = Get-SetLineRawValues -Path $templateBatPath
    $result = @{}
    foreach ($key in $templateValues.Keys) {
        $value = $templateValues[$key]
        if ($key -eq "GenerateConfigPath") {
            $value = "%BASE_PATH%clients\$ClientName.xlsx"
        } elseif ($key -eq "GenerateOutputPath") {
            $value = "%BASE_PATH%generated\$ClientName"
        }
        $result[$key] = $value
    }
    return $result
}

function Update-GroupDropdowns {
    $clientNames = @(Get-ClientNames)

    $savedSettings = Get-ComboBoxValue -SelectedItem $cmbSettingsGroupTarget.SelectedItem
    $savedLog = Get-ComboBoxValue -SelectedItem $script:logTab.GroupCombo.SelectedItem
    $savedFilters = @{}
    foreach ($cd in $categoryDefs) {
        foreach ($bd in $cd.ButtonDefs) {
            if ($bd.InputControls) {
                foreach ($ctrl in $bd.InputControls.Values) {
                    if ($ctrl -is [System.Windows.Forms.ComboBox]) {
                        $savedFilters[$bd.Label] = Get-ComboBoxValue -SelectedItem $ctrl.SelectedItem
                    }
                }
            }
        }
    }

    if ($cmbSettingsGroupTarget) {
        Update-ComboItems -ComboBox $cmbSettingsGroupTarget -Items $clientNames
        Restore-ComboSelection -ComboBox $cmbSettingsGroupTarget -SavedValue $savedSettings
    }

    foreach ($cd in $categoryDefs) {
        foreach ($bd in $cd.ButtonDefs) {
            if ($bd.InputControls) {
                foreach ($ctrl in $bd.InputControls.Values) {
                    if ($ctrl -is [System.Windows.Forms.ComboBox]) {
                        Update-ComboItems -ComboBox $ctrl -Items $clientNames
                        Restore-ComboSelection -ComboBox $ctrl -SavedValue $savedFilters[$bd.Label]
                    }
                }
            }
        }
    }

    if ($script:logTab -and $script:logTab.GroupCombo) {
        $logItems = @($allGroupsOption) + $clientNames
        Update-ComboItems -ComboBox $script:logTab.GroupCombo -Items $logItems
        Restore-ComboSelection -ComboBox $script:logTab.GroupCombo -SavedValue $savedLog
    }

    foreach ($ctrl in $script:batchInputControls.Values) {
        if ($ctrl -is [System.Windows.Forms.ComboBox]) {
            $savedBatchValue = Get-ComboBoxValue -SelectedItem $ctrl.SelectedItem
            Update-ComboItems -ComboBox $ctrl -Items $clientNames
            Restore-ComboSelection -ComboBox $ctrl -SavedValue $savedBatchValue
        }
    }
}

$categoryDefs = @(
    [PSCustomObject]@{
        Label = "パッケージ作成"
        ButtonDefs = @(
            [PSCustomObject]@{ Label = "パッケージの作成"; BatchLabel = "個別パッケージの作成"; IncludeInBatch = $true; BatchPath = (Join-Path $rootPath "generate-package.bat"); OpenTarget = $script:commonEnvVars["GenerateOutputPath"]; Inputs = @((New-ClientInput)) }
            [PSCustomObject]@{ Label = "パッケージ定義ファイルの更新"; BatchLabel = "パッケージ定義ファイル更新"; IncludeInBatch = $true; BatchPath = (Join-Path $rootPath "generate-config.bat"); OpenTarget = $script:commonEnvVars["CommonLogPath"]; Inputs = @((New-ClientInput)) }
        )
    }
)

$form = New-Form -Title "コース別パッケージ生成ツール" -Width 780 -Height 560 -MinWidth 600 -MinHeight 400 -CenterScreen
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
# $execTabControl.Controls.Add($tabBatchAll)

New-BatchRunTab -TabPage $tabBatchAll -ButtonDefs $allButtonDefs `
    -Inputs @(
        [PSCustomObject]@{ Name = "ClientName"; Label = "対象グループ"; Options = $clientOptions; LabelWidth = 75; InputWidth = 150 }
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
                        $value = Get-InputValue -Control $script:batchInputControls[$inputDef.Name]
                        $batArgs += "-$($inputDef.Name):$value"
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
                    $batArgs += "-$($inputName):$(Get-InputValue -Control $inputMap[$inputName])"
                }
            }
            return $batArgs
        }
} | Out-Null

$execTabControl.Height = 45 + $script:batchPanel.Height


$txtLog = New-LogTextBox

Add-StackedDockedControls -Container $tabRun -ControlsTopToBottom @($execTabControl, $txtLog)


$allButtonDefsForLog = @($categoryDefs | ForEach-Object { $_.ButtonDefs })

$logTabConditions = @(
    @{ PropertyName = "GroupCombo"; LabelText = "対象グループ"; LabelWidth = 150; ComboWidth = 150; Options = @($allGroupsOption, $clientOptions) }
)

New-LogTab -TabPage $tabLogs -ButtonDefs $allButtonDefsForLog `
    -LabelFn { param($bd) Get-BatchDisplayLabel -ButtonDef $bd } `
    -Conditions $logTabConditions `
    -GetLogPathFn { $script:commonEnvVars["CommonLogPath"] } `
    -OnUpdateLogView { Update-LogView } | Out-Null
$script:logPath = $script:commonEnvVars["CommonLogPath"]

$clientsDir = Join-Path $rootPath "clients"
$clientsTemplateDir = Join-Path $clientsDir "template"

function Get-GroupXlsxPath { param([string]$GroupName) Join-Path $clientsDir "$GroupName.xlsx" }

$script:commonEnvResolver = { param($name) $script:commonEnvVars[$name] }

$settingsGroups = [ordered]@{
    "COMMON" = @{
        Label = "共通"
        Overridable = $false
        Vars = [ordered]@{
            "CommonLogPath" = @{ Label = "ログの出力先"; Browse = "Folder" }
        }
    }
    "DOWNLOAD" = @{
        Label = "ダウンロード"
        Vars = [ordered]@{
            "DownloadSiteUrl"       = @{ Label = "ダウンロード元のサイトURL" }
            "DownloadSitePath"      = @{ Label = "ダウンロード元のフォルダ" }
            "DownloadSiteTenantId"  = @{ Label = "テナントID" }
            "DownloadLocalPath"     = @{ Label = "ダウンロード先のフォルダ"; Browse = "Folder" }
        }
    }
    "GENERATE" = @{
        Label = "パッケージ作成"
        Vars = [ordered]@{
            "GenerateSourcePath"      = @{ Label = "圧縮元のフォルダ"; Browse = "Folder"  }
            "GenerateConfigPath"      = @{ Label = "パッケージ定義ファイル"; Browse = "File" }
            "GenerateWorkPath"        = @{ Label = "作業用のフォルダ"; Browse = "Folder"  }
            "GenerateOutputPath"      = @{ Label = "パッケージの出力先"; Browse = "Folder" }
            "GenerateSheetsInclude"   = @{ Label = "対象のシート" }
            "GenerateSheetsExclude"   = @{ Label = "除外のシート" }
        }
    }
    "UPLOAD" = @{
        Label = "アップロード"
        Vars = [ordered]@{
            "UploadSiteUrl"       = @{ Label = "アップロード先のサイトURL" }
            "UploadSitePath"      = @{ Label = "アップロード先のフォルダ" }
            "UploadSiteTenantId"  = @{ Label = "テナントID" }
            "UploadLocalPath"     = @{ Label = "アップロード元のフォルダ"; Browse = "Folder" }
            "UploadItemsInclude"  = @{ Label = "対象の項目形式" }
            "UploadItemsExclude"  = @{ Label = "除外の項目形式" }
        }
    }
}

$commonSettingsVars = @($settingsGroups["COMMON"].Vars.Keys)
$downloadVars = @($settingsGroups["DOWNLOAD"].Vars.Keys)
$generateVars = @($settingsGroups["GENERATE"].Vars.Keys)
$uploadVars = @($settingsGroups["UPLOAD"].Vars.Keys)

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

$settingsSubTabControl = New-TabControl -Dock ([System.Windows.Forms.DockStyle]::Fill)
$tabSettings.Controls.Add($settingsSubTabControl)

$tabSettingsCommon = New-TabPage -Text "共通"
$settingsSubTabControl.Controls.Add($tabSettingsCommon)

$tabSettingsGroup = New-TabPage -Text "グループ別"
$settingsSubTabControl.Controls.Add($tabSettingsGroup)

$settingsToolTip = New-ToolTip

function Get-CommonSettingsFiles {
    return @(
        [PSCustomObject]@{ Path = (Join-Path $basePath "common-env.bat"); Save = { Save-CommonSettings }; Reload = {} }
    )
}

$settingsCommonTopPanel = (New-SettingsTopPanel `
    -OnSave { foreach ($f in (Get-CommonSettingsFiles)) { & $f.Save }; Update-CommonSettingsFields } `
    -OnReload { foreach ($f in (Get-CommonSettingsFiles)) { & $f.Reload }; Update-CommonSettingsFields }).Panel

$settingsCommonFieldPanel = New-Panel -Dock ([System.Windows.Forms.DockStyle]::Fill) -AutoScroll

$tabSettingsCommon.Controls.Add($settingsCommonFieldPanel)
$tabSettingsCommon.Controls.Add($settingsCommonTopPanel)

$lblSettingsGroupTarget = New-Label -Text "対象グループ"

$cmbSettingsGroupTarget = New-ComboBox -Width 150 -Height 24 -DisplayMember "Text" -ValueMember "Value"

$btnSettingsGroupNewGroup = New-Button -Text "新規作成" -Width 140 -Height 24

$lnkSettingsGroupOpenXlsx = New-LinkLabel -Text "開く"

function Get-GroupSettingsFiles {
    param([string]$GroupName)
    return @(
        [PSCustomObject]@{ Path = (Get-GroupBatPath $GroupName); Save = { Save-GroupSettings -GroupName $GroupName }.GetNewClosure(); Reload = {} }
    )
}

$settingsGroupTopPanel = (New-SettingsTopPanel `
    -ExtraControls @($lblSettingsGroupTarget, $cmbSettingsGroupTarget, $btnSettingsGroupNewGroup, $lnkSettingsGroupOpenXlsx) `
    -OnSave {
        $target = Get-ComboBoxValue -SelectedItem $cmbSettingsGroupTarget.SelectedItem
        if (!$target) { return }
        foreach ($f in (Get-GroupSettingsFiles -GroupName $target)) { & $f.Save }
        Update-SettingsGroupList
        Update-GroupSettingsFields
    } `
    -OnReload {
        $target = Get-ComboBoxValue -SelectedItem $cmbSettingsGroupTarget.SelectedItem
        foreach ($f in (Get-GroupSettingsFiles -GroupName $target)) { & $f.Reload }
        Update-GroupSettingsFields
    }).Panel

$settingsGroupFieldPanel = New-Panel -Dock ([System.Windows.Forms.DockStyle]::Fill) -AutoScroll

$tabSettingsGroup.Controls.Add($settingsGroupFieldPanel)
$tabSettingsGroup.Controls.Add($settingsGroupTopPanel)

function Get-GroupNames {
    if (!(Test-Path -LiteralPath $clientsDir)) { return @() }
    $names = Get-ChildItem -LiteralPath $clientsDir -Filter "*.xlsx" -File -ErrorAction SilentlyContinue | ForEach-Object {
        [System.IO.Path]::GetFileNameWithoutExtension($_.Name)
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

    $rawClient = Get-SetLineRawValues -Path (Get-GroupBatPath $GroupName)
    $isPendingNewClient = !(Test-Path -LiteralPath (Get-GroupBatPath $GroupName))
    $newClientDefaults = if ($isPendingNewClient) { Get-NewClientInitialValues $GroupName } else { @{} }

    foreach ($groupKey in @("DOWNLOAD", "GENERATE", "UPLOAD")) {
        $vars = if ($groupKey -eq "DOWNLOAD") { $downloadVars } elseif ($groupKey -eq "GENERATE") { $generateVars } else { $uploadVars }
        foreach ($varName in $vars) {
            $value = if ($rawClient.ContainsKey($varName)) { $rawClient[$varName] } elseif ($newClientDefaults.ContainsKey($varName)) { $newClientDefaults[$varName] } else { "" }
            [PSCustomObject]@{ Key = "$($groupKey)_$varName"; VarName = $varName; Group = $groupKey; Value = $value }
        }
    }
}


function Update-CommonSettingsFields {
    Render-SettingsFields -Panel $settingsCommonFieldPanel -Rows (Get-CommonSettingsFieldRows) -TargetTextBoxes $script:settingsCommonFieldTextBoxes -RadioVars $radioVars `
        -GroupLabels $settingsGroupLabels -VarLabels $settingsVarLabels -ToolTip $settingsToolTip -RootPath $rootPath -EnvResolver $script:commonEnvResolver `
        -MultilineVars $settingsMultilineVars -MaskedVars $settingsMaskedVars -FolderBrowseVars $settingsFolderBrowseVars -FileBrowseVars $settingsFileBrowseVars | Out-Null
}

function Update-GroupSettingsFields {
    $scrollX = -$settingsGroupFieldPanel.AutoScrollPosition.X
    $scrollY = -$settingsGroupFieldPanel.AutoScrollPosition.Y

    $target = Get-ComboBoxValue -SelectedItem $cmbSettingsGroupTarget.SelectedItem
    $trailingButtons = $settingsTrailingButtonVars.Clone()
    $resolverValue = $script:commonEnvResolver
    $rootPathValue = $rootPath
    Render-SettingsFields -Panel $settingsGroupFieldPanel -Rows (Get-GroupSettingsFieldRows -GroupName $target | Where-Object { $_.Group -eq "GENERATE" }) -TargetTextBoxes $script:settingsGroupFieldTextBoxes -RadioVars $radioVars `
        -GroupLabels $settingsGroupLabels -VarLabels $settingsVarLabels -ToolTip $settingsToolTip -RootPath $rootPath -EnvResolver $script:commonEnvResolver `
        -MultilineVars $settingsMultilineVars -MaskedVars $settingsMaskedVars -FolderBrowseVars $settingsFolderBrowseVars -FileBrowseVars $settingsFileBrowseVars `
        -OnOpenClick ({ param($path) Resolve-BrowseStart -RawValue $path -DefaultPath $rootPathValue -Resolver $resolverValue -BasePath $rootPathValue }).GetNewClosure() `
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

    $script:saveGroupDownloadVarMap = @{}
    foreach ($varName in $downloadVars) {
        $script:saveGroupDownloadVarMap[$varName] = "DOWNLOAD_$varName"
    }

    $script:saveGroupGenerateVarMap = @{}
    foreach ($varName in $generateVars) {
        $script:saveGroupGenerateVarMap[$varName] = "GENERATE_$varName"
    }

    $script:saveGroupUploadVarMap = @{}
    foreach ($varName in $uploadVars) {
        $script:saveGroupUploadVarMap[$varName] = "UPLOAD_$varName"
    }

    $allVars = @() + @($script:saveGroupDownloadVarMap.Keys) + @($script:saveGroupGenerateVarMap.Keys) + @($script:saveGroupUploadVarMap.Keys)

    Save-EnvBatFile -Path $groupBatPath -VarNames $allVars `
        -GetValueFn { param($varName)
            if ($script:saveGroupDownloadVarMap.ContainsKey($varName)) {
                Get-GroupSettingsFieldValue $script:saveGroupDownloadVarMap[$varName]
            } elseif ($script:saveGroupGenerateVarMap.ContainsKey($varName)) {
                Get-GroupSettingsFieldValue $script:saveGroupGenerateVarMap[$varName]
            } elseif ($script:saveGroupUploadVarMap.ContainsKey($varName)) {
                Get-GroupSettingsFieldValue $script:saveGroupUploadVarMap[$varName]
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

    Update-GroupDropdowns
}

$btnSettingsGroupNewGroup.Add_Click({
    Add-Type -AssemblyName Microsoft.VisualBasic
    $newName = [Microsoft.VisualBasic.Interaction]::InputBox("グループ名を入力してください", "グループの新規作成", "")
    $newName = $newName.Trim()
    if (!$newName) { return }

    if (($cmbSettingsGroupTarget.Items | Where-Object { (Get-ComboBoxValue -SelectedItem $_) -eq $newName }) -or (Test-Path -LiteralPath (Get-GroupXlsxPath $newName)) -or (Test-Path -LiteralPath (Get-GroupBatPath $newName))) {
        [System.Windows.Forms.MessageBox]::Show("「$newName」は既に存在します。", "グループの新規作成", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        return
    }

    $cmbSettingsGroupTarget.Items.Add([PSCustomObject]@{ Text = $newName; Value = $newName }) | Out-Null
    $cmbSettingsGroupTarget.SelectedIndex = $cmbSettingsGroupTarget.Items.Count - 1
})

$lnkSettingsGroupOpenXlsx.Add_LinkClicked({
    $target = Get-ComboBoxValue -SelectedItem $cmbSettingsGroupTarget.SelectedItem
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

$tabControl.SelectedTab = $tabRun

$form.Add_Shown({
    Update-CommonSettingsFields
    Update-GroupDropdowns

    Adjust-InitialTabHeight -NestedTabControl $execTabControl
})

[System.Windows.Forms.Application]::Run($form)
