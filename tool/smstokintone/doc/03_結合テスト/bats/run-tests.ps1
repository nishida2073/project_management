param([string]$Filter = "", [string]$Device = "", [string]$Env = "", [switch]$Setup, [string]$Sms = "")

$maestro = Join-Path $env:USERPROFILE ".maestro\bin\maestro.bat"
if (-not (Test-Path -LiteralPath $maestro)) {
    Write-Host "Maestro が見つかりません: $maestro"
    exit 1
}

$flowDir = Join-Path $PSScriptRoot "..\maestro"
$flows = @(Get-ChildItem -LiteralPath $flowDir -Filter "*.yaml" -File | Where-Object { $_.BaseName -like "*$Filter*" } | Sort-Object Name)
if ($flows.Count -eq 0) {
    Write-Host "対象のフローがありません: $Filter"
    exit 1
}

$evidenceRoot = Join-Path $PSScriptRoot "..\エビデンス"
$runDir = Join-Path $evidenceRoot (Get-Date -Format "yyyyMMdd-HHmmss")
New-Item -ItemType Directory -Force -Path $runDir | Out-Null

$script:results = @()
$deviceLabel = "既定"
if ($Device) { $deviceLabel = $Device }
$summary = Join-Path $runDir "結果.txt"

$header = @("実行日時: " + (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), "対象: $Filter", "実機: $deviceLabel", "")
[IO.File]::WriteAllLines($summary, $header, (New-Object System.Text.UTF8Encoding($true)))

function Save-Summary($item) {
    $line = "$($item.Result)  $($item.Flow)  （エビデンス: $($item.Evidence)）"
    [IO.File]::AppendAllText($summary, $line + "`r`n", (New-Object System.Text.UTF8Encoding($false)))
}

function Invoke-Flows([object[]]$flowFiles) {
    $out = @()
    foreach ($flow in $flowFiles) {
        Write-Host "=== $($flow.Name)"
        $flowOut = Join-Path $runDir $flow.BaseName
        $maestroArgs = @()
        if ($Device) { $maestroArgs += @("--udid", $Device) }
        $envArgs = @()
        $varsFile = Join-Path $PSScriptRoot "..\test-data\vars\$($flow.BaseName).json"
        if (Test-Path -LiteralPath $varsFile) {
            $vars = Get-Content -LiteralPath $varsFile -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($p in $vars.PSObject.Properties) { $envArgs += @("-e", "$($p.Name)=$($p.Value)") }
        }
        foreach ($pair in ($Env -split ";")) { if ($pair) { $envArgs += @("-e", $pair) } }
        $maestroArgs += @("test") + $envArgs + @("--debug-output", $runDir, "--flatten-debug-output", "--format", "HTML", "--output", (Join-Path $flowOut "report.html"), $flow.FullName)
        if ($Device -like "emulator-*") { & (Join-Path $PSScriptRoot "..\test-data\sms\clear-inbox.ps1") -Device $Device }
        $smsJson = if ($Sms) { $Sms } else { Join-Path $PSScriptRoot ("..\test-data\sms\" + $flow.BaseName + ".json") }
        $smsJob = $null
        if ($Device -like "emulator-*" -and (Test-Path -LiteralPath $smsJson)) { $smsJob = Start-Job -ArgumentList (Join-Path $PSScriptRoot "..\test-data\sms\load-inbox.ps1"), $Device, $smsJson -ScriptBlock { param($p, $d, $j) & $p -Device $d -Json $j -DelaySeconds 90 } }
        & $maestro @maestroArgs | Out-Host
        if ($smsJob) { Wait-Job $smsJob | Out-Null; Receive-Job $smsJob | Out-Host; Remove-Job $smsJob }
        $code = $LASTEXITCODE
        if ($code -eq 0) { $label = "成功" } else { $label = "失敗" }
        $item = [pscustomobject]@{ Flow = $flow.Name; ExitCode = $code; Result = $label; Evidence = $flowOut }
        $out += $item
        $script:results += $item
        Save-Summary $item
    }
    return $out
}

$setupFailed = $false
if ($Setup) {
    $setupFlows = @(Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot "..\maestro\setup") -Filter "*.yaml" -File | Sort-Object Name)
    if ($setupFlows.Count -eq 0) {
        Write-Host "セットアップのフローがありません"
        exit 1
    }
    $setupResults = Invoke-Flows $setupFlows
    if ($setupResults | Where-Object { $_.ExitCode -ne 0 }) {
        $setupFailed = $true
        Write-Host "セットアップに失敗したため、テストを実行しません"
    }
}
if (-not $setupFailed) {
    Invoke-Flows $flows | Out-Null
}

$results = $script:results

Write-Host ""
Write-Host "結果: $summary"
$results | Format-Table Flow, Result -AutoSize | Out-String | Write-Host

if ($results | Where-Object { $_.ExitCode -ne 0 }) { exit 1 }
exit 0