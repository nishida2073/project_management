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
        [array]$Dimensions  # 各要素: @{ Key = <集計軸のプロパティ名>; Names = <値の一覧> }
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

    $dimensionSummaryResults = [ordered]@{}
    foreach ($dimension in $Dimensions) {
        $dimensionSummaryResults[$dimension.Key] = [PSCustomObject]@{
            testSummaryResults   = Create-TestSummaryDataByGroup -UserDatas $UserDatas -TestDatas $TestDatas -ValidResultDatas $validTestResultDatas -GroupValues $dimension.Names -GroupKey $dimension.Key
            surveySummaryResults = Create-SurveySummaryDataByGroup -UserDatas $UserDatas -SurveyDatas $SurveyDatas -ValidResultDatas $validSurveyResultDatas -GroupValues $dimension.Names -GroupKey $dimension.Key
        }
    }

    return [PSCustomObject]@{
        totalTestSummaryResults   = $totalTestSummaryResults
        totalSurveySummaryResults = $totalSurveySummaryResults
        dimensionSummaryResults   = $dimensionSummaryResults
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


function Create-DimensionYearComparisonDatas {
    param(
        $CourseGroupDatas,
        [array]$YearSummaryDatasList,  # 新しい年度→古い年度の順
        [string]$DimensionKey,         # 行オブジェクト・集計結果上の集計軸プロパティ名（例: "companyName"）
        [string]$AllLabel,             # 集計軸を問わない合計スコープの表示名（例: "全社"）
        [array]$DimensionNames
    )
    Write-Message $MyInvocation.MyCommand.Name -VarName "functionName" -Type "Info" -ForegroundColor Green
    $PSBoundParameters.Keys | ForEach-Object { Write-Message $PSBoundParameters[$_] -VarName "$_" }

    $pickedSurveyItems = Get-PrimeSurveyItems
    $testViewItems = @("平均点", "中央値", "修了率")

    function New-DimensionYearRow {
        param($GroupName, $CourseName, $DimensionKey, $DimensionValue, $YearLabel, $TestResult, $SurveyResult)
        $row = [ordered]@{
            groupName = $GroupName
            courseName = $CourseName
        }
        $row[$DimensionKey] = $DimensionValue
        $row["yearLabel"] = $YearLabel
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
            # 各コースの先頭に集計軸を問わない合計のセットを追加し、その後に集計軸の値ごとのセットを続ける
            $dimensionScopes = @($AllLabel) + $DimensionNames
            foreach ($dimensionValue in $dimensionScopes) {
                $yearRows = foreach ($yearSummaryDatas in $YearSummaryDatasList) {
                    if ($dimensionValue -eq $AllLabel) {
                        $testResult   = $yearSummaryDatas.summaryDatas.totalTestSummaryResults   | Where-Object { $_.testName -eq $courseName } | Select-Object -First 1
                        $surveyResult = $yearSummaryDatas.summaryDatas.totalSurveySummaryResults | Where-Object { $_.surveyName -eq $courseName } | Select-Object -First 1
                    } else {
                        $dimensionSummaryResults = $yearSummaryDatas.summaryDatas.dimensionSummaryResults[$DimensionKey]
                        $testResult   = $dimensionSummaryResults.testSummaryResults   | Where-Object { $_.testName -eq $courseName -and $_.$DimensionKey -eq $dimensionValue } | Select-Object -First 1
                        $surveyResult = $dimensionSummaryResults.surveySummaryResults | Where-Object { $_.surveyName -eq $courseName -and $_.$DimensionKey -eq $dimensionValue } | Select-Object -First 1
                    }
                    New-DimensionYearRow -GroupName $courseGroup.groupName -CourseName $courseName -DimensionKey $DimensionKey -DimensionValue $dimensionValue -YearLabel "FY$($yearSummaryDatas.year)" -TestResult $testResult -SurveyResult $surveyResult
                }

                # 差分は現在年度と、その1年前（ComparePeriodの範囲に関わらず直前の年度）との比較
                $newestRow = $yearRows[0]
                $previousRow = $yearRows[1]
                $diffRow = [ordered]@{
                    groupName = $courseGroup.groupName
                    courseName = $courseName
                }
                $diffRow[$DimensionKey] = $dimensionValue
                $diffRow["yearLabel"] = "差分"
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


function Export-DimensionYearComparisonData {
    param(
        $Workbook,
        $DimensionYearComparisonDatas,
        [int]$RowsPerCourse,
        [int]$DimensionCount,
        [string]$DimensionKey,
        $TemplateSheetName
    )
    Write-Message $MyInvocation.MyCommand.Name -VarName "functionName" -Type "Info" -ForegroundColor Green
    $PSBoundParameters.Keys | ForEach-Object { Write-Message $PSBoundParameters[$_] -VarName "$_" }

    $pickedSurveyItems = Get-PrimeSurveyItems
    $viewItems = @("平均点", "中央値", "修了率") + $pickedSurveyItems

    function Write-DimensionYearComparisonRows {
        param($Sheet, $Rows)

        $dataStartCell = Get-CellByKey $Sheet "{コースグループデータ}" -ErrorOnMissing
        $rowStartIndex = $dataStartCell.Row

        # まず年度行をComparePeriodに応じた行数まで増やす
        $yearRowCount = $RowsPerCourse - 1
        Expand-RowsFromTemplate -Sheet $Sheet -TemplateStartRow $rowStartIndex -RowsPerSet 1 -TotalSets $yearRowCount -InsertBeforeCopy

        # 年度行＋差分行（集計軸の値1つ分）を、集計軸の値の数だけ増やす
        $rowsPerDimension = $RowsPerCourse
        Expand-RowsFromTemplate -Sheet $Sheet -TemplateStartRow $rowStartIndex -RowsPerSet $rowsPerDimension -TotalSets $DimensionCount

        # 1コース分（集計軸の値の数分の年度行＋差分行）を、コース数分だけ複製する
        $rowsPerCourseBlock = $rowsPerDimension * $DimensionCount
        $courseCount = [int]($Rows.Count / $rowsPerCourseBlock)
        Expand-RowsFromTemplate -Sheet $Sheet -TemplateStartRow $rowStartIndex -RowsPerSet $rowsPerCourseBlock -TotalSets $courseCount

        $rowDatas = @()
        for ($i = 0; $i -lt $Rows.Count; $i++) {
            $row = $Rows[$i]
            $isFirstRowOfCourse = ($i % $rowsPerCourseBlock -eq 0)
            $isFirstRowOfDimension = ($i % $rowsPerDimension -eq 0)

            # グループ名・コース名列は、コース内の先頭行にのみ書き込む。集計軸列は、その値のブロックの先頭行にのみ書き込む
            $groupCellValue = if ($isFirstRowOfCourse) { $row.groupName } else { "" }
            $courseCellValue = if ($isFirstRowOfCourse) { $row.courseName } else { "" }
            $dimensionCellValue = if ($isFirstRowOfDimension) { $row.$DimensionKey } else { "" }

            $rowData = @("$groupCellValue", "$courseCellValue", "$dimensionCellValue", "$($row.yearLabel)")
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

        # コースグループ列・研修コース名列・集計軸列を、それぞれ連続する範囲で縦に結合する
        Merge-ConsecutiveColumn -Sheet $Sheet -RowStartIndex $rowStartIndex -Rows $Rows -ColumnIndex $dataStartCell.Column       -KeySelector { param($r) $r.groupName }
        Merge-ConsecutiveColumn -Sheet $Sheet -RowStartIndex $rowStartIndex -Rows $Rows -ColumnIndex ($dataStartCell.Column + 1) -KeySelector { param($r) "$($r.groupName)|$($r.courseName)" }
        Merge-ConsecutiveColumn -Sheet $Sheet -RowStartIndex $rowStartIndex -Rows $Rows -ColumnIndex ($dataStartCell.Column + 2) -KeySelector { param($r) "$($r.groupName)|$($r.courseName)|$($r.$DimensionKey)" }

        # 初期セル設定
        Set-SheetFirstCell -Sheet $Sheet

        # オートフィット
        Set-AutoFit $Sheet
    }

    # コースグループごとに行をまとめる（出現順を保持）
    $groupNames = @()
    $rowsByGroup = [ordered]@{}
    foreach ($row in $DimensionYearComparisonDatas) {
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

        Write-DimensionYearComparisonRows -Sheet $newSheet -Rows $rowsByGroup[$groupName]
    }

    # 元のテンプレートシートには全コースをまとめて書き込み、先頭の「まとめ」シートとして残す
    $sheet = $Workbook.Worksheets.Item($TemplateSheetName)
    Write-DimensionYearComparisonRows -Sheet $sheet -Rows $DimensionYearComparisonDatas
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
        [array]$Dimensions,  # 各要素: @{ Key; Datas; Count; SheetName }
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

        foreach ($dimension in $Dimensions) {
            Export-DimensionYearComparisonData -Workbook $workbook -DimensionYearComparisonDatas $dimension.Datas -RowsPerCourse $RowsPerCourse -DimensionCount $dimension.Count -DimensionKey $dimension.Key -TemplateSheetName $dimension.SheetName
        }

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
$classNames = @($userDatas.className | Sort-Object -Unique)

# 集計軸の定義。会社別・ランク別・クラス別のシートはすべてこの定義に沿って生成される
$dimensionDefs = @(
    [PSCustomObject]@{ Key = "companyName"; AllLabel = "全社";     Names = $companyNames; SheetName = "経年比較-会社別" }
    [PSCustomObject]@{ Key = "rankName";    AllLabel = "全ランク"; Names = $rankNames;    SheetName = "経年比較-ランク別" }
    [PSCustomObject]@{ Key = "className";   AllLabel = "全クラス"; Names = $classNames;   SheetName = "経年比較-クラス別" }
)

# 新しい年度→古い年度の順で、現在年度からComparePeriod年前までを集計する
$yearSummaryDatasList = for ($offset = 0; $offset -le $ComparePeriod; $offset++) {
    $year = $TargetYear - $offset
    $groupName = "$baseGroupName-$year"
    [PSCustomObject]@{
        year         = $year
        summaryDatas = Get-YearSummaryDatas -UserDatas $userDatas -TestDatas $testDatas -SurveyDatas $surveyDatas -GroupName $groupName -Dimensions $dimensionDefs
    }
}

$yearComparisonDatas = Create-YearComparisonDatas -CourseGroupDatas $courseGroupDatas -YearSummaryDatasList $yearSummaryDatasList
# Write-Message $yearComparisonDatas -VarName "yearComparisonDatas" -Type "Info"

$dimensionResults = foreach ($dimensionDef in $dimensionDefs) {
    $dimensionDatas = Create-DimensionYearComparisonDatas -CourseGroupDatas $courseGroupDatas -YearSummaryDatasList $yearSummaryDatasList -DimensionKey $dimensionDef.Key -AllLabel $dimensionDef.AllLabel -DimensionNames $dimensionDef.Names
    # Write-Message $dimensionDatas -VarName "$($dimensionDef.Key)YearComparisonDatas" -Type "Info"
    [PSCustomObject]@{
        Key       = $dimensionDef.Key
        Datas     = $dimensionDatas
        Count     = $dimensionDef.Names.Count + 1
        SheetName = $dimensionDef.SheetName
    }
}

$outputFilePath = Join-Path $OutputRootDir "$baseGroupName-$TargetYear-年度比較結果.xlsx"
Copy-Item -Path $TemplateFilePath -Destination $outputFilePath -Force

Export-Excel -YearComparisonDatas $yearComparisonDatas -Dimensions $dimensionResults -RowsPerCourse $rowsPerCourse -OutputFilePath $outputFilePath
