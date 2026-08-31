param(
    [string]$SourceRootDir,
    [string]$TargetGroupName,
    [string]$TargetDate,
    [string]$SourseDataDefsPath,
    [string]$CollectRootDir,
    [string]$CollectDataNotFoundMessage,
    [string]$LogNamePrefix
)
$libraryDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$libraryDir = Join-Path $libraryDir "library"
Get-ChildItem -Path $libraryDir -Filter *.ps1 -Recurse | ForEach-Object {
    . $_.FullName
}

$logFilePath = New-WorkerLogPath -LogRoot $env:LOG_DIR -Prefix "$(if ($LogNamePrefix) { $LogNamePrefix } else { 'collect-app-data' })-$TargetGroupName-$TargetDate"

function Combine-ArrayHorizontal {
    param(
        [Parameter(Mandatory)]
        [array[]]$Arrays
    )
    Write-Message $MyInvocation.MyCommand.Name -VarName "functionName" -Type "Info" -ForegroundColor Magenta
    $PSBoundParameters.Keys | ForEach-Object { Write-Message $PSBoundParameters[$_] -VarName "$_" }
    
    # 最大行数
    $maxRows = ($Arrays | ForEach-Object {
        if ($_ -is [array] -and $_.Count -gt 0 -and $_[0] -is [array]) {
            $_.Count
        } else {
            1
        }
    } | Measure-Object -Maximum).Maximum
    $result = [System.Collections.Generic.List[object]]::new($maxRows)
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
        $result.Add($row)
    }
    return ,$result.ToArray()
}

function Read-SourseDataDefsFile {
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,
        [Parameter(Mandatory)]
        [string]$SourceRootDir,
        [Parameter(Mandatory)]
        [string]$TargetGroupName
    )
    Write-Message $MyInvocation.MyCommand.Name -VarName "functionName" -Type "Info" -ForegroundColor Magenta
    $PSBoundParameters.Keys | ForEach-Object { Write-Message $PSBoundParameters[$_] -VarName "$_" }

    # [ファイル識別子] セクションの下に、1行1列で「列番号[,別名[,型]]」を書く書式
    $lines = Get-Content -Path $FilePath -Encoding UTF8

    $sourseDataProps = @()
    $currentFileKey = $null
    $currentColumnDefs = @()

    foreach ($line in $lines) {
        $trimmed = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmed)) { continue }

        if ($trimmed -match '^\[(.+)\]$') {
            if ($currentFileKey) {
                $sourseDataProps += [PSCustomObject]@{
                    filePath   = Join-Path $SourceRootDir "$TargetGroupName-$currentFileKey.txt"
                    columnDefs = $currentColumnDefs
                }
            }
            $currentFileKey = $Matches[1]
            $currentColumnDefs = @()
            continue
        }

        $parts = $trimmed -split ','
        $currentColumnDefs += [PSCustomObject]@{
            Index = [int]$parts[0]
            Alias = if ($parts.Count -ge 2 -and -not [string]::IsNullOrWhiteSpace($parts[1])) { $parts[1] } else { $null }
            Type  = if ($parts.Count -ge 3 -and -not [string]::IsNullOrWhiteSpace($parts[2])) { $parts[2] } else { $null }
        }
    }
    if ($currentFileKey) {
        $sourseDataProps += [PSCustomObject]@{
            filePath   = Join-Path $SourceRootDir "$TargetGroupName-$currentFileKey.txt"
            columnDefs = $currentColumnDefs
        }
    }

    return $sourseDataProps
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
    Write-Message $MyInvocation.MyCommand.Name -VarName "functionName" -Type "Info" -ForegroundColor Magenta
    $PSBoundParameters.Keys | ForEach-Object { Write-Message $PSBoundParameters[$_] -VarName "$_" }

    $allHeaderDatas = @()
    $allBodyDatas   = @()

    foreach ($sourceDataProp in $SourseDataProps) {
        $sourceFilePath = $sourceDataProp.filePath
        $columnDefs = $sourceDataProp.columnDefs
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
        $bodyDatas = [System.Collections.Generic.List[object]]::new($range.Count)
        for ($r = 1; $r -lt $range.Count; $r++) {
            $rowData = @()
            foreach ($def in $columnDefs) {
                $val = $range[$r][([int]$def.Index-1)]
                if ([string]::IsNullOrEmpty($val)) {
                    $val = $CollectDataNotFoundMessage
                }
                $rowData += $val
            }
            $bodyDatas.Add($rowData)
        }
        $allBodyDatas += ,$bodyDatas.ToArray()
    }
    # Write-Message $allHeaderDatas -VarName "allHeaderDatas" -Type "Info" -ForegroundColor Green
    # Write-Message $allBodyDatas -VarName "allBodyDatas" -Type "Info" -ForegroundColor Green
    
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

& {
    New-Item -Path $CollectRootDir -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null

    $hasFiles = @(Get-ChildItem -Path (Join-Path $SourceRootDir "$TargetGroupName-*txt") -ErrorAction SilentlyContinue).Count -gt 0
    if (-not $hasFiles) {
        Write-Message "集計対象がありません。日付=$($TargetDate)" -VarName "message" -Type "Warn" -ForegroundColor Yellow
        return
    }

    $sourseDataProps = Read-SourseDataDefsFile -FilePath $SourseDataDefsPath -SourceRootDir $SourceRootDir -TargetGroupName $TargetGroupName

    Write-Message $sourseDataProps -VarName "sourseDataProps" -Type "Info" -ForegroundColor Green

    $collectFileName = "$($TargetGroupName)-$($TargetDate).txt"

    Export-Datas -SourseDataProps $sourseDataProps -CollectDirPath $CollectRootDir -CollectFileName $collectFileName -CollectDataNotFoundMessage $CollectDataNotFoundMessage
} *>&1 | Tee-Object -FilePath $logFilePath
ConvertTo-Utf8LogFile -Path $logFilePath
