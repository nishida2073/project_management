param(
    [string]$ClientDataRootDir,
    [int]$TargetYear,
    [int]$ComparePeriod
)

# どの年度のマスタファイルを実際に読むか（年度ごとの存在確認・フォールバック含む）は
# collect-year-comparison-result.ps1自身がTargetYear/ComparePeriodを使って解決するため、
# ここでは「年度を除いたベース名」を重複無く列挙するだけでよい。
# ただし、TargetYear-ComparePeriod ～ TargetYear の範囲に1件もファイルが無いベース名は、
# 対象外（今は動いていない過去のプログラム扱い）として除外する。
$files = Get-ChildItem -Path $ClientDataRootDir -Filter *.xlsx

$withYear = @()
$withoutYear = @()
foreach ($file in $files) {
    if ($file.BaseName -match '^(.+)-(\d{4})$') {
        $withYear += [pscustomobject]@{
            BaseName = $matches[1]
            Year     = [int]$matches[2]
        }
    } else {
        $withoutYear += $file.BaseName
    }
}

$selectedBaseNames = $withYear | Group-Object BaseName | ForEach-Object {
    $hasCandidate = $_.Group | Where-Object { $_.Year -ge ($TargetYear - $ComparePeriod) -and $_.Year -le $TargetYear }
    if ($hasCandidate) { $_.Name }
}

@($selectedBaseNames) + @($withoutYear) | Where-Object { $_ } | Select-Object -Unique
