param(
    [string]$ClientDataRootDir,
    [int]$TargetYear,
    [int]$ComparePeriod,
    [string]$TargetGroupNameFilter = ""
)

$files = Get-ChildItem -Path $ClientDataRootDir -Filter *.xlsx

if ($TargetGroupNameFilter -and $TargetGroupNameFilter -ne "*") {
    $files = $files | Where-Object { $_.BaseName -like "$TargetGroupNameFilter*" }
}

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
