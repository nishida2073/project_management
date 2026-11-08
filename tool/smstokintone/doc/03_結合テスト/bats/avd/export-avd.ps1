param(
    [string]$Avd = "Pixel_6",
    [string]$Device = "emulator-5554",
    [string]$OutFile
)
$avdHome = Join-Path $env:USERPROFILE ".android\avd"
$avdDir = Join-Path $avdHome "$Avd.avd"
$avdIni = Join-Path $avdHome "$Avd.ini"
if (!(Test-Path -LiteralPath $avdDir) -or !(Test-Path -LiteralPath $avdIni)) {
    Write-Host "AVD が見つかりません: $Avd"
    exit 1
}
if (!$OutFile) {
    $OutFile = Join-Path $PSScriptRoot "$Avd.zip"
}
New-Item -ItemType Directory -Path (Split-Path $OutFile -Parent) -Force | Out-Null

& adb -s $Device emu kill 2>$null | Out-Null
Start-Sleep -Seconds 5
Get-Process -Name qemu-system-x86_64,emulator -ErrorAction SilentlyContinue | Stop-Process -Force
Start-Sleep -Seconds 3

$configIni = Join-Path $avdDir "config.ini"
if (!(Test-Path -LiteralPath $configIni)) {
    Write-Host "config.ini が見つかりません: $configIni"
    exit 1
}
$staging = Join-Path $env:TEMP "avd-export-$Avd"
Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue
New-Item -ItemType Directory -Path (Join-Path $staging "$Avd.avd") -Force | Out-Null
Copy-Item -LiteralPath $configIni -Destination (Join-Path $staging "$Avd.avd\config.ini")
Copy-Item -LiteralPath $avdIni -Destination $staging
Remove-Item -LiteralPath $OutFile -Force -ErrorAction SilentlyContinue
try {
    Compress-Archive -Path (Join-Path $staging "*") -DestinationPath $OutFile -Force -ErrorAction Stop
} catch {
    Write-Host "エクスポートに失敗しました: $($_.Exception.Message)"
    exit 1
} finally {
    Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction SilentlyContinue
}
Write-Host "エクスポートしました（設定ファイルのみ）: $OutFile"
exit 0
