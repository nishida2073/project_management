# =========================================
# 共通処理（Azure CLI / Microsoft Graph 関連）
# =========================================
# generate-package.ps1 / download-folder.ps1 / upload-folder.ps1 で共通して使う関数をまとめたもの。
# 各スクリプトの先頭でドットソース（. "パス\common.ps1"）して読み込む。

[System.Net.ServicePointManager]::SecurityProtocol = [System.Net.SecurityProtocolType]::Tls12

$cp932 = [System.Text.Encoding]::GetEncoding(932)
$defaultClientLabel = "デフォルト"

function Write-LogFile {
    param(
        [string]$Path,
        [string[]]$Lines
    )
    [System.IO.File]::WriteAllLines($Path, $Lines, $cp932)
}

function Get-ClientLogSegment {
    if ($env:CLIENT_NAME) {
        return "$($env:CLIENT_NAME)_"
    }
    return "${defaultClientLabel}_"
}

function Get-ClientLogHeaderLines {
    if ($env:CLIENT_NAME) {
        return @("クライアント: $($env:CLIENT_NAME)")
    }
    return @("クライアント: $defaultClientLabel")
}

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

function Get-AzureCliPath {
    $az = (Get-Command az.cmd -ErrorAction SilentlyContinue).Source
    if (!$az) {
        $az = "C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd"
    }
    if (!(Test-Path $az)) {
        Write-Host "Azure CLIが見つかりません。以下でインストールしてください："
        Write-Host "  winget install --id Microsoft.AzureCLI"
        exit 1
    }
    return $az
}

function Get-GraphToken {
    param(
        [string]$Az,
        [string]$TenantId
    )

    $out = & $Az account get-access-token --resource "https://graph.microsoft.com" --tenant $TenantId 2>$null
    if ($LASTEXITCODE -ne 0 -or !$out) {
        Write-Host "サインインが必要です。表示されるURLとコードでログインしてください。"
        Write-Host ""

        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = "cmd.exe"
        $psi.Arguments = "/c ""`"$Az`" login --tenant $TenantId --scope https://graph.microsoft.com/.default --use-device-code --allow-no-subscriptions 2>&1"""
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.CreateNoWindow = $true

        $loginProc = New-Object System.Diagnostics.Process
        $loginProc.StartInfo = $psi
        $loginProc.Start() | Out-Null

        $shown = $false
        while (!$loginProc.StandardOutput.EndOfStream) {
            $line = $loginProc.StandardOutput.ReadLine()
            if (!$shown -and $line -match "open the page (?<url>\S+)\s+and enter the code (?<code>[A-Z0-9\-]+)") {
                Write-Host "URL: $($Matches.url)"
                Write-Host "コード：$($Matches.code)"
                Write-Host ""
                $shown = $true
            }
        }
        $loginProc.WaitForExit()

        $out = & $Az account get-access-token --resource "https://graph.microsoft.com" --tenant $TenantId 2>$null
    }
    if (!$out) {
        Write-Host "トークンの取得に失敗しました"
        exit 1
    }
    return ($out | Out-String | ConvertFrom-Json).accessToken
}

function Invoke-GraphGet {
    param(
        [hashtable]$Headers,
        [string]$Uri
    )
    $resp = Invoke-WebRequest -Uri $Uri -Headers $Headers -Method Get -UseBasicParsing
    return $resp.Content | ConvertFrom-Json
}

function Invoke-GraphPost {
    param(
        [hashtable]$Headers,
        [string]$Uri,
        [string]$Body
    )
    $resp = Invoke-WebRequest -Uri $Uri -Headers $Headers -Method Post -Body $Body -ContentType "application/json" -UseBasicParsing
    return $resp.Content | ConvertFrom-Json
}

function Resolve-GraphSiteId {
    param(
        [hashtable]$Headers,
        [string]$SiteUrl
    )
    $siteUri = [Uri]$SiteUrl
    $sitePath = $siteUri.AbsolutePath.TrimStart('/')
    $site = Invoke-GraphGet -Headers $Headers -Uri "https://graph.microsoft.com/v1.0/sites/$($siteUri.Host):/$sitePath"
    return $site.id
}

function Get-EncodedSitePath {
    param([string]$Path)
    return ($Path -split '/' | ForEach-Object { [System.Uri]::EscapeDataString($_) }) -join '/'
}