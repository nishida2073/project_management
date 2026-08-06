# =========================================
# Teams/SharePointファイル取得ツール（Azure CLI + Microsoft Graph版）
# =========================================
# PnP.PowerShellの既定アプリがテナントで許可されていない環境向けに、
# 既にテナントで許可されているAzure CLIでトークンを取得し、
# Microsoft Graph APIで直接ファイルを取得する。

$scriptDir = Split-Path $MyInvocation.MyCommand.Path
. (Join-Path $scriptDir "common.ps1")

$siteUrl = $env:DOWNLOAD_SITE_URL
$sitePath = $env:DOWNLOAD_SITE_PATH
$tenantId = $env:DOWNLOAD_SITE_TENANT_ID

if (!$siteUrl -or !$sitePath -or !$tenantId) {
    Write-Host "DOWNLOAD_SITE_URL と DOWNLOAD_SITE_PATH と DOWNLOAD_SITE_TENANT_ID を set-env.bat で設定してください"
    exit 1
}

$sourcePath = $env:GENERATE_SOURCE_PATH
$localPath = if ([System.IO.Path]::IsPathRooted($env:DOWNLOAD_LOCAL_PATH)) { $env:DOWNLOAD_LOCAL_PATH } else { Join-Path $sourcePath $env:DOWNLOAD_LOCAL_PATH }
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
                Write-Host "取得：$($item.Name)"
                $script:downloadLog += "$RelativePath/$($item.Name) -> $dest"
            } elseif ($item.folder) {
                Get-GraphChildrenRecursive -ItemId $item.id -LocalFolder (Join-Path $LocalFolder $item.Name) -RelativePath "$RelativePath/$($item.Name)"
            }
        }
        $uri = $page.'@odata.nextLink'
    }
}

Write-Host ""
Write-Host "取得開始：$sitePath -> $localPath"
Get-GraphChildrenRecursive -ItemId $startItem.id -LocalFolder $localPath -RelativePath $sitePath

$logFilePath = Join-Path $logPath "$($env:DOWNLOAD_LOG_PREFIX)$(Split-Path $localPath -Leaf).log"
$logLines = @()
$logLines += "# 取得結果"
$logLines += $downloadLog
$logLines += ""
$logLines += "# フォルダ構成"
$logLines += (Split-Path $localPath -Leaf)
$logLines += (Get-TreeLines -Path $localPath)
$logLines | Out-File -FilePath $logFilePath -Encoding Default

Write-Host ""
Write-Host "取得完了：$localPath"
Write-Host "$logFilePath 作成完了"