trap {
    Write-Host "エラー: $_"
    Write-Host $_.ScriptStackTrace
    Write-Host $_.Exception
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

[System.Windows.Forms.Application]::EnableVisualStyles()
[System.Windows.Forms.Application]::SetCompatibleTextRenderingDefault($false)

if ($MyInvocation.MyCommand.Path) {
    $rootPath = Split-Path $scriptDir -Parent
} else {
    $rootPath = Split-Path ([System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName)
}
$scriptDir = Join-Path $rootPath "bats"

$libraryDir = Join-Path $scriptDir "library"
Get-ChildItem -Path $libraryDir -Filter *.ps1 -Recurse | ForEach-Object {
    . $_.FullName
}

$env:GUI_LOG_MODE = "1"

$createTemplateBat = Join-Path $rootPath "create-template.bat"
$createSpaceFromTemplateBat = Join-Path $rootPath "create-space-from-template.bat"
$downloadKintoneResourcesBat = Join-Path $rootPath "download-kintone-resources.bat"
$generateConfigFromTemplateBat = Join-Path $rootPath "generate-config-from-template.bat"
$applyKintoneResourcesBat = Join-Path $rootPath "apply-kintone-resources.bat"
$checkKintoneResourcesBat = Join-Path $rootPath "check-kintone-resources.bat"

$commonEnvBat = Join-Path $scriptDir "common.bat"
$clientsDir = Join-Path $rootPath "clients"
$clientsTemplateDir = Join-Path $clientsDir "template"
$clientTemplateBat = Join-Path $clientsTemplateDir "client.bat"

function Get-GroupNames {
    if (!(Test-Path -LiteralPath $clientsDir)) { return @() }
    $names = Get-ChildItem -LiteralPath $clientsDir -Filter "*.bat" -File -ErrorAction SilentlyContinue | ForEach-Object {
        [System.IO.Path]::GetFileNameWithoutExtension($_.Name)
    }
    return @($names | Select-Object -Unique | Sort-Object)
}

function Get-KintoneOpenUrl {
    param($InputControls)
    $groupValue = Get-ComboBoxValue -SelectedItem $InputControls["TargetGroupName"].SelectedItem
    if (!$groupValue) { return $null }
    $kintoneBaseUrl = (Get-ResolvedVar -VarName "KintoneBaseUrl" -Path (Get-GroupBatPath $groupValue $clientsDir)).TrimEnd('/')
    if (!$kintoneBaseUrl) { return $null }
    if ($script:createdSpace -and $script:createdSpace.Group -eq $groupValue) {
        return "$kintoneBaseUrl/k/#/space/$($script:createdSpace.Id)"
    }
    return $kintoneBaseUrl
}

function Get-ButtonDefByBatchPath {
    param([string]$BatchPath)
    return $categoryDefs | ForEach-Object { $_.ButtonDefs } | Where-Object { $_.BatchPath -eq $BatchPath } | Select-Object -First 1
}

$noSelectOption = [PSCustomObject]@{ Text = "指定なし"; Value = "" }

$blankOptions = @([PSCustomObject]@{ Text = ""; Value = "" })
$categoryDefs = @(
    [PSCustomObject]@{
        Label = "スペース作成"
        ButtonDefs = @(
            [PSCustomObject]@{
                Label = "スペースの作成"
                Inputs = @(
                    [PSCustomObject]@{ Name = "TargetGroupName"; Label = "対象のグループ"; LabelWidth = 150; InputWidth = 200; Options = $blankOptions; Require = $true }
                    [PSCustomObject]@{ Name = "ConfigName"; Label = "スペース識別名"; LabelWidth = 150; InputWidth = 200; NewRow = $true; Require = $true }
                    [PSCustomObject]@{ Name = "SpaceTemplateId"; Label = "スペーステンプレートID"; LabelWidth = 150; InputWidth = 200; NewRow = $true; Require = $true }
                )
                BatchPath = $createSpaceFromTemplateBat
                ArgsFn = {
                    param($ic, $inputDefs)
                    $batArgs = @()
                    $nameMap = @{
                        "ConfigName" = "SpaceName"
                        "SpaceTemplateId" = "TemplateId"
                        "TargetGroupName" = "TargetGroupName"
                    }
                    foreach ($inputDef in $inputDefs) {
                        if (-not $ic.ContainsKey($inputDef.Name)) { continue }
                        $value = Get-InputValue -Control $ic[$inputDef.Name]
                        $paramName = if ($nameMap.ContainsKey($inputDef.Name)) { $nameMap[$inputDef.Name] } else { $inputDef.Name }
                        $batArgs += "-${paramName}:$value"
                    }
                    $batArgs
                }
                OutputPathFn = $null
                OpenTarget = { param($ic) Get-KintoneOpenUrl -InputControls $ic }
                OnSuccessFn = {
                    param($ic, $lastOutputLines)
                    $idLine = $lastOutputLines | Where-Object { $_ -match 'SPACE_ID=(\d+)' } | Select-Object -Last 1
                    if ($idLine -and $idLine -match 'SPACE_ID=(?<id>\d+)') {
                        $spaceId = $Matches.id
                        $downloadBd = Get-ButtonDefByBatchPath $downloadKintoneResourcesBat
                        $downloadBd.InputControls['SpaceId'].Text = $spaceId
                        $script:createdSpace = @{ Group = Get-ComboBoxValue -SelectedItem $ic["TargetGroupName"].SelectedItem; Id = $spaceId }
                    }
                }
                IncludeInBatch = $true;
            }
        )
    }
    [PSCustomObject]@{
        Label = "スペースダウンロード"
        ButtonDefs = @(
            [PSCustomObject]@{
                Label = "スペースのダウンロード"
                Inputs = @(
                    [PSCustomObject]@{ Name = "TargetGroupName"; Label = "対象のグループ"; LabelWidth = 150; InputWidth = 200; Options = $blankOptions; Require = $false }
                    [PSCustomObject]@{ Name = "ConfigName"; Label = "スペース識別名"; LabelWidth = 150; InputWidth = 200; NewRow = $true; Require = $true }
                    [PSCustomObject]@{ Name = "SpaceId"; Label = "スペースID"; LabelWidth = 150; InputWidth = 200; NewRow = $true; Require = $false }
                )
                BatchPath = $downloadKintoneResourcesBat
                ArgsFn = {
                    param($ic, $inputDefs)
                    $batArgs = @()
                    foreach ($inputDef in $inputDefs) {
                        if (-not $ic.ContainsKey($inputDef.Name)) { continue }
                        $value = Get-InputValue -Control $ic[$inputDef.Name]
                        $batArgs += "-$($inputDef.Name):$value"
                    }
                    $batArgs
                }
                OutputPathFn = { param($ic) Join-Path (Get-ResolvedVar "CommonDownloadPath" $commonEnvBat) "$($ic['ConfigName'].Text.Trim())_download.xlsx" }
                OpenTarget = { param($ic) Join-Path (Get-ResolvedVar "CommonDownloadPath" $commonEnvBat) "$($ic['ConfigName'].Text.Trim())_download.xlsx" }
            }
        )
    }
    [PSCustomObject]@{
        Label = "設定ファイル作成"
        ButtonDefs = @(
            [PSCustomObject]@{
                Label = "設定ファイルの作成"
                Inputs = @(
                    [PSCustomObject]@{ Name = "TargetGroupName"; Label = "対象のグループ"; LabelWidth = 150; InputWidth = 200; Options = $blankOptions; Require = $false }
                    [PSCustomObject]@{ Name = "ConfigName"; Label = "スペース識別名"; LabelWidth = 150; InputWidth = 200; NewRow = $true; Require = $true }
                    [PSCustomObject]@{ Name = "BaseTemplateName"; Label = "設定テンプレート名（基本）"; LabelWidth = 150; InputWidth = 200; Combo = $true; NewRow = $true; Require = $false }
                    [PSCustomObject]@{ Name = "CustomTemplateName"; Label = "設定テンプレート名（カスタム）"; LabelWidth = 150; InputWidth = 200; Combo = $true; NewRow = $true; Require = $false }
                )
                Validator = {
                    param($ic)
                    if ((Get-InputValue -Control $ic["BaseTemplateName"]) -or (Get-InputValue -Control $ic["CustomTemplateName"])) {
                        return $true 
                    }
                    [System.Windows.Forms.MessageBox]::Show("設定テンプレート名（基本）または設定テンプレート名（カスタム）のどちらかを指定してください。", "実行", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
                    return $false
                }
                BatchPath = $generateConfigFromTemplateBat
                ArgsFn = {
                    param($ic, $inputDefs)
                    $batArgs = @()
                    $nameMap = @{
                        "TargetGroupName" = "TargetGroupName"
                        "ConfigName" = "DownloadConfigName"
                        "BaseTemplateName" = "BaseTemplateConfigName"
                        "CustomTemplateName" = "CustomTemplateConfigName"
                    }
                    foreach ($inputDef in $inputDefs) {
                        if (-not $ic.ContainsKey($inputDef.Name)) { continue }
                        $value = Get-InputValue -Control $ic[$inputDef.Name]
                        $paramName = if ($nameMap.ContainsKey($inputDef.Name)) { $nameMap[$inputDef.Name] } else { $inputDef.Name }
                        $batArgs += "-${paramName}:$value"
                    }
                    $batArgs
                }
                OutputPathFn = { param($ic) Join-Path (Get-ResolvedVar "CommonConfigPath" $commonEnvBat) "$($ic['ConfigName'].Text.Trim())_config.xlsx" }
                OpenTarget = { param($ic) Join-Path (Get-ResolvedVar "CommonConfigPath" $commonEnvBat) "$($ic['ConfigName'].Text.Trim())_config.xlsx" }
            }
        )
    }
    [PSCustomObject]@{
        Label = "スペース更新"
        ButtonDefs = @(
            [PSCustomObject]@{
                Label = "スペースの更新"
                Inputs = @(
                    [PSCustomObject]@{ Name = "TargetGroupName"; Label = "対象のグループ"; LabelWidth = 150; InputWidth = 200; Options = $blankOptions; Require = $false }
                    [PSCustomObject]@{ Name = "ConfigName"; Label = "スペース識別名"; LabelWidth = 150; InputWidth = 200; NewRow = $true; Require = $true }
                )
                BatchPath = $applyKintoneResourcesBat
                ArgsFn = {
                    param($ic, $inputDefs)
                    $batArgs = @()
                    foreach ($inputDef in $inputDefs) {
                        if (-not $ic.ContainsKey($inputDef.Name)) { continue }
                        $value = Get-InputValue -Control $ic[$inputDef.Name]
                        $batArgs += "-$($inputDef.Name):$value"
                    }
                    $batArgs
                }
                OutputPathFn = $null
                OpenTarget = { param($ic) Get-KintoneOpenUrl -InputControls $ic }
            }
        )
    }
    [PSCustomObject]@{
        Label = "スペース確認"
        ButtonDefs = @(
            [PSCustomObject]@{
                Label = "スペースの確認"
                Inputs = @(
                    [PSCustomObject]@{ Name = "TargetGroupName"; Label = "対象のグループ"; LabelWidth = 150; InputWidth = 200; Options = $blankOptions; Require = $false }
                    [PSCustomObject]@{ Name = "ConfigName"; Label = "スペース識別名"; LabelWidth = 150; InputWidth = 200; NewRow = $true; Require = $true }
                )
                BatchPath = $checkKintoneResourcesBat
                ArgsFn = {
                    param($ic, $inputDefs)
                    $batArgs = @()
                    foreach ($inputDef in $inputDefs) {
                        if (-not $ic.ContainsKey($inputDef.Name)) { continue }
                        $value = Get-InputValue -Control $ic[$inputDef.Name]
                        $batArgs += "-$($inputDef.Name):$value"
                    }
                    $batArgs
                }
                OutputPathFn = { param($ic) Join-Path (Get-ResolvedVar "CommonCheckOutputPath" $commonEnvBat) "$($ic['ConfigName'].Text.Trim())_check.xlsx" }
                OpenTarget = { param($ic) Join-Path (Get-ResolvedVar "CommonCheckOutputPath" $commonEnvBat) "$($ic['ConfigName'].Text.Trim())_check.xlsx" }
            }
        )
    }
)

$form = New-Form -Title "kintoneリソース生成ツール" -Width 780 -Height 560 -MinWidth 600 -MinHeight 500 -CenterScreen
$script:currentProc = $null
$script:createdSpace = $null

$tabControl = New-TabControl
$tabRun = New-TabPage -Text "実行"

$tabLogs = New-TabPage -Text "ログ"
$tabSettings = New-TabPage -Text "設定"
$settingsSubTabControl = New-TabControl -Dock ([System.Windows.Forms.DockStyle]::Fill)

$tabSettingsCommon = New-TabPage -Text "共通"
$settingsSubTabControl.Controls.Add($tabSettingsCommon)

$tabSettingsGroup = New-TabPage -Text "グループ別"
$settingsSubTabControl.Controls.Add($tabSettingsGroup)

$tabSettings.Controls.Add($settingsSubTabControl)

$tabControl.Controls.AddRange(@($tabRun, $tabLogs, $tabSettings))
$form.Controls.Add($tabControl)


$execTabControl = New-TabControl -Dock ([System.Windows.Forms.DockStyle]::Fill)

$tabBatchRun = New-TabPage -Text "複数実行"
$execTabControl.Controls.Add($tabBatchRun)

$tabBatchAll = New-TabPage -Text "一括実行"
$execTabControl.Controls.Add($tabBatchAll)

$allStepDefs = @()
foreach ($cd in $categoryDefs) {
    foreach ($bd in $cd.ButtonDefs) {
        if ($bd.IncludeInBatch -ne $false) { $allStepDefs += $bd }
    }
}

$batchRunAllInputs = @(
    [PSCustomObject]@{ Name = "TargetGroupName"; Label = "対象のグループ"; LabelWidth = 150; InputWidth = 200; Options = $blankOptions; Require = $true },
    [PSCustomObject]@{ Name = "ConfigName"; Label = "スペース識別名"; LabelWidth = 150; InputWidth = 200; NewRow = $true; Require = $true },
    [PSCustomObject]@{ Name = "SpaceTemplateId"; Label = "スペーステンプレートID"; LabelWidth = 150; InputWidth = 200; NewRow = $true; Require = $true },
    [PSCustomObject]@{ Name = "BaseTemplateName"; Label = "設定テンプレート名（基本）"; LabelWidth = 150; InputWidth = 200; Combo = $true; NewRow = $true; Require = $false },
    [PSCustomObject]@{ Name = "CustomTemplateName"; Label = "設定テンプレート名（カスタム）"; LabelWidth = 150; InputWidth = 200; Combo = $true; NewRow = $true; Require = $false }
)

$batchTab = New-BatchRunTab -TabPage $tabBatchAll -ButtonDefs $allStepDefs -RunButtonText "実行" -ShowSteps $false `
    -Inputs $batchRunAllInputs -OnRunClick {
    param($controls, $statusLabel)
    Set-RunButtonsEnabled $false
    Set-StepStatus -Label $statusLabel -Text "実行中..."

    $exitCode = Invoke-ExecuteAll

    if ($exitCode -eq 0) {
        Set-StepStatus -Label $statusLabel -Text "成功" -State "成功"
    } elseif ($exitCode -eq 2) {
        Set-StepStatus -Label $statusLabel -Text "警告" -State "警告"
    } else {
        Set-StepStatus -Label $statusLabel -Text "失敗" -State "失敗"
    }

    Set-RunButtonsEnabled $true
}

$tabRun.Controls.Add($execTabControl)

$categoryTab = New-CategoryTabControl -CategoryDefs $categoryDefs -TabControl $execTabControl `
    -OnRunClick {
        param($bd)
        $ic = $bd.InputControls

        if ($bd.Inputs) {
            foreach ($inputDef in $bd.Inputs) {
                if ($inputDef.Require) {
                    $value = Get-InputValue -Control $ic[$inputDef.Name]
                    if (!$value) {
                        [System.Windows.Forms.MessageBox]::Show("$($inputDef.Label) を設定してください。", "実行", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
                        return 1
                    }
                }
            }
        }

        if ($bd.Validator -and -not (& $bd.Validator $ic)) { return 1 }

        Set-RunButtonsEnabled $false

        $lastOutputLines = New-Object System.Collections.Generic.List[string]
        $exitCode = Invoke-BatchStep -ButtonDef ([PSCustomObject]@{ BatchPath = $bd.BatchPath; Label = $bd.Label; StepStatusLabel = $bd.StepStatusLabel }) `
            -GetBatArgs { param($bd2) & $bd.ArgsFn $bd.InputControls $bd.Inputs } `
            -WorkingDirectory $rootPath -Form $form `
            -WriteLog { param($msg) Write-Log $msg } `
            -OnOutputLine { param($line) Write-Log $line; $lastOutputLines.Add($line) } `
            -CurrentProcessRef ([ref]$script:currentProc) `
            -DisplayLabel $bd.Label -StatusLabel $bd.StepStatusLabel

        if (($exitCode -eq 0 -or $exitCode -eq 2) -and $bd.OnSuccessFn) {
            & $bd.OnSuccessFn $bd.InputControls $lastOutputLines
        }

        Set-RunButtonsEnabled $true
    }


$txtLog = New-LogTextBox

Add-StackedDockedControls -Container $tabRun -ControlsTopToBottom @($execTabControl, $txtLog)

$allButtonDefs = @()
foreach ($cd in $categoryDefs) {
    $allButtonDefs += $cd.ButtonDefs
}

$logTabConditions = @(
    @{ PropertyName = "GroupCombo"; LabelText = "対象のグループ"; LabelWidth = 150; ComboWidth = 200; Options = $blankOptions }
    @{ PropertyName = "ConfigCombo"; LabelText = "スペース識別名"; LabelWidth = 150; ComboWidth = 200; Options = $blankOptions }
)

$logTab = New-LogTab -TabPage $tabLogs -ButtonDefs $allButtonDefs `
    -GetLogPathFn { Get-ResolvedVar "CommonLogPath" $commonEnvBat } `
    -Conditions $logTabConditions


function Update-GroupDropdowns {
    $allOption = [PSCustomObject]@{ Text = "すべて"; Value = "" }
    $groupNames = @(Get-GroupNames)

    $categoryDefs.ButtonDefs | Where-Object { $_.InputControls["TargetGroupName"] } | ForEach-Object {
        Update-ComboBoxItems -ComboBox $_.InputControls["TargetGroupName"] -Items $groupNames
    }

    $logItems = @($allOption) + $groupNames
    Update-ComboBoxItems -ComboBox $logTab.InputControls["GroupCombo"] -Items $logItems

    $configDir = Join-Path $rootPath "config"
    $configNames = @(Get-ChildItem -LiteralPath $configDir -Filter "*_config.xlsx" -ErrorAction SilentlyContinue |
        ForEach-Object {
            $basename = $_.BaseName
            $basename -replace '_config$', ''
        } |
        Sort-Object)
    $configItems = @($allOption) + $configNames
    Update-ComboBoxItems -ComboBox $logTab.InputControls["ConfigCombo"] -Items $configItems
    
    Update-ComboBoxItems -ComboBox $batchTab.InputControls["TargetGroupName"] -Items $groupNames

    Update-ComboBoxItems -ComboBox $settingsGroupTop.Controls["GroupTarget"] -Items $groupNames

    Update-ComboBoxItems -ComboBox $multipleBatchTab.InputControls["TargetGroupName"] -Items $groupNames

}

function Set-RunButtonsEnabled {
    param([bool]$Enabled)
    foreach ($cd in $categoryDefs) {
        foreach ($bd in $cd.ButtonDefs) {
            if ($bd.InputControls) {
                foreach ($ctrl in $bd.InputControls.Values) { $ctrl.Enabled = $Enabled }
            }
        }
    }
    (Get-ButtonDefByBatchPath $generateConfigFromTemplateBat).InputControls["BaseTemplateName"].Enabled = $Enabled
    (Get-ButtonDefByBatchPath $generateConfigFromTemplateBat).InputControls["CustomTemplateName"].Enabled = $Enabled
    foreach ($ctrl in $batchTab.InputControls.Values) {
        $ctrl.Enabled = $Enabled
    }
    $multipleBatchTab.InputControls["ExcelPath"].Enabled = $Enabled
    $multipleBatchTab.InputControls["ExcelPathBrowse"].Enabled = $Enabled
    $multipleBatchTab.RunButton.Enabled = $Enabled
    $multipleBatchTab.InputControls["TargetGroupName"].Enabled = $Enabled
    Set-ButtonsEnabled -Buttons $categoryTab.RunButtons -Enabled $Enabled
    Set-ButtonsEnabled -Buttons @($batchTab.RunButton) -Enabled $Enabled
}

function Copy-ComboSelection {
    param([System.Windows.Forms.ComboBox]$From, [System.Windows.Forms.ComboBox]$To)
    $value = Get-ComboBoxValue -SelectedItem $From.SelectedItem
    $matchingItem = $To.Items | Where-Object { (Get-ComboBoxValue -SelectedItem $_) -eq $value } | Select-Object -First 1
    if ($matchingItem) {
        $To.SelectedItem = $matchingItem
    } else {
        $To.Text = $value
    }
}

function Invoke-ExecuteAll {
    $batchInputs = $batchTab.InputControls

    foreach ($inputDef in $batchRunAllInputs) {
        if (-not $inputDef.Require) { continue }
        if (Get-InputValue -Control $batchInputs[$inputDef.Name]) { continue }

        [System.Windows.Forms.MessageBox]::Show("$($inputDef.Label) を設定してください。", "一括実行", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        return 1
    }

    $baseTemplateValue = Get-InputValue -Control $batchInputs["BaseTemplateName"]
    $customTemplateValue = Get-InputValue -Control $batchInputs["CustomTemplateName"]
    if (-not $baseTemplateValue -and -not $customTemplateValue) {
        [System.Windows.Forms.MessageBox]::Show("設定テンプレート名（基本）または設定テンプレート名（カスタム）のどちらかを指定してください。", "一括実行", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        return 1
    }

    $groupValue = Get-ComboBoxValue -SelectedItem $batchInputs["TargetGroupName"].SelectedItem
    $configName = $batchInputs["ConfigName"].Text.Trim()
    foreach ($cd in $categoryDefs) {
        $inputControls = $cd.ButtonDefs[0].InputControls

        $groupCombo = $inputControls["TargetGroupName"]
        if ($groupCombo) {
            $matchingItem = $groupCombo.Items | Where-Object { (Get-ComboBoxValue -SelectedItem $_) -eq $groupValue } | Select-Object -First 1
            if ($matchingItem) { $groupCombo.SelectedItem = $matchingItem }
        }

        $inputControls["ConfigName"].Text = $configName
    }

    $createSpaceBd = Get-ButtonDefByBatchPath $createSpaceFromTemplateBat
    $createSpaceBd.InputControls["SpaceTemplateId"].Text = $batchInputs["SpaceTemplateId"].Text.Trim()
    $generateBd = Get-ButtonDefByBatchPath $generateConfigFromTemplateBat
    Copy-ComboSelection -From $batchInputs["BaseTemplateName"] -To $generateBd.InputControls["BaseTemplateName"]
    Copy-ComboSelection -From $batchInputs["CustomTemplateName"] -To $generateBd.InputControls["CustomTemplateName"]

    $lastExitCode = 0
    foreach ($cd in $categoryDefs) {
        $bd = $cd.ButtonDefs[0]
        $ic = $bd.InputControls
        $lastOutputLines = New-Object System.Collections.Generic.List[string]
        $exitCode = Invoke-BatchStep -ButtonDef ([PSCustomObject]@{ BatchPath = $bd.BatchPath; Label = $bd.Label }) `
            -GetBatArgs { param($bd2) & $bd.ArgsFn $ic $bd.Inputs } `
            -WorkingDirectory $rootPath -Form $form `
            -WriteLog { param($msg) Write-Log $msg } `
            -OnOutputLine { param($line) Write-Log $line; $lastOutputLines.Add($line) } `
            -CurrentProcessRef ([ref]$script:currentProc) `
            -DisplayLabel $bd.Label -StatusLabel $bd.StepStatusLabel

        if (($exitCode -eq 0 -or $exitCode -eq 2) -and $bd.OnSuccessFn) {
            & $bd.OnSuccessFn $ic $lastOutputLines
        }

        if ($exitCode -eq 2) {
            $lastExitCode = 2
        } elseif ($exitCode -ne 0) {
            return $exitCode
        }
    }
    return $lastExitCode
}

$multipleBatchTab = New-InputRunTab -TabPage $tabBatchRun -GroupText "複数実行" -RunButtonText "実行" -Inputs @(
    [PSCustomObject]@{ Name = "TargetGroupName"; Label = "対象のグループ"; LabelWidth = 150; InputWidth = 200; Kind = "Combo" }
    [PSCustomObject]@{ Name = "ExcelPath"; Label = "実行一覧ファイル"; LabelWidth = 150; InputWidth = 200; Kind = "File"; Filter = "Excelファイル (*.xlsx)|*.xlsx"; NewRow = $true }
) -OnRunClick {
    param($controls, $statusLabel)
    $excelPath = $controls["ExcelPath"].Text.Trim()
    try {
        Set-StepStatus -Label $statusLabel -Text "実行中..."
        if (!$excelPath) {
            throw "実行一覧ファイルを選択してください。"
        }
        if (!(Test-Path -LiteralPath $excelPath)) {
            throw "実行一覧ファイルが存在しません。"
        }

        $rows = $null
        try {
            $excel = New-Object -ComObject Excel.Application
            $excel.Visible = $false
            $excel.DisplayAlerts = $false
            $excel.ScreenUpdating = $false
            $excel.EnableEvents = $false
            try {
                $workbook = $excel.Workbooks.Open($excelPath)
                $rows = @(Get-RowObjects -Sheet $workbook.Sheets.Item(1))
            }
            finally {
                if ($workbook) { $workbook.Close($false); [void][Runtime.InteropServices.Marshal]::ReleaseComObject($workbook) }
                if ($excel)    { $excel.Quit(); [void][Runtime.InteropServices.Marshal]::ReleaseComObject($excel) }
                [System.GC]::Collect()
                [System.GC]::WaitForPendingFinalizers()
            }
        } catch {
            throw "Excelの読み込みに失敗しました: $($_.Exception.Message)"
        }
        if ($rows.Count -eq 0) {
            throw "Excelに行がありません。"
        }

        Set-RunButtonsEnabled $false

        $resultLines = New-Object System.Collections.Generic.List[string]
        for ($i = 0; $i -lt $rows.Count; $i++) {
            $row = $rows[$i]
            $rowNumber = $i + 1
            $rowConfigName = "$($row.'スペース識別名')".Trim()
            $rowTemplateId = "$($row.'スペーステンプレートID')".Trim()
            $rowBaseResourceTemplate = "$($row.'設定テンプレート名（基本）')".Trim()
            $rowCustomResourceTemplate = "$($row.'設定テンプレート名（カスタム）')".Trim()

            Set-StepStatus -Label $statusLabel -Text "実行中... ($rowNumber/$($rows.Count): $rowConfigName)" -State "実行中..."
            [System.Windows.Forms.Application]::DoEvents()

            Write-Log "==================== 複数実行 $rowNumber/$($rows.Count): $rowConfigName ===================="

            if (!$rowConfigName) {
                Write-Log "行$($rowNumber): スペース識別名が空のためスキップします。"
                $resultLines.Add("行$($rowNumber): スキップ（スペース識別名が空）")
                continue
            }
            if (!$rowTemplateId) {
                Write-Log "行$($rowNumber): スペーステンプレートIDが空のためスキップします。"
                $resultLines.Add("行$($rowNumber): スキップ（スペーステンプレートIDが空）")
                continue
            }
            if (!$rowBaseResourceTemplate -and !$rowCustomResourceTemplate) {
                Write-Log "行$($rowNumber) $($rowConfigName): 設定テンプレート名（基本）・設定テンプレート名（カスタム）のいずれかが必要のためスキップします。"
                $resultLines.Add("行$($rowNumber) $($rowConfigName): スキップ（テンプレート指定がない）")
                continue
            }

            Copy-ComboSelection -From $controls["TargetGroupName"] -To $batchTab.InputControls["TargetGroupName"]
            $batchTab.InputControls["ConfigName"].Text = $rowConfigName
            $batchTab.InputControls["SpaceTemplateId"].Text = $rowTemplateId
            $batchTab.InputControls["BaseTemplateName"].Text = $rowBaseResourceTemplate
            $batchTab.InputControls["CustomTemplateName"].Text = $rowCustomResourceTemplate
            
            $exitCode = Invoke-ExecuteAll
            if ($exitCode -eq 0) {
                $resultLines.Add("行$($rowNumber) $($rowConfigName): 成功")
            } elseif ($exitCode -eq 2) {
                $resultLines.Add("行$($rowNumber) $($rowConfigName): 警告")
            } else {
                $resultLines.Add("行$($rowNumber) $($rowConfigName): 失敗")
            }
        }

        Write-Log "==================== 複数実行 結果 ===================="
        foreach ($line in $resultLines) { Write-Log $line }

        $failedCount = @($resultLines | Where-Object { $_ -match ": 失敗|: スキップ" }).Count
        $warningCount = @($resultLines | Where-Object { $_ -match "警告" }).Count
        $succsessCount = $rows.Count -$failedCount -$warningCount
        $multipleResultMessage = "終了（成功-$($succsessCount)件、警告-$($warningCount)件、失敗/スキップ-$($failedCount)件）"
        if ($failedCount -gt 0) {
            Set-StepStatus -Label $statusLabel -Text $multipleResultMessage -State "失敗"
        } elseif ($warningCount -gt 0) {
            Set-StepStatus -Label $statusLabel -Text $multipleResultMessage -State "警告"
        } else {
            Set-StepStatus -Label $statusLabel -Text $multipleResultMessage -State "成功"
        }
    } catch {
        [System.Windows.Forms.MessageBox]::Show("$_", "エラー", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
        Set-StepStatus -Label $statusLabel -Text "失敗"
    } finally {
        Set-RunButtonsEnabled $true
    }
}

function Get-TemplateFileNames {
    param([string]$EnvVarName)
    $templatePath = Get-ResolvedVar $EnvVarName $commonEnvBat
    if (!$templatePath -or !(Test-Path -LiteralPath $templatePath)) { return @() }
    return @(Get-ChildItem -LiteralPath $templatePath -Filter "*.xlsx" -ErrorAction SilentlyContinue |
        ForEach-Object { [System.IO.Path]::GetFileNameWithoutExtension($_.Name) } |
        Sort-Object)
}

function Update-BaseTemplateNameList {
    $names = Get-TemplateFileNames -EnvVarName "CommonBaseTemplatePath"
    $items = @($noSelectOption) + @($names | ForEach-Object { [PSCustomObject]@{ Text = $_; Value = $_ } })
    Update-ComboBoxItems -ComboBox (Get-ButtonDefByBatchPath $generateConfigFromTemplateBat).InputControls["BaseTemplateName"] -Items $items
    Update-ComboBoxItems -ComboBox $batchTab.InputControls["BaseTemplateName"] -Items $items
}

function Update-CustomTemplateNameList {
    $names = Get-TemplateFileNames -EnvVarName "CommonCustomTemplatePath"
    $items = @($noSelectOption) + @($names | ForEach-Object { [PSCustomObject]@{ Text = $_; Value = $_ } })
    Update-ComboBoxItems -ComboBox (Get-ButtonDefByBatchPath $generateConfigFromTemplateBat).InputControls["CustomTemplateName"] -Items $items
    Update-ComboBoxItems -ComboBox $batchTab.InputControls["CustomTemplateName"] -Items $items
}

$settingsCommonBottomPanel = New-Panel -Dock ([System.Windows.Forms.DockStyle]::Fill) -AutoScroll

$settingsCommonTopPanel = (New-SettingsTopPanel `
    -OnSave {
        foreach ($f in (Get-CommonSettingsFiles)) { & $f.Save }
        Update-CommonSettingsFields
    } `
    -OnReload {
        foreach ($f in (Get-CommonSettingsFiles)) { & $f.Reload }
        Update-CommonSettingsFields
    }).Panel

$tabSettingsCommon.Controls.Add($settingsCommonBottomPanel)
$tabSettingsCommon.Controls.Add($settingsCommonTopPanel)

$settingsGroupBottomPanel = New-Panel -Dock ([System.Windows.Forms.DockStyle]::Fill) -AutoScroll

$settingsGroups = [ordered]@{
    "Common" = @{
        Label = "共通"
        Sections = [ordered]@{
            "COMMON" = @{
                Label = "基本設定"
                Vars = [ordered]@{
                    "CommonDownloadPath"        = @{ Label = "ダウンロード先のフォルダ"; Browse = "Folder" }
                    "CommonBaseTemplatePath"   = @{ Label = "設定テンプレート（基本）ファイルのフォルダ"; Browse = "Folder" }
                    "CommonCustomTemplatePath" = @{ Label = "設定テンプレート（カスタム）ファイルのフォルダ"; Browse = "Folder" }
                    "CommonConfigPath"          = @{ Label = "設定ファイルのフォルダ"; Browse = "Folder" }
                    "CommonCheckOutputPath"    = @{ Label = "チェック結果の出力先フォルダ"; Browse = "Folder" }
                    "CommonLogPath"             = @{ Label = "ログの出力先フォルダ"; Browse = "Folder" }
                }
            }
        }
    }
    "Group" = @{
        Label = "グループ別"
        Sections = [ordered]@{
            "KINTONE" = @{
                Label = "kintoneの接続情報"
                Vars = [ordered]@{
                    "KintoneSubdomain" = @{ Label = "サブドメイン" }
                    "KintoneLoginName" = @{ Label = "ログイン名" }
                    "KintonePassword"  = @{ Label = "パスワード"; Masked = $true }
                }
            }
        }
    }
}

$settingsFlatGroups = [ordered]@{}
foreach ($section in $settingsGroups.Values) {
    foreach ($key in $section.Sections.Keys) { $settingsFlatGroups[$key] = $section.Sections[$key] }
}
$settingsRenderLists = Get-SettingsRenderLists -SettingsGroups $settingsFlatGroups

$commonEnvResolver = { param($name) Get-ResolvedVar $name $commonEnvBat }

$settingsTrailingButtonVars = @{
    "KintonePassword" = { param($Panel, $Y, $Field) Add-FieldActionButton -Panel $Panel -Y $Y -Text "テスト接続" -AddStatusLabel -OnClick {
        Invoke-ActionWithUpdateStatus -StatusLabel $Field.StatusLabel -Action {
            $subDomainVal = Get-GroupSettingsFieldValue "KintoneSubdomain"
            $loginVal = Get-GroupSettingsFieldValue "KintoneLoginName"
            $passwordVal = Get-GroupSettingsFieldValue "KintonePassword"
            if (!$subDomainVal.Trim() -or !$loginVal -or !$passwordVal) {
                throw "サブドメイン・ログイン名・パスワードをすべて入力してください。"
            }
            Test-KintoneConnection -Subdomain $subDomainVal.Trim() -LoginName $loginVal -Password $passwordVal
        }
    }.GetNewClosure() }
    "TemplateName" = { param($Panel, $Y, $Field) Add-FieldActionButton -Panel $Panel -Y $Y -Text "実行" -AddStatusLabel -OnClick {
        Invoke-ActionWithUpdateStatus -StatusLabel $Field.StatusLabel -Action {
            $spaceId = Get-GroupSettingsFieldValue "SpaceId"
            $templateName = Get-GroupSettingsFieldValue "TemplateName"
            $groupName = Get-ComboBoxValue -SelectedItem $settingsGroupTop.Controls["GroupTarget"].SelectedItem

            if (!$spaceId) {
                throw "スペースIDを入力してください。"
            }
            if (!$templateName) {
                throw "テンプレート名を入力してください。"
            }
            if (!$groupName) {
                throw "グループを選択してください。"
            }

            $batchArgs = @("-TargetGroupName:$groupName", "-SpaceId:$spaceId", "-TemplateName:$templateName")
            $exitCode = Invoke-BatProcess -BatPath $createTemplateBat -WorkingDirectory $rootPath -BatArgs $batchArgs

            if ($exitCode -eq 0) {
                Update-CustomTemplateNameList
            } else {
                throw "エラーが発生しました（終了コード: $exitCode）"
            }
        }
    }.GetNewClosure() -OnOpenClick {
        $templatePath = Get-ResolvedVar "CommonCustomTemplatePath" $commonEnvBat
        $templateName = Get-GroupSettingsFieldValue "TemplateName"
        $groupName = Get-ComboBoxValue -SelectedItem $settingsGroupTop.Controls["GroupTarget"].SelectedItem
        Open-TargetOrWarn -Path (Join-Path $templatePath "$($groupName)_$($templateName).xlsx")
    }.GetNewClosure() }
}

function Get-CommonSettingsFiles {
    return @(
        [PSCustomObject]@{ Path = $commonEnvBat; Save = { Save-CommonSettings }; Reload = {} }
    )
}

function Save-CommonSettings {
    $commonVars = @($settingsGroups["Common"].Sections.Values | ForEach-Object { $_.Vars.Keys })
    Save-EnvBatFile -Path $commonEnvBat -VarNames $commonVars `
        -GetValueFn { param($name) Get-CommonSettingsFieldValue $name } `
        -HasValueFn { param($name) $settingsCommonFieldTextBoxes.ContainsKey($name) }
}

function Get-CommonSettingsFieldRows {
    $commonDefaults = Get-SetEnvDefaults -Path $commonEnvBat
    foreach ($groupName in $settingsGroups["Common"].Sections.Keys) {
        foreach ($varName in @($settingsGroups["Common"].Sections[$groupName].Vars.Keys)) {
            $varValue = if ($commonDefaults.ContainsKey($varName)) { $commonDefaults[$varName] } else { $null }
            [PSCustomObject]@{ Group = $groupName; VarName = $varName; Value = $varValue; Key = $varName }
        }
    }
}
function Update-CommonSettingsFields {
    $scrollX = -$settingsCommonBottomPanel.AutoScrollPosition.X
    $scrollY = -$settingsCommonBottomPanel.AutoScrollPosition.Y
    $rows = @(Get-CommonSettingsFieldRows)
    Render-SettingsFields -Panel $settingsCommonBottomPanel -Rows $rows -TargetTextBoxes $settingsCommonFieldTextBoxes -TrailingButtonVars @{} `
        -GroupLabels $settingsRenderLists.GroupLabels -VarLabels $settingsRenderLists.VarLabels -RootPath $rootPath -EnvResolver $commonEnvResolver `
        -MultilineVars $settingsRenderLists.MultilineVars -MaskedVars $settingsRenderLists.MaskedVars -FolderBrowseVars $settingsRenderLists.FolderBrowseVars -FileBrowseVars $settingsRenderLists.FileBrowseVars -LabelWidth 220 | Out-Null
    $settingsCommonBottomPanel.AutoScrollPosition = New-Object System.Drawing.Point($scrollX, $scrollY)
}

$settingsCommonFieldTextBoxes = @{}
$settingsGroupFieldTextBoxes = @{}

function Get-CommonSettingsFieldValue {
    param([string]$Key)
    if ($settingsCommonFieldTextBoxes.ContainsKey($Key)) {
        return $settingsCommonFieldTextBoxes[$Key].Text
    }
    return ""
}

function Get-GroupSettingsFieldValue {
    param([string]$Key)
    if ($settingsGroupFieldTextBoxes.ContainsKey($Key)) {
        return $settingsGroupFieldTextBoxes[$Key].Text
    }
    return ""
}

function Get-GroupSettingsFiles {
    param([string]$GroupName)
    if (!$GroupName) { return @() }
    return @(
        [PSCustomObject]@{ Path = (Get-GroupBatPath $GroupName $clientsDir); Save = { Save-GroupSettings -GroupName $GroupName }.GetNewClosure(); Reload = {} }
    )
}

function Save-GroupSettings {
    param([string]$GroupName)
    if (!$GroupName) { return }

    $groupBatPath = Get-GroupBatPath $GroupName $clientsDir
    if (!(Test-Path -LiteralPath $groupBatPath)) {
        if (Test-Path -LiteralPath $clientTemplateBat) {
            Copy-Item -LiteralPath $clientTemplateBat -Destination $groupBatPath
        }
    }

    Save-EnvBatFile -Path $groupBatPath -VarNames @($settingsGroups["Group"].Sections.Values | ForEach-Object { $_.Vars.Keys }) `
        -GetValueFn { param($name) Get-GroupSettingsFieldValue $name } `
        -HasValueFn { param($name) $settingsGroupFieldTextBoxes.ContainsKey($name) }
}

function Get-GroupSettingsFieldRows {
    param([string]$GroupName)
    if (!$GroupName) { return }

    $templateDefaults = Get-SetEnvDefaults -Path ($clientTemplateBat)
    $groupDefaults = Get-SetEnvDefaults -Path (Get-GroupBatPath $GroupName $clientsDir)

    foreach ($groupName in $settingsGroups["Group"].Sections.Keys) {
        foreach ($varName in @($settingsGroups["Group"].Sections[$groupName].Vars.Keys)) {
            $varValue = if ($groupDefaults.ContainsKey($varName)) { $groupDefaults[$varName] } else { $templateDefaults[$varName] }
            [PSCustomObject]@{ Group = $groupName; VarName = $varName; Value = $varValue; Key = $varName }
        }
    }
}
function Update-GroupSettingsFields {
    $target = Get-ComboBoxValue -SelectedItem $settingsGroupTop.Controls["GroupTarget"].SelectedItem
    if (!$target) {
        $settingsGroupBottomPanel.Controls.Clear()
        return
    }

    $rows = @(Get-GroupSettingsFieldRows -GroupName $target)

    $rows += @(
        [PSCustomObject]@{ Group = "テンプレート作成"; VarName = "SpaceId"; Value = ""; Key = "SpaceId" }
        [PSCustomObject]@{ Group = "テンプレート作成"; VarName = "TemplateName"; Value = ""; Key = "TemplateName" }
    )

    $settingsRenderLists.GroupLabels["テンプレート作成"] = "テンプレート作成"

    $settingsRenderLists.VarLabels["SpaceId"] = "スペースID"
    $settingsRenderLists.VarLabels["TemplateName"] = "テンプレート名"

    Render-SettingsFields -Panel $settingsGroupBottomPanel -Rows $rows -TargetTextBoxes $settingsGroupFieldTextBoxes -TrailingButtonVars $settingsTrailingButtonVars `
        -GroupLabels $settingsRenderLists.GroupLabels -VarLabels $settingsRenderLists.VarLabels -RootPath $rootPath -EnvResolver $commonEnvResolver `
        -MultilineVars $settingsRenderLists.MultilineVars -MaskedVars $settingsRenderLists.MaskedVars -FolderBrowseVars $settingsRenderLists.FolderBrowseVars -FileBrowseVars $settingsRenderLists.FileBrowseVars -LabelWidth 150 | Out-Null
}

$settingsGroupTop = (New-SettingsTopPanel `
    -ExtraControlDefs @(
        [PSCustomObject]@{ Name = "GroupTargetLabel"; Kind = "Label"; Text = "対象のグループ"; Width = 150 }
        [PSCustomObject]@{ Name = "GroupTarget"; Kind = "Combo"; Width = 150; OnChange = { Update-GroupSettingsFields } }
        [PSCustomObject]@{ Name = "NewGroup"; Kind = "Button"; Text = "新規作成"; Width = 140; OnClick = {
            Add-Type -AssemblyName Microsoft.VisualBasic
            $newName = [Microsoft.VisualBasic.Interaction]::InputBox("グループ名を入力してください", "グループの新規作成", "")
            $newName = $newName.Trim()
            if (!$newName) { return }

            if ($settingsGroupTop.Controls["GroupTarget"].Items.Contains($newName) -or (Test-Path -LiteralPath (Get-GroupBatPath $newName $clientsDir))) {
                [System.Windows.Forms.MessageBox]::Show("「$newName」は既に存在します。", "グループの新規作成", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
                return
            }

            $settingsGroupTop.Controls["GroupTarget"].Items.Add([PSCustomObject]@{ Text = $newName; Value = $newName }) | Out-Null
            $settingsGroupTop.Controls["GroupTarget"].SelectedItem = $settingsGroupTop.Controls["GroupTarget"].Items[-1]
        } }
    ) `
    -OnSave {
        $target = Get-ComboBoxValue -SelectedItem $settingsGroupTop.Controls["GroupTarget"].SelectedItem
        if (!$target) { return }
        foreach ($f in (Get-GroupSettingsFiles -GroupName $target)) { & $f.Save }
        Update-GroupSettingsFields
        Update-GroupDropdowns
    } `
    -OnReload {
        $target = Get-ComboBoxValue -SelectedItem $settingsGroupTop.Controls["GroupTarget"].SelectedItem
        if (!$target) { return }
        foreach ($f in (Get-GroupSettingsFiles -GroupName $target)) { & $f.Reload }
        Update-GroupSettingsFields
    })

$tabSettingsGroup.Controls.Add($settingsGroupBottomPanel)
$tabSettingsGroup.Controls.Add($settingsGroupTop.Panel)

$settingsSubTabControl.Add_SelectedIndexChanged({
    if ($settingsSubTabControl.SelectedTab -eq $tabSettingsCommon) {
        Update-CommonSettingsFields
    } elseif ($settingsSubTabControl.SelectedTab -eq $tabSettingsGroup) {
        Update-GroupSettingsFields
    }
})

$tabControl.Add_SelectedIndexChanged({
    if ($tabControl.SelectedTab -eq $tabRun) {
        Update-BaseTemplateNameList
        Update-CustomTemplateNameList
    } elseif ($tabControl.SelectedTab -eq $tabLogs) {
        Update-GroupDropdowns
        Update-LogView -LogTab $logTab
    }
})

$tabControl.SelectedTab = $tabRun

$form.Add_Shown({
    Update-CommonSettingsFields
    Update-BaseTemplateNameList
    Update-CustomTemplateNameList
    Update-GroupDropdowns
    Update-TabHeight -NestedTabControl $execTabControl
})

[System.Windows.Forms.Application]::Run($form)
