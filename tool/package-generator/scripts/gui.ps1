# =========================================
# GUI（コース別パッケージ生成ツール）
# =========================================
# all.batを画面から実行するためのGUI。「実行」タブでダウンロード/パッケージ作成/
# アップロードの有効・無効を切り替えて実行し、「設定」タブでset-env.batの値を編集する。

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
$allBat = Join-Path $basePath "all.bat"
$clientsDir = Join-Path $basePath "clients"
$setEnvBat = Join-Path $clientsDir "set-env.bat"
$clientFilePrefix = [System.IO.Path]::GetFileNameWithoutExtension($setEnvBat)
$cp932 = [System.Text.Encoding]::GetEncoding(932)
$clientLineRegex = [regex]'^set "(?<var>\S+?)=(?<val>.*)"$'
$clientEnabledLineRegex = [regex]'^if not defined (?<var>\S+) set "\k<var>=(?<val>.*)"$'
$defaultClientLabel = "デフォルト"
$script:suppressComboSync = $false

function Get-ClientBatPath {
    param([string]$ClientName)
    return Join-Path $clientsDir "$clientFilePrefix-$ClientName.bat"
}

$form = New-Object System.Windows.Forms.Form
$form.Text = "コース別パッケージ生成ツール"
$form.Size = New-Object System.Drawing.Size(700, 560)
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

$runTopPanel = New-Object System.Windows.Forms.Panel
$runTopPanel.Dock = [System.Windows.Forms.DockStyle]::Top
$runTopPanel.Height = 176

$lblClient = New-Object System.Windows.Forms.Label
$lblClient.Text = "クライアント"
$lblClient.AutoSize = $true
$lblClient.Location = New-Object System.Drawing.Point(20, 17)

$cmbClient = New-Object System.Windows.Forms.ComboBox
$cmbClient.Location = New-Object System.Drawing.Point(100, 14)
$cmbClient.Size = New-Object System.Drawing.Size(260, 24)
$cmbClient.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList

$chkDownload = New-Object System.Windows.Forms.CheckBox
$chkDownload.Text = "1. ファイルダウンロード"
$chkDownload.AutoSize = $true
$chkDownload.Location = New-Object System.Drawing.Point(20, 40)

$chkGenerate = New-Object System.Windows.Forms.CheckBox
$chkGenerate.Text = "2. 個別パッケージの作成"
$chkGenerate.AutoSize = $true
$chkGenerate.Location = New-Object System.Drawing.Point(20, 66)

$chkUpload = New-Object System.Windows.Forms.CheckBox
$chkUpload.Text = "3. ファイルアップロード"
$chkUpload.AutoSize = $true
$chkUpload.Location = New-Object System.Drawing.Point(20, 92)

$btnRun = New-Object System.Windows.Forms.Button
$btnRun.Text = "実行"
$btnRun.Location = New-Object System.Drawing.Point(20, 126)
$btnRun.Size = New-Object System.Drawing.Size(100, 24)

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Text = ""
$lblStatus.AutoSize = $true
$lblStatus.Location = New-Object System.Drawing.Point(134, 136)
$lblStatus.Font = New-Object System.Drawing.Font($lblStatus.Font, [System.Drawing.FontStyle]::Bold)

function Update-ClientComboItems {
    param(
        [System.Windows.Forms.ComboBox]$ComboBox,
        [string]$FirstItem
    )
    $selected = $ComboBox.SelectedItem
    $script:suppressComboSync = $true
    $ComboBox.Items.Clear()
    $ComboBox.Items.Add($FirstItem) | Out-Null
    Get-ChildItem -LiteralPath $clientsDir -Filter "$clientFilePrefix-*.bat" -ErrorAction SilentlyContinue | Sort-Object Name | ForEach-Object {
        $clientName = [System.IO.Path]::GetFileNameWithoutExtension($_.Name).Substring($clientFilePrefix.Length + 1)
        $ComboBox.Items.Add($clientName) | Out-Null
    }
    $ComboBox.SelectedIndex = if ($selected -and $ComboBox.Items.Contains($selected)) { $ComboBox.Items.IndexOf($selected) } else { 0 }
    $script:suppressComboSync = $false
}

