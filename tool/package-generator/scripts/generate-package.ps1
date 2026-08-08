# =========================================
# コース別パッケージ生成ツール
# =========================================

$scriptDir = Split-Path $MyInvocation.MyCommand.Path
. (Join-Path $scriptDir "common.ps1")
$configPath = $env:GENERATE_CONFIG_PATH
$workPath = $env:GENERATE_WORK_PATH
$outputPath = $env:GENERATE_OUTPUT_PATH
$logPath = $env:COMMON_LOG_PATH

if (!$configPath -or !$workPath -or !$outputPath -or !$logPath) {
    Write-Host "GENERATE_CONFIG_PATH と GENERATE_WORK_PATH と GENERATE_OUTPUT_PATH と COMMON_LOG_PATH を set-env.bat で設定してください"
    exit 1
}

Remove-Item $workPath -Recurse -Force -ErrorAction SilentlyContinue
New-Item $workPath -ItemType Directory | Out-Null
New-Item $outputPath -ItemType Directory -Force | Out-Null
New-Item $logPath -ItemType Directory -Force | Out-Null

if (!(Get-Module -ListAvailable ImportExcel)) {
    Write-Host "ImportExcelをインストールします"
    Install-Module ImportExcel -Scope CurrentUser -Force
}

$excel = Get-ExcelSheetInfo $configPath


$sheetNames = $excel.Name

if ($env:GENERATE_SHEETS_INCLUDE) {
    $includeList = $env:GENERATE_SHEETS_INCLUDE.Split(",") | ForEach-Object { $_.Trim() }
    $sheetNames = $sheetNames | Where-Object { $includeList -contains $_ }
}

if ($env:GENERATE_SHEETS_EXCLUDE) {
    $excludeList = $env:GENERATE_SHEETS_EXCLUDE.Split(",") | ForEach-Object { $_.Trim() }
    $sheetNames = $sheetNames | Where-Object { $excludeList -notcontains $_ }
}

Write-Host "# パッケージ作成開始"
foreach ($sheetName in $sheetNames) {

    Write-Host ""
    $sheetStartTime = Get-Date
    Write-Host "$sheetName"

    $packageWorkPath = Join-Path $workPath $sheetName
    New-Item $packageWorkPath -ItemType Directory -Force | Out-Null

    $copyLog = @()

    $rows = Import-Excel -Path $configPath -WorksheetName $sheetName

    foreach ($row in $rows) {

        $sourcePath = $row.'取得元（フルパス）'

        if (!$sourcePath) {
            continue
        }

        if ($env:GENERATE_SOURCE_PATH -and !([System.IO.Path]::IsPathRooted($sourcePath))) {
            $sourcePath = Join-Path $env:GENERATE_SOURCE_PATH $sourcePath
        }

        $sourcePath = [System.IO.Path]::GetFullPath($sourcePath)

        if (!(Test-Path $sourcePath)) {
            Write-Host "存在しません：$sourcePath"
            continue
        }

        $storeRootPath = $packageWorkPath
        if ($row.格納先) {
            $storeRootPath = Join-Path $packageWorkPath $row.格納先
        }
        New-Item $storeRootPath -ItemType Directory -Force | Out-Null

        if (Test-Path -LiteralPath $sourcePath -PathType Container) {

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
                    $destinationPath = Join-Path $storeRootPath $relativePath
                    New-Item (Split-Path $destinationPath -Parent) -ItemType Directory -Force | Out-Null
                    Copy-Item $_.FullName $destinationPath -Force
                    $copyLog += "$($_.FullName) -> $destinationPath"
                }
            }

        } else {

            $fileName = Split-Path $sourcePath -Leaf
            $destinationPath = Join-Path $storeRootPath $fileName
            Copy-Item $sourcePath $destinationPath -Force
            $copyLog += "$sourcePath -> $destinationPath"
        }
    }

    $packagePath = Join-Path $outputPath "$sheetName.zip"
    Remove-Item $packagePath -Force -ErrorAction SilentlyContinue

    $packageItems = Get-ChildItem -LiteralPath $packageWorkPath
    if ($packageItems) {
        Compress-Archive -LiteralPath $packageItems.FullName -DestinationPath $packagePath
        Write-Host "$packagePath"
        $sheetEndTime = Get-Date
        $logFilePath = Join-Path $logPath "$($env:GENERATE_LOG_PREFIX)$(Get-ClientLogSegment)$sheetName.log"
        $logLines = @()
        $logLines += "# 実行情報"
        $logLines += (Get-ClientLogHeaderLines)
        $logLines += "バッチ名: $($env:BATCH_NAME)"
        $logLines += "シート名: $($sheetName)"
        $logLines += "開始時刻: $($sheetStartTime.ToString('yyyy/MM/dd HH:mm:ss'))"
        $logLines += "終了時刻: $($sheetEndTime.ToString('yyyy/MM/dd HH:mm:ss'))"
        $logLines += ""
        $logLines += "# コピー結果"
        $logLines += $copyLog
        $logLines += ""
        $logLines += "# フォルダ構成"
        $logLines += $sheetName
        $logLines += (Get-TreeLines -Path $packageWorkPath)
        Write-LogFile -Path $logFilePath -Lines $logLines
    } else {
        Write-Host "$sheetName：対象ファイルが無いためパッケージを作成しませんでした"
    }
}

Remove-Item $workPath -Recurse -Force -ErrorAction SilentlyContinue

Copy-Item $configPath (Join-Path $outputPath (Split-Path $configPath -Leaf)) -Force

Write-Host ""
Write-Host "# パッケージ作成完了"
