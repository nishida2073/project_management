# =========================================
# スペーステンプレートから新しいスペースを作成する
# =========================================

param(
    [string]$LogNamePrefix,
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

if (-not $SpaceName) {
    Write-MessageError "SpaceName を指定してください。"
    exit 1
}

$logFilePath = New-WorkerLogPath -LogRoot $LogRoot -Prefix "${LogNamePrefix}_$SpaceName"

$script:exitCode = 0
$psParams = $PSBoundParameters
try {
    & {
        try {
            $psParams.Keys | ForEach-Object { Write-Message $psParams[$_] -VarName "param:$_" -Type "Info" -ForegroundColor Blue }

            if (-not $TemplateId) {
                throw "TemplateId を指定してください"
            }

            $authorization = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("${KintoneLogin}:${KintonePassword}"))

            try {
                $newSpaceId = New-KintoneSpaceFromTemplate -BaseUrl $BaseUrl -Authorization $authorization -TemplateId $TemplateId -Name $SpaceName -AdminLogin $KintoneLogin
            } catch {
                throw "スペース作成に失敗しました: $($_.Exception.Message)"
            }

            Write-ApplyStepResult -ActionLabel "スペースを作成しました" -DetailLines @(
                "　スペースID: $newSpaceId"
                "　スペース名：$SpaceName"
            )
            Write-Message "　SPACE_ID=$newSpaceId" -Type "Info" -NoHeader -Hidden
        } catch {
            Write-MessageError "実行エラー: $($error[0])"
            $script:exitCode = 1
        }
    } *>&1 | Tee-Object -FilePath $logFilePath
} finally {
    ConvertTo-Utf8LogFile -Path $logFilePath
    Write-MessageComplete "ログを出力しました: $logFilePath"
}
exit $script:exitCode
