param(
    [string]$ZipFile,
    [string]$Avd = "Pixel_6",
    [switch]$Force
)
if (!$ZipFile) {
    $ZipFile = Join-Path $PSScriptRoot "$Avd.zip"
}
if (!(Test-Path -LiteralPath $ZipFile)) {
    Write-Host "ZIP が見つかりません: $ZipFile"
    exit 1
}
$avdHome = Join-Path $env:USERPROFILE ".android\avd"
$avdDir = Join-Path $avdHome "$Avd.avd"
$avdIni = Join-Path $avdHome "$Avd.ini"
if ((Test-Path -LiteralPath $avdDir) -or (Test-Path -LiteralPath $avdIni)) {
    if (!$Force) {
        Write-Host "同じ名前の AVD が既にあります: $Avd（上書きするには -Force を付けてください）"
        exit 1
    }
    Remove-Item -LiteralPath $avdDir -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $avdIni -Force -ErrorAction SilentlyContinue
}
New-Item -ItemType Directory -Path $avdHome -Force | Out-Null
Expand-Archive -LiteralPath $ZipFile -DestinationPath $avdHome -Force

$lines = Get-Content -LiteralPath $avdIni
$lines = $lines | ForEach-Object { if ($_ -match '^path=') { "path=$avdDir" } else { $_ } }
Set-Content -LiteralPath $avdIni -Value $lines -Encoding ASCII

Write-Host "インポートしました: $Avd"
$sys = $lines | Where-Object { $_ -match '^image\.sysdir\.1=' }
if ($sys) { Write-Host "必要なシステムイメージ: $($sys -replace '^image\.sysdir\.1=', '')" }
exit 0
