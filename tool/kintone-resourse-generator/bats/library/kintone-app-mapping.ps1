function Group-RowsBySpaceId {
    param([Parameter(Mandatory)][array]$Rows)
    return $Rows | Group-Object -Property 'スペースID'
}

function Expand-KintonePlaceholder {
    param([string]$Value, [Parameter(Mandatory)][string]$ConfigName)
    if (-not $Value) { return $Value }
    return $Value.Replace('{PH}', $ConfigName)
}

function Get-AppNameSimilarity {
    param([string]$A, [string]$B)
    if (-not $A -or -not $B) { return 0.0 }
    if ($A.Contains($B) -or $B.Contains($A)) { return 1.0 }
    return 0.0
}

function Get-AppNameMapping {
    param(
        [Parameter(Mandatory)][array]$TemplateApps,
        [Parameter(Mandatory)][array]$DownloadApps
    )

    $candidates = New-Object System.Collections.Generic.List[psobject]
    for ($ti = 0; $ti -lt $TemplateApps.Count; $ti++) {
        for ($di = 0; $di -lt $DownloadApps.Count; $di++) {
            $similarity = Get-AppNameSimilarity -A "$($TemplateApps[$ti].'アプリ名')" -B "$($DownloadApps[$di].'アプリ名')"
            $candidates.Add([PSCustomObject]@{ TemplateIndex = $ti; DownloadIndex = $di; Similarity = $similarity })
        }
    }

    $usedTemplateIndexes = @{}
    $usedDownloadIndexes = @{}
    $result = New-Object System.Collections.Generic.List[psobject]

    foreach ($c in ($candidates | Sort-Object -Property Similarity -Descending)) {
        if ($usedTemplateIndexes.ContainsKey($c.TemplateIndex) -or $usedDownloadIndexes.ContainsKey($c.DownloadIndex)) { continue }
        if ($c.Similarity -eq 0) { continue }
        $usedTemplateIndexes[$c.TemplateIndex] = $true
        $usedDownloadIndexes[$c.DownloadIndex] = $true
        $result.Add([PSCustomObject]@{
            TemplateAppName = $TemplateApps[$c.TemplateIndex].'アプリ名'
            DownloadAppId   = $DownloadApps[$c.DownloadIndex].'アプリID'
            DownloadAppName = $DownloadApps[$c.DownloadIndex].'アプリ名'
            Status          = "対応"
        })
    }

    for ($ti = 0; $ti -lt $TemplateApps.Count; $ti++) {
        if ($usedTemplateIndexes.ContainsKey($ti)) { continue }
        $result.Add([PSCustomObject]@{
            TemplateAppName = $TemplateApps[$ti].'アプリ名'
            DownloadAppId   = $null
            DownloadAppName = $null
            Status          = "対応なし（新スペース側に見つかりません）"
        })
    }
    for ($di = 0; $di -lt $DownloadApps.Count; $di++) {
        if ($usedDownloadIndexes.ContainsKey($di)) { continue }
        $result.Add([PSCustomObject]@{
            TemplateAppName = $null
            DownloadAppId   = $DownloadApps[$di].'アプリID'
            DownloadAppName = $DownloadApps[$di].'アプリ名'
            Status          = "対応なし（テンプレート側に見つかりません）"
        })
    }
    return $result
}
