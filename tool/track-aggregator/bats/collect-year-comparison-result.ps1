param(
    [string]$MasterDataFilePath,
    [string]$TargetGroupName,
    [int]$TargetYear,
    [int]$ComparePeriod,
    [string]$OutputRootDir,
    [string]$TemplateFilePath,
    [string]$SurveyResultRootDir,
    [string]$TestResultRootDir,
    [int]$PassScore
)

$libraryDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$libraryDir = Join-Path $libraryDir "library"
Get-ChildItem -Path $libraryDir -Filter *.psm1 -Recurse | ForEach-Object {
    Import-Module $_.FullName -ErrorAction Stop -DisableNameChecking
}

# TargetGroupName（例: 地域共催-2026）から年度を除いたベース名を求める（TargetYearの値には依存させない）
$baseGroupName = $TargetGroupName -replace "-\d{4}$", ""

# ComparePeriod年前から現在年度までの各年度分＋差分行で1コースあたりの行数を決める
$rowsPerCourse = $ComparePeriod + 2


function Get-YearSummaryDatas {
    param(
        $UserDatas,
        $TestDatas,
        $SurveyDatas,
        [string]$GroupName
    )
    Write-Message $MyInvocation.MyCommand.Name -VarName "functionName" -Type "Info" -ForegroundColor Green
    $PSBoundParameters.Keys | ForEach-Object { Write-Message $PSBoundParameters[$_] -VarName "$_" }

    $userCodes = $UserDatas.userCode

    $testResultDatas = Create-TestResultDatas -TestResultRootDir $TestResultRootDir -TargetGroupName $GroupName -TestDatas $TestDatas -PassScore $PassScore
    $validTestResultDatas = $testResultDatas |
        Where-Object { $_.isExecute -and $_.userCode -in $userCodes } |
        Group-Object userCode, testName | ForEach-Object { $_.Group[0] }
    $totalTestSummaryResults = Create-TestSummaryDataByGroup -UserDatas $UserDatas -TestDatas $TestDatas -ValidResultDatas $validTestResultDatas

    $surveyResultDatas = Create-SurveyResultDatas -SurveyResultRootDir $SurveyResultRootDir -TargetGroupName $GroupName -SurveyDatas $SurveyDatas
    $validSurveyResultDatas = $surveyResultDatas |
        Where-Object { $_.isExecute -and $_.userCode -in $userCodes } |
        Group-Object userCode, surveyName | ForEach-Object { $_.Group[0] }
    $totalSurveySummaryResults = Create-SurveySummaryDataByGroup -UserDatas $UserDatas -SurveyDatas $SurveyDatas -ValidResultDatas $validSurveyResultDatas

    return [PSCustomObject]@{
        totalTestSummaryResults   = $totalTestSummaryResults
        totalSurveySummaryResults = $totalSurveySummaryResults
    }
}


function Get-CourseGroupDatas {
    Write-Message $MyInvocation.MyCommand.Name -VarName "functionName" -Type "Info" -ForegroundColor Green

    $courseGroups = @()
    $i = 1
    while ($true) {
        $groupName = [Environment]::GetEnvironmentVariable("CourseGroup${i}Name")
        if (-not $groupName) { break }
        $coursesRaw = [Environment]::GetEnvironmentVariable("CourseGroup${i}Courses")
        $courseNames = @($coursesRaw -split "," | Where-Object { $_ -ne "" })
        $courseGroups += [pscustomobject]@{
            groupName   = $groupName
            courseNames = $courseNames
        }
        $i++
    }
    # Write-Message $courseGroups -VarName "courseGroups" -Type "Info" -ForegroundColor Green
    return $courseGroups
}


