# =========================================
# GUI（コース別パッケージ生成ツール）
# =========================================
# download-folder.bat → generate-package.bat → upload-folder.batを画面から実行するGUI
# （all.bat自体は呼ばず、チェックされたステージだけをGUI側から個別に実行し、ステージごとの
# 開始/完了ログを出す）。「実行」タブでダウンロード/パッケージ作成/アップロードの有効・無効を
# 切り替えて実行し、「設定」タブでset-env.batの値を編集する。

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

[System.Windows.Forms.Application]::EnableVisualStyles()
[System.Windows.Forms.Application]::SetCompatibleTextRenderingDefault($false)

if ($MyInvocation.MyCommand.Path) {
    $scriptDir = Split-Path $MyInvocation.MyCommand.Path
    $basePath = Split-Path $scriptDir -Parent
} else {
    $basePath = Split-Path ([System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName)
}
$downloadBat = Join-Path $basePath "download-folder.bat"
$generateBat = Join-Path $basePath "generate-package.bat"
$uploadBat = Join-Path $basePath "upload-folder.bat"
$clientsDir = Join-Path $basePath "clients"
$setEnvBat = Join-Path $clientsDir "set-env.bat"
$clientFilePrefix = [System.IO.Path]::GetFileNameWithoutExtension($setEnvBat)
$cp932 = [System.Text.Encoding]::GetEncoding(932)
$clientLineRegex = [regex]'^set "(?<var>\S+?)=(?<val>.*)"$'
$defaultClientLabel = "デフォルト"
$script:suppressComboSync = $false

$libraryDir = Join-Path $basePath "bats\library"
Get-ChildItem -Path $libraryDir -Filter *.ps1 -Recurse | ForEach-Object {
    . $_.FullName
}

# 子プロセス（Invoke-BatProcess経由で起動するbat/ps1）のWrite-Messageに、
# GUIログ向けの色タグ付き出力へ切り替えさせる合図
$env:GUI_LOG_MODE = "1"

function Get-ClientBatPath {
    param([string]$ClientName)
    return Join-Path $clientsDir "$clientFilePrefix-$ClientName.bat"
}

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

# 実行タブの中を「一括実行」「ファイルダウンロード」「個別パッケージの作成」「ファイルアップロード」の
# 4タブに分ける（kintone-aggregator/kintone-resourse-generatorと同じ構成）。ps2exeビルドでは
# TabPageCollection.Insert()がNotSupportedExceptionになるため、後から並び替えるのではなく、
# 最初から最終的な順序でAddしていく必要がある（一括実行タブを先にAddし、個別タブは
# New-CategoryTabControlに-TabControlで同じ$runTabControlを渡して追記させる）
$runTabControl = New-Object System.Windows.Forms.TabControl
$runTabControl.Dock = [System.Windows.Forms.DockStyle]::Top

$tabBatchAll = New-Object System.Windows.Forms.TabPage
$tabBatchAll.Text = "一括実行"
$runTabControl.Controls.Add($tabBatchAll)

$cmbClient = New-Object System.Windows.Forms.ComboBox
$cmbClient.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList

# ファイルダウンロード／個別パッケージの作成／ファイルアップロードの各個別実行タブは、
# New-CategoryTabControlのInputs（ExistingControl）へこれらのComboBoxをそのまま渡す。
# クライアント一覧はUpdate-ClientListが$cmbClientと合わせて4つまとめて更新する
$cmbDownloadClient = New-Object System.Windows.Forms.ComboBox
$cmbDownloadClient.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList

$cmbGenerateClient = New-Object System.Windows.Forms.ComboBox
$cmbGenerateClient.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList

$cmbUploadClient = New-Object System.Windows.Forms.ComboBox
$cmbUploadClient.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList

# 一括実行タブのチェックボックス／開くリンク、個別実行タブ、ログタブのラジオボタンすべてが
# ここで定義する$categoryDefsから生成される（kintone-aggregator/track-aggregatorと同じ、
# 単一の定義元からUIを組み立てる方式）。各プロパティの役割：
#   Label            個別実行タブのグループボックス見出し／実行中ログに使う名称
#   BatchLabel       一括実行タブのチェックボックス・ログタブのラジオボタンに使う名称（連番付き）
#   BatchPath        実行するbatのパス
#   EnabledVarName   一括実行時にDOWNLOAD_ENABLED等として渡す環境変数名
#   LogPrefixVarName ログタブでの絞り込みに使うログファイル名接頭辞の環境変数名
#   LocalPathVarName／(SiteUrlVarName+SitePathVarName)　「開く」リンクの開き先を解決する変数名
#     （一括実行タブの開くリンクはGet-BatchOpenTarget経由でこれを使う。個別実行タブは各タブ自身の
#     クライアント選択欄を直接閉じ込めたOpenTargetスクリプトブロックを使うため、変数名としては
#     重複するが、開く先の対象クライアントが一括実行タブ（$cmbClient）と個別実行タブ
#     （$cmbDownloadClient等）とで異なるため、素朴な使い回しができず已む無く分けている）
#   Inputs           個別実行タブに出すクライアント選択欄（ExistingControlでコンボボックスをそのまま渡す）
#   OpenTarget       個別実行タブの「開く」リンクの開き先
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

# 一括実行タブの「開く」リンク用。個別実行タブと違い対象クライアントは$cmbClient（共通の1つ）なので、
# ButtonDefが持つ変数名（LocalPathVarName、またはSiteUrlVarName+SitePathVarName）から解決する
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

$runTopPanel = $batchTab.Panel
$script:batchStepCheckboxes = $batchTab.CheckBoxes
$btnRun = $batchTab.RunButton
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
    foreach ($line in [System.IO.File]::ReadAllLines($clientBat, $cp932)) {
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
        $result[$varName] = Expand-VarTokens -Value $raw[$varName] -Resolver { param($name) Get-ResolvedVar $name } -BasePath $basePath
    }
    return $result
}

