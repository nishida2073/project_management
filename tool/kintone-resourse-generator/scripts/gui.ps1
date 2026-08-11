# =========================================
# GUI（kintoneリソース生成ツール）
# =========================================
# download-kintone-resources.bat → generate-config-from-template.bat →
# apply-kintone-resources.bat → check-kintone-resources.bat を画面から順番に実行するGUI。
# 「実行」タブで設定ファイル名等を入力し実行する処理にチェックを入れて実行する。
# 「設定」タブでset-env.batの値（KINTONE_*の各パス・URL）を編集する。

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
$downloadBat = Join-Path $basePath "download-kintone-resources.bat"
$generateBat = Join-Path $basePath "generate-config-from-template.bat"
$applyBat = Join-Path $basePath "apply-kintone-resources.bat"
$checkBat = Join-Path $basePath "check-kintone-resources.bat"
$clientsDir = Join-Path $basePath "clients"
$setEnvBat = Join-Path $clientsDir "set-env.bat"
$cp932 = [System.Text.Encoding]::GetEncoding(932)
$lineRegex = [regex]'^if not defined (?<var>\S+) set "\k<var>=(?<val>.*)"$'

$form = New-Object System.Windows.Forms.Form
$form.Text = "kintoneリソース生成ツール"
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

$script:isRunning = $false
$tabControl.Add_Selecting({
    if ($script:isRunning -and $_.TabPage -ne $tabRun) {
        $_.Cancel = $true
    }
})

# =========================================
# 実行タブ
# =========================================

$runTopPanel = New-Object System.Windows.Forms.Panel
$runTopPanel.Dock = [System.Windows.Forms.DockStyle]::Top
$runTopPanel.Height = 196

$lblSpaceId = New-Object System.Windows.Forms.Label
$lblSpaceId.Text = "スペースID"
$lblSpaceId.AutoSize = $true
$lblSpaceId.Location = New-Object System.Drawing.Point(20, 17)

$txtSpaceId = New-Object System.Windows.Forms.TextBox
$txtSpaceId.Location = New-Object System.Drawing.Point(160, 14)
$txtSpaceId.Size = New-Object System.Drawing.Size(200, 22)

$lblConfigName = New-Object System.Windows.Forms.Label
$lblConfigName.Text = "設定ファイル名"
$lblConfigName.AutoSize = $true
$lblConfigName.Location = New-Object System.Drawing.Point(20, 51)

$txtConfigName = New-Object System.Windows.Forms.TextBox
$txtConfigName.Location = New-Object System.Drawing.Point(160, 48)
$txtConfigName.Size = New-Object System.Drawing.Size(200, 22)

$lblTemplateName = New-Object System.Windows.Forms.Label
$lblTemplateName.Text = "テンプレート名"
$lblTemplateName.AutoSize = $true
$lblTemplateName.Location = New-Object System.Drawing.Point(20, 85)

$cmbTemplateName = New-Object System.Windows.Forms.ComboBox
$cmbTemplateName.Location = New-Object System.Drawing.Point(160, 82)
$cmbTemplateName.Size = New-Object System.Drawing.Size(220, 22)
$cmbTemplateName.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList

$chkDownload = New-Object System.Windows.Forms.CheckBox
$chkDownload.Text = "1. ダウンロード"
$chkDownload.AutoSize = $true
$chkDownload.Location = New-Object System.Drawing.Point(20, 122)

$chkGenerate = New-Object System.Windows.Forms.CheckBox
$chkGenerate.Text = "2. 設定ファイルの生成"
$chkGenerate.AutoSize = $true
$chkGenerate.Location = New-Object System.Drawing.Point(160, 122)

$chkApply = New-Object System.Windows.Forms.CheckBox
$chkApply.Text = "3. kintoneへ反映"
$chkApply.AutoSize = $true
$chkApply.Location = New-Object System.Drawing.Point(300, 122)

$chkCheck = New-Object System.Windows.Forms.CheckBox
$chkCheck.Text = "4. データチェック"
$chkCheck.AutoSize = $true
$chkCheck.Location = New-Object System.Drawing.Point(440, 122)

$btnRun = New-Object System.Windows.Forms.Button
$btnRun.Text = "実行"
$btnRun.Location = New-Object System.Drawing.Point(20, 154)
$btnRun.Size = New-Object System.Drawing.Size(100, 24)

