param(
    [Parameter(Mandatory)][string]$ProjectRoot,
    [Parameter(Mandatory)][string]$ExeName,
    [Parameter(Mandatory)][string]$ScenariosDir,
    [string[]]$CopyDirs = @("bats"),
    [string]$WindowTitle = "",
    [string]$FixtureRoot = "",
    [string[]]$FixtureDirs = @(),
    [string]$Filter = "",
    [switch]$KeepTemp
)

. "$PSScriptRoot\lib\ui-automation.ps1"
. "$PSScriptRoot\lib\mouse.ps1"
. "$PSScriptRoot\lib\log.ps1"
. "$PSScriptRoot\lib\scenario.ps1"

Write-UiLog "テスト開始: $ExeName"

$exeSource = Join-Path $ProjectRoot $ExeName
if (!(Test-Path -LiteralPath $exeSource)) { throw "実行ファイルがありません: $exeSource" }

$exeTime = (Get-Item -LiteralPath $exeSource).LastWriteTime
$newerSource = Get-ChildItem -LiteralPath (Join-Path $ProjectRoot "bats") -Recurse -Filter *.ps1 | Where-Object { $_.LastWriteTime -gt $exeTime }
if ($newerSource) {
    Write-Warning "実行ファイルより新しいスクリプトがあります。exe を作り直してから実行してください: $($newerSource[0].FullName)"
}

$scenarioFiles = @(Get-ChildItem -LiteralPath $ScenariosDir -Filter *.json | Sort-Object Name)
if ($Filter) { $scenarioFiles = @($scenarioFiles | Where-Object { $_.BaseName -like "$Filter*" }) }
if ($scenarioFiles.Count -eq 0) { throw "実行するシナリオがありません（指定: $Filter）" }

$workRoot = Join-Path $env:TEMP ("uitest-" + (Get-Date -Format "yyyyMMddHHmmss"))
$evidenceDir = Join-Path (Join-Path $ProjectRoot "doc\03_結合テスト\エビデンス") (Get-Date -Format "yyyyMMdd-HHmmss")
New-Item -ItemType Directory -Path $evidenceDir -Force | Out-Null
$results = @()

foreach ($file in $scenarioFiles) {
    $scenario = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
    $name = if ($scenario.name) { $scenario.name } else { $file.BaseName }
    $temp = Join-Path $workRoot $file.BaseName
    $proc = $null
    Write-UiLog "シナリオ開始: $name"
    $script:ShotNo = 0
    try {
        New-Item -ItemType Directory -Path $temp -Force | Out-Null
        $copyList = @($CopyDirs | ForEach-Object { [pscustomobject]@{ Root = $ProjectRoot; Dir = $_ } }) + @($FixtureDirs | ForEach-Object { [pscustomobject]@{ Root = $FixtureRoot; Dir = $_ } })
        foreach ($item in $copyList) {
            $dir = $item.Dir
            $source = Join-Path $item.Root $dir
            if (!(Test-Path -LiteralPath $source)) {
                Write-Warning "コピー元がありません（スキップ）: $dir"
                continue
            }
            $dest = Join-Path $temp $dir
            New-Item -ItemType Directory -Path (Split-Path $dest -Parent) -Force | Out-Null
            Copy-Item -LiteralPath $source -Destination $dest -Recurse
        }
        $exeTarget = Join-Path $temp $ExeName
        Copy-Item -LiteralPath $exeSource -Destination $exeTarget

        Invoke-UiSetup -Scenario $scenario -Root $temp
        $proc = Start-Process -FilePath $exeTarget -PassThru
        $window = Get-UiWindow -ProcessId $proc.Id -Title $WindowTitle -TimeoutSec 30
        $context = [pscustomobject]@{ ProcessId = $proc.Id; Window = $window; Root = $temp; ScenarioId = $file.BaseName; EvidenceDir = $evidenceDir }
        Invoke-UiSteps -Scenario $scenario -Context $context
        $results += [pscustomobject]@{ Name = $name; Result = "PASS"; Message = "" }
        Write-UiLog "シナリオ結果: PASS"
    } catch {
        $results += [pscustomobject]@{ Name = $name; Result = "FAIL"; Message = $_.Exception.Message }
        Write-UiLog "シナリオ結果: FAIL"
    } finally {
        if ($proc) { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue }
        $outputDir = Join-Path $evidenceDir $file.BaseName
        foreach ($out in @("clients", "download", "generated", "logs")) {
            $source = Join-Path $temp $out
            if (Test-Path -LiteralPath $source) {
                New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
                Copy-Item -LiteralPath $source -Destination (Join-Path $outputDir $out) -Recurse -Force
            }
        }
    }
}
if (!$KeepTemp) { Remove-Item -LiteralPath $workRoot -Recurse -Force -ErrorAction SilentlyContinue }

$results | ForEach-Object {
    $line = "$($_.Result)  $($_.Name)"
    if ($_.Message) { $line += "  -- $($_.Message)" }
    Write-UiLog $line
}
$failed = @($results | Where-Object { $_.Result -eq "FAIL" }).Count
Write-UiLog "合計 $($results.Count) 件、失敗 $failed 件"
$resultFile = Join-Path $evidenceDir "結果.txt"
$resultLines = @("合計 $($results.Count) 件、失敗 $failed 件") + @($results | ForEach-Object { if ($_.Message) { "$($_.Result)  $($_.Name)  -- $($_.Message)" } else { "$($_.Result)  $($_.Name)" } })
Set-Content -LiteralPath $resultFile -Value $resultLines -Encoding UTF8
Write-UiLog "結果ファイル: $resultFile"
if ($KeepTemp) { Write-UiLog "作業フォルダ: $workRoot" }
if ($failed -gt 0) { exit 1 }
