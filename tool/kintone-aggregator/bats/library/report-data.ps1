# =========================================
# 業務日誌・コースデータの整形
# =========================================
# 各ワーカースクリプトが使う、受講生データ・コーススケジュールをkintoneアプリ登録用の
# レコード形式に組み立てる処理。

function ConvertTo-MappedRecords {
    param(
        [Parameter(Mandatory)]
        [array]$DataLines,
        [Parameter(Mandatory)]
        [hashtable]$HeaderMap
    )
    $records = @()
    $headers = $DataLines[0] -split "`t" | ForEach-Object { $_.Trim() }
    $bodyLines = $DataLines | Select-Object -Skip 1
    foreach ($line in $bodyLines) {
        $parts = $line -split "`t" | ForEach-Object { $_.Trim() }
        $record = [PSCustomObject]@{}
        for ($i = 0; $i -lt $headers.Count; $i++) {
            $header = $headers[$i]
            $value  = $parts[$i]
            $record | Add-Member -NotePropertyName $header -NotePropertyValue $value
            if ($HeaderMap.ContainsKey($header)) {
                $internalName = $HeaderMap[$header]
                $record | Add-Member -NotePropertyName $internalName -NotePropertyValue $value -Force
            }
        }
        $records += $record
    }
    return $records
}


function Create-CourseDatas {
    param(
        [array]$DataLines
    )
    Write-Message $MyInvocation.MyCommand.Name -VarName "functionName" -Type "Info" -ForegroundColor Magenta
    $PSBoundParameters.Keys | ForEach-Object { Write-Message $PSBoundParameters[$_] -VarName "$_" }

    $headerMap = @{
        '科目番号'   = 'courseNo'
        '科目名'     = 'courseName'
        '開始日'     = 'startDate'
        '終了日'     = 'endDate'
    }
    return ConvertTo-MappedRecords -DataLines $DataLines -HeaderMap $headerMap
}


function Create-UserDatas {
    param(
        [Parameter(Mandatory=$true)]
        [string]$DataFilePath
    )
    Write-Message $MyInvocation.MyCommand.Name -VarName "functionName" -Type "Info" -ForegroundColor Magenta
    $PSBoundParameters.Keys | ForEach-Object { Write-Message $PSBoundParameters[$_] -VarName "$_" }

    $dataLines = Convert-ExcelToCsvString -ExcelFilePath $DataFilePath -SheetIndex 1

    $headerMap = @{
        '通番'     = 'userNo'
        '受講生ID' = 'userCode'
        '氏名'     = 'userName'
        '会社名'   = 'companyName'
        'クラス名'  = 'className'
    }
    $bodies = ConvertTo-MappedRecords -DataLines $dataLines -HeaderMap $headerMap
    return @($bodies | Where-Object { -not (ToBool $_.停止中) })
}

function Create-CourseScheduleDatas {
    param(
        [Parameter(Mandatory=$true)]
        [string]$DataFilePath,
        [string]$CurrentDate
    )
    Write-Message $MyInvocation.MyCommand.Name -VarName "functionName" -Type "Info" -ForegroundColor Magenta
    $PSBoundParameters.Keys | ForEach-Object { Write-Message $PSBoundParameters[$_] -VarName "$_" }

    $courseLines = Convert-ExcelToCsvString -ExcelFilePath $DataFilePath -SheetIndex -1 -DateColumnIndexes @(3,4)
    $courseDatas = Create-CourseDatas $courseLines
    if (-not $courseDatas -or @($courseDatas).Count -eq 0) {
        throw "コーススケジュールのデータが見つかりません。受講生データファイルのスケジュールシートに開始日・終了日が入力されているか確認してください。ファイル: $DataFilePath"
    }

    $results = @()

    # 開始日
    $firstStart = ($courseDatas | Sort-Object {[datetime]$_.startDate})[0].startDate
    $startDate = [datetime]$firstStart

    # 終了日
    $lastEnd = ($courseDatas | Sort-Object {[datetime]$_.endDate} -Descending)[0].endDate
    $endDate = [datetime]$lastEnd

    $previousWasHoliday = $false

    # 日付ごとの対象科目を事前計算（総登場日数の計算と連番付与の両方で使うため、フィルタ処理は1回だけ行う）
    $courseForDateByDate = @{}
    for ($date = $startDate; $date -le $endDate; $date = $date.AddDays(1)) {
        $courseForDateByDate[$date.Ticks] = @($courseDatas | Where-Object {
            $start = [datetime]$_.startDate
            $end   = [datetime]$_.endDate
            $date -ge $start -and $date -le $end
        })
    }

    # 科目ごとの総登場日数を事前計算
    $courseTotalDays = @{}
    for ($date = $startDate; $date -le $endDate; $date = $date.AddDays(1)) {
        $courseForDate = $courseForDateByDate[$date.Ticks]
        foreach ($name in ($courseForDate.courseName | Select-Object -Unique)) {
            if (-not $courseTotalDays.ContainsKey($name)) {
                $courseTotalDays[$name] = 0
            }
            $courseTotalDays[$name]++
        }
    }
    # 連番管理
    $courseCounters = @{}
    for ($date = $startDate; $date -le $endDate; $date = $date.AddDays(1)) {
        $courseForDate = $courseForDateByDate[$date.Ticks]
        if ($courseForDate) {
            $todayCourses = $courseForDate.courseName | Select-Object -Unique
            $displayNames = @()
            foreach ($courseName in $todayCourses) {
                if (-not $courseCounters.ContainsKey($courseName)) {
                    $courseCounters[$courseName] = 0
                }
                $courseCounters[$courseName]++
                # 総登場日数が1日なら連番なし
                if ($courseTotalDays[$courseName] -eq 1) {
                    $displayNames += $courseName
                }
                else {
                    $displayNames += "$courseName（$($courseCounters[$courseName])）"
                }
            }
            $results += [PSCustomObject]@{
                科目名            = ($displayNames -join "/")
                courseName        = ($displayNames -join "/")
                日付              = $date.ToString("yyyy-MM-dd")
                date              = $date.ToString("yyyy-MM-dd")
                isHoliday         = $false
                isHolidayNextDay  = $previousWasHoliday
            }
            $previousWasHoliday = $false
        }
        else {
            # 休日
            $results += [PSCustomObject]@{
                科目名            = "研修無し"
                courseName        = "研修無し"
                日付              = $date.ToString("yyyy-MM-dd")
                date              = $date.ToString("yyyy-MM-dd")
                isHoliday         = $true
                isHolidayNextDay  = $false
            }
            $previousWasHoliday = $true
        }
    }
    if ($CurrentDate) {
        $cutoff = [datetime]::ParseExact($CurrentDate, "yyyy-MM-dd", $null)
        $results = $results | Where-Object {
            [datetime]$_.date -le $cutoff
        }
    }
    # Write-Message $results -VarName "results" -Type "Info" -ForegroundColor Green
    return $results
}
