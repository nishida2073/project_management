# =========================================
# GUI（trackデータ集計ツール）
# =========================================

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

[System.Windows.Forms.Application]::EnableVisualStyles()
[System.Windows.Forms.Application]::SetCompatibleTextRenderingDefault($false)

# バッチ実行中に外部プロセス（ブラウザ等）へフォーカスが移ると、SetForegroundWindowを
# 単純に呼ぶだけではWindowsのセキュリティ制限で拒否され、タスクバーの点滅になるだけのため、
# AttachThreadInputで入力スレッドを一時的に結合してから奪う
Add-Type @'
using System;
using System.Runtime.InteropServices;
public class Win32Focus {
    [DllImport("user32.dll")]
    public static extern bool SetForegroundWindow(IntPtr hWnd);

    [DllImport("user32.dll")]
    public static extern IntPtr GetForegroundWindow();

    [DllImport("user32.dll")]
    public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);

    [DllImport("kernel32.dll")]
    public static extern uint GetCurrentThreadId();

    [DllImport("user32.dll")]
    public static extern bool AttachThreadInput(uint idAttach, uint idAttachTo, bool fAttach);

    [DllImport("user32.dll")]
    public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    public static void ForceForeground(IntPtr hWnd) {
        uint currentThreadId = GetCurrentThreadId();
        uint dummyProcessId;
        uint foregroundThreadId = GetWindowThreadProcessId(GetForegroundWindow(), out dummyProcessId);

        bool attached = false;
        if (foregroundThreadId != currentThreadId) {
            attached = AttachThreadInput(currentThreadId, foregroundThreadId, true);
        }
        try {
            ShowWindow(hWnd, 9); // SW_RESTORE
            SetForegroundWindow(hWnd);
        } finally {
            if (attached) {
                AttachThreadInput(currentThreadId, foregroundThreadId, false);
            }
        }
    }
}
'@

function Show-FormInForeground {
    param($Form)
    if ($Form.WindowState -eq [System.Windows.Forms.FormWindowState]::Minimized) {
        $Form.WindowState = [System.Windows.Forms.FormWindowState]::Normal
    }
    [Win32Focus]::ForceForeground($Form.Handle)
}

