# =========================================
# 集計結果・マスタデータの整形
# =========================================
# 各ワーカースクリプトが使う、受講生マスタ/テスト結果集計データを
# シート書き込み用の形式に組み立てる処理。

function Create-MasterDatas {
    param(
        [Parameter(Mandatory=$true)]
        [string]$DataFilePath,
        [Parameter(Mandatory=$true)]
        [int]$SheetIndex,
        [Parameter(Mandatory=$true)]
        [hashtable]$HeaderMap
    )
    Write-Message $MyInvocation.MyCommand.Name -VarName "functionName" -Type "Info" -ForegroundColor Magenta
    $PSBoundParameters.Keys | ForEach-Object { Write-Message $PSBoundParameters[$_] -VarName "$_" }

    $dataLines = Convert-ExcelToCsvString -ExcelFilePath $DataFilePath -SheetIndex $SheetIndex -Delimiter ","

    $bodies = @()
    $headers = $dataLines[0] -split ',' | ForEach-Object { $_.Trim() }
    $bodyLines = $dataLines | Select-Object -Skip 1
    foreach ($line in $bodyLines) {
        $parts = $line -split ',' | ForEach-Object { $_.Trim() }
        $body = [PSCustomObject]@{}
        for ($i = 0; $i -lt $headers.Count; $i++) {
            $header = $headers[$i]
            $value  = $parts[$i]
            $body | Add-Member -NotePropertyName $header -NotePropertyValue $value
            if ($HeaderMap.ContainsKey($header)) {
                $internalName = $HeaderMap[$header]
                $body | Add-Member -NotePropertyName $internalName -NotePropertyValue $value -Force
            }
        }
        $bodies += $body
    }
    return $bodies
}


function Get-GroupedResults {
    param(
        [array]$UserDatas,
        [array]$ValidResultDatas,
        [array]$GroupValues,
        [string]$GroupKey
    )
    if (-not $GroupValues) {
        $GroupValues = @($null)
    }
    foreach ($groupValue in $GroupValues) {
        $groupUsers = if ($GroupKey) {
            @($UserDatas | Where-Object { $_.$GroupKey -eq $groupValue })
        } else {
            $UserDatas
        }
        $groupResults = @(
            $ValidResultDatas |
            Where-Object userCode -in $groupUsers.userCode
        )
        [PSCustomObject]@{
            GroupValue   = $groupValue
            GroupUsers   = $groupUsers
            GroupResults = $groupResults
        }
    }
}


function Export-GroupSummaryDataCore {
    param(
        [Parameter(Mandatory)]
        $Sheet,
        [array]$DataItems,
        [Parameter(Mandatory)]
        [string]$ItemNameProperty,
        [array]$ViewItems,
        [array]$TotalResults,
        [array]$UseSummaryResults,
        [Parameter(Mandatory)]
        [string]$TargetUniquePropName,
        [Parameter(Mandatory)]
        [string]$DataMarkerKey,
        [switch]$FormatAsText
    )
    Write-Message $MyInvocation.MyCommand.Name -VarName "functionName" -Type "Info" -ForegroundColor Magenta
    $PSBoundParameters.Keys | ForEach-Object { Write-Message $PSBoundParameters[$_] -VarName "$_" }

    $dataStartCell = Get-CellByKey $Sheet $DataMarkerKey -ErrorOnMissing
    $columsStartIndex = $dataStartCell.Column
    Expand-ColumnsFromTemplate -Sheet $Sheet -TemplateStartColumn $columsStartIndex -TotalSets $DataItems.Count -ColumnsPerSet $ViewItems.Count

    $headData = @()
    foreach ($dataItem in $DataItems) {
        $headData += $dataItem.$ItemNameProperty
        $headData += [string[]]::new($ViewItems.Count-1)
    }
    $headDatas = ,$headData
    Write-BodyDatas -StartCell $dataStartCell -Datas $headDatas

    $rowDatas = @()

    # 全体
    $rowData = @()
    $rowData += "全体"
    foreach ($dataItem in $DataItems) {
        $totalResult = $TotalResults | Where-Object { $_.$ItemNameProperty -eq $dataItem.$ItemNameProperty } |
                      Select-Object -First 1
        foreach ($viewItem in $ViewItems) {
            $exists = $totalResult | Where-Object { $_.PSObject.Properties[$viewItem] }
            if ($exists) {
                $rowData += if ($FormatAsText) { "$($totalResult.$viewItem)" } else { $totalResult.$viewItem }
            } else {
                $rowData += ""
            }
        }
    }
    $rowDatas += ,$rowData

    # X別
    $uniqueUseSummaryResults = $UseSummaryResults | Select-Object -Property $TargetUniquePropName -Unique
    foreach ($uniqueUseSummaryResult in $uniqueUseSummaryResults) {
        $rowData = @()
        $rowData += "$($uniqueUseSummaryResult.$TargetUniquePropName)"
        $groupResults = $UseSummaryResults | Where-Object { $_.$TargetUniquePropName -eq $uniqueUseSummaryResult.$TargetUniquePropName }
        foreach ($dataItem in $DataItems) {
            $groupResult = $groupResults | Where-Object { $_.$ItemNameProperty -eq $dataItem.$ItemNameProperty } |
                          Select-Object -First 1
            foreach ($viewItem in $ViewItems) {
                $exists = $groupResult | Where-Object { $_.PSObject.Properties[$viewItem] }
                if ($exists) {
                    $rowData += if ($FormatAsText) { "$($groupResult.$viewItem)" } else { $groupResult.$viewItem }
                } else {
                    $rowData += ""
                }
            }
        }
        $rowDatas += ,$rowData
    }

    $dataStartCell = Get-CellByKey $Sheet "{結果データ}" -ErrorOnMissing
    $rowStartIndex = $dataStartCell.Row
    $columsStartIndex = $dataStartCell.Column

    # 行のコピー
    Expand-RowsFromTemplate -Sheet $Sheet -TemplateStartRow $rowStartIndex -TotalSets $rowDatas.Count

    # データの書き込み
    Write-BodyDatas -StartCell $dataStartCell -Datas $rowDatas

    # 初期セル設定
    Set-SheetFirstCell -Sheet $Sheet

    # オートフィット
    Set-AutoFit $Sheet

    return [PSCustomObject]@{
        RowStartIndex    = $rowStartIndex
        ColumnStartIndex = $columsStartIndex
        RowDatas         = $rowDatas
    }
}


function Create-UserDatas {
    param(
        [Parameter(Mandatory=$true)]
        [string]$DataFilePath
    )
    Write-Message $MyInvocation.MyCommand.Name -VarName "functionName" -Type "Info" -ForegroundColor Magenta
    $PSBoundParameters.Keys | ForEach-Object { Write-Message $PSBoundParameters[$_] -VarName "$_" }

    $headerMap = @{
        '通番'     = 'userNo'
        '受講生ID' = 'userCode'
        '氏名'     = 'userName'
        '会社名'   = 'companyName'
        'クラス名'  = 'className'
        '入社前準備講座ランク' = 'rankName'
    }
    $bodies = Create-MasterDatas -DataFilePath $DataFilePath -SheetIndex 1 -HeaderMap $headerMap
    return @($bodies | Where-Object { -not (ToBool $_.停止中) })
}
