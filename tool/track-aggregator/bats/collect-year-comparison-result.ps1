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
        [string]$GroupName,
        [array]$CompanyNames,
        [array]$RankNames
    )
    Write-Message $MyInvocation.MyCommand.Name -VarName "functionName" -Type "Info" -ForegroundColor Green
    $PSBoundParameters.Keys | ForEach-Object { Write-Message $PSBoundParameters[$_] -VarName "$_" }

    $userCodes = $UserDatas.userCode

    $testResultDatas = Create-TestResultDatas -TestResultRootDir $TestResultRootDir -TargetGroupName $GroupName -TestDatas $TestDatas -PassScore $PassScore
    $validTestResultDatas = $testResultDatas |
        Where-Object { $_.isExecute -and $_.userCode -in $userCodes } |
        Group-Object userCode, testName | ForEach-Object { $_.Group[0] }
    $totalTestSummaryResults = Create-TestSummaryDataByGroup -UserDatas $UserDatas -TestDatas $TestDatas -ValidResultDatas $validTestResultDatas
    $companyTestSummaryResults = Create-TestSummaryDataByGroup -UserDatas $UserDatas -TestDatas $TestDatas -ValidResultDatas $validTestResultDatas -GroupValues $CompanyNames -GroupKey "companyName"
    $rankTestSummaryResults = Create-TestSummaryDataByGroup -UserDatas $UserDatas -TestDatas $TestDatas -ValidResultDatas $validTestResultDatas -GroupValues $RankNames -GroupKey "rankName"

    $surveyResultDatas = Create-SurveyResultDatas -SurveyResultRootDir $SurveyResultRootDir -TargetGroupName $GroupName -SurveyDatas $SurveyDatas
    $validSurveyResultDatas = $surveyResultDatas |
        Where-Object { $_.isExecute -and $_.userCode -in $userCodes } |
        Group-Object userCode, surveyName | ForEach-Object { $_.Group[0] }
    $totalSurveySummaryResults = Create-SurveySummaryDataByGroup -UserDatas $UserDatas -SurveyDatas $SurveyDatas -ValidResultDatas $validSurveyResultDatas
    $companySurveySummaryResults = Create-SurveySummaryDataByGroup -UserDatas $UserDatas -SurveyDatas $SurveyDatas -ValidResultDatas $validSurveyResultDatas -GroupValues $CompanyNames -GroupKey "companyName"
    $rankSurveySummaryResults = Create-SurveySummaryDataByGroup -UserDatas $UserDatas -SurveyDatas $SurveyDatas -ValidResultDatas $validSurveyResultDatas -GroupValues $RankNames -GroupKey "rankName"

    return [PSCustomObject]@{
        totalTestSummaryResults     = $totalTestSummaryResults
        totalSurveySummaryResults   = $totalSurveySummaryResults
        companyTestSummaryResults   = $companyTestSummaryResults
        companySurveySummaryResults = $companySurveySummaryResults
        rankTestSummaryResults      = $rankTestSummaryResults
        rankSurveySummaryResults    = $rankSurveySummaryResults
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
        [array]$YearSummaryDatasList  # 新しい年度→古い年度の順。各要素は @{ year = <int>; summaryDatas = <Get-YearSummaryDatasの戻り値> }
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

            # 差分は現在年度と、その1年前（ComparePeriodの範囲に関わらず直前の年度）との比較
            $newestRow = $yearRows[0]
            $previousRow = $yearRows[1]
            $diffRow = [ordered]@{
                groupName  = $courseGroup.groupName
                courseName = $courseName
                yearLabel  = "差分"
            }
            foreach ($viewItem in (@($testViewItems) + $pickedSurveyItems)) {
                $currentValue  = $newestRow[$viewItem]
                $previousValue = $previousRow[$viewItem]
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


function Create-CompanyYearComparisonDatas {
    param(
        $CourseGroupDatas,
        [array]$YearSummaryDatasList,  # 新しい年度→古い年度の順
        [array]$CompanyNames
    )
    Write-Message $MyInvocation.MyCommand.Name -VarName "functionName" -Type "Info" -ForegroundColor Green
    $PSBoundParameters.Keys | ForEach-Object { Write-Message $PSBoundParameters[$_] -VarName "$_" }

    $pickedSurveyItems = Get-PrimeSurveyItems
    $testViewItems = @("平均点", "中央値", "修了率")

    function New-CompanyYearRow {
        param($GroupName, $CourseName, $CompanyName, $YearLabel, $TestResult, $SurveyResult)
        $row = [ordered]@{
            groupName   = $GroupName
            courseName  = $CourseName
            companyName = $CompanyName
            yearLabel   = $YearLabel
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
            # 各コースの先頭に「全社」（会社を問わない合計）のセットを追加し、その後に会社ごとのセットを続ける
            $companyScopes = @("全社") + $CompanyNames
            foreach ($companyName in $companyScopes) {
                $yearRows = foreach ($yearSummaryDatas in $YearSummaryDatasList) {
                    if ($companyName -eq "全社") {
                        $testResult   = $yearSummaryDatas.summaryDatas.totalTestSummaryResults   | Where-Object { $_.testName -eq $courseName } | Select-Object -First 1
                        $surveyResult = $yearSummaryDatas.summaryDatas.totalSurveySummaryResults | Where-Object { $_.surveyName -eq $courseName } | Select-Object -First 1
                    } else {
                        $testResult   = $yearSummaryDatas.summaryDatas.companyTestSummaryResults   | Where-Object { $_.testName -eq $courseName -and $_.companyName -eq $companyName } | Select-Object -First 1
                        $surveyResult = $yearSummaryDatas.summaryDatas.companySurveySummaryResults | Where-Object { $_.surveyName -eq $courseName -and $_.companyName -eq $companyName } | Select-Object -First 1
                    }
                    New-CompanyYearRow -GroupName $courseGroup.groupName -CourseName $courseName -CompanyName $companyName -YearLabel "FY$($yearSummaryDatas.year)" -TestResult $testResult -SurveyResult $surveyResult
                }

                # 差分は現在年度と、その1年前（ComparePeriodの範囲に関わらず直前の年度）との比較
                $newestRow = $yearRows[0]
                $previousRow = $yearRows[1]
                $diffRow = [ordered]@{
                    groupName   = $courseGroup.groupName
                    courseName  = $courseName
                    companyName = $companyName
                    yearLabel   = "差分"
                }
                foreach ($viewItem in (@($testViewItems) + $pickedSurveyItems)) {
                    $currentValue  = $newestRow[$viewItem]
                    $previousValue = $previousRow[$viewItem]
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
    }
    # Write-Message $results -VarName "results" -Type "Info" -ForegroundColor Green
    return $results
}


function Create-RankYearComparisonDatas {
    param(
        $CourseGroupDatas,
        [array]$YearSummaryDatasList,  # 新しい年度→古い年度の順
        [array]$RankNames
    )
    Write-Message $MyInvocation.MyCommand.Name -VarName "functionName" -Type "Info" -ForegroundColor Green
    $PSBoundParameters.Keys | ForEach-Object { Write-Message $PSBoundParameters[$_] -VarName "$_" }

    $pickedSurveyItems = Get-PrimeSurveyItems
    $testViewItems = @("平均点", "中央値", "修了率")

    function New-RankYearRow {
        param($GroupName, $CourseName, $RankName, $YearLabel, $TestResult, $SurveyResult)
        $row = [ordered]@{
            groupName  = $GroupName
            courseName = $CourseName
            rankName   = $RankName
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
            # 各コースの先頭に「全ランク」（ランクを問わない合計）のセットを追加し、その後にランクごとのセットを続ける
            $rankScopes = @("全ランク") + $RankNames
            foreach ($rankName in $rankScopes) {
                $yearRows = foreach ($yearSummaryDatas in $YearSummaryDatasList) {
                    if ($rankName -eq "全ランク") {
                        $testResult   = $yearSummaryDatas.summaryDatas.totalTestSummaryResults   | Where-Object { $_.testName -eq $courseName } | Select-Object -First 1
                        $surveyResult = $yearSummaryDatas.summaryDatas.totalSurveySummaryResults | Where-Object { $_.surveyName -eq $courseName } | Select-Object -First 1
                    } else {
                        $testResult   = $yearSummaryDatas.summaryDatas.rankTestSummaryResults   | Where-Object { $_.testName -eq $courseName -and $_.rankName -eq $rankName } | Select-Object -First 1
                        $surveyResult = $yearSummaryDatas.summaryDatas.rankSurveySummaryResults | Where-Object { $_.surveyName -eq $courseName -and $_.rankName -eq $rankName } | Select-Object -First 1
                    }
                    New-RankYearRow -GroupName $courseGroup.groupName -CourseName $courseName -RankName $rankName -YearLabel "FY$($yearSummaryDatas.year)" -TestResult $testResult -SurveyResult $surveyResult
                }

                # 差分は現在年度と、その1年前（ComparePeriodの範囲に関わらず直前の年度）との比較
                $newestRow = $yearRows[0]
                $previousRow = $yearRows[1]
                $diffRow = [ordered]@{
                    groupName  = $courseGroup.groupName
                    courseName = $courseName
                    rankName   = $rankName
                    yearLabel  = "差分"
                }
                foreach ($viewItem in (@($testViewItems) + $pickedSurveyItems)) {
                    $currentValue  = $newestRow[$viewItem]
                    $previousValue = $previousRow[$viewItem]
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
    }
    # Write-Message $results -VarName "results" -Type "Info" -ForegroundColor Green
    return $results
}


function Merge-ConsecutiveColumn {
    param($Sheet, [int]$RowStartIndex, [array]$Rows, [int]$ColumnIndex, [scriptblock]$KeySelector)
    $mergeStartRow = $RowStartIndex
    for ($i = 1; $i -le $Rows.Count; $i++) {
        $isLastRow = ($i -eq $Rows.Count)
        $changed = $isLastRow -or ((& $KeySelector $Rows[$i]) -ne (& $KeySelector $Rows[$i - 1]))
        if ($changed) {
            $mergeEndRow = $RowStartIndex + $i - 1
            if ($mergeEndRow -gt $mergeStartRow) {
                $Sheet.Range($Sheet.Cells.Item($mergeStartRow, $ColumnIndex), $Sheet.Cells.Item($mergeEndRow, $ColumnIndex)).Merge() | Out-Null
            }
            $mergeStartRow = $RowStartIndex + $i
        }
    }
}


function Export-CompanyYearComparisonData {
    param(
        $Workbook,
        $CompanyYearComparisonDatas,
        [int]$RowsPerCourse,
        [int]$CompanyCount,
        $TemplateSheetName
    )
    Write-Message $MyInvocation.MyCommand.Name -VarName "functionName" -Type "Info" -ForegroundColor Green
    $PSBoundParameters.Keys | ForEach-Object { Write-Message $PSBoundParameters[$_] -VarName "$_" }

    $pickedSurveyItems = Get-PrimeSurveyItems
    $viewItems = @("平均点", "中央値", "修了率") + $pickedSurveyItems

    function Write-CompanyYearComparisonRows {
        param($Sheet, $Rows)

        $dataStartCell = Get-CellByKey $Sheet "{コースグループデータ}" -ErrorOnMissing
        $rowStartIndex = $dataStartCell.Row

        # まず年度行をComparePeriodに応じた行数まで増やす
        $yearRowCount = $RowsPerCourse - 1
        Expand-RowsFromTemplate -Sheet $Sheet -TemplateStartRow $rowStartIndex -RowsPerSet 1 -TotalSets $yearRowCount -InsertBeforeCopy

        # 年度行＋差分行（1会社分）を、会社数分だけ増やす
        $rowsPerCompany = $RowsPerCourse
        Expand-RowsFromTemplate -Sheet $Sheet -TemplateStartRow $rowStartIndex -RowsPerSet $rowsPerCompany -TotalSets $CompanyCount

        # 1コース分（会社数分の年度行＋差分行）を、コース数分だけ複製する
        $rowsPerCourseBlock = $rowsPerCompany * $CompanyCount
        $courseCount = [int]($Rows.Count / $rowsPerCourseBlock)
        Expand-RowsFromTemplate -Sheet $Sheet -TemplateStartRow $rowStartIndex -RowsPerSet $rowsPerCourseBlock -TotalSets $courseCount

        $rowDatas = @()
        for ($i = 0; $i -lt $Rows.Count; $i++) {
            $row = $Rows[$i]
            $isFirstRowOfCourse = ($i % $rowsPerCourseBlock -eq 0)
            $isFirstRowOfCompany = ($i % $rowsPerCompany -eq 0)

            # グループ名・コース名列は、コース内の先頭行にのみ書き込む。会社名列は、会社ブロックの先頭行にのみ書き込む
            $groupCellValue = if ($isFirstRowOfCourse) { $row.groupName } else { "" }
            $courseCellValue = if ($isFirstRowOfCourse) { $row.courseName } else { "" }
            $companyCellValue = if ($isFirstRowOfCompany) { $row.companyName } else { "" }

            $rowData = @("$groupCellValue", "$courseCellValue", "$companyCellValue", "$($row.yearLabel)")
            foreach ($viewItem in $viewItems) {
                $value = $row.$viewItem
                if ($viewItem -eq "修了率" -and $null -ne $value -and $value -ne "") {
                    $value = [double]$value / 100
                }
                $rowData += "$value"
            }
            $rowDatas += ,$rowData
        }

        # データの書き込み
        Write-BodyDatas -StartCell $dataStartCell -Datas $rowDatas

        # コースグループ列・研修コース名列・会社名列を、それぞれ連続する範囲で縦に結合する
        Merge-ConsecutiveColumn -Sheet $Sheet -RowStartIndex $rowStartIndex -Rows $Rows -ColumnIndex $dataStartCell.Column       -KeySelector { param($r) $r.groupName }
        Merge-ConsecutiveColumn -Sheet $Sheet -RowStartIndex $rowStartIndex -Rows $Rows -ColumnIndex ($dataStartCell.Column + 1) -KeySelector { param($r) "$($r.groupName)|$($r.courseName)" }
        Merge-ConsecutiveColumn -Sheet $Sheet -RowStartIndex $rowStartIndex -Rows $Rows -ColumnIndex ($dataStartCell.Column + 2) -KeySelector { param($r) "$($r.groupName)|$($r.courseName)|$($r.companyName)" }

        # 初期セル設定
        Set-SheetFirstCell -Sheet $Sheet

        # オートフィット
        Set-AutoFit $Sheet
    }

    # コースグループごとに行をまとめる（出現順を保持）
    $groupNames = @()
    $rowsByGroup = [ordered]@{}
    foreach ($row in $CompanyYearComparisonDatas) {
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

        Write-CompanyYearComparisonRows -Sheet $newSheet -Rows $rowsByGroup[$groupName]
    }

    # 元のテンプレートシートには全コースをまとめて書き込み、先頭の「まとめ」シートとして残す
    $sheet = $Workbook.Worksheets.Item($TemplateSheetName)
    Write-CompanyYearComparisonRows -Sheet $sheet -Rows $CompanyYearComparisonDatas
}


function Export-RankYearComparisonData {
    param(
        $Workbook,
        $RankYearComparisonDatas,
        [int]$RowsPerCourse,
        [int]$RankCount,
        $TemplateSheetName
    )
    Write-Message $MyInvocation.MyCommand.Name -VarName "functionName" -Type "Info" -ForegroundColor Green
    $PSBoundParameters.Keys | ForEach-Object { Write-Message $PSBoundParameters[$_] -VarName "$_" }

    $pickedSurveyItems = Get-PrimeSurveyItems
    $viewItems = @("平均点", "中央値", "修了率") + $pickedSurveyItems

    function Write-RankYearComparisonRows {
        param($Sheet, $Rows)

        $dataStartCell = Get-CellByKey $Sheet "{コースグループデータ}" -ErrorOnMissing
        $rowStartIndex = $dataStartCell.Row

        # まず年度行をComparePeriodに応じた行数まで増やす
        $yearRowCount = $RowsPerCourse - 1
        Expand-RowsFromTemplate -Sheet $Sheet -TemplateStartRow $rowStartIndex -RowsPerSet 1 -TotalSets $yearRowCount -InsertBeforeCopy

        # 年度行＋差分行（1ランク分）を、ランク数分だけ増やす
        $rowsPerRank = $RowsPerCourse
        Expand-RowsFromTemplate -Sheet $Sheet -TemplateStartRow $rowStartIndex -RowsPerSet $rowsPerRank -TotalSets $RankCount

        # 1コース分（ランク数分の年度行＋差分行）を、コース数分だけ複製する
        $rowsPerCourseBlock = $rowsPerRank * $RankCount
        $courseCount = [int]($Rows.Count / $rowsPerCourseBlock)
        Expand-RowsFromTemplate -Sheet $Sheet -TemplateStartRow $rowStartIndex -RowsPerSet $rowsPerCourseBlock -TotalSets $courseCount

        $rowDatas = @()
        for ($i = 0; $i -lt $Rows.Count; $i++) {
            $row = $Rows[$i]
            $isFirstRowOfCourse = ($i % $rowsPerCourseBlock -eq 0)
            $isFirstRowOfRank = ($i % $rowsPerRank -eq 0)

            # グループ名・コース名列は、コース内の先頭行にのみ書き込む。ランク列は、ランクブロックの先頭行にのみ書き込む
            $groupCellValue = if ($isFirstRowOfCourse) { $row.groupName } else { "" }
            $courseCellValue = if ($isFirstRowOfCourse) { $row.courseName } else { "" }
            $rankCellValue = if ($isFirstRowOfRank) { $row.rankName } else { "" }

            $rowData = @("$groupCellValue", "$courseCellValue", "$rankCellValue", "$($row.yearLabel)")
            foreach ($viewItem in $viewItems) {
                $value = $row.$viewItem
                if ($viewItem -eq "修了率" -and $null -ne $value -and $value -ne "") {
                    $value = [double]$value / 100
                }
                $rowData += "$value"
            }
            $rowDatas += ,$rowData
        }

        # データの書き込み
        Write-BodyDatas -StartCell $dataStartCell -Datas $rowDatas

        # コースグループ列・研修コース名列・ランク列を、それぞれ連続する範囲で縦に結合する
        Merge-ConsecutiveColumn -Sheet $Sheet -RowStartIndex $rowStartIndex -Rows $Rows -ColumnIndex $dataStartCell.Column       -KeySelector { param($r) $r.groupName }
        Merge-ConsecutiveColumn -Sheet $Sheet -RowStartIndex $rowStartIndex -Rows $Rows -ColumnIndex ($dataStartCell.Column + 1) -KeySelector { param($r) "$($r.groupName)|$($r.courseName)" }
        Merge-ConsecutiveColumn -Sheet $Sheet -RowStartIndex $rowStartIndex -Rows $Rows -ColumnIndex ($dataStartCell.Column + 2) -KeySelector { param($r) "$($r.groupName)|$($r.courseName)|$($r.rankName)" }

        # 初期セル設定
        Set-SheetFirstCell -Sheet $Sheet

        # オートフィット
        Set-AutoFit $Sheet
    }

    # コースグループごとに行をまとめる（出現順を保持）
    $groupNames = @()
    $rowsByGroup = [ordered]@{}
    foreach ($row in $RankYearComparisonDatas) {
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

        Write-RankYearComparisonRows -Sheet $newSheet -Rows $rowsByGroup[$groupName]
    }

    # 元のテンプレートシートには全コースをまとめて書き込み、先頭の「まとめ」シートとして残す
    $sheet = $Workbook.Worksheets.Item($TemplateSheetName)
    Write-RankYearComparisonRows -Sheet $sheet -Rows $RankYearComparisonDatas
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

        # テンプレートは年度行1行＋差分行1行の状態なので、まず年度行をComparePeriodに応じた行数まで増やす
        $yearRowCount = $RowsPerCourse - 1
        Expand-RowsFromTemplate -Sheet $Sheet -TemplateStartRow $rowStartIndex -RowsPerSet 1 -TotalSets $yearRowCount -InsertBeforeCopy

        # 年度行＋差分行を1セットとして、コース数分だけ複製する
        $courseCount = [int]($Rows.Count / $RowsPerCourse)
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
                $value = $row.$viewItem
                if ($viewItem -eq "修了率" -and $null -ne $value -and $value -ne "") {
                    $value = [double]$value / 100
                }
                $rowData += "$value"
            }
            $rowDatas += ,$rowData
        }

        # データの書き込み
        Write-BodyDatas -StartCell $dataStartCell -Datas $rowDatas

        # コースグループ列・研修コース名列を、それぞれ連続する範囲で縦に結合する
        Merge-ConsecutiveColumn -Sheet $Sheet -RowStartIndex $rowStartIndex -Rows $Rows -ColumnIndex $dataStartCell.Column       -KeySelector { param($r) $r.groupName }
        Merge-ConsecutiveColumn -Sheet $Sheet -RowStartIndex $rowStartIndex -Rows $Rows -ColumnIndex ($dataStartCell.Column + 1) -KeySelector { param($r) "$($r.groupName)|$($r.courseName)" }

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
        [array]$CompanyYearComparisonDatas,
        [array]$RankYearComparisonDatas,
        [int]$RowsPerCourse,
        [int]$CompanyCount,
        [int]$RankCount,
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

        Export-CompanyYearComparisonData -Workbook $workbook -CompanyYearComparisonDatas $CompanyYearComparisonDatas -RowsPerCourse $RowsPerCourse -CompanyCount $CompanyCount -TemplateSheetName "経年比較-会社別"

        Export-RankYearComparisonData -Workbook $workbook -RankYearComparisonDatas $RankYearComparisonDatas -RowsPerCourse $RowsPerCourse -RankCount $RankCount -TemplateSheetName "経年比較-ランク別"

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
$companyNames = @($userDatas.companyName | Select-Object -Unique)
$rankOrder = @("S","A","B","C","D","E")
$rankNames = @($userDatas.rankName | Select-Object -Unique | Sort-Object { $rankOrder.IndexOf($_) })

# 新しい年度→古い年度の順で、現在年度からComparePeriod年前までを集計する
$yearSummaryDatasList = for ($offset = 0; $offset -le $ComparePeriod; $offset++) {
    $year = $TargetYear - $offset
    $groupName = "$baseGroupName-$year"
    [PSCustomObject]@{
        year         = $year
        summaryDatas = Get-YearSummaryDatas -UserDatas $userDatas -TestDatas $testDatas -SurveyDatas $surveyDatas -GroupName $groupName -CompanyNames $companyNames -RankNames $rankNames
    }
}

$yearComparisonDatas = Create-YearComparisonDatas -CourseGroupDatas $courseGroupDatas -YearSummaryDatasList $yearSummaryDatasList
# Write-Message $yearComparisonDatas -VarName "yearComparisonDatas" -Type "Info"

$companyYearComparisonDatas = Create-CompanyYearComparisonDatas -CourseGroupDatas $courseGroupDatas -YearSummaryDatasList $yearSummaryDatasList -CompanyNames $companyNames
# Write-Message $companyYearComparisonDatas -VarName "companyYearComparisonDatas" -Type "Info"

$rankYearComparisonDatas = Create-RankYearComparisonDatas -CourseGroupDatas $courseGroupDatas -YearSummaryDatasList $yearSummaryDatasList -RankNames $rankNames
# Write-Message $rankYearComparisonDatas -VarName "rankYearComparisonDatas" -Type "Info"

$outputFilePath = Join-Path $OutputRootDir "$baseGroupName-$TargetYear-年度比較結果.xlsx"
Copy-Item -Path $TemplateFilePath -Destination $outputFilePath -Force

Export-Excel -YearComparisonDatas $yearComparisonDatas -CompanyYearComparisonDatas $companyYearComparisonDatas -RankYearComparisonDatas $rankYearComparisonDatas -RowsPerCourse $rowsPerCourse -CompanyCount ($companyNames.Count + 1) -RankCount ($rankNames.Count + 1) -OutputFilePath $outputFilePath
