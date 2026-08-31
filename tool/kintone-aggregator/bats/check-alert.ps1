param(
    [string]$BaseUrl,
    [string]$MasterDataFilePath,
    [string]$TargetGroupName,
    [string]$TemplateFilePath,
    [string]$CollectRootDir,
    [string]$OutputRootDir,
    [string]$TargetDate,
    [int]$ViewAllCourseSchedule,
    [int]$ViewHolidayCourseSchedule,
    [int]$AlertInterventionTerm,
    [int]$AlertInterventionLimit,
    [int]$UseRecovery,
    [string]$RecoveryScriptPath,
    [string]$LogNamePrefix
)
$libraryDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$libraryDir = Join-Path $libraryDir "library"
Get-ChildItem -Path $libraryDir -Filter *.ps1 -Recurse | ForEach-Object {
    . $_.FullName
}

$logFilePath = New-WorkerLogPath -Prefix "$(if ($LogNamePrefix) { $LogNamePrefix } else { 'check-alert' })-$TargetGroupName-$TargetDate"

function Recovery-DailyData {
    param(
        [string]$CollectRootDir,
        [string]$TargetGroupName,
        [array]$TargetDates
    )
    Write-Message $MyInvocation.MyCommand.Name -VarName "functionName" -Type "Info" -ForegroundColor Yellow
    Write-Message $TargetDates -VarName "TargetDates" -Type "Info" -ForegroundColor Green
    
    Use-Mutex "Recovery-DailyData" {
        if (Test-Path $CollectRootDir) {
            $allFiles = Get-ChildItem -Path $CollectRootDir -Filter "$TargetGroupName-*.txt" | Sort-Object Name
            $allFileDates = $allFiles.BaseName -replace "^$TargetGroupName-",""
        } else {
            $allFileDates = @()
        }
        $missingDates = $TargetDates | Where-Object { $_ -notin $allFileDates }
        foreach ($missingDate in $missingDates) {
            if ($UseRecovery -eq 1) {
                Write-Message "未集計のため集計を実施します。日付: $missingDate" -VarName "message" -Type "Info"
                # 集計対象は当該グループのみに絞る（全グループ分を再集計する無駄な重複処理を避ける）
                Start-Process $RecoveryScriptPath -ArgumentList $missingDate, $TargetGroupName -WindowStyle Hidden -Wait
            }else{
                Write-Message "集計データがありません。日付: $missingDate" -VarName "message" -Type "Error" -ForegroundColor Red
            }
        }
    }
}


function Create-DailyUserDatas {
    param(
        [Parameter(Mandatory)]
        [string]$CollectRootDir,
        [Parameter(Mandatory)]
        [string]$TargetGroupName,
        [array]$TargetDates
    )
    Write-Message $MyInvocation.MyCommand.Name -VarName "functionName" -Type "Info" -ForegroundColor Green
    $PSBoundParameters.Keys | ForEach-Object { Write-Message $PSBoundParameters[$_] -VarName "$_" }
    
    if (-not $TargetDates -or $TargetDates.Count -eq 0) {
        Write-Message "集計対象のスケジュールがありません。" -VarName "message" -Type "Warn" -ForegroundColor Yellow
        return
    }
    
    Recovery-DailyData -CollectRootDir $CollectRootDir -TargetGroupName $TargetGroupName -TargetDates $TargetDates
    
    $allFiles = Get-ChildItem -Path $CollectRootDir -Filter "$TargetGroupName-*.txt" | Sort-Object Name -Descending
    $allData = @()
    foreach ($file in $allFiles) {
        $range = Read-FileToArray $file.FullName
        if ($range.Count -eq 0) { continue }
        $header = $range[0]
        for ($r = 1; $r -lt $range.Count; $r++) {
            $values = $range[$r]
            $row = @{}
            for ($i = 0; $i -lt $header.Count; $i++) {
                $row[$header[$i]] = $values[$i]
            }
            $row["ファイル日付"] = $file.BaseName -replace "^$TargetGroupName-",""
            $allData += [PSCustomObject]$row
        }
    }
    
    # userCode(受講生ID)ごとにまとめる
    $result = @()
    foreach ($group in $allData | Group-Object -Property 受講生ID) {
        $first = $group.Group[0]
        
        # 日付ごとの配列を作成
        $dailyResult = $group.Group | Sort-Object ファイル日付 -Descending | ForEach-Object {
            [PSCustomObject]@{
                日付                       = $_.ファイル日付
                理解度                     = $_.理解度
                人間関係                   = $_.人間関係
                体調                       = $_.体調
                パルスサーベイフリーコメント = $_.パルスサーベイフリーコメント
                提出状況_業務日誌             = ToBool $_.業務日誌提出状況
                提出状況_パルスサーベイ       = ToBool $_.パルスサーベイ提出状況
            }
        }
        $result += [PSCustomObject]@{
            通番     = $first.通番
            クラス名 = $first.クラス名
            会社名   = $first.会社名
            受講生ID = $first.受講生ID
            氏名     = $first.氏名
            dailyResults = $dailyResult
        }
    }
    # Write-Message $result -VarName "result" -Type "Info"
    return $result
}