$lblStatus = New-Object System.Windows.Forms.Label
$lblStatus.Text = ""
$lblStatus.AutoSize = $true
$lblStatus.Location = New-Object System.Drawing.Point(134, 164)
$lblStatus.Font = New-Object System.Drawing.Font($lblStatus.Font, [System.Drawing.FontStyle]::Bold)

$runTopPanel.Controls.AddRange(@(
    $lblSpaceId, $txtSpaceId, $lblConfigName, $txtConfigName,
    $lblTemplateName, $cmbTemplateName,
    $chkDownload, $chkGenerate, $chkApply, $chkCheck,
    $btnRun, $lblStatus
))

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

function Invoke-BatStep {
    param(
        [Parameter(Mandatory)][string]$BatPath,
        [string[]]$ArgList = @()
    )

    $quotedArgs = ($ArgList | ForEach-Object { '"' + $_ + '"' }) -join ' '

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "cmd.exe"
    $psi.Arguments = "/c ""`"$BatPath`" $quotedArgs 2>&1"""
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
    $script:currentProc = $null

    return $proc.ExitCode
}

$btnRun.Add_Click({
    $configName = $txtConfigName.Text.Trim()
    if (!$configName) {
        [System.Windows.Forms.MessageBox]::Show("設定ファイル名を入力してください。", "実行", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        return
    }

    $steps = @()
    if ($chkDownload.Checked) {
        if (!$txtSpaceId.Text.Trim()) {
            [System.Windows.Forms.MessageBox]::Show("①ダウンロードにはスペースIDが必要です。", "実行", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
            return
        }
        $steps += [PSCustomObject]@{
            Name = "1. ダウンロード"
            Bat  = $downloadBat
            Args = @("-SpaceId", $txtSpaceId.Text.Trim(), "-ConfigName", $configName)
        }
    }
    if ($chkGenerate.Checked) {
        if (!$cmbTemplateName.Text.Trim()) {
            [System.Windows.Forms.MessageBox]::Show("②設定ファイルの生成にはテンプレート名が必要です。", "実行", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
            return
        }
        $steps += [PSCustomObject]@{
            Name = "2. 設定ファイルの生成"
            Bat  = $generateBat
            Args = @("-TemplateConfigName", $cmbTemplateName.Text.Trim(), "-DownloadConfigName", $configName)
        }
    }
    if ($chkApply.Checked) {
        $steps += [PSCustomObject]@{
            Name = "3. kintoneへ反映"
            Bat  = $applyBat
            Args = @("-ConfigName", $configName)
        }
    }
    if ($chkCheck.Checked) {
        $steps += [PSCustomObject]@{
            Name = "4. データチェック"
            Bat  = $checkBat
            Args = @("-ConfigName", $configName)
        }
    }

    if ($steps.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("実行する処理を選択してください。", "実行", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        return
    }

    $script:isRunning = $true
    $txtConfigName.Enabled = $false
    $txtSpaceId.Enabled = $false
    $cmbTemplateName.Enabled = $false
    $chkDownload.Enabled = $false
    $chkGenerate.Enabled = $false
    $chkApply.Enabled = $false
    $chkCheck.Enabled = $false
    $btnRun.Enabled = $false
    $lblStatus.ForeColor = [System.Drawing.Color]::Black
    $lblStatus.Text = "実行中..."

    Write-Log ""
    Write-Log "-------------------- $configName --------------------"

    $failedStep = $null
    $exitCode = 0
    foreach ($step in $steps) {
        Write-Log ""
        Write-Log "===== $($step.Name) ====="
        $exitCode = Invoke-BatStep -BatPath $step.Bat -ArgList $step.Args
        if ($exitCode -ne 0) {
            $failedStep = $step.Name
            break
        }
    }

    if ($failedStep) {
        $lblStatus.ForeColor = [System.Drawing.Color]::DarkRed
        $lblStatus.Text = "エラーが発生しました（$failedStep、終了コード: $exitCode）"
    } else {
        $lblStatus.ForeColor = [System.Drawing.Color]::DarkGreen
        $lblStatus.Text = "完了しました"
    }

    $txtConfigName.Enabled = $true
    $txtSpaceId.Enabled = $true
    $cmbTemplateName.Enabled = $true
    $chkDownload.Enabled = $true
    $chkGenerate.Enabled = $true
    $chkApply.Enabled = $true
    $chkCheck.Enabled = $true
    $btnRun.Enabled = $true
    $script:isRunning = $false
})

# =========================================
# 共通: set-env.bat の読み書き
# =========================================

function Read-SetEnvLines {
    return [System.IO.File]::ReadAllLines($setEnvBat, $cp932)
}

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

function Expand-VarTokens {
    param([string]$Value)
    if (!$Value) { return $Value }
    $expanded = $Value.Replace("%BASE_PATH%", "$basePath\")
    $expanded = [regex]::Replace($expanded, '%(\w+)%', {
        param($match)
        $refVal = Get-ResolvedVar $match.Groups[1].Value
        if ($refVal) { $refVal } else { $match.Value }
    })
    return $expanded
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
    if (!$val) { return $val }
    return Expand-VarTokens $val
}

function Resolve-BrowseStart {
    param([string]$RawValue)
    if (!$RawValue) { return $basePath }
    return Expand-VarTokens $RawValue
}

function Update-TemplateNameList {
    $selected = $cmbTemplateName.SelectedItem
    $cmbTemplateName.Items.Clear()

    $templatePath = Get-ResolvedVar "KINTONE_TEMPLATE_PATH"
    if ($templatePath -and (Test-Path -LiteralPath $templatePath)) {
        $names = Get-ChildItem -LiteralPath $templatePath -Filter "*.xlsx" -ErrorAction SilentlyContinue |
            ForEach-Object { [System.IO.Path]::GetFileNameWithoutExtension($_.Name) } |
            Sort-Object
        foreach ($name in $names) {
            $cmbTemplateName.Items.Add($name) | Out-Null
        }
    }

    if ($selected -and $cmbTemplateName.Items.Contains($selected)) {
        $cmbTemplateName.SelectedItem = $selected
    }
}

# =========================================
# 設定タブ
# =========================================

$topPanel = New-Object System.Windows.Forms.Panel
$topPanel.Dock = [System.Windows.Forms.DockStyle]::Top
$topPanel.Height = 46

$btnSave = New-Object System.Windows.Forms.Button
$btnSave.Text = "保存"
$btnSave.Location = New-Object System.Drawing.Point(20, 11)
$btnSave.Size = New-Object System.Drawing.Size(100, 24)

$btnReload = New-Object System.Windows.Forms.Button
$btnReload.Text = "再読込"
$btnReload.Location = New-Object System.Drawing.Point(130, 11)
$btnReload.Size = New-Object System.Drawing.Size(100, 24)

$lblSaveStatus = New-Object System.Windows.Forms.Label
$lblSaveStatus.Text = ""
$lblSaveStatus.AutoSize = $true
$lblSaveStatus.Location = New-Object System.Drawing.Point(244, 17)
$lblSaveStatus.Font = New-Object System.Drawing.Font($lblSaveStatus.Font, [System.Drawing.FontStyle]::Bold)

$topPanel.Controls.AddRange(@($btnSave, $btnReload, $lblSaveStatus))

$fieldPanel = New-Object System.Windows.Forms.Panel
$fieldPanel.Dock = [System.Windows.Forms.DockStyle]::Fill
$fieldPanel.AutoScroll = $true

$tabSettings.Controls.Add($fieldPanel)
$tabSettings.Controls.Add($topPanel)

$varLabels = [ordered]@{
    "KINTONE_BASE_URL"         = "kintoneのサイトURL"
    "KINTONE_DOWNLOAD_PATH"    = "ダウンロード先のフォルダ"
    "KINTONE_TEMPLATE_PATH"    = "テンプレートファイルのフォルダ"
    "KINTONE_CONFIG_PATH"      = "設定ファイルのフォルダ"
    "KINTONE_CHECK_OUTPUT_PATH" = "チェック結果の出力先フォルダ"
    "KINTONE_LOG_PATH"         = "ログの出力先フォルダ"
}

$folderBrowseVars = @("KINTONE_DOWNLOAD_PATH", "KINTONE_TEMPLATE_PATH", "KINTONE_CONFIG_PATH", "KINTONE_CHECK_OUTPUT_PATH", "KINTONE_LOG_PATH")

$script:fieldTextBoxes = @{}

function Update-SettingsFields {
    $fieldPanel.Controls.Clear()
    $script:fieldTextBoxes = @{}

    $defaults = Get-SetEnvDefaults
    $y = 10

    foreach ($varName in $varLabels.Keys) {
        if (!$defaults.ContainsKey($varName)) { continue }
        $varValue = $defaults[$varName]

        $lbl = New-Object System.Windows.Forms.Label
        $lbl.Text = $varLabels[$varName]
        $lbl.AutoSize = $false
        $lbl.Size = New-Object System.Drawing.Size(280, 20)
        $lbl.Location = New-Object System.Drawing.Point(20, $y)
        $fieldPanel.Controls.Add($lbl)

        if ($folderBrowseVars -contains $varName) {
            $txt = New-Object System.Windows.Forms.TextBox
            $txt.Text = $varValue
            $txt.Location = New-Object System.Drawing.Point(310, ($y - 2))
            $txt.Size = New-Object System.Drawing.Size(300, 22)
            $txt.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left

            $btnBrowse = New-Object System.Windows.Forms.Button
            $btnBrowse.Text = "参照..."
            $btnBrowse.Location = New-Object System.Drawing.Point(620, ($y - 3))
            $btnBrowse.Size = New-Object System.Drawing.Size(70, 24)
            $btnBrowse.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left
            $btnBrowse.Tag = $txt
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

            $fieldPanel.Controls.AddRange(@($txt, $btnBrowse))
            $script:fieldTextBoxes[$varName] = $txt
        } else {
            $txt = New-Object System.Windows.Forms.TextBox
            $txt.Text = $varValue
            $txt.Location = New-Object System.Drawing.Point(310, ($y - 2))
            $txt.Size = New-Object System.Drawing.Size(380, 22)
            $txt.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left

            $fieldPanel.Controls.Add($txt)
            $script:fieldTextBoxes[$varName] = $txt
        }

        $y += 32
    }
}

$btnReload.Add_Click({
    Update-SettingsFields
    $lblSaveStatus.ForeColor = [System.Drawing.Color]::Black
    $lblSaveStatus.Text = "再読込しました"
})

$btnSave.Add_Click({
    $newLines = foreach ($line in (Read-SetEnvLines)) {
        $m = $lineRegex.Match($line.Trim())
        $varName = if ($m.Success) { $m.Groups["var"].Value } else { $null }
        if ($varName -and $script:fieldTextBoxes.ContainsKey($varName)) {
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

Update-SettingsFields

# =========================================
# ログタブ
# =========================================

$logStagePanel = New-Object System.Windows.Forms.Panel
$logStagePanel.Dock = [System.Windows.Forms.DockStyle]::Top
$logStagePanel.Height = 66

$lblLogConfigName = New-Object System.Windows.Forms.Label
$lblLogConfigName.Text = "設定ファイル名"
$lblLogConfigName.AutoSize = $true
$lblLogConfigName.Location = New-Object System.Drawing.Point(20, 17)

$cmbLogConfigName = New-Object System.Windows.Forms.ComboBox
$cmbLogConfigName.Location = New-Object System.Drawing.Point(90, 14)
$cmbLogConfigName.Size = New-Object System.Drawing.Size(220, 24)
$cmbLogConfigName.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList

$logStagePrefixes = [ordered]@{
    "download" = "1. ダウンロード"
    "generate" = "2. 設定ファイルの生成"
    "apply"    = "3. kintoneへ反映"
    "check"    = "4. データチェック"
}

$radioDownloadLog = New-Object System.Windows.Forms.RadioButton
$radioDownloadLog.Text = "1. ダウンロード"
$radioDownloadLog.AutoSize = $true
$radioDownloadLog.Checked = $true
$radioDownloadLog.Location = New-Object System.Drawing.Point(20, 40)

$radioGenerateLog = New-Object System.Windows.Forms.RadioButton
$radioGenerateLog.Text = "2. 設定ファイルの生成"
$radioGenerateLog.AutoSize = $true
$radioGenerateLog.Location = New-Object System.Drawing.Point(160, 40)

$radioApplyLog = New-Object System.Windows.Forms.RadioButton
$radioApplyLog.Text = "3. kintoneへ反映"
$radioApplyLog.AutoSize = $true
$radioApplyLog.Location = New-Object System.Drawing.Point(300, 40)

$radioCheckLog = New-Object System.Windows.Forms.RadioButton
$radioCheckLog.Text = "4. データチェック"
$radioCheckLog.AutoSize = $true
$radioCheckLog.Location = New-Object System.Drawing.Point(440, 40)

$logStagePanel.Controls.AddRange(@($lblLogConfigName, $cmbLogConfigName, $radioDownloadLog, $radioGenerateLog, $radioApplyLog, $radioCheckLog))

$logContentBox = New-Object System.Windows.Forms.TextBox
$logContentBox.Multiline = $true
$logContentBox.ReadOnly = $true
$logContentBox.ScrollBars = [System.Windows.Forms.ScrollBars]::Vertical
$logContentBox.Font = New-Object System.Drawing.Font("Consolas", 9)
$logContentBox.Dock = [System.Windows.Forms.DockStyle]::Fill

$tabLogs.Controls.Add($logContentBox)
$tabLogs.Controls.Add($logStagePanel)

function Update-LogConfigNameList {
    $selected = $cmbLogConfigName.SelectedItem
    $cmbLogConfigName.Items.Clear()
    $cmbLogConfigName.Items.Add("すべて") | Out-Null

    $logPath = Get-ResolvedVar "KINTONE_LOG_PATH"
    if ($logPath -and (Test-Path -LiteralPath $logPath)) {
        $stagePrefixPattern = '^(download|generate|apply|check)_(?<config>.+)_\d{8}_\d{6}$'
        $configNames = Get-ChildItem -LiteralPath $logPath -Filter "*.log" -ErrorAction SilentlyContinue |
            ForEach-Object {
                $m = [regex]::Match([System.IO.Path]::GetFileNameWithoutExtension($_.Name), $stagePrefixPattern)
                if ($m.Success) { $m.Groups["config"].Value }
            } | Sort-Object -Unique
        foreach ($name in $configNames) {
            $cmbLogConfigName.Items.Add($name) | Out-Null
        }
    }

    $cmbLogConfigName.SelectedIndex = if ($selected -and $cmbLogConfigName.Items.Contains($selected)) { $cmbLogConfigName.Items.IndexOf($selected) } else { 0 }
}

function Update-LogView {
    $stage = if ($radioDownloadLog.Checked) { "download" } elseif ($radioGenerateLog.Checked) { "generate" } elseif ($radioApplyLog.Checked) { "apply" } else { "check" }
    $logPath = Get-ResolvedVar "KINTONE_LOG_PATH"

    $logContentBox.Text = ""

    if (!($logPath -and (Test-Path -LiteralPath $logPath))) {
        return
    }

    $logConfigName = $cmbLogConfigName.SelectedItem
    $configFilter = if ($logConfigName -and $logConfigName -ne "すべて") { "$logConfigName" + "_" } else { "" }
    $files = Get-ChildItem -LiteralPath $logPath -Filter "${stage}_$configFilter*.log" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending

    $sections = foreach ($file in $files) { [System.IO.File]::ReadAllText($file.FullName, $cp932) }
    $logContentBox.Text = $sections -join "`r`n`r`n"
}

$radioDownloadLog.Add_CheckedChanged({ if ($radioDownloadLog.Checked) { Update-LogView } })
$radioGenerateLog.Add_CheckedChanged({ if ($radioGenerateLog.Checked) { Update-LogView } })
$radioApplyLog.Add_CheckedChanged({ if ($radioApplyLog.Checked) { Update-LogView } })
$radioCheckLog.Add_CheckedChanged({ if ($radioCheckLog.Checked) { Update-LogView } })
$cmbLogConfigName.Add_SelectedIndexChanged({ Update-LogView })

$tabControl.Add_SelectedIndexChanged({
    if ($tabControl.SelectedTab -eq $tabRun) {
        Update-TemplateNameList
    } elseif ($tabControl.SelectedTab -eq $tabLogs) {
        Update-LogConfigNameList
        Update-LogView
    } elseif ($tabControl.SelectedTab -eq $tabSettings) {
        Update-SettingsFields
    }
})

Update-TemplateNameList
Update-LogConfigNameList
Update-LogView
$tabControl.SelectedTab = $tabRun

[System.Windows.Forms.Application]::Run($form)
