# =========================================
# 個社別ZIP生成ツール
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

# 初期化
Remove-Item $workPath -Recurse -Force -ErrorAction SilentlyContinue
New-Item $workPath -ItemType Directory | Out-Null
New-Item $outputPath -ItemType Directory -Force | Out-Null
New-Item $logPath -ItemType Directory -Force | Out-Null

# Excelモジュール確認
if (!(Get-Module -ListAvailable ImportExcel)) {
    Write-Host "ImportExcelをインストールします"
    Install-Module ImportExcel -Scope CurrentUser -Force
}

# Excelシート取得
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

Write-Host "# ZIP作成開始"
foreach ($sheet in $sheetNames) {

    Write-Host ""
    $sheetStartTime = Get-Date
    Write-Host "$sheet"

    $companyWork = Join-Path $workPath $sheet
    New-Item $companyWork -ItemType Directory -Force | Out-Null

    $copyLog = @()

    $rows = Import-Excel -Path $configPath -WorksheetName $sheet

    foreach ($row in $rows) {

        $source = $row.'取得元（フルパス）'

        if (!$source) {
            continue
        }

        if ($env:GENERATE_SOURCE_PATH -and !([System.IO.Path]::IsPathRooted($source))) {
            $source = Join-Path $env:GENERATE_SOURCE_PATH $source
        }

        $source = [System.IO.Path]::GetFullPath($source)

        if (!(Test-Path $source)) {
            Write-Host "存在しません：$source"
            continue
        }

        # 格納先
        $storeRoot = $companyWork
        if ($row.格納先) {
            $storeRoot = Join-Path $companyWork $row.格納先
        }
        New-Item $storeRoot -ItemType Directory -Force | Out-Null

        if (Test-Path -LiteralPath $source -PathType Container) {

            # フォルダ処理
            $sourceTrimmed = $source.TrimEnd('\')

            Get-ChildItem $source -Recurse | ForEach-Object {

                $relative = $_.FullName.Substring($sourceTrimmed.Length).TrimStart('\')

                # 含める形式
                if ($row.含める形式) {
                    $includePatterns = $row.含める形式.Split(",") | ForEach-Object { $_.Trim() }
                    $included = $false
                    foreach ($pattern in $includePatterns) {
                        if ($relative -like $pattern) {
                            $included = $true
                            break
                        }
                    }
                    if (!$included) {
                        return
                    }
                }

                # 除外する形式
                if ($row.除外する形式) {
                    foreach ($exclude in $row.除外する形式.Split(",")) {
                        if ($relative -like $exclude.Trim()) {
                            return
                        }
                    }
                }

                if (!$_.PSIsContainer) {
                    $destination = Join-Path $storeRoot $relative
                    New-Item (Split-Path $destination -Parent) -ItemType Directory -Force | Out-Null
                    Copy-Item $_.FullName $destination -Force
                    $copyLog += "$($_.FullName) -> $destination"
                }
            }

        } else {

            # ファイル処理
            $fileName = Split-Path $source -Leaf
            $destination = Join-Path $storeRoot $fileName
            Copy-Item $source $destination -Force
            $copyLog += "$source -> $destination"
        }
    }

    # ZIP作成
    $zip = Join-Path $outputPath "$sheet.zip"
    Remove-Item $zip -Force -ErrorAction SilentlyContinue

    $zipItems = Get-ChildItem -LiteralPath $companyWork
    if ($zipItems) {
        Compress-Archive -LiteralPath $zipItems.FullName -DestinationPath $zip
        Write-Host "$zip"
        # ログ出力（ZIP単位）
        $sheetEndTime = Get-Date
        $logFilePath = Join-Path $logPath "$($env:GENERATE_LOG_PREFIX)$sheet.log"
        $logLines = @()
        $logLines += "# 実行情報"
        $logLines += "バッチ名: $($env:BATCH_NAME)"
        $logLines += "シート名: $($sheet)"
        $logLines += "開始時刻: $($sheetStartTime.ToString('yyyy/MM/dd HH:mm:ss'))"
        $logLines += "終了時刻: $($sheetEndTime.ToString('yyyy/MM/dd HH:mm:ss'))"
        $logLines += ""
        $logLines += "# コピー結果"
        $logLines += $copyLog
        $logLines += ""
        $logLines += "# フォルダ構成"
        $logLines += $sheet
        $logLines += (Get-TreeLines -Path $companyWork)
        Write-LogFile -Path $logFilePath -Lines $logLines
    } else {
        Write-Host "$sheet：対象ファイルが無いためZIPを作成しませんでした"
    }
}

Copy-Item $configPath (Join-Path $outputPath (Split-Path $configPath -Leaf)) -Force

Write-Host ""
Write-Host "# ZIP作成完了"