function Add-CheckResults {
    param(
        [array]$DailyUserDatas,
        [array]$CourseScheduleDatas,
        [int]$LookbackDays = 3
    )
    Write-Message $MyInvocation.MyCommand.Name -VarName "functionName" -Type "Info" -ForegroundColor Green
    $PSBoundParameters.Keys | ForEach-Object { Write-Message $PSBoundParameters[$_] -VarName "$_" }
    
    
    function Check-SingleAlert2022 {
        param(
            [array]$values
        )
        # 対象日が1件で値が空の場合、$valuesが配列でなくnullになる(パイプラインの単一null値の畳み込み)ため、
        # 範囲インデックス(1..)での例外を避けるためにここで配列化する
        $values = @($values)
        $latest = $values[0]
        if ($latest -eq "") { return $false }
        if ($latest -eq "NA") { return $false }
        
        $latest = [int]$values[0]
        
        # 1. 最新評価が1
        if ($latest -eq 1) { return $true }
        
        if ($values.Count -eq 1) { return $false }
        
        # 空文字を除去して int に変換
        $prev = $values[1..($values.Count-1)] | Where-Object { $_ -match '^\d+$' } | ForEach-Object { [int]$_ } | Select-Object -First 1
        if ($prev -eq $null) { return $false }
        
        # 2. 2以下が2回以上連続
        if ($latest -le 2 -and $prev -le 2) { return $true }
        # 3. 前回実施時（最新の直前の値）より2以上下がり、かつ最新評価が2以下
        if (($prev - $latest) -ge 2 -and $latest -le 2) { return $true }
        
        return $false
    }
    
    function Check-SingleAlert2021 {
        param(
            [array]$TargetDailyResults,
            [array]$CourseScheduleDatas
        )
        $latestDailyResult = $TargetDailyResults[0]
        $latest = $latestDailyResult.体調
        if ($latest -eq "NA") { return $false }
        if ($latest -eq "") { return $false }
        
        $latest = [int]$latest
        $courseScheduleData = $CourseScheduleDatas | Where-Object { $_.日付 -eq $latestDailyResult.日付 } | Select-Object -First 1
        Write-Message "isHolidayNextDay: $($courseScheduleData.isHolidayNextDay)" -ForegroundColor Cyan

        # 1. 翌日休日時、最新評価が1
        if ($courseScheduleData.isHolidayNextDay -and $latest -eq 1) { return $true }

        if ($TargetDailyResults.Count -eq 1) { return $false }

        # 空文字を除去して int に変換
        $prev = $TargetDailyResults[1..($TargetDailyResults.Count-1)] | Where-Object { $_.体調 -match '^\d+$' } | ForEach-Object { [int]$_.体調 } | Select-Object -First 1
        if ($prev -eq $null) { return $false }

        # 2. 2以下が2回以上連続
        if ($latest -le 2 -and $prev -le 2) { return $true }

        return $false
    }
    
    
    $result = @()
    foreach ($dailyUserData in $DailyUserDatas) {
        $dailyResults = $dailyUserData.dailyResults
        $dailyResults = @($dailyResults | Sort-Object { [datetime]$_.日付 } -Descending)
        for ($i=0; $i -lt $dailyResults.Count; $i++) {
            $dailyResult = $dailyResults[$i]
            Write-Message $dailyResult -VarName "dailyResult"
            # 現在日以降で取り出す
            $targetDailyResults = $dailyResults[$i..($dailyResults.Count-1)]
            # Write-Message $targetDailyResults -VarName "targetDailyResults"
            
            # alert 作成
            $理解度2022 = Check-SingleAlert2022 ($targetDailyResults | ForEach-Object { $_.理解度 })
            $人間関係2022 = Check-SingleAlert2022 ($targetDailyResults | ForEach-Object { $_.人間関係 })
            $体調2021 = Check-SingleAlert2021 $targetDailyResults $CourseScheduleDatas
            $体調2022 = Check-SingleAlert2022 ($targetDailyResults | ForEach-Object { $_.体調 })
            
            $dailyAlert = [PSCustomObject]@{
                理解度     = $理解度2022
                人間関係   = $人間関係2022
                体調2021       = $体調2021
                体調2022       = $体調2022
                体調           = $体調2021 -or $体調2022
                当日未回答_業務日誌      = -not $dailyResult.提出状況_業務日誌
                当日未回答_パルスサーベイ = -not $dailyResult.提出状況_パルスサーベイ
                連続未回答_業務日誌   = $false
                連続未回答_パルスサーベイ = $false
            }
            Write-Message $dailyAlert -VarName "dailyAlert"
            # LookbackDays分の連続未回答チェック
            $startIndex = $i
            $endIndex   = [Math]::Min($i + $LookbackDays - 1, $dailyResults.Count - 1)
            $termDailyResultCount = $endIndex - $startIndex + 1
            if($termDailyResultCount -ge $LookbackDays){
                $recentDailyResults = $dailyResults[$startIndex..$endIndex]
                if (($recentDailyResults | Where-Object { -not $_.提出状況_業務日誌 }).Count -eq $recentDailyResults.Count) {
                    $dailyAlert.連続未回答_業務日誌 = $true
                }
                if (($recentDailyResults | Where-Object { -not $_.提出状況_パルスサーベイ }).Count -eq $recentDailyResults.Count) {
                    $dailyAlert.連続未回答_パルスサーベイ = $true
                }
            }
            $dailyResult | Add-Member -NotePropertyName alert -NotePropertyValue $dailyAlert
        }
        
        $result += [PSCustomObject]@{
            通番         = $dailyUserData.通番
            クラス名     = $dailyUserData.クラス名
            会社名       = $dailyUserData.会社名
            受講生ID     = $dailyUserData.受講生ID
            氏名         = $dailyUserData.氏名
            dailyResults = $dailyResults
        }
    }
    Write-Message $result -VarName "result"
    return $result
}


