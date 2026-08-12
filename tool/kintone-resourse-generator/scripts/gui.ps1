# =========================================
# GUI（kintoneリソース生成ツール）
# =========================================
# download-kintone-resources.bat → generate-config-from-template.bat →
# apply-kintone-resources.bat → check-kintone-resources.bat を画面から順番に実行するGUI。
# 「実行」タブでスペース識別名等を入力し、工程ごとの実行ボタン（個別実行）か「まとめて実行」（全工程を順番に実行）で実行する。
# 「設定」タブでset-env.batの値（COMMON_*の各パス）とset-kintone.batの値（kintoneの接続情報）を編集する。

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
$createSpaceBat = Join-Path $basePath "create-space-from-template.bat"
$downloadBat = Join-Path $basePath "download-kintone-resources.bat"
$generateBat = Join-Path $basePath "generate-config-from-template.bat"
$applyBat = Join-Path $basePath "apply-kintone-resources.bat"
$checkBat = Join-Path $basePath "check-kintone-resources.bat"
$clientsDir = Join-Path $basePath "clients"
$setEnvBat = Join-Path $clientsDir "set-env.bat"
$setKintoneBat = Join-Path $clientsDir "set-kintone.bat"
$cp932 = [System.Text.Encoding]::GetEncoding(932)
$lineRegex = [regex]'^if not defined (?<var>\S+) set "\k<var>=(?<val>.*)"$'

# 設定タブの接続テストでInvoke-KintoneRequestを使うため読み込む（$scriptDirはexe化時は未設定になるため$basePath基準で解決する）
. (Join-Path $basePath "scripts\common.ps1")

$form = New-Object System.Windows.Forms.Form
$form.Text = "kintoneリソース生成ツール"
$form.Size = New-Object System.Drawing.Size(780, 560)
$form.StartPosition = "CenterScreen"
$form.MinimumSize = New-Object System.Drawing.Size(600, 400)

$script:currentProc = $null
$script:stepOutputPaths = @{}
$form.Add_FormClosing({
    if ($script:currentProc -and !$script:currentProc.HasExited) {
        & taskkill.exe /T /F /PID $script:currentProc.Id 2>&1 | Out-Null
    }
})

$tabControl = New-Object System.Windows.Forms.TabControl
$tabControl.Dock = [System.Windows.Forms.DockStyle]::Fill

$tabRun = New-Object System.Windows.Forms.TabPage
$tabRun.Text = "実行"

$innerRunTabControl = New-Object System.Windows.Forms.TabControl
$innerRunTabControl.Dock = [System.Windows.Forms.DockStyle]::Top
$innerRunTabControl.Height = 404

$tabSingleRun = New-Object System.Windows.Forms.TabPage
$tabSingleRun.Text = "単体実行"

$tabBatchRun = New-Object System.Windows.Forms.TabPage
$tabBatchRun.Text = "一括実行"

$innerRunTabControl.Controls.AddRange(@($tabBatchRun, $tabSingleRun))
$innerRunTabControl.Add_Selecting({
    if ($script:isRunning) { $_.Cancel = $true }
})
# 一括実行タブ・工程カードを隠した単体実行タブは内容が少ないため、状況に応じて
# innerRunTabControlの高さを変え、ログ表示（下のtxtLog）がより上に来るようにする。
# （Update-InnerRunTabHeight関数はrunTopPanel構築後に定義）
$innerRunTabControl.Add_SelectedIndexChanged({ Update-InnerRunTabHeight })

$tabLogs = New-Object System.Windows.Forms.TabPage
$tabLogs.Text = "ログ"

$tabSettings = New-Object System.Windows.Forms.TabPage
$tabSettings.Text = "設定"

$tabControl.Controls.AddRange(@($tabRun, $tabLogs, $tabSettings))
$form.Controls.Add($tabControl)

$script:isRunning = $false
$script:stepsCollapsed = $true
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
$runTopPanel.Height = 374

$lblConfigName = New-Object System.Windows.Forms.Label
$lblConfigName.Text = "スペース識別名"
$lblConfigName.AutoSize = $true
$lblConfigName.Location = New-Object System.Drawing.Point(20, 17)

$txtConfigName = New-Object System.Windows.Forms.TextBox
$txtConfigName.Location = New-Object System.Drawing.Point(160, 14)
$txtConfigName.Size = New-Object System.Drawing.Size(200, 22)

$lblSpaceTemplateId = New-Object System.Windows.Forms.Label
$lblSpaceTemplateId.Text = "スペーステンプレートID"
$lblSpaceTemplateId.AutoSize = $true
$lblSpaceTemplateId.Location = New-Object System.Drawing.Point(20, 51)

$txtSpaceTemplateId = New-Object System.Windows.Forms.TextBox
$txtSpaceTemplateId.Location = New-Object System.Drawing.Point(160, 48)
$txtSpaceTemplateId.Size = New-Object System.Drawing.Size(200, 22)

