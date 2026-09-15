$script:cp932Encoding = [System.Text.Encoding]::GetEncoding(932)
$script:setEnvLineRegex = [regex]'^if not defined (?<var>\S+) set "\k<var>=(?<val>.*)"$'

function Read-SetEnvLines {
    param([Parameter(Mandatory)][string]$Path)
    if (!(Test-Path -LiteralPath $Path)) { return @() }
    return [System.IO.File]::ReadAllLines($Path, $script:cp932Encoding)
}

function Expand-VarTokens {
    param(
        [string]$Value,
        [Parameter(Mandatory)][scriptblock]$Resolver,
        [string]$BasePath
    )
    if (!$Value) { return $Value }
    $expanded = if ($BasePath) { $Value.Replace("%BASE_PATH%", "$BasePath\") } else { $Value }
    return [regex]::Replace($expanded, '%(\w+)%', {
        param($match)
        $refVal = & $Resolver $match.Groups[1].Value
        if ($refVal) { $refVal } else { $match.Value }
    })
}

function Resolve-BrowseStart {
    param(
        [string]$RawValue,
        [Parameter(Mandatory)][string]$DefaultPath,
        [Parameter(Mandatory)][scriptblock]$Resolver,
        [string]$BasePath
    )
    if (!$RawValue) { return $DefaultPath }
    return Expand-VarTokens -Value $RawValue -Resolver $Resolver -BasePath $BasePath
}

function Get-SetEnvDefaults {
    param([Parameter(Mandatory)][string]$Path)
    $result = @{}
    foreach ($line in (Read-SetEnvLines -Path $Path)) {
        $m = $script:setEnvLineRegex.Match($line.Trim())
        if ($m.Success) {
            $result[$m.Groups["var"].Value] = $m.Groups["val"].Value
        }
    }
    return $result
}

function Get-ResolvedVar {
    param([string]$VarName, [string]$Path = $setEnvBat)
    $val = [Environment]::GetEnvironmentVariable($VarName)
    if (!$val) {
        $defaults = Get-SetEnvDefaults -Path $Path
        if ($defaults.ContainsKey($VarName)) {
            $val = $defaults[$VarName]
        }
    }
    if (!$val) { return $val }
    return Expand-VarTokens -Value $val -Resolver { param($name) Get-ResolvedVar $name } -BasePath $rootPath
}

function Save-EnvBatFile {
    param(
        [Parameter(Mandatory)][string]$Path,
        [string[]]$VarNames,
        [Parameter(Mandatory)][scriptblock]$GetValueFn,
        [Parameter(Mandatory)][scriptblock]$HasValueFn
    )
    $existingLines = Read-SetEnvLines -Path $Path
    $writtenVars = @{}

    $newLines = @(foreach ($line in $existingLines) {
        $m = $script:setEnvLineRegex.Match($line.Trim())
        $varName = if ($m.Success) { $m.Groups["var"].Value } else { $null }
        $matchesVarNames = (-not $VarNames) -or ($VarNames -contains $varName)
        if ($varName -and $matchesVarNames -and (& $HasValueFn $varName)) {
            $writtenVars[$varName] = $true
            $newVal = & $GetValueFn $varName
            "if not defined $varName set `"$varName=$newVal`""
        } else {
            $line
        }
    })

    if ($VarNames) {
        foreach ($varName in $VarNames) {
            if (!$writtenVars.ContainsKey($varName) -and (& $HasValueFn $varName)) {
                $newLines += "if not defined $varName set `"$varName=$(& $GetValueFn $varName)`""
            }
        }
    }
    if ($existingLines.Count -eq 0) {
        $newLines = @("@echo off", "") + $newLines
    }

    $content = ($newLines -join "`r`n") + "`r`n"
    [System.IO.File]::WriteAllText($Path, $content, $script:cp932Encoding)
}

$script:groupBatLineRegex = [regex]'^set "(?<var>\S+?)=(?<val>.*)"$'

function Get-GroupBatPath { param([string]$GroupName) Join-Path $clientsDir "$GroupName.bat" }

function Get-SetLineRawValues {
    param([string]$Path)
    $result = @{}
    if (!(Test-Path -LiteralPath $Path)) { return $result }
    foreach ($line in [System.IO.File]::ReadAllLines($Path, $script:cp932Encoding)) {
        $m = $script:groupBatLineRegex.Match($line.Trim())
        if ($m.Success) { $result[$m.Groups["var"].Value] = $m.Groups["val"].Value }
    }
    return $result
}

function Get-GroupKintoneThreadUrl {
    param([string]$GroupName)
    if (!$GroupName) { return $null }
    $raw = Get-SetLineRawValues -Path (Get-GroupBatPath $GroupName)
    $subdomain = $raw["KintoneSubdomain"]
    $spaceId = $raw["SpaceId"]
    $threadId = $raw["ThreadId"]
    if (!$subdomain -or !$spaceId -or !$threadId) { return $null }
    return "https://$subdomain.cybozu.com/k/#/space/$spaceId/thread/$threadId"
}

function ConvertFrom-MentionUserCodesText {
    param([string]$Text)
    $rows = [System.Collections.Generic.List[object]]::new()
    foreach ($part in ($Text -split ',')) {
        $trimmed = $part.Trim()
        if (!$trimmed) { continue }
        $pair = $trimmed -split ':', 2
        $code = $pair[0].Trim()
        if (!$code) { continue }
        $type = if ($pair.Count -ge 2 -and $pair[1].Trim()) { $pair[1].Trim().ToUpper() } else { "USER" }
        if ($mentionTypeOptions -notcontains $type) { $type = "USER" }
        $rows.Add([PSCustomObject]@{ Code = $code; Type = $type })
    }
    return $rows
}

function ConvertTo-MentionUserCodesText {
    param($Rows)
    return (($Rows | Where-Object { $_.Code } | ForEach-Object { "$($_.Code):$($_.Type)" }) -join ',')
}

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

    public static void ForceForeground(IntPtr hWnd) {
        uint currentThreadId = GetCurrentThreadId();
        uint dummyProcessId;
        uint foregroundThreadId = GetWindowThreadProcessId(GetForegroundWindow(), out dummyProcessId);

        bool attached = false;
        if (foregroundThreadId != currentThreadId) {
            attached = AttachThreadInput(currentThreadId, foregroundThreadId, true);
        }
        try {
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

function Invoke-BatProcess {
    param(
        [Parameter(Mandatory)][string]$BatPath,
        [Parameter(Mandatory)][string]$WorkingDirectory,
        [string[]]$BatArgs,
        [scriptblock]$OnOutputLine,
        [ref]$CurrentProcessRef
    )

    $batArgsSegment = ""
    foreach ($batArg in $BatArgs) {
        $batArgsSegment += " ""$batArg"""
    }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = "cmd.exe"
    $psi.Arguments = "/c ""`"$BatPath`"$batArgsSegment 2>&1"""
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