function Create-DailySummaryDatas {
    param(
        [array]$CheckedDatas
    )
    Write-Message $MyInvocation.MyCommand.Name -VarName "functionName" -Type "Info" -ForegroundColor Green
    $PSBoundParameters.Keys | ForEach-Object { Write-Message $PSBoundParameters[$_] -VarName "$_" }
    
    $dailySummary = @{}
    foreach ($checkedData in $CheckedDatas) {
        # 受講生ID
        $userId = $checkedData.受講生ID
        foreach ($dailyResult in $checkedData.dailyResults) {
            $date = $dailyResult.日付
            if (-not $dailySummary.ContainsKey($date)) {
                $dailySummary[$date] = [PSCustomObject]@{
                    日付 = $date
                    
                    アラート人数理解度     = 0
                    アラート人数人間関係   = 0
                    アラート人数体調       = 0
                    アラート人数体調2021   = 0
                    アラート人数体調2022   = 0
                    
                    アラート人数連続未回答_業務日誌       = 0
                    アラート人数連続未回答_パルスサーベイ = 0
                    アラート人数合計       = 0
                    
                    アラート受講生ID一覧   = @{}
                    
                    # 平均計算用
                    平均理解度             = 0.0
                    平均人間関係           = 0.0
                    平均体調               = 0.0
                    合計理解度             = 0
                    件数理解度             = 0
                    合計人間関係           = 0
                    件数人間関係           = 0
                    合計体調               = 0
                    件数体調               = 0
                }
            }
            $summary = $dailySummary[$date]
            # ==========
            # アラート種類別カウント
            # ==========
            if ($dailyResult.alert.理解度) { $summary.アラート人数理解度++ }
            if ($dailyResult.alert.人間関係) { $summary.アラート人数人間関係++ }
            if ($dailyResult.alert.体調) { $summary.アラート人数体調++ }
            if ($dailyResult.alert.体調2021 ) { $summary.アラート人数体調2021++ }
            if ($dailyResult.alert.体調2022 ) { $summary.アラート人数体調2022++ }
            
            if ($dailyResult.alert.連続未回答_業務日誌) { $summary.アラート人数連続未回答_業務日誌++ }
            if ($dailyResult.alert.連続未回答_パルスサーベイ) { $summary.アラート人数連続未回答_パルスサーベイ++ }
            
            # ==========
            # 合計人数
            # 1つでもアラートがあれば登録
            # 連続未回答_業務日誌は対象外
            # ==========
            $hasAlert =
                $dailyResult.alert.理解度 -or
                $dailyResult.alert.人間関係 -or
                $dailyResult.alert.体調 -or
                $dailyResult.alert.連続未回答_パルスサーベイ
            if ($hasAlert -and $userId) {
                $summary.アラート受講生ID一覧[$userId] = $true
            }
            # ==========
            # 平均値計算用
            # ==========
            if ($dailyResult.理解度 -match '^\d+$') {
                $summary.合計理解度 += [int]$dailyResult.理解度
                $summary.件数理解度++
            }
            if ($dailyResult.人間関係 -match '^\d+$') {
                $summary.合計人間関係 += [int]$dailyResult.人間関係
                $summary.件数人間関係++
            }
            if ($dailyResult.体調 -match '^\d+$') {
                $summary.合計体調 += [int]$dailyResult.体調
                $summary.件数体調++
            }
        }
    }
    # ==========================
    # 集計確定処理
    # ==========================
    foreach ($summary in $dailySummary.Values) {
        # ユニーク人数確定
        $summary.アラート人数合計 =
            $summary.アラート受講生ID一覧.Count
        # 平均計算
        $summary.平均理解度 =
            if ($summary.件数理解度 -gt 0) {
                [Math]::Round($summary.合計理解度 / $summary.件数理解度, 2)
            } else { 0 }
        
        $summary.平均人間関係 =
            if ($summary.件数人間関係 -gt 0) {
                [Math]::Round($summary.合計人間関係 / $summary.件数人間関係, 2)
            } else { 0 }
        
        $summary.平均体調 =
            if ($summary.件数体調 -gt 0) {
                [Math]::Round($summary.合計体調 / $summary.件数体調, 2)
            } else { 0 }
        
        # 内部フィールド削除
        $summary.PSObject.Properties.Remove('アラート受講生ID一覧')
        $summary.PSObject.Properties.Remove('合計理解度')
        $summary.PSObject.Properties.Remove('件数理解度')
        $summary.PSObject.Properties.Remove('合計人間関係')
        $summary.PSObject.Properties.Remove('件数人間関係')
        $summary.PSObject.Properties.Remove('合計体調')
        $summary.PSObject.Properties.Remove('件数体調')
    }
    return $dailySummary.Values | Sort-Object 日付 -Descending
}