function Create-YearComparisonDatas {
    param(
        $CourseGroupDatas,
        [array]$YearSummaryDatasList  # 古い年度→新しい年度の順。各要素は @{ year = <int>; summaryDatas = <Get-YearSummaryDatasの戻り値> }
    )
    Write-Message $MyInvocation.MyCommand.Name -VarName "functionName" -Type "Info" -ForegroundColor Green
    $PSBoundParameters.Keys | ForEach-Object { Write-Message $PSBoundParameters[$_] -VarName "$_" }

    $pickedSurveyItems = Get-PrimeSurveyItems
    $testViewItems = @("平均点", "中央値", "修了率")

    function New-YearRow {
        param($GroupName, $CourseName, $YearLabel, $TestResult, $SurveyResult)
        $row = [ordered]@{
            groupName  = $GroupName
            courseName = $CourseName
            yearLabel  = $YearLabel
        }
        foreach ($testViewItem in $testViewItems) {
            $row[$testViewItem] = if ($TestResult -and $TestResult.isExecute) { $TestResult.$testViewItem } else { $null }
        }
        foreach ($pickedSurveyItem in $pickedSurveyItems) {
            $row[$pickedSurveyItem] = if ($SurveyResult -and $SurveyResult.PSObject.Properties[$pickedSurveyItem]) { $SurveyResult.$pickedSurveyItem } else { $null }
        }
        return $row
    }

    $results = foreach ($courseGroup in $CourseGroupDatas) {
        # コースが1件も無いグループでも、グループ名の行だけは出力する
        $courseNamesInGroup = if ($courseGroup.courseNames.Count -eq 0) { @($null) } else { $courseGroup.courseNames }
        foreach ($courseName in $courseNamesInGroup) {
            $yearRows = foreach ($yearSummaryDatas in $YearSummaryDatasList) {
                $testResult   = $yearSummaryDatas.summaryDatas.totalTestSummaryResults   | Where-Object { $_.testName -eq $courseName } | Select-Object -First 1
                $surveyResult = $yearSummaryDatas.summaryDatas.totalSurveySummaryResults | Where-Object { $_.surveyName -eq $courseName } | Select-Object -First 1
                New-YearRow -GroupName $courseGroup.groupName -CourseName $courseName -YearLabel "FY$($yearSummaryDatas.year)" -TestResult $testResult -SurveyResult $surveyResult
            }

            $oldestRow = $yearRows[0]
            $newestRow = $yearRows[-1]
            $diffRow = [ordered]@{
                groupName  = $courseGroup.groupName
                courseName = $courseName
                yearLabel  = "差分"
            }
            foreach ($viewItem in (@($testViewItems) + $pickedSurveyItems)) {
                $currentValue  = $newestRow[$viewItem]
                $previousValue = $oldestRow[$viewItem]
                $diffRow[$viewItem] = if ($null -eq $currentValue -and $null -eq $previousValue) {
                    $null
                } else {
                    [double]($currentValue) - [double]($previousValue)
                }
            }

            foreach ($yearRow in $yearRows) { [pscustomobject]$yearRow }
            [pscustomobject]$diffRow
        }
    }
    # Write-Message $results -VarName "results" -Type "Info" -ForegroundColor Green
    return $results
}


