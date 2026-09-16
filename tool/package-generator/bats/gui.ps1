
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
$downloadBat = Join-Path $rootPath "download-folder.bat"
$generateBat = Join-Path $rootPath "generate-package.bat"
$uploadBat = Join-Path $rootPath "upload-folder.bat"
$clientsDir = Join-Path $rootPath "clients"
$setEnvBat = Join-Path $clientsDir "set-env.bat"
$clientFilePrefix = [System.IO.Path]::GetFileNameWithoutExtension($setEnvBat)
$clientLineRegex = [regex]'^set "(?<var>\S+?)=(?<val>.*)"$'
$defaultClientLabel = "デフォルト"
$script:suppressComboSync = $false

$libraryDir = Join-Path $rootPath "bats\library"
Get-ChildItem -Path $libraryDir -Filter *.ps1 -Recurse | ForEach-Object {
    . $_.FullName
}

$env:GUI_LOG_MODE = "1"

function Get-ClientBatPath {
    param([string]$ClientName)
    return Join-Path $clientsDir "$clientFilePrefix-$ClientName.bat"
}

$cmbClient = New-Object System.Windows.Forms.ComboBox
$cmbClient.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList

$cmbDownloadClient = New-Object System.Windows.Forms.ComboBox
$cmbDownloadClient.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList

$cmbGenerateClient = New-Object System.Windows.Forms.ComboBox
$cmbGenerateClient.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList

$cmbUploadClient = New-Object System.Windows.Forms.ComboBox
$cmbUploadClient.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList

function New-ClientInputDef {
    param([System.Windows.Forms.ComboBox]$Combo)
    return @([PSCustomObject]@{ Name = "Client"; Label = "クライアント"; ExistingControl = $Combo; LabelWidth = 80; InputWidth = 220 })
}

$categoryDefs = @(
    [PSCustomObject]@{
        Label = "ファイルダウンロード"
        ButtonDefs = @(
            [PSCustomObject]@{
                Label            = "ファイルダウンロード"
                BatchLabel       = "ファイルダウンロード"
                BatchPath        = $downloadBat
                EnabledVarName   = "DOWNLOAD_ENABLED"
                LogPrefixVarName = "DOWNLOAD_LOG_PREFIX"
                LocalPathVarName = "DOWNLOAD_LOCAL_PATH"
                Inputs           = New-ClientInputDef -Combo $cmbDownloadClient
                OpenTarget       = { Get-ValueForClient -ClientName $cmbDownloadClient.Text -VarName "DOWNLOAD_LOCAL_PATH" }
            }
        )
    }
    [PSCustomObject]@{
        Label = "個別パッケージの作成"
        ButtonDefs = @(
            [PSCustomObject]@{
                Label            = "個別パッケージの作成"
                BatchLabel       = "個別パッケージの作成"
                BatchPath        = $generateBat
                EnabledVarName   = "GENERATE_ENABLED"
                LogPrefixVarName = "GENERATE_LOG_PREFIX"
                LocalPathVarName = "GENERATE_OUTPUT_PATH"
                Inputs           = New-ClientInputDef -Combo $cmbGenerateClient
                OpenTarget       = { Get-ValueForClient -ClientName $cmbGenerateClient.Text -VarName "GENERATE_OUTPUT_PATH" }
            }
        )
    }
    [PSCustomObject]@{
        Label = "ファイルアップロード"
        ButtonDefs = @(
            [PSCustomObject]@{
                Label            = "ファイルアップロード"
                BatchLabel       = "ファイルアップロード"
                BatchPath        = $uploadBat
                EnabledVarName   = "UPLOAD_ENABLED"
                LogPrefixVarName = "UPLOAD_LOG_PREFIX"
                SiteUrlVarName   = "UPLOAD_SITE_URL"
                SitePathVarName  = "UPLOAD_SITE_PATH"
                Inputs           = New-ClientInputDef -Combo $cmbUploadClient
                OpenTarget       = {
                    Get-SharePointFolderUrl `
                        -SiteUrl (Get-ValueForClient -ClientName $cmbUploadClient.Text -VarName "UPLOAD_SITE_URL") `
                        -SitePath (Get-ValueForClient -ClientName $cmbUploadClient.Text -VarName "UPLOAD_SITE_PATH")
                }
            }
        )
    }
)
$allButtonDefs = @($categoryDefs | ForEach-Object { $_.ButtonDefs })