function Export-Excel {
    param(
        [string]$OutputFilePath,
        [array]$CourseScheduleDatas,
        [array]$DailySummaryDatas,
        [array]$UserDatas,
        [string]$TargetDate,
        [string]$TargetGroupName
    )
    Write-Message $MyInvocation.MyCommand.Name -VarName "functionName" -Type "Info" -ForegroundColor Green
    $PSBoundParameters.Keys | ForEach-Object { Write-Message $PSBoundParameters[$_] -VarName "$_" }
    
    $excel = $null
    $workbook = $null
    try {
        $excel = New-Object -ComObject Excel.Application
        $excel.Visible = $false
        $excel.DisplayAlerts = $false
        $excel.ScreenUpdating = $false
        $excel.EnableEvents = $false
        $workbook = $excel.Workbooks.Open($OutputFilePath)
        $excel.Calculation = -4135
        
        $summaryDataSheet = $workbook.Worksheets.Item("アラート結果-サマリ")
        Export-SummaryData $summaryDataSheet $CourseScheduleDatas $DailySummaryDatas
        
        $summaryChartSheet = $workbook.Worksheets.Item("アラート結果-サマリグラフ")
        Export-SummaryChart $summaryDataSheet $summaryChartSheet -TargetGroupName $TargetGroupName
        
        $userDataSheet = $workbook.Worksheets.Item("アラート結果-受講生別")
        Export-UserData $userDataSheet $CourseScheduleDatas $UserDatas $TargetDate
        
        $courseScheduleSheet = $workbook.Worksheets.Item("研修スケジュール")
        Export-CourseScheduleData $courseScheduleSheet $CourseScheduleDatas
        
        $dailyResultSheet = $workbook.Worksheets.Item("提出状況-当日")
        Export-DailyResult $dailyResultSheet $CourseScheduleDatas $UserDatas $TargetDate
        
        $totalResultSheet = $workbook.Worksheets.Item("提出状況-全日")
        Export-TotalResult $totalResultSheet $CourseScheduleDatas $UserDatas
        # 最初のシートをアクティブに
        Set-FirstVisibleSheet -Workbook $workbook
        
        # 保存
        $workbook.SaveAs($OutputFilePath, 51)
    }
    finally {
        if ($workbook) { $workbook.Close($true) }
        if ($excel) { $excel.Quit() }
        if ($workbook) { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($workbook) }
        if ($excel) { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($excel) }
    }
}

function Export-DailyResult {
    param(
        $Sheet,
        [array]$CourseScheduleDatas,
        [array]$UserDatas,
        [string]$TargetDate
    )
    Write-Message $MyInvocation.MyCommand.Name -VarName "functionName" -Type "Info" -ForegroundColor Green
    $PSBoundParameters.Keys | ForEach-Object { Write-Message $PSBoundParameters[$_] -VarName "$_" }
    
    $dataStartCell = Get-CellByKey $sheet "{研修データ}" -ErrorOnMissing
    $targetDateCourseData = $CourseScheduleDatas | Where-Object { $_.日付 -eq $TargetDate }
    $courseDatas = @(
        @(
            $TargetDate,
            $targetDateCourseData.科目名
        )
    )
    Write-BodyDatas -StartCell $dataStartCell -Datas $courseDatas
    
    $rowDatas = @()
    foreach ($userData in $UserDatas) {
        $dailyResult = $userData.dailyResults | Where-Object { $_.日付 -eq $TargetDate }
        # 業務日誌が対象
        if (-not $dailyResult.提出状況_業務日誌) { 
            $userUrl = "$BaseUrl/k/#/people/user/$($userData.受講生ID)"
            $reminderLink = '=HYPERLINK("' + $userUrl + '","督促")'
        } else {
            $reminderLink = ""
        }
        $rowData = @(
            $reminderLink
            $dailyResult.提出状況_業務日誌
            $dailyResult.提出状況_パルスサーベイ
            $userData.通番
            $userData.受講生ID
            $userData.クラス名
            $userData.会社名
            $userData.氏名
            $dailyResult.理解度
            $dailyResult.人間関係
            $dailyResult.体調
            $dailyResult.パルスサーベイフリーコメント
        )
        $rowDatas += ,$rowData
    }
    
    $dataStartCell = Get-CellByKey $sheet "{提出状況データ}" -ErrorOnMissing
    $rowStartIndex = $dataStartCell.Row
    $columsStartIndex = $dataStartCell.Column
    # 行のコピー
    Expand-RowsFromTemplate -Sheet $Sheet -TemplateStartRow $rowStartIndex -TotalSets $rowDatas.Count
    
    # データの書き込み
    Write-BodyDatas -StartCell $Sheet.Cells.Item($rowStartIndex,$columsStartIndex) -Datas $rowDatas
    
    # オートフィット
    Set-AutoFit $Sheet
    
    # 初期セル設定
    Set-SheetFirstCell -Sheet $Sheet
    
    $headerRange = $Sheet.Range(
        $Sheet.Cells.Item($rowStartIndex - 1,$columsStartIndex),
        $Sheet.Cells.Item($rowStartIndex - 1,$columsStartIndex + $rowDatas[0].Count)
    )
    # Set-AutoFilter $headerRange 2 "FALSE"
    Set-AutoFilter $headerRange
    
    # セルの色
    $resultRange = $sheet.Range(
        $Sheet.Cells.Item($rowStartIndex, $columsStartIndex + 2 -1 ), 
        $Sheet.Cells.Item($rowStartIndex + $rowDatas.Count - 1, $columsStartIndex + 3 -1))
    Set-ResultCellColor $resultRange
}


