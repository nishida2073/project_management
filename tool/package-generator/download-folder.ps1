# =========================================
# Teams/SharePointファイル取得ツール（Azure CLI + Microsoft Graph版）
# =========================================
# PnP.PowerShellの既定アプリがテナントで許可されていない環境向けに、
# 既にテナントで許可されているAzure CLIでトークンを取得し、
# Microsoft Graph APIで直接ファイルを取得する。

$basePath = Split-Path $MyInvocation.MyCommand.Path
. (Join-Path $basePath "common.ps1")

$siteUrl = $env:DOWNLOAD_SITE_URL
$folder = $env:DOWNLOAD_FOLDER
$tenantId = $env:DOWNLOAD_TENANT_ID

if (!$siteUrl -or !$folder -or !$tenantId) {
    Write-Host "DOWNLOAD_SITE_URL と DOWNLOAD_FOLDER と DOWNLOAD_TENANT_ID を set-env.bat で設定してください"
    exit 1
}

$sourceBase = if ($env:GENERATE_SOURCE_BASE) { $env:GENERATE_SOURCE_BASE } else { $basePath }
$localDest = if ($env:DOWNLOAD_LOCAL_DEST) { if ([System.IO.Path]::IsPathRooted($env:DOWNLOAD_LOCAL_DEST)) { $env:DOWNLOAD_LOCAL_DEST } else { Join-Path $sourceBase $env:DOWNLOAD_LOCAL_DEST } } else { Join-Path $sourceBase (Split-Path $folder -Leaf) }
$logBasePath = if ($env:COMMON_LOG_PATH) { $env:COMMON_LOG_PATH } else { Join-Path $basePath "log" }
New-Item -ItemType Directory -Path $logBasePath -Force | Out-Null

$downloadLog = @()

$az = Get-AzureCliPath
$token = Get-GraphToken -Az $az -TenantId $tenantId
$headers = @{ Authorization = "Bearer $token" }

# --- サイトIDの解決 ---
$siteId = Resolve-GraphSiteId -Headers $headers -SiteUrl $siteUrl

# --- フォルダパスの解決（先頭のドキュメントライブラリ名を除いた残りが既定のdriveのroot以下のパスになる） ---
$folderParts = $folder -split '/'
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
Write-Host "取得開始：$folder -> $localDest"
Get-GraphChildrenRecursive -ItemId $startItem.id -LocalFolder $localDest -RelativePath $folder

$logPath = Join-Path $logBasePath "$($env:DOWNLOAD_LOG_PREFIX)$(Split-Path $localDest -Leaf).log"
$logLines = @()
$logLines += "# 取得結果"
$logLines += $downloadLog
$logLines += ""
$logLines += "# フォルダ構成"
$logLines += (Split-Path $localDest -Leaf)
$logLines += (Get-TreeLines -Path $localDest)
$logLines | Out-File -FilePath $logPath -Encoding Default

Write-Host ""
Write-Host "取得完了：$localDest"
Write-Host "$logPath 作成完了"