if ($MyInvocation.MyCommand.Path) {
    $scriptDir = Split-Path $MyInvocation.MyCommand.Path
    $rootPath = Split-Path $scriptDir -Parent
} else {
    $rootPath = Split-Path ([System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName)
}
# build-gui.ps1でps2exeビルドした実行ファイルはプロジェクトルートに置かれるため、batsフォルダを別途辿る
$basePath = Join-Path $rootPath "bats"
$cp932 = [System.Text.Encoding]::GetEncoding(932)

# 子プロセス（Invoke-BatStep経由で起動するbat/ps1）のWrite-Messageに、
# GUIログ向けの色タグ付き出力へ切り替えさせる合図
$env:GUI_LOG_MODE = "1"

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

$buttonDefs = @(
    [PSCustomObject]@{ Label = "データ取得状況確認"; BatchPath = (Join-Path $basePath "check-download-status.bat"); TargetDirPath = $script:commonEnvVars["MasterDataRootDir"] }
    [PSCustomObject]@{ Label = "データ取得"; BatchPath = (Join-Path $basePath "download-results.bat"); TargetDirPath = $script:commonEnvVars["ResultRootDir"] }
    [PSCustomObject]@{ Label = "実施状況集計"; BatchPath = (Join-Path $basePath "collect-combine-result.bat"); TargetDirPath = $script:commonEnvVars["OutputCombineCollectDir"] }
    [PSCustomObject]@{ Label = "テスト結果集計"; BatchPath = (Join-Path $basePath "collect-test-result.bat"); TargetDirPath = $script:commonEnvVars["OutputTestCollectDir"] }
    [PSCustomObject]@{ Label = "アンケート結果集計"; BatchPath = (Join-Path $basePath "collect-survey-result.bat"); TargetDirPath = $script:commonEnvVars["OutputSurveyCollectDir"] }
    [PSCustomObject]@{ Label = "経年比較集計"; BatchPath = (Join-Path $basePath "collect-year-comparison-result.bat"); TargetDirPath = $script:commonEnvVars["OutputYearComparisonCollectDir"] }
)

function Open-TargetDir {
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

    if ($bd.TargetDirPath) {
        $lnkOpen = New-Object System.Windows.Forms.LinkLabel
        $lnkOpen.Text = "開く"
        $lnkOpen.AutoSize = $false
        $lnkOpen.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
        $lnkOpen.Size = New-Object System.Drawing.Size(70, 30)
        $lnkOpen.Location = New-Object System.Drawing.Point(290, $buttonY)
        $lnkOpen.Tag = $bd
        $lnkOpen.Add_LinkClicked({ Open-TargetDir $this.Tag.TargetDirPath })
        $buttonPanel.Controls.Add($lnkOpen)
    }

    $lblStepStatus = New-Object System.Windows.Forms.Label
    $lblStepStatus.Text = "未実行"
    $lblStepStatus.AutoSize = $false
    $lblStepStatus.TextAlign = [System.Drawing.ContentAlignment]::MiddleLeft
    $lblStepStatus.Size = New-Object System.Drawing.Size(150, 22)
    $lblStepStatus.Location = New-Object System.Drawing.Point(370, ($buttonY + 4))
    $lblStepStatus.ForeColor = [System.Drawing.Color]::Gray
    $buttonPanel.Controls.Add($lblStepStatus)
    $script:stepStatusLabels[$bd.Label] = $lblStepStatus

    $buttonY += 40
}

function Set-StepStatus {
    param([string]$Label, [string]$Text)
    $lbl = $script:stepStatusLabels[$Label]
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

function Get-LogLineColor {
    param([string]$ConsoleColorName)
    switch ($ConsoleColorName) {
        "Black"       { [System.Drawing.Color]::Black }
        "DarkBlue"    { [System.Drawing.Color]::DarkBlue }
        "DarkGreen"   { [System.Drawing.Color]::DarkGreen }
        "DarkCyan"    { [System.Drawing.Color]::DarkCyan }
        "DarkRed"     { [System.Drawing.Color]::DarkRed }
        "DarkMagenta" { [System.Drawing.Color]::DarkMagenta }
        "DarkYellow"  { [System.Drawing.Color]::Olive }
        "Gray"        { [System.Drawing.Color]::Gray }
        "DarkGray"    { [System.Drawing.Color]::DarkGray }
        "Blue"        { [System.Drawing.Color]::Blue }
        "Green"       { [System.Drawing.Color]::Green }
        "Cyan"        { [System.Drawing.Color]::Cyan }
        "Red"         { [System.Drawing.Color]::Red }
        "Magenta"     { [System.Drawing.Color]::Magenta }
        "Yellow"      { [System.Drawing.Color]::Gold }
        "White"       { [System.Drawing.Color]::Black } # 白背景のログ欄では白文字が見えなくなるため黒にする
        default       { [System.Drawing.Color]::Black }
    }
}

function Write-Log {
    param([string]$Text)
    $color = [System.Drawing.Color]::Black
    if ($Text -match '^\[\[COLOR:(?<color>\w+)\]\](?<rest>.*)$') {
        $color = Get-LogLineColor -ConsoleColorName $Matches['color']
        $Text = $Matches['rest']
    }
    $txtLog.SelectionStart = $txtLog.TextLength
    $txtLog.SelectionLength = 0
    $txtLog.SelectionColor = $color
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
    Set-StepStatus -Label $ButtonDef.Label -Text "実行中..."

    Write-Log ""
    Write-Log "===== $($ButtonDef.Label) ====="

    $exitCode = Invoke-BatStep -BatPath $ButtonDef.BatchPath

    Show-FormInForeground -Form $form

    if ($exitCode -ne 0) {
        Write-Log "----- $($ButtonDef.Label) 失敗（終了コード: $exitCode） -----"
        Set-StepStatus -Label $ButtonDef.Label -Text "失敗"
    } else {
        Write-Log "----- $($ButtonDef.Label) 完了 -----"
        Set-StepStatus -Label $ButtonDef.Label -Text "成功"
    }

    Set-RunButtonsEnabled $true
}

[System.Windows.Forms.Application]::Run($form)
