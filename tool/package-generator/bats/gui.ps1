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

$clientOptions = @()
foreach ($clientName in (Get-ClientNames)) {
    $clientOptions += [PSCustomObject]@{ Text = $clientName; Value = $clientName }
}
function New-ClientInput {
    param([bool]$NewRow = $false)
    [PSCustomObject]@{ Name = "ClientName"; Label = "クライアント"; Default = ""; LabelWidth = 75; InputWidth = 150; Options = $clientOptions; NewRow = $NewRow }
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
        } elseif ($key -eq "UploadSitePath") {
            $value = $value -replace [regex]::Escape("サンプル"), $ClientName
        } else {
            $value = $value -replace [regex]::Escape("サンプル"), $ClientName
        }
        $result[$key] = $value
    }
    return $result
}

$categoryDefs = @(
    [PSCustomObject]@{
        Label = "個別パッケージの作成"
        ButtonDefs = @(
            [PSCustomObject]@{ Label = "パッケージ定義ファイル生成"; BatchLabel = "パッケージ定義ファイル生成"; IncludeInBatch = $true; BatchPath = (Join-Path $rootPath "generate-config.bat"); OpenTarget = $script:commonEnvVars["CommonLogPath"]; Inputs = @((New-ClientInput)) }
            [PSCustomObject]@{ Label = "個別パッケージの作成"; BatchLabel = "個別パッケージの作成"; IncludeInBatch = $true; BatchPath = (Join-Path $rootPath "generate-package.bat"); OpenTarget = $script:commonEnvVars["GenerateOutputPath"]; Inputs = @((New-ClientInput)) }
        )
    }
)

$form = New-Object System.Windows.Forms.Form
$form.Text = "コース別パッケージ生成ツール"
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
        [PSCustomObject]@{ Name = "ClientName"; Label = "クライアント"; Options = $clientOptions; LabelWidth = 90; InputWidth = 150 }
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

New-LogTab -TabPage $tabLogs -ButtonDefs $allButtonDefsForLog `
    -LabelFn { param($bd) Get-BatchDisplayLabel -ButtonDef $bd } `
    -ExtraLabelText "クライアント" -ExtraComboWidth 150 `
    -GetLogPathFn { $script:commonEnvVars["CommonLogPath"] } `
    -OnUpdateLogView { Update-LogView } | Out-Null
$script:logPath = $script:commonEnvVars["CommonLogPath"]
$cmbLogGroup = $script:logTab.ExtraCombo
$cmbLogGroup.DisplayMember = "Text"
foreach ($opt in $clientOptions) { $cmbLogGroup.Items.Add($opt) | Out-Null }
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

function Invoke-GenerateConfigForClient {
    param([string]$ClientName)

    $clientRaw = Get-SetLineRawValues -Path (Get-GroupBatPath $ClientName)
    $rawSourcePath = if ($clientRaw.ContainsKey("GenerateSourcePath")) { $clientRaw["GenerateSourcePath"] } else { "" }
    $sourcePath = Expand-VarTokens -Value $rawSourcePath -Resolver { param($name) $script:commonEnvVars[$name] } -BasePath $rootPath

    if ([string]::IsNullOrWhiteSpace($sourcePath) -or !(Test-Path -LiteralPath $sourcePath)) {
        [System.Windows.Forms.MessageBox]::Show(
            "圧縮元のフォルダが未設定か、存在しません。`r`n先に「圧縮元のフォルダ」を設定して保存してください。",
            "パッケージ定義ファイルの作成",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        return
    }

    $rawDestPath = if ($clientRaw.ContainsKey("GenerateConfigPath")) { $clientRaw["GenerateConfigPath"] } else { "" }
    $destPath = Expand-VarTokens -Value $rawDestPath -Resolver { param($name) $script:commonEnvVars[$name] } -BasePath $rootPath

    $commonLogPath = $script:commonEnvVars["CommonLogPath"]
    $batArgs = @("-ClientName:$ClientName", "-GenerateSourcePath:$sourcePath", "-GenerateConfigPath:$destPath", "-CommonLogPath:$commonLogPath")

    if (Test-Path -LiteralPath $destPath) {
        $confirm = [System.Windows.Forms.MessageBox]::Show(
            "既に存在します。上書きしますか？`r`n$destPath",
            "パッケージ定義ファイルの作成",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning)
        if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) { return }
        $batArgs += "-Force:1"
    }

    $exitCode = Invoke-BatProcess -BatPath (Join-Path $rootPath "generate-config.bat") -WorkingDirectory $rootPath -BatArgs $batArgs `
        -OnOutputLine {}

    if ($exitCode -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("パッケージ定義ファイルを作成しました。", "パッケージ定義ファイルの作成", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
    }
}

$settingsTrailingButtonVars = @{
    "GenerateConfigPath" = { param($Panel, $Y, $Field) Add-FieldActionButton -Panel $Panel -Y $Y -Text "テンプレートの更新" -Width 120 -OnClick {
        $client = $cmbSettingsGroupTarget.SelectedItem
        if (!$client) {
            [System.Windows.Forms.MessageBox]::Show("クライアントを選択してください。", "パッケージ定義ファイルの作成", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
            return
        }
        Invoke-GenerateConfigForClient -ClientName $client
    } }
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

$lnkSettingsGroupOpenXlsx = New-Object System.Windows.Forms.LinkLabel
$lnkSettingsGroupOpenXlsx.Text = "開く"

function Get-GroupSettingsFiles {
    param([string]$GroupName)
    return @(
        [PSCustomObject]@{ Path = (Get-GroupBatPath $GroupName); Save = { Save-GroupSettings -GroupName $GroupName }.GetNewClosure(); Reload = {} }
    )
}

$settingsGroupTopPanel = (New-SettingsTopPanel `
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
    }).Panel

$settingsGroupFieldPanel = New-Object System.Windows.Forms.Panel
$settingsGroupFieldPanel.Dock = [System.Windows.Forms.DockStyle]::Fill
$settingsGroupFieldPanel.AutoScroll = $true

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

    $target = $cmbSettingsGroupTarget.SelectedItem
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

    $clientOptions += [PSCustomObject]@{ Text = $newName; Value = $newName }

    foreach ($control in $script:batchInputControls.Values) {
        if ($control -is [System.Windows.Forms.ComboBox]) {
            $control.Items.Clear()
            foreach ($opt in $clientOptions) {
                $control.Items.Add($opt) | Out-Null
            }
            if ($control.Items.Count -gt 0) {
                $control.SelectedIndex = 0
            }
        }
    }
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
