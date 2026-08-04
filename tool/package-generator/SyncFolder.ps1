# =========================================
# Teams/SharePointファイル取得ツール（Azure CLI + Microsoft Graph版）
# =========================================
# PnP.PowerShellの既定アプリがテナントで許可されていない環境向けに、
# 既にテナントで許可されているAzure CLIでトークンを取得し、
# Microsoft Graph APIで直接ファイルを取得する。

$basePath = Split-Path $MyInvocation.MyCommand.Path

$siteUrl = $env:SYNC_SITE_URL
$folder = $env:SYNC_FOLDER
$tenantId = $env:SYNC_TENANT_ID

if (!$siteUrl -or !$folder -or !$tenantId) {
    Write-Host "SYNC_SITE_URL と SYNC_FOLDER と SYNC_TENANT_ID を SetEnv.bat で設定してください"
    exit 1
}

$sourceBase = if ($env:GENERATE_SOURCE_BASE) { $env:GENERATE_SOURCE_BASE } else { $basePath }
$localDest = if ($env:SYNC_LOCAL_DEST) { if ([System.IO.Path]::IsPathRooted($env:SYNC_LOCAL_DEST)) { $env:SYNC_LOCAL_DEST } else { Join-Path $sourceBase $env:SYNC_LOCAL_DEST } } else { Join-Path $sourceBase (Split-Path $folder -Leaf) }
$logBasePath = if ($env:COMMON_LOG_PATH) { $env:COMMON_LOG_PATH } else { Join-Path $basePath "log" }
New-Item -ItemType Directory -Path $logBasePath -Force | Out-Null

$downloadLog = @()

# --- Azure CLI の場所を確認 ---
$az = (Get-Command az.cmd -ErrorAction SilentlyContinue).Source
if (!$az) {
    $az = "C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd"
}
if (!(Test-Path $az)) {
    Write-Host "Azure CLIが見つかりません。以下でインストールしてください："
    Write-Host "  winget install --id Microsoft.AzureCLI"
    exit 1
}

# --- Graph用トークン取得（未ログイン・期限切れなら device code でログイン） ---
function Get-GraphToken {
    $out = & $az account get-access-token --resource "https://graph.microsoft.com" --tenant $tenantId 2>$null
    if ($LASTEXITCODE -ne 0 -or !$out) {
        Write-Host "サインインが必要です。表示されるURLとコードでログインしてください。"
        & $az login --tenant $tenantId --scope "https://graph.microsoft.com/.default" --use-device-code --allow-no-subscriptions | Out-Null
        $out = & $az account get-access-token --resource "https://graph.microsoft.com" --tenant $tenantId 2>$null
    }
    if (!$out) {
        Write-Host "トークンの取得に失敗しました"
        exit 1
    }
    return ($out | Out-String | ConvertFrom-Json).accessToken
}

$token = Get-GraphToken
$headers = @{ Authorization = "Bearer $token" }

function Invoke-GraphGet($uri) {
    $resp = Invoke-WebRequest -Uri $uri -Headers $headers -Method Get -UseBasicParsing
    return $resp.Content | ConvertFrom-Json
}

# --- サイトIDの解決 ---
$siteUri = [Uri]$siteUrl
$sitePath = $siteUri.AbsolutePath.TrimStart('/')
$site = Invoke-GraphGet "https://graph.microsoft.com/v1.0/sites/$($siteUri.Host):/$sitePath"
$siteId = $site.id

# --- フォルダパスの解決（先頭のドキュメントライブラリ名を除いた残りが既定のdriveのroot以下のパスになる） ---
$folderParts = $folder -split '/'
$relativeFolder = ($folderParts | Select-Object -Skip 1) -join '/'
$encodedRelativeFolder = [System.Uri]::EscapeDataString($relativeFolder) -replace '%2F', '/'

$startUri = if ($relativeFolder) {
    "https://graph.microsoft.com/v1.0/sites/$siteId/drive/root:/${encodedRelativeFolder}"
} else {
    "https://graph.microsoft.com/v1.0/sites/$siteId/drive/root"
}
$startItem = Invoke-GraphGet $startUri

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
        $page = Invoke-GraphGet $uri
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

$logPath = Join-Path $logBasePath "$($env:SYNC_LOG_PREFIX)$(Split-Path $localDest -Leaf).log"
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