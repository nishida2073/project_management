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
    Write-Message "DOWNLOAD_SITE_URL と DOWNLOAD_SITE_PATH と DOWNLOAD_SITE_TENANT_ID を set-env.bat で設定してください" -ForegroundColor Red
    exit 1
}

$localPath = $env:DOWNLOAD_LOCAL_PATH
$logPath = $env:COMMON_LOG_PATH
New-Item -ItemType Directory -Path $logPath -Force | Out-Null

$downloadLog = @()

$az = Get-AzureCliPath
$token = Get-GraphToken -Az $az -TenantId $tenantId
$headers = @{ Authorization = "Bearer $token" }

$siteId = Resolve-GraphSiteId -Headers $headers -SiteUrl $siteUrl

$folderParts = $sitePath -split '/'
$relativeFolder = ($folderParts | Select-Object -Skip 1) -join '/'
$encodedRelativeFolder = Get-EncodedSitePath $relativeFolder

$startUri = if ($relativeFolder) {
    "https://graph.microsoft.com/v1.0/sites/$siteId/drive/root:/${encodedRelativeFolder}"
} else {
    "https://graph.microsoft.com/v1.0/sites/$siteId/drive/root"
}
$startItem = Invoke-GraphGet -Headers $headers -Uri $startUri

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
                Write-Message "操作中：$($item.Name)"
                try {
                    Invoke-WebRequest -Uri $item.'@microsoft.graph.downloadUrl' -OutFile $dest -UseBasicParsing
                    $script:downloadLog += "$RelativePath/$($item.Name) -> $dest"
                } catch {
                    $script:downloadLog += "$RelativePath/$($item.Name) -> エラー: $($_.Exception.Message)"
                }
            } elseif ($item.folder) {
                Get-GraphChildrenRecursive -ItemId $item.id -LocalFolder (Join-Path $LocalFolder $item.Name) -RelativePath "$RelativePath/$($item.Name)"
            }
        }
        $uri = $page.'@odata.nextLink'
    }
}

Get-GraphChildrenRecursive -ItemId $startItem.id -LocalFolder $localPath -RelativePath $sitePath

$endTime = Get-Date
$logFilePath = Write-RunLogFile -LogPath $logPath -LogFileName "$($env:DOWNLOAD_LOG_PREFIX)$(Get-ClientLogSegment)$(Split-Path $sitePath -Leaf).log" `
    -StartTime $startTime -EndTime $endTime `
    -ResultSectionTitle "ダウンロード結果" -ResultLines $downloadLog `
    -TreeRootPath $localPath
Show-LogFileContent -Path $logFilePath
