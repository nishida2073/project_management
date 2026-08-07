# =========================================
# Teams/SharePointファイル取得ツール（Azure CLI + Microsoft Graph版）
# =========================================
# PnP.PowerShellの既定アプリがテナントで許可されていない環境向けに、
# 既にテナントで許可されているAzure CLIでトークンを取得し、
# Microsoft Graph APIで直接ファイルを取得する。

$scriptDir = Split-Path $MyInvocation.MyCommand.Path
. (Join-Path $scriptDir "common.ps1")
$startTime = Get-Date

$siteUrl = $env:DOWNLOAD_SITE_URL
$sitePath = $env:DOWNLOAD_SITE_PATH
$tenantId = $env:DOWNLOAD_SITE_TENANT_ID

if (!$siteUrl -or !$sitePath -or !$tenantId) {
    Write-Host "DOWNLOAD_SITE_URL と DOWNLOAD_SITE_PATH と DOWNLOAD_SITE_TENANT_ID を set-env.bat で設定してください"
    exit 1
}

$localPath = $env:DOWNLOAD_LOCAL_PATH
$logPath = $env:COMMON_LOG_PATH
New-Item -ItemType Directory -Path $logPath -Force | Out-Null

$downloadLog = @()

$az = Get-AzureCliPath
$token = Get-GraphToken -Az $az -TenantId $tenantId
$headers = @{ Authorization = "Bearer $token" }

# --- サイトIDの解決 ---
$siteId = Resolve-GraphSiteId -Headers $headers -SiteUrl $siteUrl

# --- フォルダパスの解決（先頭のドキュメントライブラリ名を除いた残りが既定のdriveのroot以下のパスになる） ---
$folderParts = $sitePath -split '/'
$relativeFolder = ($folderParts | Select-Object -Skip 1) -join '/'
$encodedRelativeFolder = Get-EncodedSitePath $relativeFolder

$startUri = if ($relativeFolder) {
    "https://graph.microsoft.com/v1.0/sites/$siteId/drive/root:/${encodedRelativeFolder}"
} else {
    "https://graph.microsoft.com/v1.0/sites/$siteId/drive/root"
}
$startItem = Invoke-GraphGet -Headers $headers -Uri $startUri

# --- 再帰ダウンロード ---
function Get-GraphChildrenRecursive {
    param(
        [string]$ItemId,
        [string]$LocalFolder,
        [string]$RelativePath
    )

    New-Item -ItemType Directory -Path $LocalFolder -Force | Out-Null

    $uri = "https://graph.microsoft.com/v1.0/sites/$siteId/drive/items/$ItemId/children"
    while ($uri) {
        $page = Invoke-GraphGet -Headers $headers -Uri $uri
        foreach ($item in $page.value) {
            if ($item.file) {
                $dest = Join-Path $LocalFolder $item.Name
                Invoke-WebRequest -Uri $item.'@microsoft.graph.downloadUrl' -OutFile $dest -UseBasicParsing
                Write-Host "$($item.Name)"
                $script:downloadLog += "$RelativePath/$($item.Name) -> $dest"
            } elseif ($item.folder) {
                Get-GraphChildrenRecursive -ItemId $item.id -LocalFolder (Join-Path $LocalFolder $item.Name) -RelativePath "$RelativePath/$($item.Name)"
            }
        }
        $uri = $page.'@odata.nextLink'
    }
}

Write-Host "# ダウンロード開始"
Write-Host "$sitePath -> $localPath"
Get-GraphChildrenRecursive -ItemId $startItem.id -LocalFolder $localPath -RelativePath $sitePath

$endTime = Get-Date
$logFilePath = Join-Path $logPath "$($env:DOWNLOAD_LOG_PREFIX)$(Split-Path $sitePath -Leaf).log"
$logLines = @()
$logLines += "# 実行情報"
$logLines += "バッチ名: $($env:BATCH_NAME)"
$logLines += "開始時刻: $($startTime.ToString('yyyy/MM/dd HH:mm:ss'))"
$logLines += "終了時刻: $($endTime.ToString('yyyy/MM/dd HH:mm:ss'))"
$logLines += ""
$logLines += "# ダウンロード結果"
$logLines += $downloadLog
$logLines += ""
$logLines += "# フォルダ構成"
$logLines += (Split-Path $localPath -Leaf)
$logLines += (Get-TreeLines -Path $localPath)
Write-LogFile -Path $logFilePath -Lines $logLines

Write-Host ""
Write-Host "# ダウンロード完了"