function Update-ClientList {
    Update-ClientComboItems -ComboBox $cmbClient -FirstItem $defaultClientLabel
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
            $m = $clientEnabledLineRegex.Match($trimmed)
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
        $result[$varName] = Expand-VarTokens $raw[$varName]
    }
    return $result
}

$runTopPanel.Controls.AddRange(@($chkDownload, $chkGenerate, $chkUpload, $btnRun, $lblStatus, $lblClient, $cmbClient))

$txtLog = New-Object System.Windows.Forms.RichTextBox
$txtLog.Multiline = $true
$txtLog.ScrollBars = [System.Windows.Forms.RichTextBoxScrollBars]::Vertical
$txtLog.ReadOnly = $true
$txtLog.Font = New-Object System.Drawing.Font("Consolas", 9)
$txtLog.Dock = [System.Windows.Forms.DockStyle]::Fill
$txtLog.DetectUrls = $true
$txtLog.Add_LinkClicked({ [System.Diagnostics.Process]::Start($_.LinkText) })

$tabRun.Controls.Add($txtLog)
$tabRun.Controls.Add($runTopPanel)

function Write-Log {
    param([string]$Text)
    $txtLog.AppendText("$Text`r`n")
}

$btnRun.Add_Click({
    $script:isRunning = $true
    $chkDownload.Enabled = $false
    $chkGenerate.Enabled = $false
    $chkUpload.Enabled = $false
    $btnRun.Enabled = $false
    $cmbClient.Enabled = $false
    $lblStatus.ForeColor = [System.Drawing.Color]::Black
    $lblStatus.Text = "実行中..."
    if ($txtLog.Text.Length -gt 0) {
        Write-Log ""
        Write-Log "-------------------- 新しい実行 --------------------"
        Write-Log ""
    }

    $env:DOWNLOAD_ENABLED = if ($chkDownload.Checked) { "1" } else { "0" }
    $env:GENERATE_ENABLED = if ($chkGenerate.Checked) { "1" } else { "0" }
    $env:UPLOAD_ENABLED = if ($chkUpload.Checked) { "1" } else { "0" }

    foreach ($varName in $script:lastClientVars) {
        [Environment]::SetEnvironmentVariable($varName, $null)
    }
    $script:lastClientVars = @()

    $selectedClient = $cmbClient.SelectedItem
    if ($selectedClient -and $selectedClient -ne $defaultClientLabel) {
        Write-Log "# クライアント"
        Write-Log "$selectedClient"
        Write-Log ""
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

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "cmd.exe"
    $psi.Arguments = "/c ""`"$allBat`" 2>&1"""
    $psi.WorkingDirectory = $basePath
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.CreateNoWindow = $true
    $psi.StandardOutputEncoding = $cp932

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi

    $outputQueue = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()
    $outputAction = {
        if ($null -ne $EventArgs.Data) {
            $Event.MessageData.Enqueue($EventArgs.Data)
        }
    }
    $outputEvent = Register-ObjectEvent -InputObject $proc -EventName OutputDataReceived -Action $outputAction -MessageData $outputQueue

    $proc.Start() | Out-Null
    $script:currentProc = $proc
    $proc.BeginOutputReadLine()

    while (!$proc.HasExited) {
        $line = $null
        while ($outputQueue.TryDequeue([ref]$line)) {
            Write-Log $line
        }
        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 50
    }

    $proc.WaitForExit()
    Start-Sleep -Milliseconds 200
    $line = $null
    while ($outputQueue.TryDequeue([ref]$line)) {
        Write-Log $line
    }

    Unregister-Event -SourceIdentifier $outputEvent.Name
    Remove-Job -Name $outputEvent.Name -Force

    if ($proc.ExitCode -eq 0) {
        $lblStatus.ForeColor = [System.Drawing.Color]::DarkGreen
        $lblStatus.Text = "完了しました"
    } else {
        $lblStatus.ForeColor = [System.Drawing.Color]::DarkRed
        $lblStatus.Text = "エラーが発生しました（終了コード: $($proc.ExitCode)）"
    }

    $chkDownload.Enabled = $true
    $chkGenerate.Enabled = $true
    $chkUpload.Enabled = $true
    $btnRun.Enabled = $true
    $cmbClient.Enabled = $true
    $script:isRunning = $false
    $script:currentProc = $null
})

$lineRegex = [regex]'^if not defined (?<var>\S+) set "\k<var>=(?<val>.*)"$'

function Read-SetEnvLines {
    $rawLines = [System.IO.File]::ReadAllLines($setEnvBat, $cp932)
    return $rawLines
}

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
    "GENERATE_SHEETS_INCLUDE" = "対象のシート名"
    "GENERATE_SHEETS_EXCLUDE" = "除外のシート名"
    "GENERATE_LOG_PREFIX" = "ログファイル名の接頭辞"
    "UPLOAD_ENABLED" = "機能の有効化"
    "UPLOAD_SITE_URL" = "アップロード先のサイトURL"
    "UPLOAD_SITE_PATH" = "アップロード先のフォルダ"
    "UPLOAD_SITE_TENANT_ID" = "テナントID"
    "UPLOAD_LOCAL_PATH" = "アップロード元のフォルダ"
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
    "UPLOAD_ENABLED", "UPLOAD_SITE_URL", "UPLOAD_SITE_PATH", "UPLOAD_SITE_TENANT_ID", "UPLOAD_LOCAL_PATH"
)
$clientRuntimeExcludeVars = @("DOWNLOAD_ENABLED", "GENERATE_ENABLED", "UPLOAD_ENABLED")

function Expand-VarTokens {
    param([string]$Value)
    $expanded = $Value.Replace("%BASE_PATH%", "$basePath\")
    $expanded = [regex]::Replace($expanded, '%(\w+)%', {
        param($match)
        $refVal = Get-ResolvedVar $match.Groups[1].Value
        if ($refVal) { $refVal } else { $match.Value }
    })
    return $expanded
}

function Resolve-BrowseStart {
    param([string]$RawValue)
    if (!$RawValue) {
        return $basePath
    }
    return Expand-VarTokens $RawValue
}

function Get-SettingsFieldSource {
    $client = $cmbSettingsClient.SelectedItem
    if ($client -and $client -ne $defaultClientLabel) {
        $clientRaw = Get-ClientProfileRawValues $client
        $defaults = Get-SetEnvDefaults
        foreach ($varName in $clientOverridableVars) {
            $varValue = if ($clientRaw.ContainsKey($varName)) { $clientRaw[$varName] } else { $defaults[$varName] }
            [PSCustomObject]@{ VarName = $varName; VarValue = $varValue }
        }
    } else {
        foreach ($line in (Read-SetEnvLines)) {
            $m = $lineRegex.Match($line.Trim())
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
                $separator.Size = New-Object System.Drawing.Size(630, 2)
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
                    $startPath = Resolve-BrowseStart $targetTxt.Text
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
                    $startPath = Resolve-BrowseStart $targetTxt.Text
                    if (Test-Path -LiteralPath $startPath) {
                        $dlg.InitialDirectory = Split-Path $startPath -Parent
                        $dlg.FileName = Split-Path $startPath -Leaf
                    }
                    if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                        $targetTxt.Text = $dlg.FileName
                    }
                })
            }

            $fieldPanel.Controls.AddRange(@($txt, $btnBrowse))
            $script:fieldTextBoxes[$varName] = $txt
        } else {
            $txt = New-Object System.Windows.Forms.TextBox
            $txt.Text = $varValue
            $txt.Location = New-Object System.Drawing.Point(250, ($y - 2))
            $txt.Size = New-Object System.Drawing.Size(380, 22)
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

function Save-ClientProfile {
    param([string]$ClientName)
    $clientBat = Get-ClientBatPath $ClientName
    $newLines = foreach ($varName in $clientOverridableVars) {
        if ($script:fieldRadios.ContainsKey($varName)) {
            $newVal = if ($script:fieldRadios[$varName].Checked) { "1" } else { "0" }
            "if not defined $varName set `"$varName=$newVal`""
        } else {
            $newVal = $script:fieldTextBoxes[$varName].Text
            "set `"$varName=$newVal`""
        }
    }
    $content = ($newLines -join "`r`n") + "`r`n"
    [System.IO.File]::WriteAllText($clientBat, $content, $cp932)
}

function Save-DefaultSettings {
    $lines = Read-SetEnvLines
    $newLines = for ($i = 0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        $m = $lineRegex.Match($line.Trim())
        if ($m.Success -and $script:fieldRadios.ContainsKey($m.Groups["var"].Value)) {
            $varName = $m.Groups["var"].Value
            $newVal = if ($script:fieldRadios[$varName].Checked) { "1" } else { "0" }
            "if not defined $varName set `"$varName=$newVal`""
        } elseif ($m.Success -and $script:fieldTextBoxes.ContainsKey($m.Groups["var"].Value)) {
            $varName = $m.Groups["var"].Value
            $newVal = $script:fieldTextBoxes[$varName].Text
            "if not defined $varName set `"$varName=$newVal`""
        } else {
            $line
        }
    }

    $content = ($newLines -join "`r`n") + "`r`n"
    [System.IO.File]::WriteAllText($setEnvBat, $content, $cp932)
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
})

function Update-SettingsClientList {
    Update-ClientComboItems -ComboBox $cmbSettingsClient -FirstItem $defaultClientLabel
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
    if (Test-Path -LiteralPath $newClientBat) {
        [System.Windows.Forms.MessageBox]::Show("「$newName」は既に存在します。", "クライアントの新規作成", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        return
    }

    [System.IO.File]::WriteAllText($newClientBat, "", $cp932)
    Update-SettingsClientList
    $cmbSettingsClient.SelectedItem = $newName
})

function Get-SetEnvDefaults {
    $result = @{}
    foreach ($line in (Read-SetEnvLines)) {
        $m = $lineRegex.Match($line.Trim())
        if ($m.Success) {
            $result[$m.Groups["var"].Value] = $m.Groups["val"].Value
        }
    }
    return $result
}

function Get-ResolvedVar {
    param([string]$VarName)

    $val = [Environment]::GetEnvironmentVariable($VarName)
    if (!$val) {
        $defaults = Get-SetEnvDefaults
        if ($defaults.ContainsKey($VarName)) {
            $val = $defaults[$VarName]
        }
    }
    if (!$val) {
        return $val
    }

    return Expand-VarTokens $val
}

$logStagePanel = New-Object System.Windows.Forms.Panel
$logStagePanel.Dock = [System.Windows.Forms.DockStyle]::Top
$logStagePanel.Height = 66

$lblLogClient = New-Object System.Windows.Forms.Label
$lblLogClient.Text = "クライアント"
$lblLogClient.AutoSize = $true
$lblLogClient.Location = New-Object System.Drawing.Point(20, 17)

$cmbLogClient = New-Object System.Windows.Forms.ComboBox
$cmbLogClient.Location = New-Object System.Drawing.Point(100, 14)
$cmbLogClient.Size = New-Object System.Drawing.Size(260, 24)
$cmbLogClient.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList

function Update-LogClientList {
    Update-ClientComboItems -ComboBox $cmbLogClient -FirstItem "すべて"
}

$radioDownloadLog = New-Object System.Windows.Forms.RadioButton
$radioDownloadLog.Text = "1. ファイルダウンロード"
$radioDownloadLog.AutoSize = $true
$radioDownloadLog.Checked = $true
$radioDownloadLog.Location = New-Object System.Drawing.Point(20, 40)

$radioGenerateLog = New-Object System.Windows.Forms.RadioButton
$radioGenerateLog.Text = "2. 個別パッケージの作成"
$radioGenerateLog.AutoSize = $true
$radioGenerateLog.Location = New-Object System.Drawing.Point(220, 40)

$radioUploadLog = New-Object System.Windows.Forms.RadioButton
$radioUploadLog.Text = "3. ファイルアップロード"
$radioUploadLog.AutoSize = $true
$radioUploadLog.Location = New-Object System.Drawing.Point(440, 40)

$logStagePanel.Controls.AddRange(@($lblLogClient, $cmbLogClient, $radioDownloadLog, $radioGenerateLog, $radioUploadLog))

$logContentBox = New-Object System.Windows.Forms.TextBox
$logContentBox.Multiline = $true
$logContentBox.ReadOnly = $true
$logContentBox.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
$logContentBox.Font = New-Object System.Drawing.Font("Consolas", 9)
$logContentBox.Dock = [System.Windows.Forms.DockStyle]::Fill

$tabLogs.Controls.Add($logContentBox)
$tabLogs.Controls.Add($logStagePanel)

function Get-LogPrefixForStage {
    param([string]$Stage)
    switch ($Stage) {
        "download" { return Get-ResolvedVar "DOWNLOAD_LOG_PREFIX" }
        "generate" { return Get-ResolvedVar "GENERATE_LOG_PREFIX" }
        "upload"   { return Get-ResolvedVar "UPLOAD_LOG_PREFIX" }
    }
}

function Update-LogView {
    $stage = if ($radioDownloadLog.Checked) { "download" } elseif ($radioGenerateLog.Checked) { "generate" } else { "upload" }
    $logPath = Get-ResolvedVar "COMMON_LOG_PATH"
    $prefix = Get-LogPrefixForStage $stage

    $logContentBox.Text = ""

    if (!($logPath -and $prefix -and (Test-Path -LiteralPath $logPath))) {
        return
    }

    $logClient = $cmbLogClient.SelectedItem
    $clientFilter = if ($logClient -and $logClient -ne "すべて") { "$logClient" + "_" } else { "" }
    $files = Get-ChildItem -LiteralPath $logPath -Filter "$prefix$clientFilter*.log" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending

    $sections = foreach ($file in $files) { [System.IO.File]::ReadAllText($file.FullName, $cp932) }
    $logContentBox.Text = $sections -join "`r`n`r`n"
}

$radioDownloadLog.Add_CheckedChanged({ if ($radioDownloadLog.Checked) { Update-LogView } })
$radioGenerateLog.Add_CheckedChanged({ if ($radioGenerateLog.Checked) { Update-LogView } })
$radioUploadLog.Add_CheckedChanged({ if ($radioUploadLog.Checked) { Update-LogView } })
$cmbLogClient.Add_SelectedIndexChanged({ if (!$script:suppressComboSync) { Update-LogView } })

function Get-ClientAwareEnabledValue {
    param([string]$VarName)
    $client = $cmbClient.SelectedItem
    if ($client -and $client -ne $defaultClientLabel) {
        $clientValues = Get-ClientProfileValues $client
        if ($clientValues.ContainsKey($VarName)) {
            return $clientValues[$VarName]
        }
    }
    return Get-ResolvedVar $VarName
}

function Update-RunCheckboxesFromClient {
    $chkDownload.Checked = (Get-ClientAwareEnabledValue "DOWNLOAD_ENABLED") -eq "1"
    $chkGenerate.Checked = (Get-ClientAwareEnabledValue "GENERATE_ENABLED") -eq "1"
    $chkUpload.Checked = (Get-ClientAwareEnabledValue "UPLOAD_ENABLED") -eq "1"
}

function Sync-RunCheckboxes {
    Update-ClientList
}

$cmbClient.Add_SelectedIndexChanged({ if (!$script:suppressComboSync) { Update-RunCheckboxesFromClient } })

$tabControl.Add_SelectedIndexChanged({
    if ($tabControl.SelectedTab -eq $tabRun) {
        Sync-RunCheckboxes
    } elseif ($tabControl.SelectedTab -eq $tabLogs) {
        Update-LogClientList
        Update-LogView
    } elseif ($tabControl.SelectedTab -eq $tabSettings) {
        Update-SettingsClientList
    }
})

Sync-RunCheckboxes
Update-RunCheckboxesFromClient
Update-LogClientList
Update-LogView
$tabControl.SelectedTab = $tabRun

[System.Windows.Forms.Application]::Run($form)