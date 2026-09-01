param(
    [string]$SourceRootDir,
    [string]$TargetGroupName,
    [string]$TargetDate,
    [string]$CollectDataDefsPath,
    [string]$CollectRootDir,
    [string]$SourceTypeFileNameMap,
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
        [string]$TargetGroupName,
        [Parameter(Mandatory)]
        [hashtable]$FileKeyMap
    )
    Write-Message $MyInvocation.MyCommand.Name -VarName "functionName" -Type "Info" -ForegroundColor Magenta
    $PSBoundParameters.Keys | ForEach-Object { Write-Message $PSBoundParameters[$_] -VarName "$_" }

    # [ファイル識別子] セクションの下に、1行1列で「元の列名[,新しい列名]」を書く書式。
    # ファイル識別子はcommon-env.bat側の*SourceType変数名（DailyReportSourceType等）をそのまま書き、
    # 実際の出力ファイル名（create-app-data.ps1がその変数の値から組み立てる"<グループ名>-業務日誌.txt"等）
    # へは$FileKeyMap経由で変換する。値をハードコードすると、common-env.bat側の値を変えたときに
    # ファイル名がずれて気づかずに集計漏れる
    $lines = Get-Content -Path $FilePath -Encoding UTF8

    $sourseDataProps = @()
    $currentFileKey = $null
    $currentColumnDefs = @()

    foreach ($line in $lines) {
        $trimmed = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmed)) { continue }

        if ($trimmed -match '^\[(.+)\]$') {
            if ($currentFileKey) {
                $sourceType = if ($FileKeyMap.ContainsKey($currentFileKey)) { $FileKeyMap[$currentFileKey] } else { $currentFileKey }
                $sourseDataProps += [PSCustomObject]@{
                    filePath   = Join-Path $SourceRootDir "$TargetGroupName-$sourceType.txt"
                    columnDefs = $currentColumnDefs
                }
            }
            $currentFileKey = $Matches[1]
            $currentColumnDefs = @()
            continue
        }

        $parts = $trimmed -split ','
        $currentColumnDefs += [PSCustomObject]@{
            OrgName = $parts[0]
            NewName = if ($parts.Count -ge 2 -and -not [string]::IsNullOrWhiteSpace($parts[1])) { $parts[1] } else { $null }
        }
    }
    if ($currentFileKey) {
        $sourceType = if ($FileKeyMap.ContainsKey($currentFileKey)) { $FileKeyMap[$currentFileKey] } else { $currentFileKey }
        $sourseDataProps += [PSCustomObject]@{
            filePath   = Join-Path $SourceRootDir "$TargetGroupName-$sourceType.txt"
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
        [string]$CollectFileName
    )
    Write-Message $MyInvocation.MyCommand.Name -VarName "functionName" -Type "Info" -ForegroundColor Magenta
    $PSBoundParameters.Keys | ForEach-Object { Write-Message $PSBoundParameters[$_] -VarName "$_" }

    $allHeaderDatas = @()
    $allBodyDatas   = @()

    foreach ($sourceDataProp in $SourseDataProps) {
        $sourceFilePath = $sourceDataProp.filePath
        $columnDefs = $sourceDataProp.columnDefs
        $range = Read-FileToArray $sourceFilePath
        $headerRow = $range[0]

        # 元の列名から列位置を引くためのインデックス。同じ列を複数回引くので事前に1回だけ計算する。
        # 見つからない列はアプリ側のフィールド変更等でずれている可能性があるため、処理は止めずに
        # 警告を出したうえで該当列を空欄扱いにする（-1のままにしておき、後段の値取得側で判定する）
        $columnIndexes = @($columnDefs | ForEach-Object {
            $index = [array]::IndexOf($headerRow, $_.OrgName)
            if ($index -lt 0) {
                Write-Message "列が見つかりません: $($_.OrgName) (ファイル: $sourceFilePath)" -VarName "message" -Type "Warn" -ForegroundColor Yellow
            }
            $index
        })

        # ヘッダー
        $headerDatas = @()
        foreach ($def in $columnDefs) {
            $headerName = if (-not [string]::IsNullOrWhiteSpace($def.NewName)) {
                $def.NewName
            } else {
                $def.OrgName
            }
            $headerDatas += ,$headerName
        }
        $allHeaderDatas += ,$headerDatas
        # ボディ
        $bodyDatas = [System.Collections.Generic.List[object]]::new($range.Count)
        for ($r = 1; $r -lt $range.Count; $r++) {
            $rowData = @()
            foreach ($columnIndex in $columnIndexes) {
                $val = if ($columnIndex -lt 0) { $null } else { $range[$r][$columnIndex] }
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

    $fileKeyMap = @{}
    foreach ($pair in ($SourceTypeFileNameMap -split ',' | Where-Object { $_ })) {
        $kv = $pair -split '=', 2
        if ($kv.Count -eq 2) { $fileKeyMap[$kv[0]] = $kv[1] }
    }
    $sourseDataProps = Read-SourseDataDefsFile -FilePath $CollectDataDefsPath -SourceRootDir $SourceRootDir -TargetGroupName $TargetGroupName -FileKeyMap $fileKeyMap

    Write-Message $sourseDataProps -VarName "sourseDataProps" -Type "Info" -ForegroundColor Green

    $collectFileName = "$($TargetGroupName)-$($TargetDate).txt"

    Export-Datas -SourseDataProps $sourseDataProps -CollectDirPath $CollectRootDir -CollectFileName $collectFileName
} *>&1 | Tee-Object -FilePath $logFilePath
ConvertTo-Utf8LogFile -Path $logFilePath
