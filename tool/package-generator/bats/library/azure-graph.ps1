# =========================================
# 共通処理（Azure CLI / Microsoft Graph 関連）
# =========================================
# 各ワーカースクリプトが使うAzure CLI認証・Microsoft Graph API呼び出し・
# SharePointサイト/パス解決の共通処理。

function Get-AzureCliPath {
    $az = (Get-Command az.cmd -ErrorAction SilentlyContinue).Source
    if (!$az) {
        $az = "C:\Program Files\Microsoft SDKs\Azure\CLI2\wbin\az.cmd"
    }
    if (!(Test-Path $az)) {
        Write-Message "Azure CLIが見つかりません。以下でインストールしてください：" -ForegroundColor Red -Type "Info" -NoHeader
        Write-Message "  winget install --id Microsoft.AzureCLI" -ForegroundColor Red -Type "Info" -NoHeader
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
        Write-Message "サインインが必要です。表示されるURLとコードでログインしてください。" -ForegroundColor Cyan -Type "Info" -NoHeader
        Write-Message "" -Type "Info" -NoHeader

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
                Write-Message "URL: $($Matches.url)" -ForegroundColor Cyan -Type "Info" -NoHeader
                Write-Message "コード：$($Matches.code)" -ForegroundColor Cyan -Type "Info" -NoHeader
                Write-Message "" -Type "Info" -NoHeader
                $shown = $true
            }
        }
        $loginProc.WaitForExit()

        $out = & $Az account get-access-token --resource "https://graph.microsoft.com" --tenant $TenantId 2>$null
    }
    if (!$out) {
        Write-Message "トークンの取得に失敗しました" -ForegroundColor Red -Type "Info" -NoHeader
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

function Test-NameMatchesPatterns {
    param([string]$Name, [string[]]$Patterns)
    foreach ($pattern in $Patterns) {
        if ($Name -like $pattern) {
            return $true
        }
    }
    return $false
}

function Get-EncodedSitePath {
    param([string]$Path)
    return ($Path -split '/' | ForEach-Object { [System.Uri]::EscapeDataString($_) }) -join '/'
}