$form = New-Object System.Windows.Forms.Form
$form.Text = "コース別パッケージ生成ツール"
$form.Size = New-Object System.Drawing.Size(760, 560)
$form.StartPosition = "CenterScreen"
$form.MinimumSize = New-Object System.Drawing.Size(520, 360)

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

$script:isRunning = $false
$script:lastClientVars = @()
$tabControl.Add_Selecting({
    if ($script:isRunning -and $_.TabPage -ne $tabRun) {
        $_.Cancel = $true
    }
})

$execTabControl = New-Object System.Windows.Forms.TabControl
$execTabControl.Dock = [System.Windows.Forms.DockStyle]::Top

$tabBatchAll = New-Object System.Windows.Forms.TabPage
$tabBatchAll.Text = "一括実行"
$execTabControl.Controls.Add($tabBatchAll)

function Get-BatchOpenTarget {
    param($ButtonDef, [string]$ClientName)
    if ($ButtonDef.SiteUrlVarName) {
        return Get-SharePointFolderUrl `
            -SiteUrl (Get-ValueForClient -ClientName $ClientName -VarName $ButtonDef.SiteUrlVarName) `
            -SitePath (Get-ValueForClient -ClientName $ClientName -VarName $ButtonDef.SitePathVarName)
    }
    return Get-ValueForClient -ClientName $ClientName -VarName $ButtonDef.LocalPathVarName
}

function Get-SharePointFolderUrl {
    param([string]$SiteUrl, [string]$SitePath)
    if (!$SiteUrl -or !$SitePath) { return $null }
    $siteUri = [Uri]$SiteUrl
    $library = ($SitePath -split '/', 2)[0]
    $serverRelativePath = "$($siteUri.AbsolutePath.TrimEnd('/'))/$SitePath"
    return "$($siteUri.Scheme)://$($siteUri.Authority)$($siteUri.AbsolutePath.TrimEnd('/'))/$([Uri]::EscapeDataString($library))/Forms/AllItems.aspx?id=$([Uri]::EscapeDataString($serverRelativePath))"
}

