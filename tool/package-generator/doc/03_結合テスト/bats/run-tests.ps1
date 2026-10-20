param([switch]$KeepTemp)

$projectRoot = Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
$toolRoot = Split-Path $projectRoot -Parent

& (Join-Path $toolRoot "ui-test\run-ui-tests.ps1") `
    -ProjectRoot $projectRoot `
    -ExeName "コース別パッケージ生成ツール.exe" `
    -ScenariosDir (Join-Path $projectRoot "doc\03_結合テスト\シナリオ") `
    -CopyDirs @("bats") `
    -FixtureRoot (Join-Path $PSScriptRoot "..\test-data") `
    -FixtureDirs @("clients", "download") `
    -WindowTitle "コース別パッケージ生成ツール" `
    -KeepTemp:$KeepTemp
