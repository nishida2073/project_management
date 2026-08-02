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

        if ($row.利用 -eq "×") {
            continue
        }

        $source = $row.取得元フルパス

        if (!(Test-Path $source)) {
            Write-Host "存在しません：$source"
            continue
        }

        # ZIP配置先
        $zipTarget = $companyWork
        if ($row.ZIP配置先) {
            $zipTarget = Join-Path $companyWork $row.ZIP配置先
        }
        New-Item $zipTarget -ItemType Directory -Force | Out-Null

        # Folder処理
        if ($row.種別 -eq "Folder") {

            $sourceTrimmed = $source.TrimEnd('\')

            Get-ChildItem $source -Recurse | ForEach-Object {

                $relative = $_.FullName.Substring($sourceTrimmed.Length).TrimStart('\')

                # Include判定
                if ($row.Include -and !($relative -like $row.Include)) {
                    return
                }

                # Exclude判定
                if ($row.Exclude) {
                    foreach ($exclude in $row.Exclude.Split(",")) {
                        if ($relative -like "*$($exclude.Trim())*") {
                            return
                        }
                    }
                }

                if (!$_.PSIsContainer) {
                    $destination = Join-Path $zipTarget $relative
                    New-Item (Split-Path $destination -Parent) -ItemType Directory -Force | Out-Null
                    Copy-Item $_.FullName $destination -Force
                }
            }

        }
        # File処理
        elseif ($row.種別 -eq "File") {

            $fileName = Split-Path $source -Leaf
            if ($row.ZIP名) {
                $fileName = $row.ZIP名
            }

            Copy-Item $source (Join-Path $zipTarget $fileName) -Force
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
