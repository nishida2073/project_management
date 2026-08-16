# =========================================
# GUI（trackデータ集計ツール）
# =========================================

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
# build-gui.ps1でps2exeビルドした実行ファイルはプロジェクトルートに置かれるため、batsフォルダを別途辿る
$basePath = Join-Path $rootPath "bats"
$cp932 = [System.Text.Encoding]::GetEncoding(932)

$buttonDefs = @(
    [PSCustomObject]@{ Id = 0; Label = "データ取得"; Bat = (Join-Path $basePath "download-results.bat"); OutputDirVar = "ResultRootDir" }
    [PSCustomObject]@{ Id = 3; Label = "実施状況集計"; Bat = (Join-Path $basePath "collect-combine-result.bat"); OutputDirVar = "OutputCombineCollectDir" }
    [PSCustomObject]@{ Id = 1; Label = "テスト結果集計"; Bat = (Join-Path $basePath "collect-test-result.bat"); OutputDirVar = "OutputTestCollectDir" }
    [PSCustomObject]@{ Id = 2; Label = "アンケート結果集計"; Bat = (Join-Path $basePath "collect-survey-result.bat"); OutputDirVar = "OutputSurveyCollectDir" }
    [PSCustomObject]@{ Id = 4; Label = "経年比較集計"; Bat = (Join-Path $basePath "collect-year-comparison-result.bat"); OutputDirVar = "OutputYearComparisonCollectDir" }
)

# common-env.batを実際に呼び出してset済みの環境変数を取り込む（パスの組み立てロジックをこちらで二重管理しない）
function Get-BatEnvVars {
    param([string]$BatPath)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "cmd.exe"
    $psi.Arguments = "/c ""call ""$BatPath"" >nul && set"""
    $psi.WorkingDirectory = Split-Path $BatPath
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.CreateNoWindow = $true
    $psi.StandardOutputEncoding = $cp932

    $proc = [System.Diagnostics.Process]::Start($psi)
    $output = $proc.StandardOutput.ReadToEnd()
    $proc.WaitForExit()

    $vars = @{}
    foreach ($line in ($output -split "`r?`n")) {
        if ($line -match "^([^=]+)=(.*)$") {
            $vars[$Matches[1]] = $Matches[2]
        }
    }
    return $vars
}

$script:commonEnvVars = Get-BatEnvVars -BatPath (Join-Path $basePath "common-env.bat")

function Open-OutputFolder {
    param([string]$Path)
    if (!$Path -or !(Test-Path -LiteralPath $Path)) {
        [System.Windows.Forms.MessageBox]::Show("フォルダが見つかりません:`r`n$Path", "開く", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        return
    }
    Start-Process -FilePath $Path
}

$form = New-Object System.Windows.Forms.Form
$form.Text = "trackデータ集計ツール"
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
$tabControl.Controls.Add($tabRun)
$form.Controls.Add($tabControl)

# =========================================
# 実行タブ
# =========================================

$buttonPanel = New-Object System.Windows.Forms.Panel
$buttonPanel.Dock = [System.Windows.Forms.DockStyle]::Top
$buttonPanel.Height = 20 + (40 * $buttonDefs.Count)

$script:runButtons = @{}
$script:stepStatusLabels = @{}
$buttonY = 10
foreach ($bd in $buttonDefs) {
    $btn = New-Object System.Windows.Forms.Button
    $btn.Text = $bd.Label
    $btn.Size = New-Object System.Drawing.Size(260, 30)
    $btn.Location = New-Object System.Drawing.Point(20, $buttonY)
    $btn.Tag = $bd
    $btn.Add_Click({ Invoke-BatButton -ButtonDef $this.Tag })
    $buttonPanel.Controls.Add($btn)
    $script:runButtons[$bd.Label] = $btn

    $btnOpen = New-Object System.Windows.Forms.Button
    $btnOpen.Text = "開く"
    $btnOpen.Size = New-Object System.Drawing.Size(70, 30)
    $btnOpen.Location = New-Object System.Drawing.Point(290, $buttonY)
    $btnOpen.Tag = $bd
    $btnOpen.Add_Click({ Open-OutputFolder $script:commonEnvVars[$this.Tag.OutputDirVar] })
    $buttonPanel.Controls.Add($btnOpen)

    $lblStepStatus = New-Object System.Windows.Forms.Label
    $lblStepStatus.Text = "未実行"
    $lblStepStatus.AutoSize = $false
    $lblStepStatus.Size = New-Object System.Drawing.Size(150, 22)
    $lblStepStatus.Location = New-Object System.Drawing.Point(370, ($buttonY + 4))
    $lblStepStatus.ForeColor = [System.Drawing.Color]::Gray
    $buttonPanel.Controls.Add($lblStepStatus)
    $script:stepStatusLabels[$bd.Id] = $lblStepStatus

    $buttonY += 40
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

$txtLog = New-Object System.Windows.Forms.RichTextBox
$txtLog.Multiline = $true
$txtLog.ScrollBars = [System.Windows.Forms.RichTextBoxScrollBars]::Vertical
$txtLog.ReadOnly = $true
$txtLog.Font = New-Object System.Drawing.Font("Consolas", 9)
$txtLog.Dock = [System.Windows.Forms.DockStyle]::Fill
$txtLog.DetectUrls = $true
$txtLog.Add_LinkClicked({ [System.Diagnostics.Process]::Start($_.LinkText) })

$tabRun.Controls.Add($txtLog)
$tabRun.Controls.Add($buttonPanel)

function Write-Log {
    param([string]$Text)
    $txtLog.AppendText("$Text`r`n")
    $txtLog.SelectionStart = $txtLog.TextLength
    $txtLog.ScrollToCaret()
}

function Set-RunButtonsEnabled {
    param([bool]$Enabled)
    foreach ($btn in $script:runButtons.Values) { $btn.Enabled = $Enabled }
}

function Invoke-BatStep {
    param(
        [Parameter(Mandatory)][string]$BatPath
    )

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "cmd.exe"
    $psi.Arguments = "/c ""`"$BatPath`" 2>&1"""
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

function Invoke-BatButton {
    param($ButtonDef)

    Set-RunButtonsEnabled $false
    Set-StepStatus -Id $ButtonDef.Id -Text "実行中..."

    Write-Log ""
    Write-Log "===== $($ButtonDef.Label) ====="

    $exitCode = Invoke-BatStep -BatPath $ButtonDef.Bat

    if ($exitCode -ne 0) {
        Write-Log "----- $($ButtonDef.Label) 失敗（終了コード: $exitCode） -----"
        Set-StepStatus -Id $ButtonDef.Id -Text "失敗"
    } else {
        Write-Log "----- $($ButtonDef.Label) 完了 -----"
        Set-StepStatus -Id $ButtonDef.Id -Text "成功"
    }

    Set-RunButtonsEnabled $true
}

[System.Windows.Forms.Application]::Run($form)