function Export-SummaryData {
    param(
        $Sheet,
        [array]$CourseScheduleDatas,
        [array]$DailySummaryDatas
    )
    Write-Message $MyInvocation.MyCommand.Name -VarName "functionName" -Type "Info" -ForegroundColor Green
    $PSBoundParameters.Keys | ForEach-Object { Write-Message $PSBoundParameters[$_] -VarName "$_" }
    
    $dataStartCell = Get-CellByKey $sheet "{集計データ}" -ErrorOnMissing
    $rowStartIndex = $dataStartCell.Row
    $columsStartIndex = $dataStartCell.Column
    $colDatas = @()
    foreach ($courseScheduleData in $CourseScheduleDatas) {
        $summaryData = $DailySummaryDatas | Where-Object { $_.日付 -eq $courseScheduleData.日付 } | Select-Object -First 1
        if ($summaryData) {
            $colData = @(
                                $courseScheduleData.科目名,
                                $courseScheduleData.日付,
                                $summaryData.アラート人数合計,
                                $summaryData.アラート人数理解度,
                                $summaryData.アラート人数人間関係,
                                $summaryData.アラート人数体調,
                                $summaryData.アラート人数体調2021,
                                $summaryData.アラート人数体調2022,
                                $summaryData.アラート人数連続未回答_パルスサーベイ,
                                $summaryData.平均理解度,
                                $summaryData.平均人間関係,
                                $summaryData.平均体調
                            )
        } else {
            $colData = @(
                        $courseScheduleData.科目名,
                        $courseScheduleData.日付,
                        0,
                        0,
                        0,
                        0,
                        0,
                        0,
                        0,
                        0,
                        0,
                        0
                    )
        }
        $colDatas += ,$colData
    }
    
    $colDatas = Transpose-Array $colDatas
    if( $colDatas ){
        $targetDateColumnIndex = [Array]::IndexOf($colDatas[1], $TargetDate) + $columsStartIndex
        $colDataCount = $colDatas[1].Count
    }else{
        Write-Message "データ不足" -VarName "message" -Type "Warn" -ForegroundColor Yellow
        $targetDateColumnIndex = -1
        $colDataCount = 0
    }
    # 列のコピー
    Expand-ColumnsFromTemplate -Sheet $Sheet -TemplateStartColumn $columsStartIndex -TotalSets $colDataCount
    
    # データの書き込み
    Write-BodyDatas -StartCell $Sheet.Cells.Item($rowStartIndex,$columsStartIndex) -Datas $colDatas
    
    # オートフィット
    Set-AutoFit $Sheet
    
    # 指定日の色分け
    $columsStartIndex = 6
    foreach ($courseScheduleData in $CourseScheduleDatas) {
        $courseScheduleRage = $Sheet.Range($Sheet.Cells($rowStartIndex,$columsStartIndex), $Sheet.Cells($rowStartIndex + 1,$columsStartIndex))
        Set-CourseScheduleDateCellColor -Range $courseScheduleRage -courseScheduleData $courseScheduleData
        $columsStartIndex++
    }
    
    # 初期セル設定
    Set-SheetFirstCell -Sheet $Sheet
    
    $offsetColumnIndex = -4
    Scroll-ToIndex -Sheet $Sheet -ColumnIndex $($targetDateColumnIndex + $offsetColumnIndex)
    
}


function Get-AlertStatus {
    param(
        [PSObject]$AlertData,
        [string[]]$Exclude = @("当日未回答_業務日誌","当日未回答_パルスサーベイ","体調2021","体調2022")
    )
    
    $trueProps = $AlertData.PSObject.Properties |
        Where-Object { $_.Value -eq $true -and $Exclude -notcontains $_.Name } |
        Select-Object -ExpandProperty Name
        
    return [PSCustomObject]@{
        HasTrue = ($trueProps.Count -gt 0)
        Text    = $trueProps -join "`n"
        Array   = $trueProps
    }
}


function Set-CourseScheduleDateCellColor {
    param(
        [Parameter(Mandatory=$true)]
        $Range,
        [Parameter(Mandatory=$true)]
        $courseScheduleData
    )
    if ($courseScheduleData.isHoliday) {
        $Range.Interior.ColorIndex = 15
    }
    elseif ($courseScheduleData.isHolidayNextDay) {
        $Range.Interior.ColorIndex = 6
    }
}


