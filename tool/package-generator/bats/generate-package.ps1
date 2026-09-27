# =========================================
# コース別パッケージ生成ツール
# =========================================

param(
    [string]$ConfigPath,
    [string]$WorkPath,
    [string]$OutputPath,
    [string]$LogPath,
    [string]$LogPrefix,
    [string]$SheetsInclude,
    [string]$SheetsExclude,
    [string]$SourcePath,
    [string]$ClientName = ""
)

$scriptDir = Split-Path $MyInvocation.MyCommand.Path
$libraryDir = Join-Path $scriptDir "library"
Get-ChildItem -Path $libraryDir -Filter *.ps1 -Recurse | ForEach-Object {
    . $_.FullName
}

Remove-Item $WorkPath -Recurse -Force -ErrorAction SilentlyContinue
New-Item $WorkPath -ItemType Directory | Out-Null
New-Item $OutputPath -ItemType Directory -Force | Out-Null
New-Item $LogPath -ItemType Directory -Force | Out-Null

$logNamePrefix = "$($LogPrefix)_$($ClientName)"
$logFilePath = New-WorkerLogPath -LogRoot $LogPath -Prefix $logNamePrefix

$script:exitCode = 0
$psParams = $PSBoundParameters
& {
    $psParams.Keys | ForEach-Object { Write-Message $psParams[$_] -VarName "param:$_" -Type "Info" -ForegroundColor Blue }
    
    $excel = $null
    $workbook = $null
    try {
        $excel = New-Object -ComObject Excel.Application
        $excel.Visible = $false
        $excel.DisplayAlerts = $false
        $excel.ScreenUpdating = $false
        $excel.EnableEvents = $false
        $workbook = $excel.Workbooks.Open($ConfigPath)
        $sheetNames = @()
        for ($i = 1; $i -le $workbook.Sheets.Count; $i++) {
            $sheetNames += $workbook.Sheets.Item($i).Name
        }
        if ($SheetsInclude) {
            $includePatterns = $SheetsInclude.Split(",") | ForEach-Object { $_.Trim() }
            $sheetNames = $sheetNames | Where-Object { Test-NameMatchesPatterns -Name $_ -Patterns $includePatterns }
        }

        if ($SheetsExclude) {
            $excludePatterns = $SheetsExclude.Split(",") | ForEach-Object { $_.Trim() }
            $sheetNames = $sheetNames | Where-Object { !(Test-NameMatchesPatterns -Name $_ -Patterns $excludePatterns) }
        }

        foreach ($sheetName in $sheetNames) {
            $packageWorkPath = Join-Path $WorkPath $sheetName
            New-Item $packageWorkPath -ItemType Directory -Force | Out-Null

            $packageLog = @()

            $sheet = $workbook.Sheets.Item($sheetName)
            $rows = Get-RowObjects -Sheet $sheet
            $baseSourcePath = $SourcePath

            foreach ($row in $rows) {
                $sourcePath = $row.'取得元（フルパス）'
                if (!$sourcePath) {
                    continue
                }
                if ($baseSourcePath -and !([System.IO.Path]::IsPathRooted($sourcePath))) {
                    $sourcePath = Join-Path $baseSourcePath $sourcePath
                }
                $sourcePath = [System.IO.Path]::GetFullPath($sourcePath)
                if (!(Test-Path $sourcePath)) {
                    Write-MessageWarn "取得元（フルパス）が存在しません：$sourcePath"
                    $packageLog += "$sourcePath -> 存在しません"
                    continue
                }

                $sourceIsFolder = Test-Path -LiteralPath $sourcePath -PathType Container
                $storeRootPath = $packageWorkPath
                $renameFileName = $null
                if ($row.格納先) {
                    if (!$sourceIsFolder -and [System.IO.Path]::HasExtension($row.格納先)) {
                        $storeSubDir = Split-Path $row.格納先 -Parent
                        $renameFileName = Split-Path $row.格納先 -Leaf
                        if ($storeSubDir) {
                            $storeRootPath = Join-Path $packageWorkPath $storeSubDir
                        }
                    } else {
                        $storeRootPath = Join-Path $packageWorkPath $row.格納先
                    }
                }
                New-Item $storeRootPath -ItemType Directory -Force | Out-Null

                if ($sourceIsFolder) {

                    $sourcePathTrimmed = $sourcePath.TrimEnd('\')

                    Get-ChildItem $sourcePath -Recurse | ForEach-Object {

                        $relativePath = $_.FullName.Substring($sourcePathTrimmed.Length).TrimStart('\')

                        if ($row.含める形式) {
                            $includePatterns = $row.含める形式.Split(",") | ForEach-Object { $_.Trim() }
                            $included = $false
                            foreach ($pattern in $includePatterns) {
                                if ($relativePath -like $pattern) {
                                    $included = $true
                                    break
                                }
                            }
                            if (!$included) {
                                return
                            }
                        }

                        if ($row.除外する形式) {
                            foreach ($exclude in $row.除外する形式.Split(",")) {
                                if ($relativePath -like $exclude.Trim()) {
                                    return
                                }
                            }
                        }

                        if (!$_.PSIsContainer) {
                            $currentFile = $_.FullName
                            $destinationPath = Join-Path $storeRootPath $relativePath
                            New-Item (Split-Path $destinationPath -Parent) -ItemType Directory -Force | Out-Null
                            try {
                                Copy-Item $currentFile $destinationPath -Force
                                $packageLog += "$currentFile -> $destinationPath"
                            } catch {
                                $packageLog += "$currentFile -> エラー: $($_.Exception.Message)"
                            }
                        }
                    }
                } else {
                    $fileName = if ($renameFileName) { $renameFileName } else { Split-Path $sourcePath -Leaf }
                    $destinationPath = Join-Path $storeRootPath $fileName
                    try {
                        Copy-Item $sourcePath $destinationPath -Force
                        $packageLog += "$sourcePath -> $destinationPath"
                    } catch {
                        $packageLog += "$sourcePath -> エラー: $($_.Exception.Message)"
                    }
                }
            }

            $packagePath = Join-Path $OutputPath "$sheetName.zip"
            Remove-Item $packagePath -Force -ErrorAction SilentlyContinue

            $packageItems = Get-ChildItem -LiteralPath $packageWorkPath
            if ($packageItems) {
                Write-Message "操作中：$sheetName.zip" -Type "Info" -NoHeader
                try {
                    Compress-Archive -LiteralPath $packageItems.FullName -DestinationPath $packagePath
                } catch {
                    throw "パッケージ作成エラー: $($_.Exception.Message)"
                }
            } else {
                Write-MessageWarn "$sheetName：対象ファイルが無いためパッケージを作成しませんでした"
                $packageLog += "対象ファイルが無いためパッケージを作成しませんでした"
            }

            $runLogArgs = @{
                ExtraHeaderLines   = @("シート名: $sheetName")
                ResultSectionTitle = "パッケージ結果"
                ResultLines        = $packageLog
            }
            if (Test-Path -LiteralPath $packagePath) {
                $runLogArgs["TreeRootPath"] = $packagePath
            }
            Write-Message (Get-RunLogMessage @runLogArgs) -Type "Info" -NoHeader
            Write-MessageComplete "パッケージを作成しました: $packagePath"
        }

        Remove-Item $WorkPath -Recurse -Force -ErrorAction SilentlyContinue

        Copy-Item $ConfigPath (Join-Path $OutputPath (Split-Path $ConfigPath -Leaf)) -Force

    } catch {
        Write-MessageError "実行エラー: $($error[0])"
        $script:exitCode = 1
    } finally {
        if ($workbook) { $workbook.Close($true) }
        if ($excel) { $excel.Quit() }
        if ($workbook) { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($workbook) }
        if ($excel) { [void][Runtime.InteropServices.Marshal]::ReleaseComObject($excel) }
    }
} *>&1 | Tee-Object -FilePath $logFilePath
ConvertTo-Utf8LogFile -Path $logFilePath
Write-MessageComplete "ログを出力しました: $logFilePath"
exit $script:exitCode
