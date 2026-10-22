param(
    [Parameter(Mandatory)][string[]]$SpecPath,
    [int]$Zoom = 80,
    [string]$ColumnWidths = "通番=8,区分=10,入力値=50,操作=50,期待値=50,参照=40,実施結果=12,ケース数=10",
    [string]$LineBreakColumns = "入力値,期待値"
)

$script:WidthMap = @{}
foreach ($pair in ($ColumnWidths -split ",")) {
    $kv = $pair -split "=", 2
    if ($kv.Count -eq 2) { $script:WidthMap[$kv[0].Trim()] = [double]$kv[1] }
}

$toolRoot = Split-Path -Parent $PSScriptRoot

function Read-SpecTables {
    param([string]$Path)
    $lines = Get-Content -LiteralPath $Path -Encoding UTF8
    $title = ""
    $tables = New-Object System.Collections.Generic.List[object]
    $heading = ""
    $current = $null
    $skipHeader = $false
    foreach ($line in $lines) {
        if (-not $title -and $line -match '^# (.+)$') { $title = $Matches[1]; continue }
        if ($line -match '^### (.+)$') { $heading = $Matches[1]; $current = $null; continue }
        if ($line -match '^## ') { $heading = ""; $current = $null; continue }
        if ($line -match '^\|') {
            $cells = @($line.Trim().Trim('|').Split('|') | ForEach-Object { $_.Trim() })
            if (@($cells | Where-Object { $_ -notmatch '^:?-+:?$' }).Count -eq 0) { continue }
            if ($null -eq $current) {
                $last = $null
                if ($tables.Count -gt 0) { $last = $tables[$tables.Count - 1] }
                if ($last -and $heading -and $last.Heading -eq $heading) {
                    $current = $last
                    $skipHeader = $true
                }
                else {
                    $current = [pscustomobject]@{ Heading = $heading; Rows = New-Object System.Collections.Generic.List[object] }
                    $tables.Add($current)
                }
            }
            if ($skipHeader) {
                $skipHeader = $false
                continue
            }
            $current.Rows.Add($cells)
        }
        else {
            $current = $null
        }
    }
    return [pscustomobject]@{ Title = $title; Tables = $tables }
}

function Get-SheetName {
    param([string]$Heading, [int]$Index)
    if ($Heading) { $name = $Heading }
    elseif ($Index -eq 1) { $name = "一覧" }
    else { $name = "表$Index" }
    $name = $name -replace '[\\/?*\[\]:]', ''
    if ($name.Length -gt 31) { $name = $name.Substring(0, 31) }
    return $name
}

function Get-ColumnWidth {
    param([string]$Name)
    if ($script:WidthMap.ContainsKey($Name)) { return $script:WidthMap[$Name] }
    return [double]18
}

function Write-SpecWorkbook {
    param([string]$SpecPath, [string]$OutPath)
    $spec = Read-SpecTables -Path $SpecPath
    if ($spec.Tables.Count -eq 0) { throw "表がありません: $SpecPath" }

    $excel = New-Object -ComObject Excel.Application
    $excel.Visible = $false
    $excel.DisplayAlerts = $false
    $wb = $excel.Workbooks.Add()
    try {
        $index = 0
        foreach ($table in $spec.Tables) {
            $index++
            if ($index -eq 1) {
                $ws = $wb.Worksheets.Item(1)
            }
            else {
                $ws = $wb.Worksheets.Add([System.Reflection.Missing]::Value, $wb.Worksheets.Item($wb.Worksheets.Count))
            }
            $ws.Name = Get-SheetName -Heading $table.Heading -Index $index

            $header = $table.Rows[0]
            $rowCount = $table.Rows.Count
            $colCount = $header.Count
            $range = $ws.Range($ws.Cells.Item(1, 1), $ws.Cells.Item($rowCount, $colCount))
            $range.NumberFormat = "@"
            $data = New-Object 'object[,]' $rowCount, $colCount
            for ($r = 0; $r -lt $rowCount; $r++) {
                $cells = $table.Rows[$r]
                for ($c = 0; $c -lt $colCount; $c++) {
                    $value = if ($c -lt $cells.Count) { $cells[$c] } else { "" }
                    if ($r -gt 0 -and @($LineBreakColumns -split ",") -contains $header[$c]) { $value = $value -replace '、(?=[^、：]+：)', [string][char]10 }
                    $data[$r, $c] = $value
                }
            }
            $range.Value2 = $data

            $headerRange = $ws.Range($ws.Cells.Item(1, 1), $ws.Cells.Item(1, $colCount))
            $headerRange.Font.Bold = $true
            $headerRange.Interior.Color = 15921906
            $range.Borders.LineStyle = 1
            $range.WrapText = $true
            $range.VerticalAlignment = -4160
            for ($c = 1; $c -le $colCount; $c++) {
                $ws.Columns.Item($c).ColumnWidth = Get-ColumnWidth -Name $header[$c - 1]
            }
            $range.AutoFilter() | Out-Null

            $ws.Activate()
            $excel.ActiveWindow.Zoom = $Zoom
            $excel.ActiveWindow.FreezePanes = $false
            $excel.ActiveWindow.SplitColumn = 0
            $excel.ActiveWindow.SplitRow = 1
            $excel.ActiveWindow.FreezePanes = $true
        }
        $wb.Worksheets.Item(1).Activate()
        if (Test-Path -LiteralPath $OutPath) { Remove-Item -LiteralPath $OutPath -Force }
        $wb.SaveAs($OutPath, 51)
    }
    finally {
        $wb.Close($false)
        $excel.Quit()
        [System.Runtime.InteropServices.Marshal]::ReleaseComObject($wb) | Out-Null
        [System.Runtime.InteropServices.Marshal]::ReleaseComObject($excel) | Out-Null
        [GC]::Collect()
        [GC]::WaitForPendingFinalizers()
    }
}

foreach ($specPath in $SpecPath) {
    $found = @(Resolve-Path -Path $specPath -ErrorAction SilentlyContinue)
    if ($found.Count -eq 0) { Write-Output "NG  見つかりません: $specPath"; continue }
    foreach ($item in $found) {
        $resolved = $item.Path
        $outPath = [System.IO.Path]::ChangeExtension($resolved, ".xlsx")
        try {
            Write-SpecWorkbook -SpecPath $resolved -OutPath $outPath
            Write-Output "OK  $outPath"
        }
        catch {
            Write-Output "NG  $resolved : $($_.Exception.Message)"
        }
    }
}
