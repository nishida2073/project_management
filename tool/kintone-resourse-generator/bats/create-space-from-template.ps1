# =========================================
# スペーステンプレートから新しいスペースを作成する
# =========================================

param(
    [string]$TemplateId,
    [string]$SpaceName,
    [string]$BaseUrl,
    [string]$LogRoot,
    [string]$KintoneLogin,
    [string]$KintonePassword
)

$libraryDir = Join-Path (Split-Path $MyInvocation.MyCommand.Path) "library"
Get-ChildItem -Path $libraryDir -Filter *.ps1 -Recurse | ForEach-Object {
    . $_.FullName
}

if (-not $TemplateId) {
    Write-MessageError "TemplateId を指定してください"
    exit 1
}
if (-not $SpaceName) {
    Write-MessageError "SpaceName を指定してください"
    exit 1
}

$logFilePath = New-WorkerLogPath -LogRoot $LogRoot -Prefix "createspace_$SpaceName"

$script:exitCode = 0
$script:newSpaceId = $null

& {
    $authorization = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("${KintoneLogin}:${KintonePassword}"))

    $newSpaceId = $null
    try {
        $newSpaceId = New-KintoneSpaceFromTemplate -BaseUrl $BaseUrl -Authorization $authorization -TemplateId $TemplateId -Name $SpaceName -AdminLogin $KintoneLogin
    } catch {
        Write-MessageError "スペース作成に失敗しました: $($_.Exception.Message)"
        $script:exitCode = 1
        return
    }

    $script:newSpaceId = $newSpaceId
    Write-Message "" -Type "Info" -NoHeader
    Write-ApplyStepResult -ActionLabel "スペースを作成しました" -DetailLines @(
        "　スペースID: $newSpaceId"
        "　スペース名：$SpaceName"
    )
    Write-Message "　SPACE_ID=$newSpaceId" -Type "Info" -NoHeader -Hidden
} *>&1 | Tee-Object -FilePath $logFilePath
ConvertTo-Utf8LogFile -Path $logFilePath

Write-MessageComplete "ログを出力しました: $logFilePath"
exit $script:exitCode
