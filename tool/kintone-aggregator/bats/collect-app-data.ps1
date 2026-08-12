param(
    [string]$SourceRootDir,
    [string]$TargetGroupName,
    [string]$TargetDate,
    [string]$SourseDataDefs,
    [string]$CollectRootDir,
    [string]$CollectDataNotFoundMessage
)
$libraryDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$libraryDir = Join-Path $libraryDir "library"
Get-ChildItem -Path $libraryDir -Filter *.psm1 -Recurse | ForEach-Object {
    Import-Module $_.FullName -ErrorAction Stop -DisableNameChecking
}

function Combine-ArrayHorizontal {
    param(
        [Parameter(Mandatory)]
        [array[]]$Arrays
    )
    Write-Message $MyInvocation.MyCommand.Name -VarName "functionName" -Type "Info" -ForegroundColor Green
    $PSBoundParameters.Keys | ForEach-Object { Write-Message $PSBoundParameters[$_] -VarName "$_" }
    
    $result = @()
    # 最大行数
    $maxRows = ($Arrays | ForEach-Object {
        if ($_ -is [array] -and $_.Count -gt 0 -and $_[0] -is [array]) {
            $_.Count
        } else {
            1
        }
    } | Measure-Object -Maximum).Maximum
    for ($r = 0; $r -lt $maxRows; $r++) {
        $row = @()
        foreach ($arr in $Arrays) {
            if ($arr -isnot [array]) {
                $row += $arr
                continue
            }
            # 2次元
            if ($arr.Count -gt 0 -and $arr[0] -is [array]) {
                if ($r -lt $arr.Count) {
                    $row += $arr[$r]
                }
            }
            # 1次元
            else {
                if ($r -eq 0) {
                    $row += $arr
                }
            }
        }
        $result += ,$row
    }
    return ,$result
}

function Export-Datas {
    param(
        [string]$SourceRootDir,
        [string]$TargetGroupName,
        [string]$TargetDate,
        [array]$SourseDataProps,
        [string]$CollectDirPath,
        [string]$CollectFileName,
        [string]$CollectDataNotFoundMessage
    )
    Write-Message $MyInvocation.MyCommand.Name -VarName "functionName" -Type "Info" -ForegroundColor Green
    $PSBoundParameters.Keys | ForEach-Object { Write-Message $PSBoundParameters[$_] -VarName "$_" }
    
    $allHeaderDatas = @()
    $allBodyDatas   = @()
    
    foreach ($sourceDataProp in $SourseDataProps) {
        $sourceFilePath = $sourceDataProp.filePath
        $sourceDataColumns   = $sourceDataProp.dataColumns
        $columnDefs = Get-ColumnDefs $sourceDataColumns
        $range = Read-FileToArray $sourceFilePath
        
        # ヘッダー
        $headerDatas = @()
        foreach ($def in $columnDefs) {
            $headerName = if (-not [string]::IsNullOrWhiteSpace($def.Alias)) {
                $def.Alias
            } else {
                $range[0][([int]$def.Index-1)]
            }
            $headerDatas += ,$headerName
        }
        $allHeaderDatas += ,$headerDatas
        # ボディ
        $bodyDatas = @()
        for ($r = 1; $r -lt $range.Count; $r++) {
            $rowData = @()
            foreach ($def in $columnDefs) {
                $val = $range[$r][([int]$def.Index-1)]
                if ([string]::IsNullOrEmpty($val)) {
                    $val = $CollectDataNotFoundMessage
                }
                $rowData += $val
            }
            $bodyDatas += ,$rowData
        }
        $allBodyDatas += ,$bodyDatas
    }
    Write-Message $allHeaderDatas -VarName "allHeaderDatas" -Type "Info" -ForegroundColor Green
    Write-Message $allBodyDatas -VarName "allBodyDatas" -Type "Info" -ForegroundColor Green
    
    # フラット化
    $allHeaderDatas = Combine-ArrayHorizontal $allHeaderDatas
    $allBodyDatas = Combine-ArrayHorizontal $allBodyDatas
    
    # ファイルに出力
    $allDatas = @()
    $allDatas += $allHeaderDatas
    $allDatas += $allBodyDatas
    
    # 集計用ファイルを作成
    $collectFilePath = Join-Path -Path $CollectDirPath -ChildPath $CollectFileName
    Export-ArrayToFile $allDatas $collectFilePath
}

New-Item -Path $CollectRootDir -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null

$hasFiles = @(Get-ChildItem -Path (Join-Path $SourceRootDir "$TargetGroupName-*txt") -ErrorAction SilentlyContinue).Count -gt 0
if (-not $hasFiles) {
    Write-Message "集計対象がありません。日付=$($TargetDate)" -VarName "message" -Type "Warn" -ForegroundColor Yellow
    return
}

$sourseDataDefsParts = $SourseDataDefs -split ";"

$sourseDataProps = @()
foreach ($sourseDataDefsPart in $sourseDataDefsParts) {
    if ([string]::IsNullOrWhiteSpace($sourseDataDefsPart)) { continue }
    $parts = $sourseDataDefsPart -split '@@'
    $sourseDataProps += [PSCustomObject]@{
        filePath    =  Join-Path $SourceRootDir "$TargetGroupName-$($parts[0]).txt"
        dataColumns  = $parts[1] -split '[,\s]+'
    }
}

Write-Message $sourseDataProps -VarName "sourseDataProps" -Type "Info" -ForegroundColor Green

$collectFileName = "$($TargetGroupName)-$($TargetDate).txt"

Export-Datas -SourseDataProps $sourseDataProps -CollectDirPath $CollectRootDir -CollectFileName $collectFileName -CollectDataNotFoundMessage $CollectDataNotFoundMessage
