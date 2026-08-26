# =========================================
# クライアント用パッケージ定義ファイル生成
# =========================================
# config\package_definition.xlsx をコピーして config\package_definition_<クライアント名>.xlsx を作成し、
# 先頭シートの「取得元（フルパス）」列に DOWNLOAD_LOCAL_PATH 配下のファイルを再帰的に一覧化する。

$scriptDir = Split-Path $MyInvocation.MyCommand.Path
. (Join-Path $scriptDir "common.ps1")
$basePath = Split-Path $scriptDir -Parent

$clientName = $env:CLIENT_NAME
$downloadLocalPath = $env:DOWNLOAD_LOCAL_PATH

if (!$clientName) {
    Write-Host "CLIENT_NAME が指定されていません（generate-config.bat client:<クライアント名> のように指定してください）"
    exit 1
}

if (!$downloadLocalPath) {
    Write-Host "DOWNLOAD_LOCAL_PATH を set-env.bat で設定してください"
    exit 1
}

if (!(Test-Path -LiteralPath $downloadLocalPath)) {
    Write-Host "存在しません：$downloadLocalPath"
    exit 1
}

$templatePath = Join-Path $basePath "config\package_definition.xlsx"
if (!(Test-Path -LiteralPath $templatePath)) {
    Write-Host "テンプレートが見つかりません：$templatePath"
    exit 1
}

$destPath = Join-Path (Split-Path $templatePath -Parent) "package_definition_$clientName.xlsx"

if ((Test-Path -LiteralPath $destPath) -and $env:FORCE -ne "1") {
    Write-Host "すでに存在します：$destPath"
    Write-Host "上書きする場合は force:1 を指定してください"
    exit 1
}

if (!(Get-Module -ListAvailable ImportExcel)) {
    Write-Host "ImportExcelをインストールします"
    Install-Module ImportExcel -Scope CurrentUser -Force
}

Copy-Item -LiteralPath $templatePath -Destination $destPath -Force

$prevEap = $ErrorActionPreference
try {
    $ErrorActionPreference = "Stop"

    $pkg = Open-ExcelPackage -Path $destPath
    try {
        $ws = $pkg.Workbook.Worksheets[1]

        if (!$ws.Dimension) {
            throw "先頭シート（$($ws.Name)）にヘッダー行がありません"
        }

        $headerRow = $ws.Dimension.Start.Row
        $lastCol = $ws.Dimension.End.Column

        $colMap = @{}
        for ($c = 1; $c -le $lastCol; $c++) {
            $header = $ws.Cells[$headerRow, $c].Text
            if ($header) {
                $colMap[$header] = $c
            }
        }

        if (!$colMap.ContainsKey("取得元（フルパス）")) {
            throw "先頭シート（$($ws.Name)）に「取得元（フルパス）」列が見つかりません"
        }
        $sourceCol = $colMap["取得元（フルパス）"]
        $noCol = $colMap["No"]

        if ($ws.Dimension.End.Row -gt $headerRow) {
            for ($r = $headerRow + 1; $r -le $ws.Dimension.End.Row; $r++) {
                for ($c = 1; $c -le $lastCol; $c++) {
                    $ws.Cells[$r, $c].Value = $null
                }
            }
        }

        $downloadLocalPathTrimmed = $downloadLocalPath.TrimEnd('\')
        $files = @(Get-ChildItem -LiteralPath $downloadLocalPath -Recurse -File)

        $row = $headerRow + 1
        foreach ($file in $files) {
            $relativePath = ".\" + $file.FullName.Substring($downloadLocalPathTrimmed.Length).TrimStart('\')
            $ws.Cells[$row, $sourceCol].Value = $relativePath
            if ($noCol) {
                $ws.Cells[$row, $noCol].Value = ($row - $headerRow)
            }
            $row++
        }

        Write-Host "作成しました：$destPath（$($files.Count)件）"
    } finally {
        Close-ExcelPackage $pkg
    }
} catch {
    Write-Host "処理に失敗しました：$($_.Exception.Message)"
    exit 1
} finally {
    $ErrorActionPreference = $prevEap
}
