param(
    [string]$MasterDataRootDir,
    [int]$TargetYear,
    [int]$ComparePeriod
)

$files = Get-ChildItem -Path $MasterDataRootDir -Filter *.xlsx

$withYear = @()
$withoutYear = @()
foreach ($file in $files) {
    if ($file.BaseName -match '^(.+)-(\d{4})$') {
        $withYear += [pscustomobject]@{
            BaseName = $matches[1]
            Year     = [int]$matches[2]
            FullName = $file.FullName
        }
    } else {
        $withoutYear += $file.FullName
    }
}

# ベース名ごとに、TargetYear-ComparePeriod ～ TargetYear の範囲内で最も新しい年度のファイルを選ぶ
$selectedWithYear = $withYear | Group-Object BaseName | ForEach-Object {
    $candidates = $_.Group | Where-Object { $_.Year -ge ($TargetYear - $ComparePeriod) -and $_.Year -le $TargetYear }
    if ($candidates) {
        ($candidates | Sort-Object Year -Descending | Select-Object -First 1).FullName
    }
}

@($selectedWithYear) + @($withoutYear) | Where-Object { $_ }
