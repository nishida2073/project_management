$scriptDir = Split-Path $MyInvocation.MyCommand.Path
$basePath = Split-Path $scriptDir -Parent

if (!(Get-Module -ListAvailable ps2exe)) {
    Write-Host "ps2exeをインストールします"
    Install-Module ps2exe -Scope CurrentUser -Force -AllowClobber
}

$inputFile = Join-Path $scriptDir "gui.ps1"
$outputFile = Join-Path $basePath "個社別ZIP生成ツール.exe"

Invoke-PS2EXE -inputFile $inputFile -outputFile $outputFile -STA -noConsole -title "個社別ZIP生成ツール" -product "個社別ZIP生成ツール" -version "1.0.0.0"

if (Test-Path $outputFile) {
    Write-Host ""
    Write-Host "$outputFile を作成しました"
} else {
    Write-Host "ビルドに失敗しました"
    exit 1
}