$lblSpaceId = New-Object System.Windows.Forms.Label
$lblSpaceId.Text = "スペースID"
$lblSpaceId.AutoSize = $true
$lblSpaceId.Location = New-Object System.Drawing.Point(20, 85)

$txtSpaceId = New-Object System.Windows.Forms.TextBox
$txtSpaceId.Location = New-Object System.Drawing.Point(160, 82)
$txtSpaceId.Size = New-Object System.Drawing.Size(200, 22)

$lblTemplateName = New-Object System.Windows.Forms.Label
$lblTemplateName.Text = "設定テンプレート名"
$lblTemplateName.AutoSize = $true
$lblTemplateName.Location = New-Object System.Drawing.Point(20, 119)

$cmbTemplateName = New-Object System.Windows.Forms.ComboBox
$cmbTemplateName.Location = New-Object System.Drawing.Point(160, 116)
$cmbTemplateName.Size = New-Object System.Drawing.Size(220, 22)
$cmbTemplateName.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList

$btnRunAll = New-Object System.Windows.Forms.Button
$btnRunAll.Text = "まとめて実行"
$btnRunAll.Location = New-Object System.Drawing.Point(20, 152)
$btnRunAll.Size = New-Object System.Drawing.Size(120, 26)

$lblOverallStatus = New-Object System.Windows.Forms.Label
$lblOverallStatus.Text = ""
$lblOverallStatus.AutoSize = $true
$lblOverallStatus.Location = New-Object System.Drawing.Point(150, 158)
$lblOverallStatus.Font = New-Object System.Drawing.Font($lblOverallStatus.Font, [System.Drawing.FontStyle]::Bold)

$lnkToggleSteps = New-Object System.Windows.Forms.LinkLabel
$lnkToggleSteps.Text = "▼ 詳細を表示"
$lnkToggleSteps.AutoSize = $true
$lnkToggleSteps.Location = New-Object System.Drawing.Point(640, 158)

$runTopPanel.Controls.AddRange(@(
    $lblConfigName, $txtConfigName,
    $lblSpaceTemplateId, $txtSpaceTemplateId,
    $lblSpaceId, $txtSpaceId,
    $lblTemplateName, $cmbTemplateName,
    $lnkToggleSteps,
    $btnRunAll, $lblOverallStatus
))