$txtLog = New-LogTextBox

$tabRun.Controls.Add($txtLog)
$tabRun.Controls.Add($runTabControl)

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

    # download→generate→uploadは前段の出力を後段が使う依存関係があるため、
    # kintone-aggregator/track-aggregator側と違い最初の失敗で処理を打ち切る（-StopOnFailure）
    $script:isRunning = $true
    Invoke-BatchRunAll -ButtonDefs $allButtonDefs -CheckBoxes $script:batchStepCheckboxes `
        -StatusLabel $lblStatus -StopOnFailure -HeaderSuffix "（$clientDisplayName）" `
        -WriteLog { param($msg) Write-Log $msg } -SetRunButtonsEnabled { param($e) Set-RunButtonsEnabled $e } `
        -InvokeStep {
            param($bd)
            Invoke-BatchStep -ButtonDef $bd -WorkingDirectory $basePath -Form $form `
                -WriteLog { param($msg) Write-Log $msg } -CurrentProcessRef ([ref]$script:currentProc) `
                -GetBatArgs { param($bd) @() }
        }

    $script:isRunning = $false
    $script:currentProc = $null
}

$btnRun.Add_Click({ Start-BatchRunAll })


$topPanel = New-Object System.Windows.Forms.Panel
$topPanel.Dock = [System.Windows.Forms.DockStyle]::Top
$topPanel.Height = 70

$lblSettingsClient = New-Object System.Windows.Forms.Label
$lblSettingsClient.Text = "クライアント"
$lblSettingsClient.AutoSize = $true
$lblSettingsClient.Location = New-Object System.Drawing.Point(20, 17)

$cmbSettingsClient = New-Object System.Windows.Forms.ComboBox
$cmbSettingsClient.Location = New-Object System.Drawing.Point(100, 14)
$cmbSettingsClient.Size = New-Object System.Drawing.Size(260, 24)
$cmbSettingsClient.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList

$btnNewClient = New-Object System.Windows.Forms.Button
$btnNewClient.Text = "新規作成..."
$btnNewClient.Location = New-Object System.Drawing.Point(370, 14)
$btnNewClient.Size = New-Object System.Drawing.Size(100, 24)

$btnSave = New-Object System.Windows.Forms.Button
$btnSave.Text = "保存"
$btnSave.Location = New-Object System.Drawing.Point(20, 44)
$btnSave.Size = New-Object System.Drawing.Size(100, 24)

$btnReload = New-Object System.Windows.Forms.Button
$btnReload.Text = "再読込"
$btnReload.Location = New-Object System.Drawing.Point(130, 44)
$btnReload.Size = New-Object System.Drawing.Size(100, 24)

$lblSaveStatus = New-Object System.Windows.Forms.Label
$lblSaveStatus.Text = ""
$lblSaveStatus.AutoSize = $true
$lblSaveStatus.Location = New-Object System.Drawing.Point(244, 50)
$lblSaveStatus.Font = New-Object System.Drawing.Font($lblSaveStatus.Font, [System.Drawing.FontStyle]::Bold)

$topPanel.Controls.AddRange(@($lblSettingsClient, $cmbSettingsClient, $btnNewClient, $btnSave, $btnReload, $lblSaveStatus))

$fieldPanel = New-Object System.Windows.Forms.Panel
$fieldPanel.Dock = [System.Windows.Forms.DockStyle]::Fill
$fieldPanel.AutoScroll = $true

$tabSettings.Controls.Add($fieldPanel)
$tabSettings.Controls.Add($topPanel)

$settingsToolTip = New-Object System.Windows.Forms.ToolTip

$groupLabels = @{
    "COMMON" = "共通"
    "DOWNLOAD" = "ダウンロード"
    "GENERATE" = "パッケージ作成"
    "UPLOAD" = "アップロード"
}

$varLabels = @{
    "COMMON_LOG_PATH" = "ログの出力先"
    "DOWNLOAD_ENABLED" = "機能の有効化"
    "DOWNLOAD_SITE_URL" = "ダウンロード元のサイトURL"
    "DOWNLOAD_SITE_PATH" = "ダウンロード元のフォルダ"
    "DOWNLOAD_SITE_TENANT_ID" = "テナントID"
    "DOWNLOAD_LOCAL_PATH" = "ダウンロード先のフォルダ"
    "DOWNLOAD_LOG_PREFIX" = "ログファイル名の接頭辞"
    "GENERATE_ENABLED" = "機能の有効化"
    "GENERATE_SOURCE_PATH" = "圧縮元のフォルダ"
    "GENERATE_CONFIG_PATH" = "パッケージ定義ファイル"
    "GENERATE_WORK_PATH" = "作業用のフォルダ"
    "GENERATE_OUTPUT_PATH" = "パッケージの出力先"
    "GENERATE_SHEETS_INCLUDE" = "対象のシート"
    "GENERATE_SHEETS_EXCLUDE" = "除外のシート"
    "GENERATE_LOG_PREFIX" = "ログファイル名の接頭辞"
    "UPLOAD_ENABLED" = "機能の有効化"
    "UPLOAD_SITE_URL" = "アップロード先のサイトURL"
    "UPLOAD_SITE_PATH" = "アップロード先のフォルダ"
    "UPLOAD_SITE_TENANT_ID" = "テナントID"
    "UPLOAD_LOCAL_PATH" = "アップロード元のフォルダ"
    "UPLOAD_ITEMS_INCLUDE" = "対象の項目形式"
    "UPLOAD_ITEMS_EXCLUDE" = "除外の項目形式"
    "UPLOAD_LOG_PREFIX" = "ログファイル名の接頭辞"
}

$script:fieldTextBoxes = @{}
$script:fieldRadios = @{}

$enabledVars = @("DOWNLOAD_ENABLED", "GENERATE_ENABLED", "UPLOAD_ENABLED")
$folderBrowseVars = @("COMMON_LOG_PATH","DOWNLOAD_LOCAL_PATH", "GENERATE_OUTPUT_PATH", "UPLOAD_LOCAL_PATH")
$fileBrowseVars = @("GENERATE_CONFIG_PATH")

$clientOverridableVars = @(
    "DOWNLOAD_ENABLED", "DOWNLOAD_SITE_URL", "DOWNLOAD_SITE_PATH", "DOWNLOAD_SITE_TENANT_ID", "DOWNLOAD_LOCAL_PATH",
    "GENERATE_ENABLED", "GENERATE_SOURCE_PATH", "GENERATE_CONFIG_PATH", "GENERATE_WORK_PATH", "GENERATE_OUTPUT_PATH",
    "GENERATE_SHEETS_INCLUDE", "GENERATE_SHEETS_EXCLUDE",
    "UPLOAD_ENABLED", "UPLOAD_SITE_URL", "UPLOAD_SITE_PATH", "UPLOAD_SITE_TENANT_ID", "UPLOAD_LOCAL_PATH",
    "UPLOAD_ITEMS_INCLUDE", "UPLOAD_ITEMS_EXCLUDE"
)
$clientRuntimeExcludeVars = @("DOWNLOAD_ENABLED", "GENERATE_ENABLED", "UPLOAD_ENABLED")

function Get-NewClientInitialValues {
    param([string]$ClientName, [hashtable]$Defaults)
    return @{
        "GENERATE_CONFIG_PATH" = $Defaults["GENERATE_CONFIG_PATH"] -replace '\.xlsx$', "_$ClientName.xlsx"
        "GENERATE_OUTPUT_PATH" = "$($Defaults["GENERATE_OUTPUT_PATH"])/$ClientName"
        "UPLOAD_SITE_PATH" = "$($Defaults["UPLOAD_SITE_PATH"])/$ClientName"
    }
}

function Get-SettingsFieldSource {
    $client = $cmbSettingsClient.SelectedItem
    if ($client -and $client -ne $defaultClientLabel) {
        $clientRaw = Get-ClientProfileRawValues $client
        $defaults = Get-SetEnvDefaults -Path $setEnvBat
        $isPendingNewClient = !(Test-Path -LiteralPath (Get-ClientBatPath $client))
        $newClientDefaults = if ($isPendingNewClient) { Get-NewClientInitialValues $client $defaults } else { @{} }
        foreach ($varName in $clientOverridableVars) {
            $varValue = if ($clientRaw.ContainsKey($varName)) { $clientRaw[$varName] } elseif ($newClientDefaults.ContainsKey($varName)) { $newClientDefaults[$varName] } else { $defaults[$varName] }
            [PSCustomObject]@{ VarName = $varName; VarValue = $varValue }
        }
    } else {
        foreach ($line in (Read-SetEnvLines -Path $setEnvBat)) {
            $m = $script:setEnvLineRegex.Match($line.Trim())
            if ($m.Success) {
                [PSCustomObject]@{ VarName = $m.Groups["var"].Value; VarValue = $m.Groups["val"].Value }
            }
        }
    }
}

function Update-SettingsFields {
    $fieldPanel.Controls.Clear()
    $script:fieldTextBoxes = @{}
    $script:fieldRadios = @{}

    $y = 10
    $lastGroup = ""

    foreach ($field in (Get-SettingsFieldSource)) {
        $varName = $field.VarName
        $varValue = $field.VarValue

        $group = $varName.Split("_")[0]
        if ($group -ne $lastGroup) {
            if ($lastGroup -ne "") {
                $y += 10
                $separator = New-Object System.Windows.Forms.Panel
                $separator.BackColor = [System.Drawing.Color]::LightGray
                $separator.Location = New-Object System.Drawing.Point(10, $y)
                $separator.Size = New-Object System.Drawing.Size(690, 2)
                $fieldPanel.Controls.Add($separator)
                $y += 14
            }

            $lblGroup = New-Object System.Windows.Forms.Label
            $lblGroup.Text = if ($groupLabels.ContainsKey($group)) { $groupLabels[$group] } else { $group }
            $lblGroup.AutoSize = $true
            $lblGroup.Location = New-Object System.Drawing.Point(10, $y)
            $lblGroup.Font = New-Object System.Drawing.Font($lblGroup.Font.FontFamily, 10, [System.Drawing.FontStyle]::Bold)
            $fieldPanel.Controls.Add($lblGroup)
            $y += 28
            $lastGroup = $group
        }

        $lbl = New-Object System.Windows.Forms.Label
        $lbl.Text = if ($varLabels.ContainsKey($varName)) { $varLabels[$varName] } else { $varName }
        $lbl.AutoSize = $false
        $lbl.Size = New-Object System.Drawing.Size(220, 20)
        $lbl.Location = New-Object System.Drawing.Point(20, $y)
        $settingsToolTip.SetToolTip($lbl, $varName)
        $fieldPanel.Controls.Add($lbl)

        if ($enabledVars -contains $varName) {
            $radioGroupPanel = New-Object System.Windows.Forms.Panel
            $radioGroupPanel.Location = New-Object System.Drawing.Point(250, ($y - 2))
            $radioGroupPanel.Size = New-Object System.Drawing.Size(200, 22)

            $radioEnabled = New-Object System.Windows.Forms.RadioButton
            $radioEnabled.Text = "有効"
            $radioEnabled.AutoSize = $true
            $radioEnabled.Location = New-Object System.Drawing.Point(0, 0)
            $radioEnabled.Checked = ($varValue -eq "1")

            $radioDisabled = New-Object System.Windows.Forms.RadioButton
            $radioDisabled.Text = "無効"
            $radioDisabled.AutoSize = $true
            $radioDisabled.Location = New-Object System.Drawing.Point(70, 0)
            $radioDisabled.Checked = ($varValue -ne "1")

            $radioGroupPanel.Controls.AddRange(@($radioEnabled, $radioDisabled))
            $fieldPanel.Controls.Add($radioGroupPanel)
            $script:fieldRadios[$varName] = $radioEnabled
        } elseif ($folderBrowseVars -contains $varName -or $fileBrowseVars -contains $varName) {
            $isFileBrowse = $fileBrowseVars -contains $varName

            $txt = New-Object System.Windows.Forms.TextBox
            $txt.Text = $varValue
            $txt.Location = New-Object System.Drawing.Point(250, ($y - 2))
            $txt.Size = New-Object System.Drawing.Size(300, 22)
            $txt.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left

            $btnBrowse = New-Object System.Windows.Forms.Button
            $btnBrowse.Text = "参照..."
            $btnBrowse.Location = New-Object System.Drawing.Point(560, ($y - 3))
            $btnBrowse.Size = New-Object System.Drawing.Size(70, 24)
            $btnBrowse.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left
            $btnBrowse.Tag = $txt

            if ($folderBrowseVars -contains $varName) {
                $btnBrowse.Add_Click({
                    $targetTxt = $this.Tag
                    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
                    $startPath = Resolve-BrowseStart -RawValue $targetTxt.Text -DefaultPath $basePath -Resolver { param($name) Get-ResolvedVar $name } -BasePath $basePath
                    if (Test-Path -LiteralPath $startPath) {
                        $dlg.SelectedPath = $startPath
                    }
                    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                        $targetTxt.Text = $dlg.SelectedPath
                    }
                })
            } else {
                $btnBrowse.Add_Click({
                    $targetTxt = $this.Tag
                    $dlg = New-Object System.Windows.Forms.OpenFileDialog
                    $dlg.Filter = "Excel ファイル (*.xlsx)|*.xlsx|すべてのファイル (*.*)|*.*"
                    $startPath = Resolve-BrowseStart -RawValue $targetTxt.Text -DefaultPath $basePath -Resolver { param($name) Get-ResolvedVar $name } -BasePath $basePath
                    if (Test-Path -LiteralPath $startPath) {
                        $dlg.InitialDirectory = Split-Path $startPath -Parent
                        $dlg.FileName = Split-Path $startPath -Leaf
                    }
                    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                        $targetTxt.Text = $dlg.FileName
                    }
                })
            }

            if ($isFileBrowse) {
                $btnOpen = New-Object System.Windows.Forms.LinkLabel
                $btnOpen.Text = "開く"
                $btnOpen.AutoSize = $false
                $btnOpen.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
                $btnOpen.Size = New-Object System.Drawing.Size(50, 22)
                $btnOpen.Location = New-Object System.Drawing.Point(640, ($y - 2))
                $btnOpen.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left
                $btnOpen.Tag = $txt
                $btnOpen.Add_LinkClicked({
                    $targetTxt = $this.Tag
                    $openPath = Resolve-BrowseStart -RawValue $targetTxt.Text -DefaultPath $basePath -Resolver { param($name) Get-ResolvedVar $name } -BasePath $basePath
                    if (Test-Path -LiteralPath $openPath) {
                        Start-Process -FilePath $openPath
                    } else {
                        [System.Windows.Forms.MessageBox]::Show("ファイルが見つかりません: $openPath", "エラー") | Out-Null
                    }
                })
                $fieldPanel.Controls.AddRange(@($txt, $btnBrowse, $btnOpen))
            } else {
                $fieldPanel.Controls.AddRange(@($txt, $btnBrowse))
            }
            $script:fieldTextBoxes[$varName] = $txt
        } else {
            $txt = New-Object System.Windows.Forms.TextBox
            $txt.Text = $varValue
            $txt.Location = New-Object System.Drawing.Point(250, ($y - 2))
            $txt.Size = New-Object System.Drawing.Size(440, 22)
            $txt.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left

            $fieldPanel.Controls.Add($txt)
            $script:fieldTextBoxes[$varName] = $txt
        }

        $y += 28
    }
}

$btnReload.Add_Click({
    Update-SettingsFields
    $lblSaveStatus.ForeColor = [System.Drawing.Color]::Black
    $lblSaveStatus.Text = "再読込しました"
})

function Get-FieldValue {
    param([string]$VarName)
    if ($script:fieldRadios.ContainsKey($VarName)) {
        if ($script:fieldRadios[$VarName].Checked) { return "1" }
        return "0"
    }
    return $script:fieldTextBoxes[$VarName].Text
}

function Save-ClientProfile {
    param([string]$ClientName)
    $clientBat = Get-ClientBatPath $ClientName
    $isNewClient = !(Test-Path -LiteralPath $clientBat)

    $newLines = foreach ($varName in $clientOverridableVars) {
        $newVal = Get-FieldValue $varName
        if ($script:fieldRadios.ContainsKey($varName)) {
            "if not defined $varName set `"$varName=$newVal`""
        } else {
            "set `"$varName=$newVal`""
        }
    }
    $content = ($newLines -join "`r`n") + "`r`n"
    [System.IO.File]::WriteAllText($clientBat, $content, $cp932)

    if ($isNewClient) {
        $defaults = Get-SetEnvDefaults -Path $setEnvBat
        $defaultConfigPath = Expand-VarTokens -Value $defaults["GENERATE_CONFIG_PATH"] -Resolver { param($name) Get-ResolvedVar $name } -BasePath $basePath
        $newConfigPath = Expand-VarTokens -Value (Get-FieldValue "GENERATE_CONFIG_PATH") -Resolver { param($name) Get-ResolvedVar $name } -BasePath $basePath
        if ($newConfigPath -ne $defaultConfigPath -and (Test-Path -LiteralPath $defaultConfigPath) -and !(Test-Path -LiteralPath $newConfigPath)) {
            New-Item (Split-Path $newConfigPath -Parent) -ItemType Directory -Force | Out-Null
            Copy-Item -LiteralPath $defaultConfigPath -Destination $newConfigPath
        }
    }
}

function Save-DefaultSettings {
    Save-EnvBatFile -Path $setEnvBat `
        -GetValueFn { param($name) Get-FieldValue $name } `
        -HasValueFn { param($name) $script:fieldRadios.ContainsKey($name) -or $script:fieldTextBoxes.ContainsKey($name) }
}

$btnSave.Add_Click({
    $client = $cmbSettingsClient.SelectedItem
    if ($client -and $client -ne $defaultClientLabel) {
        Save-ClientProfile $client
    } else {
        Save-DefaultSettings
    }

    $lblSaveStatus.ForeColor = [System.Drawing.Color]::DarkGreen
    $lblSaveStatus.Text = "保存しました"
    Update-RunCheckboxesFromClient
})

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
            [System.IO.File]::ReadAllText($file.FullName, $cp932)
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

# =========================================
# ファイルダウンロード／個別パッケージの作成／ファイルアップロードの個別実行タブ
# （kintone-aggregator/kintone-resourse-generatorと同じ、1タブ1ステージの構成）。
# 各batはclient=引数を自分で解釈する（parse_args）ため、一括実行タブのように環境変数を
# 差し替える必要はなく、選択したクライアント名をそのままbatへ渡すだけでよい
# =========================================

function Get-ClientArgValue {
    param([System.Windows.Forms.ComboBox]$ComboBox)
    $value = $ComboBox.Text.Trim()
    if ($value -and $value -ne $defaultClientLabel) { return $value }
    return ""
}

function Set-RunButtonsEnabled {
    param([bool]$Enabled)
    foreach ($chk in $script:batchStepCheckboxes) { $chk.Enabled = $Enabled }
    $btnRun.Enabled = $Enabled
    $cmbClient.Enabled = $Enabled
    $cmbDownloadClient.Enabled = $Enabled
    $cmbGenerateClient.Enabled = $Enabled
    $cmbUploadClient.Enabled = $Enabled
    Set-ButtonsEnabled -Buttons $script:individualRunButtons -Enabled $Enabled
}

function Invoke-IndividualStep {
    param($ButtonDef)

    # download/upload側のAzureサインイン待ちでURL・コードが表示されている間に実行タブを
    # 離れられてしまわないよう、一括実行と同じ$script:isRunningで外側タブの切り替えをブロックする
    $script:isRunning = $true
    Invoke-BatButton -ButtonDef $ButtonDef -WorkingDirectory $basePath -Form $form `
        -WriteLog { param($msg) Write-Log $msg } -SetRunButtonsEnabled { param($e) Set-RunButtonsEnabled $e } `
        -CurrentProcessRef ([ref]$script:currentProc) `
        -GetBatArgs {
            param($bd)
            $clientArg = Get-ClientArgValue -ComboBox $bd.InputControls['Client']
            if ($clientArg) { @("client=$clientArg") } else { @() }
        }
    $script:isRunning = $false
}

$individualTabResult = New-CategoryTabControl -TabControl $runTabControl -CategoryDefs $categoryDefs -OnRunClick { param($bd) Invoke-IndividualStep -ButtonDef $bd }
$script:individualRunButtons = $individualTabResult.RunButtons

# 一括実行タブが既定の選択タブになるため、New-CategoryTabControl側で計算済みだった
# 初期の$runTabControl.Height（個別タブ基準）をこのタブの内容量に合わせて上書きする。
# 45はNew-CategoryTabControlの$TabHeaderAllowance既定値
$runTabControl.Height = 45 + $runTopPanel.Height

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
# 既定でtabControlが「設定」タブを表示してしまうps2exeの不具合（原因不明、ビルド後のみ再現）と同様の
# 問題が$runTabControlでも起き得るため、念のため一括実行タブを明示的に選択しておく
$runTabControl.SelectedTab = $tabBatchAll
$tabControl.SelectedTab = $tabRun

[System.Windows.Forms.Application]::Run($form)