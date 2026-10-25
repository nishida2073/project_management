param([string]$Filter = "", [switch]$KeepTemp)

$projectRoot = Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
$toolRoot = Split-Path $projectRoot -Parent

& (Join-Path $toolRoot "ui-test\run-ui-tests.ps1") `
    -ProjectRoot $projectRoot `
    -ExeName "kintoneデータ集計ツール.exe" `
    -ScenariosDir (Join-Path $projectRoot "doc\03_結合テスト\シナリオ") `
    -CopyDirs @("bats") `
    -FixtureRoot (Join-Path $PSScriptRoot "..\test-data") `
    -FixtureDirs @("clients", "template") `
    -EvidenceDirs @("clients", "logs", "output") `
    -WindowTitle "kintoneデータ集計ツール" `
    -Filter $Filter `
    -KeepTemp:$KeepTemp