$batchTab = New-BatchRunTab -TabPage $tabBatchAll -ButtonDefs $allButtonDefs -RunButtonText "実行" `
    -Inputs @(
        [PSCustomObject]@{ Name = "Client"; Label = "クライアント"; ExistingControl = $cmbClient; LabelWidth = 80; InputWidth = 260 }
    ) `
    -ShowOpenLink { param($bd) $true } `
    -OnOpenClick {
        param($bd, $inputControls)
        Open-TargetOrWarn -Path (Get-BatchOpenTarget -ButtonDef $bd -ClientName $inputControls["Client"].SelectedItem)
    }

$batchPanel = $batchTab.Panel
$script:batchStepCheckboxes = $batchTab.CheckBoxes
$btnRunAll = $batchTab.RunButton
$lblStatus = $batchTab.StatusLabel

function Update-ClientComboItems {
    param(
        [System.Windows.Forms.ComboBox]$ComboBox,
        [string[]]$FixedItems
    )
    $selected = $ComboBox.SelectedItem
    $script:suppressComboSync = $true
    $ComboBox.Items.Clear()
    foreach ($item in $FixedItems) {
        $ComboBox.Items.Add($item) | Out-Null
    }
    Get-ChildItem -LiteralPath $clientsDir -Filter "$clientFilePrefix-*.bat" -ErrorAction SilentlyContinue | Sort-Object Name | ForEach-Object {
        $clientName = [System.IO.Path]::GetFileNameWithoutExtension($_.Name).Substring($clientFilePrefix.Length + 1)
        $ComboBox.Items.Add($clientName) | Out-Null
    }
    $ComboBox.SelectedIndex = if ($selected -and $ComboBox.Items.Contains($selected)) { $ComboBox.Items.IndexOf($selected) } else { 0 }
    $script:suppressComboSync = $false
}

function Update-ClientList {
    Update-ClientComboItems -ComboBox $cmbClient -FixedItems @($defaultClientLabel)
    Update-ClientComboItems -ComboBox $cmbDownloadClient -FixedItems @($defaultClientLabel)
    Update-ClientComboItems -ComboBox $cmbGenerateClient -FixedItems @($defaultClientLabel)
    Update-ClientComboItems -ComboBox $cmbUploadClient -FixedItems @($defaultClientLabel)
}
Update-ClientList

function Get-ClientProfileRawValues {
    param([string]$ClientName)
    $result = @{}
    $clientBat = Get-ClientBatPath $ClientName
    if (!(Test-Path -LiteralPath $clientBat)) {
        return $result
    }
    foreach ($line in [System.IO.File]::ReadAllLines($clientBat, $script:cp932Encoding)) {
        $trimmed = $line.Trim()
        $m = $clientLineRegex.Match($trimmed)
        if (!$m.Success) {
            $m = $script:setEnvLineRegex.Match($trimmed)
        }
        if ($m.Success) {
            $result[$m.Groups["var"].Value] = $m.Groups["val"].Value
        }
    }
    return $result
}

function Get-ClientProfileValues {
    param([string]$ClientName)
    $raw = Get-ClientProfileRawValues $ClientName
    $result = @{}
    foreach ($varName in $raw.Keys) {
        $result[$varName] = Expand-VarTokens -Value $raw[$varName] -Resolver { param($name) Get-ResolvedVar $name } -BasePath $rootPath
    }
    return $result
}

$txtLog = New-LogTextBox

Add-StackedDockedControls -Container $tabRun -ControlsTopToBottom @($execTabControl, $txtLog)

function Start-BatchRunAll {
    $selectedClient = $cmbClient.SelectedItem
    $clientDisplayName = if ($selectedClient -and $selectedClient -ne $defaultClientLabel) { $selectedClient } else { $defaultClientLabel }

    foreach ($chk in $script:batchStepCheckboxes) {
        Set-Item -Path "env:$($chk.Tag.EnabledVarName)" -Value $(if ($chk.Checked) { "1" } else { "0" })
    }

    foreach ($varName in $script:lastClientVars) {
        [Environment]::SetEnvironmentVariable($varName, $null)
    }
    $script:lastClientVars = @()

    if ($selectedClient -and $selectedClient -ne $defaultClientLabel) {
        $clientValues = Get-ClientProfileValues $selectedClient
        $appliedVars = @()
        foreach ($varName in $clientValues.Keys) {
            if ($clientRuntimeExcludeVars -contains $varName) {
                continue
            }
            [Environment]::SetEnvironmentVariable($varName, $clientValues[$varName])
            $appliedVars += $varName
        }
        $script:lastClientVars = $appliedVars
        [Environment]::SetEnvironmentVariable("CLIENT_NAME", $selectedClient)
    } else {
        [Environment]::SetEnvironmentVariable("CLIENT_NAME", $null)
    }

    $script:isRunning = $true
    Invoke-BatchRunAll -ButtonDefs $allButtonDefs -CheckBoxes $script:batchStepCheckboxes `
        -StatusLabel $lblStatus -StopOnFailure -HeaderSuffix "（$clientDisplayName）" `
        -WriteLog { param($msg) Write-Log $msg } -SetRunButtonsEnabled { param($e) Set-RunButtonsEnabled $e } `
        -InvokeStep {
            param($bd)
            Invoke-BatchStep -ButtonDef $bd -WorkingDirectory $rootPath -Form $form `
                -WriteLog { param($msg) Write-Log $msg } -CurrentProcessRef ([ref]$script:currentProc) `
                -GetBatArgs { param($bd) @() }
        }

    $script:isRunning = $false
    $script:currentProc = $null
}

$btnRunAll.Add_Click({ Start-BatchRunAll })

function Update-LogClientList {
    Update-ClientComboItems -ComboBox $script:logTab.ExtraCombo -FixedItems @("すべて", $defaultClientLabel)
}

