# =========================================
# 個社別ZIP生成ツール
# =========================================

$basePath = Split-Path $MyInvocation.MyCommand.Path
$configPath = Join-Path $basePath "config\package_definition.xlsx"
$workPath = Join-Path $basePath "work"
$outputPath = Join-Path $basePath "output"

# 初期化
Remove-Item $workPath -Recurse -Force -ErrorAction SilentlyContinue
New-Item $workPath -ItemType Directory | Out-Null
New-Item $outputPath -ItemType Directory -Force | Out-Null

# Excelモジュール確認
if (!(Get-Module -ListAvailable ImportExcel)) {
    Write-Host "ImportExcelをインストールします"
    Install-Module ImportExcel -Scope CurrentUser -Force
}

# Excelシート取得
$excel = Get-ExcelSheetInfo $configPath

foreach ($sheet in $excel.Name) {

    Write-Host ""
    Write-Host "===================="
    Write-Host "$sheet 作成開始"
    Write-Host "===================="

    $companyWork = Join-Path $workPath $sheet
    New-Item $companyWork -ItemType Directory -Force | Out-Null

    $rows = Import-Excel -Path $configPath -WorksheetName $sheet

    foreach ($row in $rows) {

        $source = $row.'取得元（フルパス）'

        if (!$source) {
            continue
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
                }
            }

        } else {

            # ファイル処理
            $fileName = Split-Path $source -Leaf
            Copy-Item $source (Join-Path $storeRoot $fileName) -Force
        }
    }

    # ZIP作成
    $zip = Join-Path $outputPath "$sheet.zip"
    Remove-Item $zip -Force -ErrorAction SilentlyContinue

    $zipItems = Get-ChildItem -LiteralPath $companyWork
    if ($zipItems) {
        Compress-Archive -LiteralPath $zipItems.FullName -DestinationPath $zip
        Write-Host "$zip 作成完了"
    } else {
        Write-Host "$sheet ：対象ファイルが無いためZIPを作成しませんでした"
    }
}

Write-Host ""
Write-Host "全処理完了"
