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
    # .ps1として実行された場合（scripts配下）
    $scriptDir = Split-Path $MyInvocation.MyCommand.Path
    $basePath = Split-Path $scriptDir -Parent
} else {
    # build-gui.batでexe化された場合、$MyInvocation.MyCommand.Pathは空になるため
    # 実行中のexe自身のパスから取得する（exeはプロジェクトルートに置かれる）
    $basePath = Split-Path ([System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName)
}
$allBat = Join-Path $basePath "all.bat"
$setEnvBat = Join-Path $basePath "set-env.bat"
$cp932 = [System.Text.Encoding]::GetEncoding(932)

$form = New-Object System.Windows.Forms.Form
$form.Text = "コース別パッケージ生成ツール"
$form.Size = New-Object System.Drawing.Size(700, 560)
$form.StartPosition = "CenterScreen"
$form.MinimumSize = New-Object System.Drawing.Size(520, 360)

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

# ----- 実行タブ -----

$runTopPanel = New-Object System.Windows.Forms.Panel
$runTopPanel.Dock = [System.Windows.Forms.DockStyle]::Top
$runTopPanel.Height = 150

$chkDownload = New-Object System.Windows.Forms.CheckBox
$chkDownload.Text = "1. ファイルダウンロード"
$chkDownload.AutoSize = $true
$chkDownload.Location = New-Object System.Drawing.Point(20, 14)

$chkGenerate = New-Object System.Windows.Forms.CheckBox
$chkGenerate.Text = "2. 個別パッケージの作成"
$chkGenerate.AutoSize = $true
$chkGenerate.Location = New-Object System.Drawing.Point(20, 40)

$chkUpload = New-Object System.Windows.Forms.CheckBox
$chkUpload.Text = "3. ファイルアップロード"
$chkUpload.AutoSize = $true
$chkUpload.Location = New-Object System.Drawing.Point(20, 66)

$btnRun = New-Object System.Windows.Forms.Button
$btnRun.Text = "実行"
$btnRun.Location = New-Object System.Drawing.Point(20, 100)
$btnRun.Size = New-Object System.Drawing.Size(100, 24)

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Text = ""
$lblStatus.AutoSize = $true
$lblStatus.Location = New-Object System.Drawing.Point(134, 110)
$lblStatus.Font = New-Object System.Drawing.Font($lblStatus.Font, [System.Drawing.FontStyle]::Bold)

$runTopPanel.Controls.AddRange(@($chkDownload, $chkGenerate, $chkUpload, $btnRun, $lblStatus))

$txtLog = New-Object System.Windows.Forms.TextBox
$txtLog.Multiline = $true
$txtLog.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
$txtLog.ReadOnly = $true
$txtLog.Font = New-Object System.Drawing.Font("Consolas", 9)
$txtLog.Dock = [System.Windows.Forms.DockStyle]::Fill

$tabRun.Controls.Add($txtLog)
$tabRun.Controls.Add($runTopPanel)

function Write-Log {
    param([string]$Text)
    $txtLog.AppendText("$Text`r`n")
}

$btnRun.Add_Click({
    $tabControl.Enabled = $false
    $chkDownload.Enabled = $false
    $chkGenerate.Enabled = $false
    $chkUpload.Enabled = $false
    $btnRun.Enabled = $false
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

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $allBat
    $psi.WorkingDirectory = $basePath
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.CreateNoWindow = $true
    $psi.StandardOutputEncoding = $cp932
    $psi.StandardErrorEncoding = $cp932

    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    $proc.Start() | Out-Null

    while (!$proc.StandardOutput.EndOfStream) {
        Write-Log $proc.StandardOutput.ReadLine()
        [System.Windows.Forms.Application]::DoEvents()
    }
    while (!$proc.StandardError.EndOfStream) {
        Write-Log $proc.StandardError.ReadLine()
        [System.Windows.Forms.Application]::DoEvents()
    }

    $proc.WaitForExit()

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
    $tabControl.Enabled = $true
})

# ----- 設定タブ（set-env.batの編集） -----

$lineRegex = [regex]'^if not defined (?<var>\S+) set "\k<var>=(?<val>.*)"$'

function Read-SetEnvLines {
    $rawLines = [System.IO.File]::ReadAllLines($setEnvBat, $cp932)
    return $rawLines
}

$topPanel = New-Object System.Windows.Forms.Panel
$topPanel.Dock = [System.Windows.Forms.DockStyle]::Top
$topPanel.Height = 40

$btnSave = New-Object System.Windows.Forms.Button
$btnSave.Text = "保存"
$btnSave.Location = New-Object System.Drawing.Point(20, 14)
$btnSave.Size = New-Object System.Drawing.Size(100, 24)

$btnReload = New-Object System.Windows.Forms.Button
$btnReload.Text = "再読込"
$btnReload.Location = New-Object System.Drawing.Point(130, 14)
$btnReload.Size = New-Object System.Drawing.Size(100, 24)

$lblSaveStatus = New-Object System.Windows.Forms.Label
$lblSaveStatus.Text = ""
$lblSaveStatus.AutoSize = $true
$lblSaveStatus.Location = New-Object System.Drawing.Point(244, 20)
$lblSaveStatus.Font = New-Object System.Drawing.Font($lblSaveStatus.Font, [System.Drawing.FontStyle]::Bold)

$topPanel.Controls.AddRange(@($btnSave, $btnReload, $lblSaveStatus))

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

function Resolve-BrowseStart {
    param([string]$RawValue)
    if (!$RawValue) {
        return $basePath
    }
    $expanded = $RawValue.Replace("%BASE_PATH%", "$basePath\")
    $expanded = [regex]::Replace($expanded, '%(\w+)%', {
        param($match)
        $refVal = Get-ResolvedVar $match.Groups[1].Value
        if ($refVal) { $refVal } else { $match.Value }
    })
    return $expanded
}

function Update-SettingsFields {
    $fieldPanel.Controls.Clear()
    $script:fieldTextBoxes = @{}
    $script:fieldRadios = @{}

    $lines = Read-SetEnvLines
    $y = 10
    $lastGroup = ""

    foreach ($line in $lines) {
        $m = $lineRegex.Match($line.Trim())
        if (!$m.Success) {
            continue
        }

        $varName = $m.Groups["var"].Value
        $varValue = $m.Groups["val"].Value

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
            # 同じ親を共有するラジオボタンは自動的に排他制御されるため、フィールドごとに
            # 専用のパネルへ入れて「有効・無効」のペアをそれぞれ独立させる
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

Update-SettingsFields

$btnReload.Add_Click({
    Update-SettingsFields
    $lblSaveStatus.ForeColor = [System.Drawing.Color]::Black
    $lblSaveStatus.Text = "再読込しました"
})

$btnSave.Add_Click({
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

    $lblSaveStatus.ForeColor = [System.Drawing.Color]::DarkGreen
    $lblSaveStatus.Text = "保存しました"
})

# ----- ログタブ（各段階のログファイルを確認） -----

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

    $val = $val.Replace("%BASE_PATH%", "$basePath\")
    $val = [regex]::Replace($val, '%(\w+)%', {
        param($match)
        $refVal = Get-ResolvedVar $match.Groups[1].Value
        if ($refVal) { $refVal } else { $match.Value }
    })
    return $val
}

$logStagePanel = New-Object System.Windows.Forms.Panel
$logStagePanel.Dock = [System.Windows.Forms.DockStyle]::Top
$logStagePanel.Height = 40

$radioDownloadLog = New-Object System.Windows.Forms.RadioButton
$radioDownloadLog.Text = "1. ファイルダウンロード"
$radioDownloadLog.AutoSize = $true
$radioDownloadLog.Checked = $true
$radioDownloadLog.Location = New-Object System.Drawing.Point(20, 14)

$radioGenerateLog = New-Object System.Windows.Forms.RadioButton
$radioGenerateLog.Text = "2. 個別パッケージの作成"
$radioGenerateLog.AutoSize = $true
$radioGenerateLog.Location = New-Object System.Drawing.Point(220, 14)

$radioUploadLog = New-Object System.Windows.Forms.RadioButton
$radioUploadLog.Text = "3. ファイルアップロード"
$radioUploadLog.AutoSize = $true
$radioUploadLog.Location = New-Object System.Drawing.Point(440, 14)

$logStagePanel.Controls.AddRange(@($radioDownloadLog, $radioGenerateLog, $radioUploadLog))

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

    $files = Get-ChildItem -LiteralPath $logPath -Filter "$prefix*.log" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending

    $sections = foreach ($file in $files) { [System.IO.File]::ReadAllText($file.FullName, $cp932) }
    $logContentBox.Text = $sections -join "`r`n`r`n"
}

$radioDownloadLog.Add_CheckedChanged({ if ($radioDownloadLog.Checked) { Update-LogView } })
$radioGenerateLog.Add_CheckedChanged({ if ($radioGenerateLog.Checked) { Update-LogView } })
$radioUploadLog.Add_CheckedChanged({ if ($radioUploadLog.Checked) { Update-LogView } })

function Sync-RunCheckboxes {
    $chkDownload.Checked = (Get-ResolvedVar "DOWNLOAD_ENABLED") -eq "1"
    $chkGenerate.Checked = (Get-ResolvedVar "GENERATE_ENABLED") -eq "1"
    $chkUpload.Checked = (Get-ResolvedVar "UPLOAD_ENABLED") -eq "1"
}

$tabControl.Add_SelectedIndexChanged({
    if ($tabControl.SelectedTab -eq $tabRun) {
        Sync-RunCheckboxes
    } elseif ($tabControl.SelectedTab -eq $tabLogs) {
        Update-LogView
    }
})

Sync-RunCheckboxes
Update-LogView
$tabControl.SelectedTab = $tabRun

[System.Windows.Forms.Application]::Run($form)