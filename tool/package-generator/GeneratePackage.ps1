# =========================================
# 個社別ZIP生成ツール
# =========================================

$basePath = Split-Path $MyInvocation.MyCommand.Path
$configPath = if ($env:GENERATE_CONFIG_PATH) { $env:GENERATE_CONFIG_PATH } else { Join-Path $basePath "config\package_definition.xlsx" }
$workPath = if ($env:COMMON_WORK_PATH) { $env:COMMON_WORK_PATH } else { Join-Path $basePath "work" }
$outputPath = if ($env:COMMON_OUTPUT_PATH) { $env:COMMON_OUTPUT_PATH } else { Join-Path $basePath "output" }
$logBasePath = if ($env:COMMON_LOG_PATH) { $env:COMMON_LOG_PATH } else { Join-Path $basePath "log" }

# 初期化
Remove-Item $workPath -Recurse -Force -ErrorAction SilentlyContinue
New-Item $workPath -ItemType Directory | Out-Null
New-Item $outputPath -ItemType Directory -Force | Out-Null
New-Item $logBasePath -ItemType Directory -Force | Out-Null

# Excelモジュール確認
if (!(Get-Module -ListAvailable ImportExcel)) {
    Write-Host "ImportExcelをインストールします"
    Install-Module ImportExcel -Scope CurrentUser -Force
}

# Excelシート取得
$excel = Get-ExcelSheetInfo $configPath

function Get-TreeLines {
    param(
        [string]$Path,
        [string]$Prefix = ""
    )

    $items = Get-ChildItem -LiteralPath $Path | Sort-Object { !$_.PSIsContainer }, Name

    for ($i = 0; $i -lt $items.Count; $i++) {
        $item = $items[$i]
        $isLast = ($i -eq $items.Count - 1)
        $connector = if ($isLast) { "└─ " } else { "├─ " }
        Write-Output "$Prefix$connector$($item.Name)"

        if ($item.PSIsContainer) {
            $childPrefix = if ($isLast) { "$Prefix    " } else { "$Prefix│   " }
            Get-TreeLines -Path $item.FullName -Prefix $childPrefix
        }
    }
}

$sheetNames = $excel.Name

if ($env:GENERATE_SHEETS_INCLUDE) {
    $includeList = $env:GENERATE_SHEETS_INCLUDE.Split(",") | ForEach-Object { $_.Trim() }
    $sheetNames = $sheetNames | Where-Object { $includeList -contains $_ }
}

if ($env:GENERATE_SHEETS_EXCLUDE) {
    $excludeList = $env:GENERATE_SHEETS_EXCLUDE.Split(",") | ForEach-Object { $_.Trim() }
    $sheetNames = $sheetNames | Where-Object { $excludeList -notcontains $_ }
}

foreach ($sheet in $sheetNames) {

    Write-Host ""
    Write-Host "===================="
    Write-Host "$sheet 作成開始"
    Write-Host "===================="

    $companyWork = Join-Path $workPath $sheet
    New-Item $companyWork -ItemType Directory -Force | Out-Null

    $copyLog = @()

    $rows = Import-Excel -Path $configPath -WorksheetName $sheet

    foreach ($row in $rows) {

        $source = $row.'取得元（フルパス）'

        if (!$source) {
            continue
        }

        if ($env:GENERATE_SOURCE_BASE -and !([System.IO.Path]::IsPathRooted($source))) {
            $source = Join-Path $env:GENERATE_SOURCE_BASE $source
        }

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
                if ($row.含める形式 -and !($relative -like $row.含める形式)) {
                    return
                }

                # 除外する形式
                if ($row.除外する形式) {
                    foreach ($exclude in $row.除外する形式.Split(",")) {
                        if ($relative -like "*$($exclude.Trim())*") {
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
        Write-Host "$zip 作成完了"

        # ログ出力（ZIP単位）
        $logPath = Join-Path $logBasePath "$($env:GENERATE_LOG_PREFIX)$sheet.log"
        $logLines = @()
        $logLines += "# コピー結果"
        $logLines += $copyLog
        $logLines += ""
        $logLines += "# 最終結果"
        $logLines += $sheet
        $logLines += (Get-TreeLines -Path $companyWork)
        $logLines | Out-File -FilePath $logPath -Encoding Default
        Write-Host "$logPath 作成完了"
    } else {
        Write-Host "$sheet ：対象ファイルが無いためZIPを作成しませんでした"
    }
}

Write-Host ""
Write-Host "全処理完了"