$script:logTab = New-LogTab -TabPage $tabLogs -ButtonDefs $allButtonDefs `
    -LabelFn { param($bd) Get-BatchDisplayLabel -ButtonDef $bd } `
    -ExtraLabelText "クライアント" -ExtraComboWidth 260 `
    -GetLogPathFn { Get-ResolvedVar "COMMON_LOG_PATH" } `
    -OnAfterClear { Update-LogClientList } `
    -OnUpdateLogView { Update-LogView }
$cmbLogClient = $script:logTab.ExtraCombo

function Update-LogView {
    $selectedRadio = $script:logTab.Radios | Where-Object { $_.Checked } | Select-Object -First 1
    if (-not $selectedRadio) { return }
    $logPath = Get-ResolvedVar "COMMON_LOG_PATH"
    $prefix = Get-ResolvedVar $selectedRadio.Tag.LogPrefixVarName

    $script:logTab.ContentBox.Text = ""

    if (!($logPath -and $prefix -and (Test-Path -LiteralPath $logPath))) {
        return
    }

    $logClient = $cmbLogClient.SelectedItem
    $clientFilter = if ($logClient -and $logClient -ne "すべて") { "$logClient" + "_" } else { "" }
    $files = Get-ChildItem -LiteralPath $logPath -Filter "$prefix$clientFilter*.log" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending

    $sections = foreach ($file in $files) {
        try {
            [System.IO.File]::ReadAllText($file.FullName, $script:cp932Encoding)
        } catch {
            "$($file.Name) は他のプロセスで使用中のため表示できません（実行中の可能性があります）。"
        }
    }
    $script:logTab.ContentBox.Text = $sections -join "`r`n`r`n"
}

foreach ($radio in $script:logTab.Radios) {
    $radio.Add_CheckedChanged({ if ($this.Checked) { Update-LogView } })
}
$cmbLogClient.Add_SelectedIndexChanged({ if (!$script:suppressComboSync) { Update-LogView } })


$lblSettingsClient = New-Object System.Windows.Forms.Label
$lblSettingsClient.Text = "クライアント"

$cmbSettingsClient = New-Object System.Windows.Forms.ComboBox
$cmbSettingsClient.Size = New-Object System.Drawing.Size(260, 24)
$cmbSettingsClient.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList

$btnNewClient = New-Object System.Windows.Forms.Button
$btnNewClient.Text = "新規作成..."
$btnNewClient.Size = New-Object System.Drawing.Size(100, 24)

$settingsToolTip = New-Object System.Windows.Forms.ToolTip

$enabledRadioOptions = @(
    [PSCustomObject]@{ Label = "有効"; Value = "1" }
    [PSCustomObject]@{ Label = "無効"; Value = "0" }
)

$settingsGroups = [ordered]@{
    "COMMON" = @{
        Label = "共通"
        Overridable = $false
        Vars = [ordered]@{
            "COMMON_LOG_PATH" = @{ Label = "ログの出力先"; Browse = "Folder" }
        }
    }
    "DOWNLOAD" = @{
        Label = "ダウンロード"
        Vars = [ordered]@{
            "DOWNLOAD_ENABLED"        = @{ Label = "機能の有効化"; Radio = $enabledRadioOptions; IsEnabledFlag = $true }
            "DOWNLOAD_SITE_URL"       = @{ Label = "ダウンロード元のサイトURL" }
            "DOWNLOAD_SITE_PATH"      = @{ Label = "ダウンロード元のフォルダ" }
            "DOWNLOAD_SITE_TENANT_ID" = @{ Label = "テナントID" }
            "DOWNLOAD_LOCAL_PATH"     = @{ Label = "ダウンロード先のフォルダ"; Browse = "Folder" }
            "DOWNLOAD_LOG_PREFIX"     = @{ Label = "ログファイル名の接頭辞"; Overridable = $false }
        }
    }
    "GENERATE" = @{
        Label = "パッケージ作成"
        Vars = [ordered]@{
            "GENERATE_ENABLED"        = @{ Label = "機能の有効化"; Radio = $enabledRadioOptions; IsEnabledFlag = $true }
            "GENERATE_SOURCE_PATH"    = @{ Label = "圧縮元のフォルダ" }
            "GENERATE_CONFIG_PATH"    = @{ Label = "パッケージ定義ファイル"; Browse = "File" }
            "GENERATE_WORK_PATH"      = @{ Label = "作業用のフォルダ" }
            "GENERATE_OUTPUT_PATH"    = @{ Label = "パッケージの出力先"; Browse = "Folder" }
            "GENERATE_SHEETS_INCLUDE" = @{ Label = "対象のシート" }
            "GENERATE_SHEETS_EXCLUDE" = @{ Label = "除外のシート" }
            "GENERATE_LOG_PREFIX"     = @{ Label = "ログファイル名の接頭辞"; Overridable = $false }
        }
    }
    "UPLOAD" = @{
        Label = "アップロード"
        Vars = [ordered]@{
            "UPLOAD_ENABLED"        = @{ Label = "機能の有効化"; Radio = $enabledRadioOptions; IsEnabledFlag = $true }
            "UPLOAD_SITE_URL"       = @{ Label = "アップロード先のサイトURL" }
            "UPLOAD_SITE_PATH"      = @{ Label = "アップロード先のフォルダ" }
            "UPLOAD_SITE_TENANT_ID" = @{ Label = "テナントID" }
            "UPLOAD_LOCAL_PATH"     = @{ Label = "アップロード元のフォルダ"; Browse = "Folder" }
            "UPLOAD_ITEMS_INCLUDE"  = @{ Label = "対象の項目形式" }
            "UPLOAD_ITEMS_EXCLUDE"  = @{ Label = "除外の項目形式" }
            "UPLOAD_LOG_PREFIX"     = @{ Label = "ログファイル名の接頭辞"; Overridable = $false }
        }
    }
}

$settingsGroupLabels = @{}
$settingsVarLabels = @{}
$settingsFolderBrowseVars = @()
$settingsFileBrowseVars = @()
$settingsMaskedVars = @()
$settingsMultilineVars = @()
$settingsRadioVars = @{}
$enabledVars = @()
$clientOverridableVars = @()
foreach ($groupKey in $settingsGroups.Keys) {
    $group = $settingsGroups[$groupKey]
    $settingsGroupLabels[$groupKey] = $group.Label
    $isOverridableGroup = if ($group.ContainsKey("Overridable")) { $group.Overridable } else { $true }
    foreach ($varKey in $group.Vars.Keys) {
        $varDef = $group.Vars[$varKey]
        $settingsVarLabels[$varKey] = $varDef.Label
        if ($varDef.Browse -eq "Folder") { $settingsFolderBrowseVars += $varKey }
        if ($varDef.Browse -eq "File") { $settingsFileBrowseVars += $varKey }
        if ($varDef.Masked) { $settingsMaskedVars += $varKey }
        if ($varDef.Multiline) { $settingsMultilineVars += $varKey }
        if ($varDef.Radio) { $settingsRadioVars[$varKey] = $varDef.Radio }
        if ($varDef.IsEnabledFlag) { $enabledVars += $varKey }
        $isOverridableVar = if ($varDef.ContainsKey("Overridable")) { $varDef.Overridable } else { $isOverridableGroup }
        if ($isOverridableVar) { $clientOverridableVars += $varKey }
    }
}
$clientRuntimeExcludeVars = $enabledVars

$script:fieldTextBoxes = @{}

$script:commonEnvResolver = { param($name) Get-ResolvedVar $name }

function Get-NewClientInitialValues {
    param([string]$ClientName, [hashtable]$Defaults)
    return @{
        "GENERATE_CONFIG_PATH" = $Defaults["GENERATE_CONFIG_PATH"] -replace '\.xlsx$', "_$ClientName.xlsx"
        "GENERATE_OUTPUT_PATH" = "$($Defaults["GENERATE_OUTPUT_PATH"])/$ClientName"
        "UPLOAD_SITE_PATH" = "$($Defaults["UPLOAD_SITE_PATH"])/$ClientName"
    }
}

function Get-SettingsFieldRows {
    $client = $cmbSettingsClient.SelectedItem
    if ($client -and $client -ne $defaultClientLabel) {
        $clientRaw = Get-ClientProfileRawValues $client
        $defaults = Get-SetEnvDefaults -Path $setEnvBat
        $isPendingNewClient = !(Test-Path -LiteralPath (Get-ClientBatPath $client))
        $newClientDefaults = if ($isPendingNewClient) { Get-NewClientInitialValues $client $defaults } else { @{} }
        foreach ($varName in $clientOverridableVars) {
            $varValue = if ($clientRaw.ContainsKey($varName)) { $clientRaw[$varName] } elseif ($newClientDefaults.ContainsKey($varName)) { $newClientDefaults[$varName] } else { $defaults[$varName] }
            [PSCustomObject]@{ Group = $varName.Split("_")[0]; VarName = $varName; Value = $varValue; Key = $varName }
        }
    } else {
        foreach ($line in (Read-SetEnvLines -Path $setEnvBat)) {
            $m = $script:setEnvLineRegex.Match($line.Trim())
            if ($m.Success) {
                [PSCustomObject]@{ Group = $m.Groups["var"].Value.Split("_")[0]; VarName = $m.Groups["var"].Value; Value = $m.Groups["val"].Value; Key = $m.Groups["var"].Value }
            }
        }
    }
}

function Update-SettingsFields {
    Render-SettingsFields -Panel $fieldPanel -Rows (Get-SettingsFieldRows) -TextBoxes $script:fieldTextBoxes -RadioVars $settingsRadioVars -TrailingButtonVars $settingsTrailingButtonVars `
        -GroupLabels $settingsGroupLabels -VarLabels $settingsVarLabels -ToolTip $settingsToolTip -RootPath $rootPath -EnvResolver $script:commonEnvResolver `
        -MultilineVars $settingsMultilineVars -MaskedVars $settingsMaskedVars -FolderBrowseVars $settingsFolderBrowseVars -FileBrowseVars $settingsFileBrowseVars | Out-Null
}

function Get-FieldValue {
    param([string]$VarName)
    return $script:fieldTextBoxes[$VarName].Text
}

function Save-ClientProfile {
    param([string]$ClientName)
    $clientBat = Get-ClientBatPath $ClientName
    $isNewClient = !(Test-Path -LiteralPath $clientBat)

    $newLines = foreach ($varName in $clientOverridableVars) {
        $newVal = Get-FieldValue $varName
        if ($enabledVars -contains $varName) {
            "if not defined $varName set `"$varName=$newVal`""
        } else {
            "set `"$varName=$newVal`""
        }
    }
    $content = ($newLines -join "`r`n") + "`r`n"
    [System.IO.File]::WriteAllText($clientBat, $content, $script:cp932Encoding)

    if ($isNewClient) {
        $defaults = Get-SetEnvDefaults -Path $setEnvBat
        $defaultConfigPath = Expand-VarTokens -Value $defaults["GENERATE_CONFIG_PATH"] -Resolver $script:commonEnvResolver -BasePath $rootPath
        $newConfigPath = Expand-VarTokens -Value (Get-FieldValue "GENERATE_CONFIG_PATH") -Resolver $script:commonEnvResolver -BasePath $rootPath
        if ($newConfigPath -ne $defaultConfigPath -and (Test-Path -LiteralPath $defaultConfigPath) -and !(Test-Path -LiteralPath $newConfigPath)) {
            New-Item (Split-Path $newConfigPath -Parent) -ItemType Directory -Force | Out-Null
            Copy-Item -LiteralPath $defaultConfigPath -Destination $newConfigPath
        }
    }
}

function Save-DefaultSettings {
    Save-EnvBatFile -Path $setEnvBat `
        -GetValueFn { param($name) Get-FieldValue $name } `
        -HasValueFn { param($name) $script:fieldTextBoxes.ContainsKey($name) }
}

function Get-SettingsFiles {
    $client = $cmbSettingsClient.SelectedItem
    if ($client -and $client -ne $defaultClientLabel) {
        return @([PSCustomObject]@{ Path = (Get-ClientBatPath $client); Save = { Save-ClientProfile $client }.GetNewClosure(); Reload = {} })
    } else {
        return @([PSCustomObject]@{ Path = $setEnvBat; Save = { Save-DefaultSettings }; Reload = {} })
    }
}

function Invoke-GenerateConfigForClient {
    param([string]$ClientName)

    $clientRaw = Get-ClientProfileRawValues $ClientName
    $defaults = Get-SetEnvDefaults -Path $setEnvBat
    $rawSourcePath = if ($clientRaw.ContainsKey("GENERATE_SOURCE_PATH")) { $clientRaw["GENERATE_SOURCE_PATH"] } else { $defaults["GENERATE_SOURCE_PATH"] }
    $sourcePath = Expand-VarTokens -Value $rawSourcePath -Resolver { param($name) Get-ResolvedVar $name } -BasePath $rootPath

    if ([string]::IsNullOrWhiteSpace($sourcePath) -or !(Test-Path -LiteralPath $sourcePath)) {
        [System.Windows.Forms.MessageBox]::Show(
            "圧縮元のフォルダが未設定か、存在しません。`r`n先に「圧縮元のフォルダ」を設定して保存してください。",
            "パッケージ定義ファイルの作成",
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        return
    }

    $destPath = Join-Path $rootPath "config\package_definition_$ClientName.xlsx"
    $batArgs = @("client:$ClientName")

    if (Test-Path -LiteralPath $destPath) {
        $confirm = [System.Windows.Forms.MessageBox]::Show(
            "既に存在します。上書きしますか？`r`n$destPath",
            "パッケージ定義ファイルの作成",
            [System.Windows.Forms.MessageBoxButtons]::YesNo,
            [System.Windows.Forms.MessageBoxIcon]::Warning)
        if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) { return }
        $batArgs += "force:1"
    }

    $exitCode = Invoke-BatProcess -BatPath (Join-Path $rootPath "generate-config.bat") -WorkingDirectory $rootPath -BatArgs $batArgs `
        -OnOutputLine {}

    if ($exitCode -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("作成しました：$destPath", "パッケージ定義ファイルの作成", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
    } else {
        [System.Windows.Forms.MessageBox]::Show("作成に失敗しました。", "パッケージ定義ファイルの作成に失敗しました", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
    }
}

$settingsTrailingButtonVars = @{
    "GENERATE_CONFIG_PATH" = { param($Panel, $Y, $Field) Add-FieldActionButton -Panel $Panel -Y $Y -Text "更新" -OnClick {
        $client = $cmbSettingsClient.SelectedItem
        if (!$client -or $client -eq $defaultClientLabel) {
            [System.Windows.Forms.MessageBox]::Show("クライアントを選択してください。", "パッケージ定義ファイルの作成", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
            return
        }
        foreach ($f in (Get-SettingsFiles)) { & $f.Save }
        Update-RunCheckboxesFromClient
        Invoke-GenerateConfigForClient -ClientName $client
    } }
}

$settingsTopPanel = New-SettingsTopPanel `
    -ExtraControls @($lblSettingsClient, $cmbSettingsClient, $btnNewClient) `
    -OnSave {
        foreach ($f in (Get-SettingsFiles)) { & $f.Save }
        Update-RunCheckboxesFromClient
    } `
    -OnReload { foreach ($f in (Get-SettingsFiles)) { & $f.Reload }; Update-SettingsFields }
$topPanel = $settingsTopPanel.Panel

$fieldPanel = New-Object System.Windows.Forms.Panel
$fieldPanel.Dock = [System.Windows.Forms.DockStyle]::Fill
$fieldPanel.AutoScroll = $true

$tabSettings.Controls.Add($fieldPanel)
$tabSettings.Controls.Add($topPanel)

function Update-SettingsClientList {
    Update-ClientComboItems -ComboBox $cmbSettingsClient -FixedItems @($defaultClientLabel)
}
Update-SettingsClientList
Update-SettingsFields

$cmbSettingsClient.Add_SelectedIndexChanged({ if (!$script:suppressComboSync) { Update-SettingsFields } })

$btnNewClient.Add_Click({
    Add-Type -AssemblyName Microsoft.VisualBasic
    $newName = [Microsoft.VisualBasic.Interaction]::InputBox("クライアント名を入力してください", "クライアントの新規作成", "")
    $newName = $newName.Trim()
    if (!$newName) {
        return
    }

    $newClientBat = Get-ClientBatPath $newName
    if ((Test-Path -LiteralPath $newClientBat) -or $cmbSettingsClient.Items.Contains($newName)) {
        [System.Windows.Forms.MessageBox]::Show("「$newName」は既に存在します。", "クライアントの新規作成", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        return
    }

    $cmbSettingsClient.Items.Add($newName) | Out-Null
    $cmbSettingsClient.SelectedItem = $newName
})


function Get-ValueForClient {
    param([string]$ClientName, [string]$VarName)
    if ($ClientName -and $ClientName -ne $defaultClientLabel) {
        $clientValues = Get-ClientProfileValues $ClientName
        if ($clientValues.ContainsKey($VarName)) {
            return $clientValues[$VarName]
        }
    }
    return Get-ResolvedVar $VarName
}

function Get-ClientAwareEnabledValue {
    param([string]$VarName)
    return Get-ValueForClient -ClientName $cmbClient.SelectedItem -VarName $VarName
}

function Update-RunCheckboxesFromClient {
    foreach ($chk in $script:batchStepCheckboxes) {
        $chk.Checked = (Get-ClientAwareEnabledValue $chk.Tag.EnabledVarName) -eq "1"
    }
}

$cmbClient.Add_SelectedIndexChanged({ if (!$script:suppressComboSync) { Update-RunCheckboxesFromClient } })


function Get-ClientArgValue {
    param([System.Windows.Forms.ComboBox]$ComboBox)
    $value = $ComboBox.Text.Trim()
    if ($value -and $value -ne $defaultClientLabel) { return $value }
    return ""
}

function Set-RunButtonsEnabled {
    param([bool]$Enabled)
    foreach ($chk in $script:batchStepCheckboxes) { $chk.Enabled = $Enabled }
    $btnRunAll.Enabled = $Enabled
    $cmbClient.Enabled = $Enabled
    $cmbDownloadClient.Enabled = $Enabled
    $cmbGenerateClient.Enabled = $Enabled
    $cmbUploadClient.Enabled = $Enabled
    Set-ButtonsEnabled -Buttons $script:runButtons -Enabled $Enabled
}

function Invoke-IndividualStep {
    param($ButtonDef)

    $script:isRunning = $true
    Invoke-BatButton -ButtonDef $ButtonDef -WorkingDirectory $rootPath -Form $form `
        -WriteLog { param($msg) Write-Log $msg } -SetRunButtonsEnabled { param($e) Set-RunButtonsEnabled $e } `
        -CurrentProcessRef ([ref]$script:currentProc) `
        -GetBatArgs {
            param($bd)
            $clientArg = Get-ClientArgValue -ComboBox $bd.InputControls['Client']
            if ($clientArg) { @("client=$clientArg") } else { @() }
        }
    $script:isRunning = $false
}

$tabResult = New-CategoryTabControl -TabControl $execTabControl -CategoryDefs $categoryDefs -OnRunClick { param($bd) Invoke-IndividualStep -ButtonDef $bd }
$script:runButtons = $tabResult.RunButtons

$execTabControl.Height = 45 + $batchPanel.Height

$tabControl.Add_SelectedIndexChanged({
    if ($tabControl.SelectedTab -eq $tabRun) {
        Update-ClientList
    } elseif ($tabControl.SelectedTab -eq $tabLogs) {
        Update-LogClientList
        Update-LogView
    } elseif ($tabControl.SelectedTab -eq $tabSettings) {
        Update-SettingsClientList
    }
})

Update-ClientList
Update-RunCheckboxesFromClient
Update-LogClientList
Update-LogView
$execTabControl.SelectedTab = $tabBatchAll
$tabControl.SelectedTab = $tabRun

$form.Add_Shown({ Update-SettingsFields })

[System.Windows.Forms.Application]::Run($form)