function Export-UserData {
    param(
        $Sheet,
        [array]$CourseScheduleDatas,
        [array]$UserDatas,
        [string]$TargetDate
    )
    Write-Message $MyInvocation.MyCommand.Name -VarName "functionName" -Type "Info" -ForegroundColor Green
    $PSBoundParameters.Keys | ForEach-Object { Write-Message $PSBoundParameters[$_] -VarName "$_" }
    
    # 特定日の指定
    $targetDateCourseData = $CourseScheduleDatas | Where-Object { $_.日付 -eq $TargetDate }
    $targetDateData = @()
    $targetDateData += $TargetDate
    $targetDateData += $targetDateCourseData.科目名
    
    Write-BodyDatas -StartCell $Sheet.Cells.Item(2,5) -Datas $targetDateData
    
    # スケジュールのデータ
    $dataStartCell = Get-CellByKey $sheet "{スケジュールデータ}" -ErrorOnMissing
    $rowStartIndex = $dataStartCell.Row
    $columsStartIndex = $dataStartCell.Column
    $dateDatas = @()
    $dateData = @()
    foreach ($courseScheduleData in $CourseScheduleDatas) {
        $dateData += $courseScheduleData.日付
        $dateData += $courseScheduleData.科目名
    }
    $dateDatas += ,$dateData
    if( $dateDatas ){
        $targetDateColumnIndex = [Array]::IndexOf($dateData, $TargetDate) + $columsStartIndex
    }else{
        Write-Message "データ不足" -VarName "message" -Type "Warn" -ForegroundColor Yellow
        $targetDateColumnIndex = -1
    }
    Write-Message $targetDateColumnIndex -VarName "targetDateColumnIndex"
    Write-Message $dateDatas -VarName "dateDatas"
    # 列のコピー
    Expand-ColumnsFromTemplate -Sheet $Sheet -TemplateStartColumn $columsStartIndex -TotalSets $CourseScheduleDatas.Count -ColumnsPerSet 2
    # データの書き込み
    Write-BodyDatas -StartCell $Sheet.Cells.Item($rowStartIndex,$columsStartIndex) -Datas $dateDatas
    
    # 指定日の色分け
    foreach ($courseScheduleData in $CourseScheduleDatas) {
        $courseScheduleRage = $Sheet.Range($Sheet.Cells($rowStartIndex,$columsStartIndex), $Sheet.Cells($rowStartIndex + 1,$columsStartIndex + 1))
        Set-CourseScheduleDateCellColor -Range $courseScheduleRage -courseScheduleData $courseScheduleData
        $columsStartIndex = $columsStartIndex + 2
    }
    
    $rowDatas = @()
    foreach ($userData in $UserDatas) {
        # ユーザのデータ
        $rowData = @()
        $rowData += $userData.受講生ID
        $rowData += $userData.氏名
        $rowData += $userData.会社名
        
        # 当日のデータ
        $targetDailyResultData = $userData.dailyResults | Where-Object { $_.日付 -eq $TargetDate } | Select-Object -First 1
        if( $targetDailyResultData ){
            $excludeAlertItems = @("当日未回答_業務日誌","当日未回答_パルスサーベイ","体調2021","体調2022")
            $targetDailyAlertStatus = Get-AlertStatus -AlertData $targetDailyResultData.alert -Exclude $excludeAlertItems
            $monitoringFlagLabel = if ($targetDailyAlertStatus.HasTrue) { "必要" } else { "" }
            
            $truePropertyNames = $targetDailyAlertStatus.Text
            $targetRecentResultDatas = $userData.dailyResults | Where-Object { $_.日付 -le $TargetDate } | Sort-Object -Property 日付 -Descending
            if($AlertInterventionTerm -gt 0){
                $targetRecentResultDatas = $targetRecentResultDatas | Select-Object -First $AlertInterventionTerm
            }
            $alertCount = @($targetRecentResultDatas | Where-Object { (Get-AlertStatus -AlertData $_.alert -Exclude $excludeAlertItems).HasTrue }).Count
            if ($alertCount -ge $AlertInterventionLimit) { 
                $userUrl = "$BaseUrl/k/#/people/user/$($userData.受講生ID)"
                $interventionFlagLabel = '=HYPERLINK("' + $userUrl + '","必要")'
            } else {
                $interventionFlagLabel = ""
            }
            Write-Message $targetRecentResultDatas -VarName "targetRecentResultDatas"
            Write-Message $alertCount -VarName "alertCount"
            
            $rowData += $monitoringFlagLabel
            $rowData += $truePropertyNames
            $rowData += $targetDailyResultData.パルスサーベイフリーコメント
            $rowData += $interventionFlagLabel
        } else {
            $rowData += @("","","","")
        }
        
        # 日付ごとのデータ
        foreach ($courseScheduleData in $CourseScheduleDatas) {
            $dailyResultData = $userData.dailyResults | Where-Object { $_.日付 -eq $courseScheduleData.日付 } | Select-Object -First 1
            $dailyAlertStatus = Get-AlertStatus -AlertData $dailyResultData.alert -Exclude @("体調2021","体調2022")
            if( $dailyResultData ){
                $rowData += $dailyAlertStatus.Text
                $rowData += $dailyResultData.パルスサーベイフリーコメント
            } else {
                $rowData += ""
                $rowData += ""
            }
        }
        
        $rowDatas += ,$rowData
    }
    
    $dataStartCell = Get-CellByKey $sheet "{受講生データ}" -ErrorOnMissing
    $rowStartIndex = $dataStartCell.Row
    $columsStartIndex = $dataStartCell.Column
    # 行のコピー
    Expand-RowsFromTemplate -Sheet $Sheet -TemplateStartRow $rowStartIndex -TotalSets $rowDatas.Count
    
    # データの書き込み
    Write-BodyDatas -StartCell $Sheet.Cells.Item($rowStartIndex,$columsStartIndex) -Datas $rowDatas
    
    # オートフィット
    Set-AutoFit $Sheet
    
    # 初期セル設定
    Set-SheetFirstCell -Sheet $Sheet
    
    $offsetColumnIndex = -2
    Scroll-ToIndex -Sheet $Sheet -ColumnIndex $($targetDateColumnIndex + $offsetColumnIndex)
    
    $headerRange = $sheet.Range(
        $sheet.Cells.Item($rowStartIndex - 1, $columsStartIndex),
        $sheet.Cells.Item($rowStartIndex - 1, $columsStartIndex + $rowDatas[0].Count)
    )
    
    # オートフィルター
    Set-AutoFilter $headerRange
    
}


