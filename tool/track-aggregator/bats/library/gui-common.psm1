$script:cp932Encoding = [System.Text.Encoding]::GetEncoding(932)

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
    $psi.StandardOutputEncoding = $script:cp932Encoding

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

# バッチファイルをcmd.exe経由で実行し、標準出力を1行ずつ$OnOutputLineへ渡す。
# $CurrentProcessRefを渡すと、呼び出し側でウィンドウを閉じる際にプロセスを強制終了できるよう
# 実行中のProcessオブジェクトを書き戻す
function Invoke-BatStep {
    param(
        [Parameter(Mandatory)][string]$BatPath,
        [Parameter(Mandatory)][string]$WorkingDirectory,
        [scriptblock]$OnOutputLine,
        [ref]$CurrentProcessRef
    )

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "cmd.exe"
    $psi.Arguments = "/c ""`"$BatPath`" 2>&1"""
    $psi.WorkingDirectory = $WorkingDirectory
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.CreateNoWindow = $true
    $psi.StandardOutputEncoding = $script:cp932Encoding

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
    if ($CurrentProcessRef) { $CurrentProcessRef.Value = $proc }
    $proc.BeginOutputReadLine()

    while (!$proc.HasExited) {
        $line = $null
        while ($outputQueue.TryDequeue([ref]$line)) {
            if ($OnOutputLine) { & $OnOutputLine $line }
        }
        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 50
    }

    $proc.WaitForExit()
    Start-Sleep -Milliseconds 200
    $line = $null
    while ($outputQueue.TryDequeue([ref]$line)) {
        if ($OnOutputLine) { & $OnOutputLine $line }
    }

    Unregister-Event -SourceIdentifier $outputEvent.Name
    Remove-Job -Name $outputEvent.Name -Force
    if ($CurrentProcessRef) { $CurrentProcessRef.Value = $null }

    return $proc.ExitCode
}