function Open-KintoneOutputFile {
    param([string]$Path)
    if (!$Path -or !(Test-Path -LiteralPath $Path)) {
        [System.Windows.Forms.MessageBox]::Show("ファイルが見つかりません:`r`n$Path", "開く", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        return
    }
    Start-Process -FilePath $Path
}

# 「0. スペース作成」も「まとめて実行」の対象。成功すると①で使うスペースIDが自動入力されるため、
# 各工程の必須項目チェックは開始前ではなく工程の直前に行う。
$stepMeta = @(
    [PSCustomObject]@{
        Id = 0; Label = "0. スペース作成"; StageKey = "createspace"; Bat = $createSpaceBat
        ArgsFn = { param($ConfigName) @("-TemplateId", $txtSpaceTemplateId.Text.Trim(), "-SpaceName", $ConfigName) }
        OutputPathFn = $null
    }
    [PSCustomObject]@{
        Id = 1; Label = "1. ダウンロード"; StageKey = "download"; Bat = $downloadBat
        ArgsFn = { param($ConfigName) @("-SpaceId", $txtSpaceId.Text.Trim(), "-ConfigName", $ConfigName) }
        OutputPathFn = { param($ConfigName) Join-Path (Get-ResolvedVar "COMMON_DOWNLOAD_PATH") "${ConfigName}_download.xlsx" }
    }
    [PSCustomObject]@{
        Id = 2; Label = "2. 設定ファイルの生成"; StageKey = "generate"; Bat = $generateBat
        ArgsFn = { param($ConfigName) @("-TemplateConfigName", $cmbTemplateName.Text.Trim(), "-DownloadConfigName", $ConfigName) }
        OutputPathFn = { param($ConfigName) Join-Path (Get-ResolvedVar "COMMON_CONFIG_PATH") "${ConfigName}_config.xlsx" }
    }
    [PSCustomObject]@{
        Id = 3; Label = "3. kintoneへ反映"; StageKey = "apply"; Bat = $applyBat
        ArgsFn = { param($ConfigName) @("-ConfigName", $ConfigName) }
        OutputPathFn = $null
    }
    [PSCustomObject]@{
        Id = 4; Label = "4. データチェック"; StageKey = "check"; Bat = $checkBat
        ArgsFn = { param($ConfigName) @("-ConfigName", $ConfigName) }
        OutputPathFn = { param($ConfigName) Join-Path (Get-ResolvedVar "COMMON_CHECK_OUTPUT_PATH") "${ConfigName}_check.xlsx" }
    }
)

$script:stepRunButtons = @{}
$script:stepStatusLabels = @{}
$script:stepOpenButtons = @{}

# 工程カードを専用のパネルにまとめておき、折りたたみ時はこのパネルごとVisible=$falseにする
# （runTopPanelの高さだけで隠すと、はみ出た分がわずかに見えてしまうため）。
$stepCardsPanel = New-Object System.Windows.Forms.Panel
$stepCardsPanel.Location = New-Object System.Drawing.Point(0, 188)
$stepCardsPanel.Size = New-Object System.Drawing.Size(760, ($stepMeta.Count * 34))

$stepRowY = 0
foreach ($sm in $stepMeta) {
    $lblStepName = New-Object System.Windows.Forms.Label
    $lblStepName.Text = $sm.Label
    $lblStepName.AutoSize = $false
    $lblStepName.Size = New-Object System.Drawing.Size(180, 22)
    $lblStepName.Location = New-Object System.Drawing.Point(20, $stepRowY)
    $stepCardsPanel.Controls.Add($lblStepName)

    $btnStepRun = New-Object System.Windows.Forms.Button
    $btnStepRun.Text = "実行"
    $btnStepRun.Size = New-Object System.Drawing.Size(70, 24)
    $btnStepRun.Location = New-Object System.Drawing.Point(210, ($stepRowY - 2))
    $btnStepRun.Tag = $sm.Id
    $btnStepRun.Add_Click({ Invoke-SingleStep -Id $this.Tag })
    $stepCardsPanel.Controls.Add($btnStepRun)
    $script:stepRunButtons[$sm.Id] = $btnStepRun

    $lblStepStatus = New-Object System.Windows.Forms.Label
    $lblStepStatus.Text = "未実行"
    $lblStepStatus.AutoSize = $false
    $lblStepStatus.Size = New-Object System.Drawing.Size(150, 22)
    $lblStepStatus.Location = New-Object System.Drawing.Point(300, $stepRowY)
    $lblStepStatus.ForeColor = [System.Drawing.Color]::Gray
    $stepCardsPanel.Controls.Add($lblStepStatus)
    $script:stepStatusLabels[$sm.Id] = $lblStepStatus

    if ($sm.OutputPathFn) {
        $btnStepOpen = New-Object System.Windows.Forms.Button
        $btnStepOpen.Text = "開く"
        $btnStepOpen.Size = New-Object System.Drawing.Size(70, 24)
        $btnStepOpen.Location = New-Object System.Drawing.Point(460, ($stepRowY - 2))
        $btnStepOpen.Enabled = $false
        $btnStepOpen.Tag = $sm.Id
        $btnStepOpen.Add_Click({ Open-KintoneOutputFile $script:stepOutputPaths[$this.Tag] })
        $stepCardsPanel.Controls.Add($btnStepOpen)
        $script:stepOpenButtons[$sm.Id] = $btnStepOpen
    }

    $stepRowY += 34
}
$runTopPanel.Controls.Add($stepCardsPanel)

$script:singleRunExpandedHeight = $runTopPanel.Height
$script:singleRunCollapsedHeight = 190

function Update-InnerRunTabHeight {
    if ($innerRunTabControl.SelectedTab -eq $tabBatchRun) {
        $innerRunTabControl.Height = $batchPanel.Height + 30
    } else {
        $stepCardsPanel.Visible = !$script:stepsCollapsed
        if ($script:stepsCollapsed) {
            $runTopPanel.Height = $script:singleRunCollapsedHeight
            $innerRunTabControl.Height = $script:singleRunCollapsedHeight + 30
        } else {
            $runTopPanel.Height = $script:singleRunExpandedHeight
            $innerRunTabControl.Height = $script:singleRunExpandedHeight + 30
        }
    }
    # フォーム表示前に高さを変えてもtxtLog（Dock=Fill）側の再レイアウトが
    # 即時に反映されないことがあるため、明示的にレイアウトをやり直す。
    $tabRun.PerformLayout()
}

$lnkToggleSteps.Add_LinkClicked({
    $script:stepsCollapsed = !$script:stepsCollapsed
    $lnkToggleSteps.Text = if ($script:stepsCollapsed) { "▼ 詳細を表示" } else { "▲ 詳細を隠す" }
    Update-InnerRunTabHeight
})

# =========================================
# 一括実行（Excelの複数行を順に0→4まで自動実行）
# =========================================

$batchPanel = New-Object System.Windows.Forms.Panel
$batchPanel.Dock = [System.Windows.Forms.DockStyle]::Top
$batchPanel.Height = 64

$lblBatchExcelPath = New-Object System.Windows.Forms.Label
$lblBatchExcelPath.Text = "実行一覧ファイル"
$lblBatchExcelPath.AutoSize = $true
$lblBatchExcelPath.Location = New-Object System.Drawing.Point(20, 17)

$txtBatchExcelPath = New-Object System.Windows.Forms.TextBox
$txtBatchExcelPath.Location = New-Object System.Drawing.Point(140, 14)
$txtBatchExcelPath.Size = New-Object System.Drawing.Size(250, 22)
$txtBatchExcelPath.ReadOnly = $true

$btnBatchBrowse = New-Object System.Windows.Forms.Button
$btnBatchBrowse.Text = "参照..."
$btnBatchBrowse.Location = New-Object System.Drawing.Point(400, 13)
$btnBatchBrowse.Size = New-Object System.Drawing.Size(70, 24)

$btnBatchRunAll = New-Object System.Windows.Forms.Button
$btnBatchRunAll.Text = "実行"
$btnBatchRunAll.Location = New-Object System.Drawing.Point(480, 12)
$btnBatchRunAll.Size = New-Object System.Drawing.Size(100, 26)

$lblBatchStatus = New-Object System.Windows.Forms.Label
$lblBatchStatus.Text = ""
$lblBatchStatus.AutoSize = $true
$lblBatchStatus.Location = New-Object System.Drawing.Point(20, 42)
$lblBatchStatus.Font = New-Object System.Drawing.Font($lblBatchStatus.Font, [System.Drawing.FontStyle]::Bold)

$batchPanel.Controls.AddRange(@(
    $lblBatchExcelPath, $txtBatchExcelPath, $btnBatchBrowse, $btnBatchRunAll, $lblBatchStatus
))

$dlgBatchExcel = New-Object System.Windows.Forms.OpenFileDialog
$dlgBatchExcel.Filter = "Excelファイル (*.xlsx)|*.xlsx"

$btnBatchBrowse.Add_Click({
    if ($dlgBatchExcel.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $txtBatchExcelPath.Text = $dlgBatchExcel.FileName
    }
})

$txtLog = New-Object System.Windows.Forms.RichTextBox
$txtLog.Multiline = $true
$txtLog.ScrollBars = [System.Windows.Forms.RichTextBoxScrollBars]::Vertical
$txtLog.ReadOnly = $true
$txtLog.Font = New-Object System.Drawing.Font("Consolas", 9)
$txtLog.Dock = [System.Windows.Forms.DockStyle]::Fill
$txtLog.DetectUrls = $true
$txtLog.Add_LinkClicked({ [System.Diagnostics.Process]::Start($_.LinkText) })

$tabSingleRun.Controls.Add($runTopPanel)
$tabBatchRun.Controls.Add($batchPanel)

$tabRun.Controls.Add($txtLog)
$tabRun.Controls.Add($innerRunTabControl)

function Write-Log {
    param([string]$Text)
    $txtLog.AppendText("$Text`r`n")
    $txtLog.SelectionStart = $txtLog.TextLength
    $txtLog.ScrollToCaret()
}

function Invoke-BatStep {
    param(
        [Parameter(Mandatory)][string]$BatPath,
        [string[]]$ArgList = @()
    )

    $script:lastStepOutputLines = New-Object System.Collections.Generic.List[string]

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
            $script:lastStepOutputLines.Add($line)
        }
        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 50
    }

    $proc.WaitForExit()
    Start-Sleep -Milliseconds 200
    $line = $null
    while ($outputQueue.TryDequeue([ref]$line)) {
        Write-Log $line
        $script:lastStepOutputLines.Add($line)
    }

    Unregister-Event -SourceIdentifier $outputEvent.Name
    Remove-Job -Name $outputEvent.Name -Force
    $script:currentProc = $null

    return $proc.ExitCode
}