function Export-TotalResult {
    param(
        $Sheet,
        [array]$CourseScheduleDatas,
        [array]$UserDatas
    )
    Write-Message $MyInvocation.MyCommand.Name -VarName "functionName" -Type "Info" -ForegroundColor Green
    $PSBoundParameters.Keys | ForEach-Object { Write-Message $PSBoundParameters[$_] -VarName "$_" }
    
    $rowDatas = @()
    $dailyResultMaps = @{}
    foreach ($userData in $UserDatas) {
        $dailyResultMaps[$userData.受講生ID] = @{}
        foreach ($dailyResult in $userData.dailyResults) {
            $dailyResultMaps[$userData.受講生ID][$dailyResult.日付] = $dailyResult
        }
    }
    $targetCourseScheduleDatas = $CourseScheduleDatas | Where-Object { -not $_.isHoliday }
    foreach ($courseScheduleData in $targetCourseScheduleDatas) {
        $targetDate = $courseScheduleData.日付
        foreach ($userData in $UserDatas) {
            $dailyResult = $dailyResultMaps[$userData.受講生ID][$targetDate]
            $rowData = @(
                $targetDate
                $dailyResult.提出状況_業務日誌
                $dailyResult.提出状況_パルスサーベイ
                $userData.通番
                $userData.受講生ID
                $userData.クラス名
                $userData.会社名
                $userData.氏名
                $dailyResult.理解度
                $dailyResult.人間関係
                $dailyResult.体調
                $dailyResult.パルスサーベイフリーコメント
            )
            $rowDatas += ,$rowData
        }
    }
    $dataStartCell = Get-CellByKey $sheet "{受講生データ}" -ErrorOnMissing
    $rowStartIndex = $dataStartCell.Row
    $columsStartIndex = $dataStartCell.Column
    # 行のコピー
    Expand-RowsFromTemplate -Sheet $Sheet -TemplateStartRow $rowStartIndex -TotalSets $rowDatas.Count
    
    # データの書き込み
    Write-BodyDatas -StartCell $Sheet.Cells.Item($rowStartIndex,$columsStartIndex) -Datas $rowDatas
    
    # オートフィット
    Set-AutoFit $Sheet
    
    # 初期セル設定
    Set-SheetFirstCell -Sheet $Sheet
    
    # スクロールバーの移動
    Scroll-ToIndex -Sheet $Sheet -RowIndex $($rowStartIndex + $rowDatas.Count - $UserDatas.Count)
    
    $headerRange = $Sheet.Range(
        $Sheet.Cells.Item($rowStartIndex - 1,$columsStartIndex),
        $Sheet.Cells.Item($rowStartIndex - 1,$columsStartIndex + $rowDatas[0].Count)
    )
    # Set-AutoFilter $headerRange 2 "FALSE"
    Set-AutoFilter $headerRange
    
    # セルの色
    $resultRange = $sheet.Range(
        $Sheet.Cells.Item($rowStartIndex, $columsStartIndex + 2 -1 ), 
        $Sheet.Cells.Item($rowStartIndex + $rowDatas.Count - 1, $columsStartIndex + 3 -1))
    Set-ResultCellColor $resultRange
}


function Export-SummaryChart {
    param(
        [Parameter(Mandatory=$true)]
        $DataSheet,
        [Parameter(Mandatory=$true)]
        $WriteSheet,
        [string]$TargetGroupName
    )
    Write-Message $MyInvocation.MyCommand.Name -VarName "functionName" -Type "Info" -ForegroundColor Green
    $PSBoundParameters.Keys | ForEach-Object { Write-Message $PSBoundParameters[$_] -VarName "$_" }
    
    # -------------------------
    # 開始列（F列）
    # -------------------------
    $startCol = 6   # F列
    $dateRow  = 4
    $courseRow = 3
    
    $understandingRow = 12
    $relationRow      = 13
    $conditionRow     = 14
    $totalRow = 5
    
    # -------------------------
    # 最終列取得（日付行基準）
    # -------------------------
    $lastCol = $DataSheet.Cells($dateRow, $DataSheet.Columns.Count).End(-4159).Column
    if ($lastCol -lt $startCol) {
        Write-Message "データ不足" -VarName "message" -Type "Warn" -ForegroundColor Yellow
        return
    }
    
    # -------------------------
    # 横軸ラベル作成（補助行を使用）
    # -------------------------
    $labelRow = $conditionRow + 2
    for ($col = $startCol; $col -le $lastCol; $col++) {
        # 日付取得（OADate対応）
        $dateValue = $DataSheet.Cells($dateRow, $col).Value2
        if ($dateValue -ne $null -and $dateValue -ne "") {
            $date = [DateTime]::FromOADate($dateValue).ToString("M月d日")
        }
        else {
            $date = ""
        }
        
        # 科目名取得
        $course = $DataSheet.Cells($courseRow, $col).Value2
        
        # 横軸ラベル（改行付き）
        $DataSheet.Cells($labelRow, $col).Value2 = "$course  $date"
        $DataSheet.Cells($labelRow, $col).WrapText = $true
    }
    
    $xRange = $DataSheet.Range(
        $DataSheet.Cells($labelRow,$startCol),
        $DataSheet.Cells($labelRow,$lastCol)
    )
    $DataSheet.Rows($labelRow).Hidden = $true
    
    # -------------------------
    # グラフ作成
    # -------------------------
    $anchorCell = $WriteSheet.Range("B3")
    $chartObject = $WriteSheet.ChartObjects().Add($anchorCell.Left, $anchorCell.Top, 1200, 400)
    $chart = $chartObject.Chart
    $chart.PlotVisibleOnly = $false
    #$chart.ChartType = [Microsoft.Office.Interop.Excel.XlChartType]::xlLineMarkers
    $chart.ChartType = [Microsoft.Office.Interop.Excel.XlChartType]::xlLine

    while ($chart.SeriesCollection().Count -gt 0) {
        $chart.SeriesCollection(1).Delete()
    }

    # 理解度
    $series1 = $chart.SeriesCollection().NewSeries()
    $series1.Name = $DataSheet.Cells($understandingRow,4).Value2
    $series1.XValues = $xRange
    $series1.Values = $DataSheet.Range(
        $DataSheet.Cells($understandingRow,$startCol),
        $DataSheet.Cells($understandingRow,$lastCol)
    )

    # 人間関係
    $series2 = $chart.SeriesCollection().NewSeries()
    $series2.Name = $DataSheet.Cells($relationRow,4).Value2
    $series2.XValues = $xRange
    $series2.Values = $DataSheet.Range(
        $DataSheet.Cells($relationRow,$startCol),
        $DataSheet.Cells($relationRow,$lastCol)
    )

    # 体調
    $series3 = $chart.SeriesCollection().NewSeries()
    $series3.Name = $DataSheet.Cells($conditionRow,4).Value2
    $series3.XValues = $xRange
    $series3.Values = $DataSheet.Range(
        $DataSheet.Cells($conditionRow,$startCol),
        $DataSheet.Cells($conditionRow,$lastCol)
    )

    # アラート人数合計
    $series4 = $chart.SeriesCollection().NewSeries()
    $series4.Name = $DataSheet.Cells($totalRow,2).Value2
    $series4.XValues = $xRange
    $series4.Values = $DataSheet.Range(
        $DataSheet.Cells($totalRow,$startCol),
        $DataSheet.Cells($totalRow,$lastCol)
    )
    $series4.ChartType = [Microsoft.Office.Interop.Excel.XlChartType]::xlColumnClustered
    $series4.AxisGroup = 2

    # -------------------------
    # タイトル
    # -------------------------
    $chart.HasTitle = $true
    $chart.ChartTitle.Text = $TargetGroupName

    $chart.Axes(1).HasTitle = $true
    $chart.Axes(1).AxisTitle.Text = "研修日程"
    $chart.Axes(1).TickLabels.Orientation = -90
    $chart.Axes(1).TickLabels.Orientation = [Microsoft.Office.Interop.Excel.XlOrientation]::xlVertical
    # $chart.Axes(1).TickLabels.Font.Size = 8

    $chart.Axes(2).HasTitle = $true
    $chart.Axes(2).AxisTitle.Text = "理解度・人間関係・体調の平均値"

    $chart.Axes(2,2).HasTitle = $true
    $chart.Axes(2,2).AxisTitle.Text = "アラート人数（人）"

    $chart.HasLegend = $true
    $chart.Legend.Position = [Microsoft.Office.Interop.Excel.XlLegendPosition]::xlLegendPositionBottom
}


