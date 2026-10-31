param([string]$Filter = "", [string]$Device = "")

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

$results = @()
foreach ($flow in $flows) {
    Write-Host "=== $($flow.Name)"
    $flowOut = Join-Path $runDir $flow.BaseName
    New-Item -ItemType Directory -Force -Path $flowOut | Out-Null
    $maestroArgs = @()
    if ($Device) { $maestroArgs += @("--udid", $Device) }
    $maestroArgs += @("test", "--debug-output", $runDir, "--flatten-debug-output", "--format", "HTML", "--output", (Join-Path $flowOut "report.html"), $flow.FullName)
    & $maestro @maestroArgs
    $code = $LASTEXITCODE
    if ($code -eq 0) { $label = "成功" } else { $label = "失敗" }
    $results += [pscustomobject]@{ Flow = $flow.Name; ExitCode = $code; Result = $label; Evidence = $flowOut }
}

$deviceLabel = "既定"
if ($Device) { $deviceLabel = $Device }
$lines = @("実行日時: " + (Get-Date -Format "yyyy-MM-dd HH:mm:ss"), "対象: $Filter", "実機: $deviceLabel", "")
foreach ($r in $results) { $lines += "$($r.Result)  $($r.Flow)  （エビデンス: $($r.Evidence)）" }
$summary = Join-Path $runDir "結果.txt"
[IO.File]::WriteAllLines($summary, $lines, (New-Object System.Text.UTF8Encoding($true)))

Write-Host ""
Write-Host "結果: $summary"
$results | Format-Table Flow, Result -AutoSize | Out-String | Write-Host

if ($results | Where-Object { $_.ExitCode -ne 0 }) { exit 1 }
exit 0