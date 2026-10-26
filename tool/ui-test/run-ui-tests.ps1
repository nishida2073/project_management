param(
    [Parameter(Mandatory)][string]$ProjectRoot,
    [Parameter(Mandatory)][string]$ExeName,
    [Parameter(Mandatory)][string]$ScenariosDir,
    [string[]]$CopyDirs = @("bats"),
    [string]$WindowTitle = "",
    [string]$FixtureRoot = "",
    [string[]]$FixtureDirs = @(),
    [string[]]$EvidenceDirs = @("clients", "download", "generated", "logs"),
    [string]$Filter = "",
    [switch]$KeepTemp,
    [switch]$StopOnFail
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

$scenarioFiles = @(Get-ChildItem -LiteralPath $ScenariosDir -Filter *.json | Sort-Object { $p = ($_.BaseName -split '-')[0]; if ($p -match '^\d+\.\d+$') { [version]$p } else { [version]'0.0' } }, Name)
if ($Filter) { $scenarioFiles = @($scenarioFiles | Where-Object { $_.BaseName -like "$Filter*" }) }
if ($scenarioFiles.Count -eq 0) { throw "実行するシナリオがありません（指定: $Filter）" }

$workRoot = Join-Path $env:TEMP ("uitest-" + (Get-Date -Format "yyyyMMddHHmmss"))
$evidenceDir = Join-Path (Join-Path $ProjectRoot "doc\03_結合テスト\エビデンス") (Get-Date -Format "yyyyMMdd-HHmmss")
New-Item -ItemType Directory -Path $evidenceDir -Force | Out-Null
$results = @()
$resultFile = Join-Path $evidenceDir "実施結果.txt"

$partsFile = Join-Path (Split-Path -Parent $ScenariosDir) "部品座標.json"
$parts = @{}
if (Test-Path -LiteralPath $partsFile) {
    foreach ($item in (Get-Content -LiteralPath $partsFile -Raw -Encoding UTF8 | ConvertFrom-Json)) {
        $key = if ($item.PSObject.Properties.Name -contains "screen") { "$($item.screen)/$($item.name)" } else { $item.name }
        if ($parts.ContainsKey($key)) { throw "部品座標のキーが重複しています: $key" }
        $parts[$key] = $item
    }
}

foreach ($file in $scenarioFiles) {
    $scenario = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($step in $scenario.steps) {
        if ($step.PSObject.Properties.Name -contains "part") {
            if ($step.PSObject.Properties.Name -contains "x") { throw "part と x は同時に書けません: $($file.BaseName)" }
            $p = $parts[$step.part]
            if (-not $p) { throw "部品座標がありません: $($step.part) ($($file.BaseName))" }
            $step | Add-Member -NotePropertyName x -NotePropertyValue ([int]$p.X)
            $step | Add-Member -NotePropertyName y -NotePropertyValue ([int]$p.Y)
        }
    }
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
        $shotDir = Join-Path (Join-Path $evidenceDir $file.BaseName) "screenshots"
        New-Item -ItemType Directory -Path $shotDir -Force | Out-Null
        $context = [pscustomobject]@{ ProcessId = $proc.Id; Window = $window; Root = $temp; ScenarioId = $file.BaseName; EvidenceDir = $shotDir }
        Invoke-UiSteps -Scenario $scenario -Context $context
        $results += [pscustomobject]@{ Name = $name; Result = "PASS"; Message = "" }
        Write-UiLog "シナリオ結果: PASS"
    } catch {
        $results += [pscustomobject]@{ Name = $name; Result = "FAIL"; Message = $_.Exception.Message }
        Write-UiLog "シナリオ結果: FAIL"
    } finally {
        if ($proc) { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue }
        $outputDir = Join-Path $evidenceDir $file.BaseName
        foreach ($out in $EvidenceDirs) {
            $source = Join-Path $temp $out
            if (Test-Path -LiteralPath $source) {
                New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
                Copy-Item -LiteralPath $source -Destination (Join-Path $outputDir $out) -Recurse -Force
            }
        }
    }
    $last = $results[-1]
    $line = "$($last.Result)  $($last.Name)"
    if ($last.Message) { $line += "  -- $($last.Message)" }
    Add-Content -LiteralPath $resultFile -Value $line -Encoding UTF8
    if ($StopOnFail -and $last.Result -eq "FAIL") {
        Write-UiLog "失敗があったため、ここで中断します。"
        break
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
$resultFile = Join-Path $evidenceDir "実施結果.txt"
$resultLines = @("合計 $($results.Count) 件、失敗 $failed 件") + @($results | ForEach-Object { if ($_.Message) { "$($_.Result)  $($_.Name)  -- $($_.Message)" } else { "$($_.Result)  $($_.Name)" } })
Set-Content -LiteralPath $resultFile -Value $resultLines -Encoding UTF8
Write-UiLog "結果ファイル: $resultFile"
if ($KeepTemp) { Write-UiLog "作業フォルダ: $workRoot" }
if ($failed -gt 0) { exit 1 }