function Export-CourseScheduleData {
    param(
        $Sheet,
        [array]$CourseScheduleDatas
    )
    Write-Message $MyInvocation.MyCommand.Name -VarName "functionName" -Type "Info" -ForegroundColor Green
    $PSBoundParameters.Keys | ForEach-Object { Write-Message $PSBoundParameters[$_] -VarName "$_" }
    
    $dataStartCell = Get-CellByKey $sheet "{スケジュールデータ}" -ErrorOnMissing
    $rowStartIndex = $dataStartCell.Row
    $columsStartIndex = $dataStartCell.Column
    
    $rowDatas = @()
    foreach ($courseScheduleData in $CourseScheduleDatas) {
        if ($courseScheduleData) {
            $rowData = @(
                              $courseScheduleData.科目名,
                              $courseScheduleData.日付
                          )
        }
        $rowDatas += ,$rowData
    }
    # 列のコピー
    Expand-RowsFromTemplate -Sheet $Sheet -TemplateStartRow $rowStartIndex -TotalSets $rowDatas.Count
    
    # データの書き込み
    Write-BodyDatas -StartCell $Sheet.Cells.Item($rowStartIndex,$columsStartIndex) -Datas $rowDatas
    
    # 初期セル設定
    Set-SheetFirstCell -Sheet $Sheet
    
}


& {
    $allCourseScheduleDatas = if ($ViewAllCourseSchedule -eq 1) {
        Create-CourseScheduleDatas -DataFilePath $MasterDataFilePath
    } else {
        Create-CourseScheduleDatas -DataFilePath $MasterDataFilePath -CurrentDate $TargetDate
    }
    Write-Message $allCourseScheduleDatas -VarName "allCourseScheduleDatas"

    $targetCourseScheduleDatas = $allCourseScheduleDatas | Where-Object { -not $_.isHoliday }
    Write-Message $targetCourseScheduleDatas -VarName "targetCourseScheduleDatas"

    $targetDates = @($targetCourseScheduleDatas |
        Where-Object { $_.日付 -le $TargetDate } |
        Sort-Object 日付 |
        ForEach-Object 日付)
    Write-Message $targetDates -VarName "targetDates" -Type "Info"
    if (-not $targetDates -or $targetDates.Count -eq 0) {
        Write-Message "対象の科目がありません。" -VarName "message" -Type "Warn" -ForegroundColor Yellow
        return
    }

    $dailyUserDatas = Create-DailyUserDatas -TargetGroupName $TargetGroupName -CollectRootDir $CollectRootDir -TargetDates $targetDates
    Write-Message $dailyUserDatas -VarName "dailyUserDatas"

    $checkedUserDatas = Add-CheckResults $dailyUserDatas $targetCourseScheduleDatas
    Write-Message $checkedUserDatas -VarName "checkedUserDatas"

    $dailySummaryDatas = Create-DailySummaryDatas $checkedUserDatas
    Write-Message $dailySummaryDatas -VarName "dailySummaryDatas"

    New-Item -Path $OutputRootDir -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null
    $outputFilePath = Join-Path $OutputRootDir "$TargetGroupName.xlsx"
    Copy-Item -Path $TemplateFilePath -Destination $outputFilePath -Force
    $viewCourseScheduleDatas = if ($ViewHolidayCourseSchedule -eq 1) {
        $allCourseScheduleDatas
    }else{
        $targetCourseScheduleDatas
    }
    Export-Excel $outputFilePath $viewCourseScheduleDatas $dailySummaryDatas $checkedUserDatas $targetDates[-1] -TargetGroupName $TargetGroupName

    $backupDirPath = Join-Path $OutputRootDir "backup"
    New-Item -Path $backupDirPath -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null

    $backupFilePath = Join-Path $backupDirPath "$TargetGroupName-$TargetDate.xlsx"

    Copy-Item -Path $outputFilePath -Destination $backupFilePath -Force
} *>&1 | Tee-Object -FilePath $logFilePath
ConvertTo-Utf8LogFile -Path $logFilePath