function Get-StepBat {
    param([int]$Id)
    return ($stepMeta | Where-Object { $_.Id -eq $Id }).Bat
}

function Get-StepArgs {
    param([int]$Id, [string]$ConfigName)
    $sm = $stepMeta | Where-Object { $_.Id -eq $Id }
    return & $sm.ArgsFn $ConfigName
}

function Get-StepOutputPath {
    param([int]$Id, [string]$ConfigName)
    $sm = $stepMeta | Where-Object { $_.Id -eq $Id }
    if (!$sm.OutputPathFn) { return $null }
    return & $sm.OutputPathFn $ConfigName
}

function Test-StepPrereq {
    param([int]$Id, [string]$ConfigName)
    if (!$ConfigName) {
        [System.Windows.Forms.MessageBox]::Show("スペース識別名を入力してください。", "実行", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        return $false
    }
    if ($Id -eq 0 -and !$txtSpaceTemplateId.Text.Trim()) {
        [System.Windows.Forms.MessageBox]::Show("スペース作成にはスペーステンプレートIDが必要です。", "実行", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        return $false
    }
    if ($Id -eq 1 -and !$txtSpaceId.Text.Trim()) {
        [System.Windows.Forms.MessageBox]::Show("ダウンロードにはスペースIDが必要です。", "実行", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        return $false
    }
    if ($Id -eq 2 -and !$cmbTemplateName.Text.Trim()) {
        [System.Windows.Forms.MessageBox]::Show("設定ファイルの生成には設定テンプレート名が必要です。", "実行", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        return $false
    }
    return $true
}

function Set-StepStatus {
    param([int]$Id, [string]$Text)
    $lbl = $script:stepStatusLabels[$Id]
    $lbl.Text = $Text
    $lbl.ForeColor = switch ($Text) {
        "実行中..." { [System.Drawing.Color]::Black }
        "成功"      { [System.Drawing.Color]::DarkGreen }
        "失敗"      { [System.Drawing.Color]::DarkRed }
        default     { [System.Drawing.Color]::Gray }
    }
}

function Set-RunControlsEnabled {
    param([bool]$Enabled)
    $txtConfigName.Enabled = $Enabled
    $txtSpaceId.Enabled = $Enabled
    $cmbTemplateName.Enabled = $Enabled
    $txtSpaceTemplateId.Enabled = $Enabled
    $btnRunAll.Enabled = $Enabled
    $btnBatchBrowse.Enabled = $Enabled
    $btnBatchRunAll.Enabled = $Enabled
    foreach ($btn in $script:stepRunButtons.Values) { $btn.Enabled = $Enabled }
}

function Invoke-Step {
    param([int]$Id, [string]$ConfigName)

    Set-StepStatus -Id $Id -Text "実行中..."
    $label = ($stepMeta | Where-Object { $_.Id -eq $Id }).Label
    Write-Log ""
    Write-Log "===== $label ====="

    $exitCode = Invoke-BatStep -BatPath (Get-StepBat -Id $Id) -ArgList (Get-StepArgs -Id $Id -ConfigName $ConfigName)

    if ($exitCode -ne 0) {
        Set-StepStatus -Id $Id -Text "失敗"
        return $false
    }

    Set-StepStatus -Id $Id -Text "成功"
    if ($Id -eq 0) {
        $idLine = $script:lastStepOutputLines | Where-Object { $_ -match '作成されたスペースID:\s*(\d+)' } | Select-Object -Last 1
        if ($idLine -and $idLine -match '作成されたスペースID:\s*(?<id>\d+)') {
            $txtSpaceId.Text = $Matches.id
        }
    }
    if ($script:stepOpenButtons.ContainsKey($Id)) {
        $outputPath = Get-StepOutputPath -Id $Id -ConfigName $ConfigName
        if ($outputPath -and (Test-Path -LiteralPath $outputPath)) {
            $script:stepOutputPaths[$Id] = $outputPath
            $script:stepOpenButtons[$Id].Enabled = $true
        }
    }
    return $true
}

function Invoke-SingleStep {
    param([int]$Id)

    $configName = $txtConfigName.Text.Trim()
    if (!(Test-StepPrereq -Id $Id -ConfigName $configName)) { return }

    $script:isRunning = $true
    Set-RunControlsEnabled $false
    $lblOverallStatus.Text = ""

    Write-Log ""
    Write-Log "-------------------- $configName --------------------"
    Invoke-Step -Id $Id -ConfigName $configName | Out-Null

    Set-RunControlsEnabled $true
    $script:isRunning = $false
}

# 失敗した工程のLabelを返す（全部成功なら$null）。
function Invoke-AllStepsForCurrentInputs {
    foreach ($sm in $stepMeta) {
        $configName = $txtConfigName.Text.Trim()
        if (!(Test-StepPrereq -Id $sm.Id -ConfigName $configName)) {
            return $sm.Label
        }
        if (!(Invoke-Step -Id $sm.Id -ConfigName $configName)) {
            return $sm.Label
        }
    }
    return $null
}

$btnRunAll.Add_Click({
    $configName = $txtConfigName.Text.Trim()
    if (!(Test-StepPrereq -Id 0 -ConfigName $configName)) { return }

    $script:isRunning = $true
    Set-RunControlsEnabled $false
    $lblOverallStatus.ForeColor = [System.Drawing.Color]::Black
    $lblOverallStatus.Text = "実行中..."

    Write-Log ""
    Write-Log "-------------------- $configName --------------------"

    $failedLabel = Invoke-AllStepsForCurrentInputs

    if ($failedLabel) {
        $lblOverallStatus.ForeColor = [System.Drawing.Color]::DarkRed
        $lblOverallStatus.Text = "エラーが発生しました（$failedLabel）"
    } else {
        $lblOverallStatus.ForeColor = [System.Drawing.Color]::DarkGreen
        $lblOverallStatus.Text = "完了しました"
    }

    Set-RunControlsEnabled $true
    $script:isRunning = $false
})

# Excelの列: スペース識別名 / スペーステンプレートID / 設定テンプレート名。
# 1行につき現在の入力欄へ値をセットしてから0→4を順に実行する。
$btnBatchRunAll.Add_Click({
    $excelPath = $txtBatchExcelPath.Text.Trim()
    if (!$excelPath -or !(Test-Path -LiteralPath $excelPath)) {
        [System.Windows.Forms.MessageBox]::Show("実行一覧ファイルを選択してください。", "一括実行", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        return
    }

    $rows = $null
    try {
        $rows = @(Import-Excel -Path $excelPath)
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Excelの読み込みに失敗しました: $($_.Exception.Message)", "一括実行", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        return
    }
    if ($rows.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("Excelに行がありません。", "一括実行", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        return
    }

    $script:isRunning = $true
    Set-RunControlsEnabled $false

    $resultLines = New-Object System.Collections.Generic.List[string]
    for ($i = 0; $i -lt $rows.Count; $i++) {
        $row = $rows[$i]
        $rowConfigName = "$($row.'スペース識別名')".Trim()
        $rowTemplateId = "$($row.'スペーステンプレートID')".Trim()
        $rowResourceTemplate = "$($row.'設定テンプレート名')".Trim()

        $lblBatchStatus.ForeColor = [System.Drawing.Color]::Black
        $lblBatchStatus.Text = "実行中... ($($i + 1)/$($rows.Count): $rowConfigName)"
        [System.Windows.Forms.Application]::DoEvents()

        Write-Log ""
        Write-Log "==================== 一括実行 $($i + 1)/$($rows.Count): $rowConfigName ===================="

        if (!$rowConfigName -or !$rowTemplateId -or !$rowResourceTemplate) {
            Write-Log "スペース識別名・スペーステンプレートID・設定テンプレート名のいずれかが空のためスキップします。"
            $resultLines.Add("行$($i + 2) ($rowConfigName): スキップ（必須項目が空）")
            continue
        }

        $txtConfigName.Text = $rowConfigName
        $txtSpaceTemplateId.Text = $rowTemplateId
        $txtSpaceId.Text = ""
        if ($cmbTemplateName.Items.Contains($rowResourceTemplate)) {
            $cmbTemplateName.SelectedItem = $rowResourceTemplate
        } else {
            $cmbTemplateName.Text = $rowResourceTemplate
        }

        $failedLabel = Invoke-AllStepsForCurrentInputs
        if ($failedLabel) {
            $resultLines.Add("行$($i + 2) ($rowConfigName): 失敗（$failedLabel）")
        } else {
            $resultLines.Add("行$($i + 2) ($rowConfigName): 成功")
        }
    }

    Write-Log ""
    Write-Log "==================== 一括実行 結果 ===================="
    foreach ($line in $resultLines) { Write-Log $line }

    $failedCount = @($resultLines | Where-Object { $_ -notmatch ": 成功$" }).Count
    if ($failedCount -gt 0) {
        $lblBatchStatus.ForeColor = [System.Drawing.Color]::DarkRed
        $lblBatchStatus.Text = "完了（$($rows.Count)件中$failedCount件が失敗/スキップ）"
    } else {
        $lblBatchStatus.ForeColor = [System.Drawing.Color]::DarkGreen
        $lblBatchStatus.Text = "完了しました（全$($rows.Count)件成功）"
    }

    Set-RunControlsEnabled $true
    $script:isRunning = $false
})

# =========================================
# 共通: 環境変数バッチファイル（set-env.bat・set-kintone.bat）の読み書き
# =========================================

function Read-EnvBatLines {
    param([string]$Path = $setEnvBat)
    if (!(Test-Path -LiteralPath $Path)) { return @() }
    return [System.IO.File]::ReadAllLines($Path, $cp932)
}

function Get-EnvBatDefaults {
    param([string]$Path = $setEnvBat)
    $result = @{}
    foreach ($line in (Read-EnvBatLines -Path $Path)) {
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
        $defaults = Get-EnvBatDefaults
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

    $templatePath = Get-ResolvedVar "COMMON_TEMPLATE_PATH"
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

# 「設定」タブの入力欄（保存前の値）を使ってkintoneに接続できるか確認する。set-kintone.batへの保存は行わない。
# 結果はボタンの下の専用ラベル（StatusLabel、ボタン再生成のたびにTagで渡す）に表示する。
function Test-KintoneConnectionFromFields {
    param(
        [System.Windows.Forms.Button]$Button,
        [System.Windows.Forms.Label]$StatusLabel
    )

    $baseUrlVal = $script:fieldTextBoxes["KINTONE_BASE_URL"].Text.Trim()
    $loginVal = $script:fieldTextBoxes["KINTONE_LOGIN"].Text
    $passwordVal = $script:fieldTextBoxes["KINTONE_PASSWORD"].Text

    if (!$baseUrlVal -or !$loginVal -or !$passwordVal) {
        $StatusLabel.ForeColor = [System.Drawing.Color]::DarkRed
        $StatusLabel.Text = "kintoneのサイトURL・ログイン名・パスワードをすべて入力してください"
        return
    }

    $Button.Enabled = $false
    $StatusLabel.ForeColor = [System.Drawing.Color]::Black
    $StatusLabel.Text = "接続テスト中..."
    [System.Windows.Forms.Application]::DoEvents()

    try {
        $pair = "${loginVal}:${passwordVal}"
        $authorization = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($pair))
        Invoke-KintoneRequest -BaseUrl $baseUrlVal -Authorization $authorization -Method GET -Path "/k/v1/apps.json?limit=1" | Out-Null
        $StatusLabel.ForeColor = [System.Drawing.Color]::DarkGreen
        $StatusLabel.Text = "成功しました"
    } catch {
        $StatusLabel.ForeColor = [System.Drawing.Color]::DarkRed
        $StatusLabel.Text = "失敗しました（$($_.Exception.Message)）"
    }

    $Button.Enabled = $true
}

$fieldPanel = New-Object System.Windows.Forms.Panel
$fieldPanel.Dock = [System.Windows.Forms.DockStyle]::Fill
$fieldPanel.AutoScroll = $true

$tabSettings.Controls.Add($fieldPanel)
$tabSettings.Controls.Add($topPanel)

$varLabels = [ordered]@{
    "COMMON_DOWNLOAD_PATH"     = "ダウンロード先のフォルダ"
    "COMMON_TEMPLATE_PATH"     = "テンプレートファイルのフォルダ"
    "COMMON_CONFIG_PATH"       = "設定ファイルのフォルダ"
    "COMMON_CHECK_OUTPUT_PATH" = "チェック結果の出力先フォルダ"
    "COMMON_LOG_PATH"          = "ログの出力先フォルダ"
    "KINTONE_BASE_URL"         = "kintoneのサイトURL"
    "KINTONE_LOGIN"            = "ログイン名"
    "KINTONE_PASSWORD"         = "パスワード"
}

$folderBrowseVars = @("COMMON_DOWNLOAD_PATH", "COMMON_TEMPLATE_PATH", "COMMON_CONFIG_PATH", "COMMON_CHECK_OUTPUT_PATH", "COMMON_LOG_PATH")
# kintoneの接続情報の3項目はset-env.batではなくset-kintone.batに保存する（未存在の場合は保存時に新規作成する）
$kintoneVars = @("KINTONE_BASE_URL", "KINTONE_LOGIN", "KINTONE_PASSWORD")
$passwordVars = @("KINTONE_PASSWORD")

$script:fieldTextBoxes = @{}

function Update-SettingsFields {
    $fieldPanel.Controls.Clear()
    $script:fieldTextBoxes = @{}

    $defaults = Get-EnvBatDefaults -Path $setEnvBat
    $kintoneDefaults = Get-EnvBatDefaults -Path $setKintoneBat
    $y = 10

    foreach ($varName in $varLabels.Keys) {
        $isKintoneVar = $kintoneVars -contains $varName
        if ($isKintoneVar) {
            # set-kintone.batが未存在/未設定でも空欄で入力できるようにする
            $varValue = if ($kintoneDefaults.ContainsKey($varName)) { $kintoneDefaults[$varName] } else { "" }
        } else {
            if (!$defaults.ContainsKey($varName)) { continue }
            $varValue = $defaults[$varName]
        }

        if ($varName -eq "KINTONE_BASE_URL") {
            $y += 8
            $lblKintoneHeader = New-Object System.Windows.Forms.Label
            $lblKintoneHeader.Text = "kintoneの接続情報"
            $lblKintoneHeader.AutoSize = $true
            $lblKintoneHeader.Location = New-Object System.Drawing.Point(20, $y)
            $lblKintoneHeader.Font = New-Object System.Drawing.Font($lblKintoneHeader.Font, [System.Drawing.FontStyle]::Bold)
            $fieldPanel.Controls.Add($lblKintoneHeader)
            $y += 28
        }

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
            if ($passwordVars -contains $varName) {
                $txt.UseSystemPasswordChar = $true
            }

            $fieldPanel.Controls.Add($txt)
            $script:fieldTextBoxes[$varName] = $txt
        }

        $y += 32
    }

    $y += 4
    $btnTestConnection = New-Object System.Windows.Forms.Button
    $btnTestConnection.Text = "接続テスト"
    $btnTestConnection.Location = New-Object System.Drawing.Point(310, $y)
    $btnTestConnection.Size = New-Object System.Drawing.Size(100, 26)
    $fieldPanel.Controls.Add($btnTestConnection)
    $y += 32

    $lblTestStatus = New-Object System.Windows.Forms.Label
    $lblTestStatus.Text = ""
    $lblTestStatus.AutoSize = $true
    # 幅を制限して、長いエラーメッセージでも横スクロールにならず折り返して表示させる
    $lblTestStatus.MaximumSize = New-Object System.Drawing.Size(420, 0)
    $lblTestStatus.Location = New-Object System.Drawing.Point(310, $y)
    $lblTestStatus.Font = New-Object System.Drawing.Font($lblTestStatus.Font, [System.Drawing.FontStyle]::Bold)
    $fieldPanel.Controls.Add($lblTestStatus)

    # ボタンは「設定」タブを開くたびに再生成されるため、対応する結果ラベルをTagで持たせてクリック時に参照する
    $btnTestConnection.Tag = $lblTestStatus
    $btnTestConnection.Add_Click({ Test-KintoneConnectionFromFields -Button $this -StatusLabel $this.Tag })
}

$btnReload.Add_Click({
    Update-SettingsFields
    $lblSaveStatus.ForeColor = [System.Drawing.Color]::Black
    $lblSaveStatus.Text = "再読込しました"
})

function Save-EnvBatFile {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string[]]$VarNames
    )
    $existingLines = Read-EnvBatLines -Path $Path
    $writtenVars = @{}

    $newLines = @(foreach ($line in $existingLines) {
        $m = $lineRegex.Match($line.Trim())
        $varName = if ($m.Success) { $m.Groups["var"].Value } else { $null }
        if ($varName -and $VarNames -contains $varName -and $script:fieldTextBoxes.ContainsKey($varName)) {
            $writtenVars[$varName] = $true
            $newVal = $script:fieldTextBoxes[$varName].Text
            "if not defined $varName set `"$varName=$newVal`""
        } else {
            $line
        }
    })

    # ファイルが未存在、または既存の内容に該当変数の行が無い場合は末尾に追加する
    foreach ($varName in $VarNames) {
        if (!$writtenVars.ContainsKey($varName) -and $script:fieldTextBoxes.ContainsKey($varName)) {
            $newLines += "if not defined $varName set `"$varName=$($script:fieldTextBoxes[$varName].Text)`""
        }
    }
    if ($existingLines.Count -eq 0) {
        $newLines = @("@echo off", "") + $newLines
    }

    $content = ($newLines -join "`r`n") + "`r`n"
    [System.IO.File]::WriteAllText($Path, $content, $cp932)
}

$btnSave.Add_Click({
    Save-EnvBatFile -Path $setEnvBat -VarNames @($varLabels.Keys | Where-Object { $kintoneVars -notcontains $_ })
    Save-EnvBatFile -Path $setKintoneBat -VarNames $kintoneVars

    $lblSaveStatus.ForeColor = [System.Drawing.Color]::DarkGreen
    $lblSaveStatus.Text = "保存しました"
})

Update-SettingsFields

# =========================================
# ログタブ
# =========================================

$logStagePanel = New-Object System.Windows.Forms.Panel
$logStagePanel.Dock = [System.Windows.Forms.DockStyle]::Top
$logStagePanel.Height = 90

$lblLogConfigName = New-Object System.Windows.Forms.Label
$lblLogConfigName.Text = "スペース識別名"
$lblLogConfigName.AutoSize = $true
$lblLogConfigName.Location = New-Object System.Drawing.Point(20, 17)

$cmbLogConfigName = New-Object System.Windows.Forms.ComboBox
$cmbLogConfigName.Location = New-Object System.Drawing.Point(160, 14)
$cmbLogConfigName.Size = New-Object System.Drawing.Size(220, 24)
$cmbLogConfigName.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList

$script:logStageRadios = @{}
for ($i = 0; $i -lt $stepMeta.Count; $i++) {
    $sm = $stepMeta[$i]
    $radio = New-Object System.Windows.Forms.RadioButton
    $radio.Text = $sm.Label
    $radio.AutoSize = $true
    $radio.Tag = $sm.StageKey
    $radio.Checked = ($sm.Id -eq 0)
    $radio.Location = New-Object System.Drawing.Point((20 + 140 * ($i % 3)), (40 + 24 * [Math]::Floor($i / 3)))
    $radio.Add_CheckedChanged({ if ($this.Checked) { Update-LogView } })
    $logStagePanel.Controls.Add($radio)
    $script:logStageRadios[$sm.StageKey] = $radio
}

$logStagePanel.Controls.AddRange(@($lblLogConfigName, $cmbLogConfigName))

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

    $logPath = Get-ResolvedVar "COMMON_LOG_PATH"
    if ($logPath -and (Test-Path -LiteralPath $logPath)) {
        $stageKeyPattern = ($stepMeta.StageKey -join '|')
        $stagePrefixPattern = "^(?:$stageKeyPattern)_(?<config>.+)_\d{8}_\d{6}$"
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
    $stage = ($script:logStageRadios.GetEnumerator() | Where-Object { $_.Value.Checked }).Key
    $logPath = Get-ResolvedVar "COMMON_LOG_PATH"

    $logContentBox.Text = ""

    if (!($logPath -and (Test-Path -LiteralPath $logPath))) {
        return
    }

    $logConfigName = $cmbLogConfigName.SelectedItem
    $configFilter = if ($logConfigName -and $logConfigName -ne "すべて") { "$logConfigName" + "_" } else { "" }
    $files = Get-ChildItem -LiteralPath $logPath -Filter "${stage}_$configFilter*.log" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime

    $sections = foreach ($file in $files) { [System.IO.File]::ReadAllText($file.FullName, $cp932) }
    $logContentBox.Text = $sections -join "`r`n`r`n"
}

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
# フォーム表示前はTabControlのSelectedTabが正しく解決されないことがあるため、
# 実際に表示された後（Add_Shown）に高さ調整をやり直す。
$form.Add_Shown({ Update-InnerRunTabHeight })
$tabControl.SelectedTab = $tabRun

[System.Windows.Forms.Application]::Run($form)