function Export-YearComparisonData {
    param(
        $Workbook,
        $YearComparisonDatas,
        [int]$RowsPerCourse,
        $TemplateSheetName
    )
    Write-Message $MyInvocation.MyCommand.Name -VarName "functionName" -Type "Info" -ForegroundColor Green
    $PSBoundParameters.Keys | ForEach-Object { Write-Message $PSBoundParameters[$_] -VarName "$_" }

    $pickedSurveyItems = Get-PrimeSurveyItems
    $viewItems = @("平均点", "中央値", "修了率") + $pickedSurveyItems

    function Write-YearComparisonRows {
        param($Sheet, $Rows)

        $dataStartCell = Get-CellByKey $Sheet "{コースグループデータ}" -ErrorOnMissing
        $rowStartIndex = $dataStartCell.Row

        # 1コースにつき「各年度」＋「差分」の行を1セットとして展開する（行数はComparePeriodに応じて可変）
        $courseCount = [int]($Rows.Count / $RowsPerCourse)
        # 行のコピー
        Expand-RowsFromTemplate -Sheet $Sheet -TemplateStartRow $rowStartIndex -RowsPerSet $RowsPerCourse -TotalSets $courseCount

        $rowDatas = @()
        for ($i = 0; $i -lt $Rows.Count; $i++) {
            $row = $Rows[$i]
            $isFirstRowOfCourse = ($i % $RowsPerCourse -eq 0)

            # グループ名・コース名列は、コースの現在年度行（先頭行）にのみ書き込む
            $groupCellValue = if ($isFirstRowOfCourse) { $row.groupName } else { "" }
            $courseCellValue = if ($isFirstRowOfCourse) { $row.courseName } else { "" }

            $rowData = @("$groupCellValue", "$courseCellValue", "$($row.yearLabel)")
            foreach ($viewItem in $viewItems) {
                $rowData += "$($row.$viewItem)"
            }
            $rowDatas += ,$rowData
        }

        # データの書き込み
        Write-BodyDatas -StartCell $dataStartCell -Datas $rowDatas

        # コースグループ列は、同じグループが連続する範囲を縦に結合する
        $groupColumnIndex = $dataStartCell.Column
        $mergeStartRow = $rowStartIndex
        for ($i = 1; $i -le $Rows.Count; $i++) {
            $isLastRow = ($i -eq $Rows.Count)
            $groupChanged = $isLastRow -or ($Rows[$i].groupName -ne $Rows[$i - 1].groupName)
            if ($groupChanged) {
                $mergeEndRow = $rowStartIndex + $i - 1
                if ($mergeEndRow -gt $mergeStartRow) {
                    $Sheet.Range($Sheet.Cells.Item($mergeStartRow, $groupColumnIndex), $Sheet.Cells.Item($mergeEndRow, $groupColumnIndex)).Merge() | Out-Null
                }
                $mergeStartRow = $rowStartIndex + $i
            }
        }

        # 初期セル設定
        Set-SheetFirstCell -Sheet $Sheet

        # オートフィット
        Set-AutoFit $Sheet
    }

    # コースグループごとに行をまとめる（出現順を保持）
    $groupNames = @()
    $rowsByGroup = [ordered]@{}
    foreach ($row in $YearComparisonDatas) {
        if (-not $rowsByGroup.Contains($row.groupName)) {
            $groupNames += $row.groupName
            $rowsByGroup[$row.groupName] = @()
        }
        $rowsByGroup[$row.groupName] += $row
    }

    # グループ別シートを、テンプレートのマーカーが残っているうちに先に作成する
    foreach ($groupName in $groupNames) {
        $sourceSheet = $Workbook.Worksheets.Item($TemplateSheetName)
        $sourceSheet.Copy([Type]::Missing, $Workbook.Sheets.Item($Workbook.Sheets.Count))
        $newSheet = $Workbook.ActiveSheet
        $newSheet.Name = "$TemplateSheetName-$groupName"

        Write-YearComparisonRows -Sheet $newSheet -Rows $rowsByGroup[$groupName]
    }

    # 元のテンプレートシートには全コースをまとめて書き込み、先頭の「まとめ」シートとして残す
    $sheet = $Workbook.Worksheets.Item($TemplateSheetName)
    Write-YearComparisonRows -Sheet $sheet -Rows $YearComparisonDatas
}


function Export-Excel {
    param(
        [array]$YearComparisonDatas,
        [int]$RowsPerCourse,
        [string]$OutputFilePath
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

        Export-YearComparisonData -Workbook $workbook -YearComparisonDatas $YearComparisonDatas -RowsPerCourse $RowsPerCourse -TemplateSheetName "経年比較"

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


New-Item -Path $OutputRootDir -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null

$userDatas = Create-UserDatas -DataFilePath $MasterDataFilePath

$testDatas = Create-TestDatas -DataFilePath $MasterDataFilePath
$testDatas = @($testDatas | Where-Object { -not (ToBool $_.停止中) })

$surveyDatas = Create-SurveyDatas -DataFilePath $MasterDataFilePath
$surveyDatas = @($surveyDatas | Where-Object { -not (ToBool $_.停止中) })

$courseGroupDatas = Get-CourseGroupDatas

# 古い年度→新しい年度の順で、ComparePeriod年前から現在年度までを集計する
$yearSummaryDatasList = for ($offset = $ComparePeriod; $offset -ge 0; $offset--) {
    $year = $TargetYear - $offset
    $groupName = "$baseGroupName-$year"
    [PSCustomObject]@{
        year         = $year
        summaryDatas = Get-YearSummaryDatas -UserDatas $userDatas -TestDatas $testDatas -SurveyDatas $surveyDatas -GroupName $groupName
    }
}

$yearComparisonDatas = Create-YearComparisonDatas -CourseGroupDatas $courseGroupDatas -YearSummaryDatasList $yearSummaryDatasList
# Write-Message $yearComparisonDatas -VarName "yearComparisonDatas" -Type "Info"

$outputFilePath = Join-Path $OutputRootDir "$baseGroupName-$TargetYear-年度比較結果.xlsx"
Copy-Item -Path $TemplateFilePath -Destination $outputFilePath -Force

Export-Excel -YearComparisonDatas $yearComparisonDatas -RowsPerCourse $rowsPerCourse -OutputFilePath $outputFilePath
