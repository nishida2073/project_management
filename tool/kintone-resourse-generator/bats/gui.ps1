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
    $scriptDir = Split-Path $MyInvocation.MyCommand.Path
    $rootPath = Split-Path $scriptDir -Parent
} else {
    $rootPath = Split-Path ([System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName)
}
$createSpaceBat = Join-Path $rootPath "create-space-from-template.bat"
$downloadBat = Join-Path $rootPath "download-kintone-resources.bat"
$generateBat = Join-Path $rootPath "generate-config-from-template.bat"
$applyBat = Join-Path $rootPath "apply-kintone-resources.bat"
$checkBat = Join-Path $rootPath "check-kintone-resources.bat"
$clientsDir = Join-Path $rootPath "clients"
$setEnvBat = Join-Path $clientsDir "set-env.bat"

$libraryDir = Join-Path $rootPath "bats\library"
Get-ChildItem -Path $libraryDir -Filter *.ps1 -Recurse | ForEach-Object {
    . $_.FullName
}

$env:GUI_LOG_MODE = "1"

$script:baseTemplateNamePlaceholder = "未選択"

$script:customTemplateNamePlaceholder = "指定なし"

$cmbBaseTemplateName = New-Object System.Windows.Forms.ComboBox
$cmbBaseTemplateName.Size = New-Object System.Drawing.Size(220, 22)
$cmbBaseTemplateName.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList

$cmbCustomTemplateName = New-Object System.Windows.Forms.ComboBox
$cmbCustomTemplateName.Size = New-Object System.Drawing.Size(180, 22)
$cmbCustomTemplateName.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList

$categoryDefs = @(
    [PSCustomObject]@{
        Label = "スペース作成"
        ButtonDefs = @(
            [PSCustomObject]@{
                Label = "スペース作成"
                StageKey = "createspace"
                Inputs = @(
                    [PSCustomObject]@{ Name = "ConfigName"; Label = "スペース識別名"; LabelWidth = 151; InputWidth = 200; Require = $true }
                    [PSCustomObject]@{ Name = "SpaceTemplateId"; Label = "スペーステンプレートID"; LabelWidth = 151; InputWidth = 200; NewRow = $true; Require = $true }
                )
                BatchPath = $createSpaceBat
                ArgsFn = { param($ic) @("-LogNamePrefix", "createspace", "-TemplateId", $ic['SpaceTemplateId'].Text.Trim(), "-SpaceName", $ic['ConfigName'].Text.Trim()) }
                OutputPathFn = $null
                OpenTarget = { $script:createdSpaceUrl }
                InputControls = $null
                StepStatusLabel = $null
                OnSuccessFn = {
                    param($ic, $lastOutputLines)
                    $idLine = $lastOutputLines | Where-Object { $_ -match 'SPACE_ID=(\d+)' } | Select-Object -Last 1
                    if ($idLine -and $idLine -match 'SPACE_ID=(?<id>\d+)') {
                        $bd1 = $categoryDefs[1].ButtonDefs[0]
                        if ($bd1 -and $bd1.InputControls.ContainsKey('SpaceId')) { $bd1.InputControls['SpaceId'].Text = $Matches.id }
                        $baseUrl = (Get-ResolvedVar -VarName "KINTONE_BASE_URL" -Path $setEnvBat).TrimEnd('/')
                        if ($baseUrl) { $script:createdSpaceUrl = "$baseUrl/k/#/space/$($Matches.id)" }
                    }
                }
            }
        )
    }
    [PSCustomObject]@{
        Label = "ダウンロード"
        ButtonDefs = @(
            [PSCustomObject]@{
                Label = "ダウンロード"
                StageKey = "download"
                Inputs = @(
                    [PSCustomObject]@{ Name = "ConfigName"; Label = "スペース識別名"; LabelWidth = 151; InputWidth = 200; Require = $true }
                    [PSCustomObject]@{ Name = "SpaceId"; Label = "スペースID"; LabelWidth = 151; InputWidth = 200; NewRow = $true; Require = $false }
                )
                BatchPath = $downloadBat
                ArgsFn = { param($ic) @("-LogNamePrefix", "download", "-SpaceId", $ic['SpaceId'].Text.Trim(), "-ConfigName", $ic['ConfigName'].Text.Trim()) }
                OutputPathFn = { param($ic) Join-Path (Get-ResolvedVar "COMMON_DOWNLOAD_PATH") "$($ic['ConfigName'].Text.Trim())_download.xlsx" }
                OpenTarget = { param($ic) & $_.OutputPathFn $ic }
                InputControls = $null
                StepStatusLabel = $null
            }
        )
    }
    [PSCustomObject]@{
        Label = "設定ファイルの生成"
        ButtonDefs = @(
            [PSCustomObject]@{
                Label = "設定ファイルの生成"
                StageKey = "generate"
                Inputs = @(
                    [PSCustomObject]@{ Name = "ConfigName"; Label = "スペース識別名"; LabelWidth = 151; InputWidth = 200; Require = $true }
                    [PSCustomObject]@{ Name = "BaseTemplateName"; Label = "設定テンプレート名（基本）"; LabelWidth = 151; ExistingControl = $cmbBaseTemplateName; NewRow = $true; Require = $true }
                    [PSCustomObject]@{ Name = "CustomTemplateName"; Label = "設定テンプレート名（カスタム）"; LabelWidth = 151; ExistingControl = $cmbCustomTemplateName; NewRow = $true; Require = $false }
                )
                BatchPath = $generateBat
                ArgsFn = {
                    param($ic)
                    $stepArgs = @("-LogNamePrefix", "generate", "-BaseTemplateConfigName", $ic['BaseTemplateName'].Text.Trim(), "-DownloadConfigName", $ic['ConfigName'].Text.Trim())
                    $customTemplateName = $ic['CustomTemplateName'].Text.Trim()
                    if ($customTemplateName -and $customTemplateName -ne $script:customTemplateNamePlaceholder) {
                        $stepArgs += @("-CustomTemplateConfigName", $customTemplateName)
                    }
                    $stepArgs
                }
                OutputPathFn = { param($ic) Join-Path (Get-ResolvedVar "COMMON_CONFIG_PATH") "$($ic['ConfigName'].Text.Trim())_config.xlsx" }
                OpenTarget = { param($ic) & $_.OutputPathFn $ic }
                InputControls = $null
                StepStatusLabel = $null
            }
        )
    }
    [PSCustomObject]@{
        Label = "kintoneへ反映"
        ButtonDefs = @(
            [PSCustomObject]@{
                Label = "kintoneへ反映"
                StageKey = "apply"
                Inputs = @(
                    [PSCustomObject]@{ Name = "ConfigName"; Label = "スペース識別名"; LabelWidth = 151; InputWidth = 200; Require = $true }
                )
                BatchPath = $applyBat
                ArgsFn = { param($ic) @("-LogNamePrefix", "apply", "-ConfigName", $ic['ConfigName'].Text.Trim()) }
                OutputPathFn = $null
                OpenTarget = { $script:createdSpaceUrl }
                InputControls = $null
                StepStatusLabel = $null
            }
        )
    }
    [PSCustomObject]@{
        Label = "データチェック"
        ButtonDefs = @(
            [PSCustomObject]@{
                Label = "データチェック"
                StageKey = "check"
                Inputs = @(
                    [PSCustomObject]@{ Name = "ConfigName"; Label = "スペース識別名"; LabelWidth = 151; InputWidth = 200; Require = $true }
                )
                BatchPath = $checkBat
                ArgsFn = { param($ic) @("-LogNamePrefix", "check", "-ConfigName", $ic['ConfigName'].Text.Trim()) }
                OutputPathFn = { param($ic) Join-Path (Get-ResolvedVar "COMMON_CHECK_OUTPUT_PATH") "$($ic['ConfigName'].Text.Trim())_check.xlsx" }
                OpenTarget = { param($ic) & $_.OutputPathFn $ic }
                InputControls = $null
                StepStatusLabel = $null
            }
        )
    }
)

$form = New-Object System.Windows.Forms.Form
$form.Text = "kintoneリソース生成ツール"
$form.Size = New-Object System.Drawing.Size(780, 560)
$form.StartPosition = "CenterScreen"
$form.MinimumSize = New-Object System.Drawing.Size(600, 500)

$script:currentProc = $null
$script:stepOutputPaths = @{}
$script:createdSpaceUrl = $null
$form.Add_FormClosing({
    if ($script:currentProc -and !$script:currentProc.HasExited) {
        & taskkill.exe /T /F /PID $script:currentProc.Id 2>&1 | Out-Null
    }
})

$tabControl = New-Object System.Windows.Forms.TabControl
$tabControl.Dock = [System.Windows.Forms.DockStyle]::Fill

$tabRun = New-Object System.Windows.Forms.TabPage
$tabRun.Text = "実行"

$innerRunTabControl = New-Object System.Windows.Forms.TabControl
$innerRunTabControl.Dock = [System.Windows.Forms.DockStyle]::Top

$tabSingleRun = New-Object System.Windows.Forms.TabPage
$tabSingleRun.Text = "単体実行"

$tabBatchRun = New-Object System.Windows.Forms.TabPage
$tabBatchRun.Text = "複数実行"

$innerRunTabControl.Controls.AddRange(@($tabBatchRun, $tabSingleRun))
$innerRunTabControl.Add_Selecting({
    if ($script:isRunning) { $_.Cancel = $true }
})

$innerRunTabControl.Add_SelectedIndexChanged({ Update-InnerRunTabHeight })

$tabLogs = New-Object System.Windows.Forms.TabPage
$tabLogs.Text = "ログ"

$tabSettings = New-Object System.Windows.Forms.TabPage
$tabSettings.Text = "設定"

$tabControl.Controls.AddRange(@($tabRun, $tabLogs, $tabSettings))
$form.Controls.Add($tabControl)

$script:isRunning = $false
$tabControl.Add_Selecting({
    if ($script:isRunning -and $_.TabPage -ne $tabRun) {
        $_.Cancel = $true
    }
})

$runTopPanel = New-Object System.Windows.Forms.Panel
$runTopPanel.Dock = [System.Windows.Forms.DockStyle]::Top

$execTabControl = New-Object System.Windows.Forms.TabControl

$tabBatchAll = New-Object System.Windows.Forms.TabPage
$tabBatchAll.Text = "一括実行"
$execTabControl.Controls.Add($tabBatchAll)

$cmbRunAllBaseTemplateName = New-Object System.Windows.Forms.ComboBox
$cmbRunAllBaseTemplateName.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList

$cmbRunAllCustomTemplateName = New-Object System.Windows.Forms.ComboBox
$cmbRunAllCustomTemplateName.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList

$allStepDefs = @($categoryDefs | ForEach-Object { $_.ButtonDefs })

$batchRunAllInputs = @(
    [PSCustomObject]@{ Name = "ConfigName"; Label = "スペース識別名"; LabelWidth = 150; InputWidth = 200; Require = $true },
    [PSCustomObject]@{ Name = "SpaceTemplateId"; Label = "スペーステンプレートID"; LabelWidth = 150; InputWidth = 200; NewRow = $true; Require = $true },
    [PSCustomObject]@{ Name = "BaseTemplateName"; Label = "設定テンプレート名（基本）"; LabelWidth = 150; InputWidth = 220; ExistingControl = $cmbRunAllBaseTemplateName; NewRow = $true; Require = $true },
    [PSCustomObject]@{ Name = "CustomTemplateName"; Label = "設定テンプレート名（カスタム）"; LabelWidth = 150; InputWidth = 180; ExistingControl = $cmbRunAllCustomTemplateName; NewRow = $true; Require = $false }
)

New-BatchRunTab -TabPage $tabBatchAll -ButtonDefs $allStepDefs -RunButtonText "実行" -ShowSteps $false `
    -Inputs $batchRunAllInputs | Out-Null

$lblOverallStatus = $script:batchStatusLabel

New-CategoryTabControl -CategoryDefs $categoryDefs -TabControl $execTabControl `
    -OnRunClick {
        param($bd)
        $ic = $bd.InputControls

        if ($bd.Inputs) {
            foreach ($inputDef in $bd.Inputs) {
                if ($inputDef.Require) {
                    $ctrl = $ic[$inputDef.Name]
                    $value = if ($ctrl -is [System.Windows.Forms.TextBox]) { $ctrl.Text.Trim() } else { $ctrl.SelectedItem }
                    if (!$value -or ($value -eq $script:customTemplateNamePlaceholder) -or ($value -eq $script:baseTemplateNamePlaceholder)) {
                        [System.Windows.Forms.MessageBox]::Show("$($inputDef.Label) を設定してください。", "実行", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
                        return
                    }
                }
            }
        }

        $script:isRunning = $true
        Set-RunButtonsEnabled $false
        $lblOverallStatus.Text = ""

        $lastOutputLines = New-Object System.Collections.Generic.List[string]
        $exitCode = Invoke-BatchStep -ButtonDef ([PSCustomObject]@{ BatchPath = $bd.BatchPath; Label = $bd.Label; StepStatusLabel = $bd.StepStatusLabel }) `
            -GetBatArgs { param($bd2) & $bd.ArgsFn $bd.InputControls } `
            -WorkingDirectory $rootPath -Form $form `
            -WriteLog { param($msg) Write-Log $msg } `
            -OnOutputLine { param($line) Write-Log $line; $lastOutputLines.Add($line) } `
            -CurrentProcessRef ([ref]$script:currentProc) `
            -DisplayLabel $bd.Label -StatusLabel $bd.StepStatusLabel

        if (($exitCode -eq 0 -or $exitCode -eq 2) -and $bd.OnSuccessFn) {
            & $bd.OnSuccessFn $bd.InputControls $lastOutputLines
        }

        Set-RunButtonsEnabled $true
        $script:isRunning = $false
    } | Out-Null


$execTabControl.Dock = [System.Windows.Forms.DockStyle]::None
$execTabControl.Location = New-Object System.Drawing.Point(0, 0)
$execTabControl.Width = 760
$runTopPanel.Controls.Add($execTabControl)

$execTabControl.Height = 45 + $script:batchPanel.Height

$execTabControl.Add_SelectedIndexChanged({
    $runTopPanel.Height = $execTabControl.Top + $execTabControl.Height
    Update-InnerRunTabHeight
})
$runTopPanel.Height = $execTabControl.Top + $execTabControl.Height

function Update-InnerRunTabHeight {
    if ($innerRunTabControl.SelectedTab -eq $tabBatchRun) {
        $innerRunTabControl.Height = $batchExcelPanel.Height + 30
    } else {
        $innerRunTabControl.Height = $runTopPanel.Height + 30
    }
    $tabRun.PerformLayout()
}

$batchExcelPanel = New-Object System.Windows.Forms.Panel
$batchExcelPanel.Dock = [System.Windows.Forms.DockStyle]::Top
$batchExcelPanel.Height = 90

$lblBatchExcelPath = New-Object System.Windows.Forms.Label
$lblBatchExcelPath.Text = "実行一覧ファイル"
$lblBatchExcelPath.AutoSize = $true
$lblBatchExcelPath.Location = New-Object System.Drawing.Point(20, 17)

$txtBatchExcelPath = New-Object System.Windows.Forms.TextBox
$txtBatchExcelPath.Location = New-Object System.Drawing.Point(140, 14)
$txtBatchExcelPath.Size = New-Object System.Drawing.Size(250, 22)
$txtBatchExcelPath.ReadOnly = $true

$btnBatchBrowse = New-Object System.Windows.Forms.Button
$btnBatchBrowse.Text = "参照..."
$btnBatchBrowse.Location = New-Object System.Drawing.Point(400, 13)
$btnBatchBrowse.Size = New-Object System.Drawing.Size(70, 24)

$btnBatchRunAll = New-Object System.Windows.Forms.Button
$btnBatchRunAll.Text = "実行"
$btnBatchRunAll.Location = New-Object System.Drawing.Point(20, 50)
$btnBatchRunAll.Size = New-Object System.Drawing.Size(100, 26)

$lblBatchStatus = New-Object System.Windows.Forms.Label
$lblBatchStatus.Text = ""
$lblBatchStatus.AutoSize = $true
$lblBatchStatus.Location = New-Object System.Drawing.Point(130, 56)

$batchExcelPanel.Controls.AddRange(@(
    $lblBatchExcelPath, $txtBatchExcelPath, $btnBatchBrowse, $btnBatchRunAll, $lblBatchStatus
))

$dlgBatchExcel = New-Object System.Windows.Forms.OpenFileDialog
$dlgBatchExcel.Filter = "Excelファイル (*.xlsx)|*.xlsx"

$btnBatchBrowse.Add_Click({
    if ($dlgBatchExcel.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $txtBatchExcelPath.Text = $dlgBatchExcel.FileName
    }
})

$tabSingleRun.Controls.Add($runTopPanel)
$tabBatchRun.Controls.Add($batchExcelPanel)

$txtLog = New-LogTextBox

Add-StackedDockedControls -Container $tabRun -ControlsTopToBottom @($innerRunTabControl, $txtLog)

$allButtonDefs = @($categoryDefs | ForEach-Object { $_.ButtonDefs })

New-LogTab -TabPage $tabLogs -ButtonDefs $allButtonDefs `
    -ExtraLabelText "スペース識別名" -ExtraComboWidth 220 `
    -GetLogPathFn { Get-ResolvedVar "COMMON_LOG_PATH" } `
    -OnAfterClear { Update-LogConfigNameList } `
    -OnUpdateLogView { Update-LogView } | Out-Null
foreach ($radio in $script:logTab.Radios) {
    $radio.Add_CheckedChanged({ if ($this.Checked) { Update-LogView } })
}
$cmbLogConfigName = $script:logTab.ExtraCombo

function Update-LogConfigNameList {
    $selected = $cmbLogConfigName.SelectedItem
    $cmbLogConfigName.Items.Clear()
    $cmbLogConfigName.Items.Add("すべて") | Out-Null

    $logPath = Get-ResolvedVar "COMMON_LOG_PATH"
    if ($logPath -and (Test-Path -LiteralPath $logPath)) {
        $stageKeys = @()
        foreach ($bd in $allButtonDefs) {
            if ($bd.StageKey) { $stageKeys += $bd.StageKey } else { $stageKeys += ".*" }
        }
        $stageKeyPattern = $stageKeys -join '|'
        $stagePrefixPattern = "^(?:$stageKeyPattern)_(?<config>.+)_\d{8}_\d{6}$"
        $configNames = Get-ChildItem -LiteralPath $logPath -Filter "*.log" -ErrorAction SilentlyContinue |
            ForEach-Object {
                $m = [regex]::Match([System.IO.Path]::GetFileNameWithoutExtension($_.Name), $stagePrefixPattern)
                if ($m.Success) { $m.Groups["config"].Value }
            } | Sort-Object -Unique
        foreach ($name in $configNames) {
            $cmbLogConfigName.Items.Add($name) | Out-Null
        }
    }

    $cmbLogConfigName.SelectedIndex = if ($selected -and $cmbLogConfigName.Items.Contains($selected)) { $cmbLogConfigName.Items.IndexOf($selected) } else { 0 }
}

function Update-LogView {
    $selectedRadio = $script:logTab.Radios | Where-Object { $_.Checked } | Select-Object -First 1
    if (-not $selectedRadio) { return }
    $stage = $selectedRadio.Tag.StageKey
    $logPath = Get-ResolvedVar "COMMON_LOG_PATH"

    $script:logTab.ContentBox.Text = ""

    if (!($logPath -and (Test-Path -LiteralPath $logPath))) {
        return
    }

    $logConfigName = $cmbLogConfigName.SelectedItem
    $configFilter = if ($logConfigName -and $logConfigName -ne "すべて") { "$logConfigName" + "_" } else { "" }
    $files = Get-ChildItem -LiteralPath $logPath -Filter "${stage}_$configFilter*.log" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime

    $sections = foreach ($file in $files) {
        try {
            [System.IO.File]::ReadAllText($file.FullName, $script:cp932Encoding)
        } catch {
            "$($file.Name) は他のプロセスで使用中のため表示できません（実行中の可能性があります）。"
        }
    }
    $script:logTab.ContentBox.Text = $sections -join "`r`n`r`n"
}

$cmbLogConfigName.Add_SelectedIndexChanged({ Update-LogView })

Update-LogConfigNameList
Update-LogView

function Set-RunButtonsEnabled {
    param([bool]$Enabled)
    foreach ($cd in $categoryDefs) {
        foreach ($bd in $cd.ButtonDefs) {
            if ($bd.InputControls) {
                foreach ($ctrl in $bd.InputControls.Values) { $ctrl.Enabled = $Enabled }
            }
        }
    }
    $cmbBaseTemplateName.Enabled = $Enabled
    $cmbCustomTemplateName.Enabled = $Enabled
    $script:batchInputControls["ConfigName"].Enabled = $Enabled
    $script:batchInputControls["SpaceTemplateId"].Enabled = $Enabled
    $script:batchInputControls["BaseTemplateName"].Enabled = $Enabled
    $script:batchInputControls["CustomTemplateName"].Enabled = $Enabled
    $script:batchRunButton.Enabled = $Enabled
    $btnBatchBrowse.Enabled = $Enabled
    $btnBatchRunAll.Enabled = $Enabled
    foreach ($btn in $tabResult.RunButtons) { $btn.Enabled = $Enabled }
}

function Copy-ComboSelection {
    param([System.Windows.Forms.ComboBox]$From, [System.Windows.Forms.ComboBox]$To)
    $value = "$($From.SelectedItem)"
    if ($To.Items.Contains($value)) {
        $To.SelectedItem = $value
    } else {
        $To.Text = $value
    }
}

function Invoke-AllStepsForCurrentInputs {
    $lastExitCode = 0
    foreach ($cd in $categoryDefs) {
        $bd = $cd.ButtonDefs[0]
        $canProceed = $true

        $ic = $bd.InputControls
        if ($bd.Inputs) {
            foreach ($inputDef in $bd.Inputs) {
                if ($inputDef.Require) {
                    $value = $ic[$inputDef.Name].Text.Trim()
                    if (!$value -or ($value -eq $script:customTemplateNamePlaceholder)) {
                        $canProceed = $false
                        break
                    }
                }
            }
        }

        if (-not $canProceed) { return 1 }
        $lastOutputLines = New-Object System.Collections.Generic.List[string]
        $exitCode = Invoke-BatchStep -ButtonDef ([PSCustomObject]@{ BatchPath = $bd.BatchPath; Label = $bd.Label }) `
            -GetBatArgs { param($bd2) & $bd.ArgsFn $ic } `
            -WorkingDirectory $rootPath -Form $form `
            -WriteLog { param($msg) Write-Log $msg } `
            -OnOutputLine { param($line) Write-Log $line; $lastOutputLines.Add($line) } `
            -CurrentProcessRef ([ref]$script:currentProc)

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

function Invoke-SeededAllSteps {
    foreach ($inputDef in $batchRunAllInputs) {
        if ($inputDef.Require) {
            $ctrl = $script:batchInputControls[$inputDef.Name]
            if ($ctrl -is [System.Windows.Forms.TextBox]) {
                $value = $ctrl.Text.Trim()
                if (!$value) {
                    [System.Windows.Forms.MessageBox]::Show("$($inputDef.Label) を設定してください。", "一括実行", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
                    return 1
                }
            } else {
                $value = $ctrl.SelectedItem
                if (!$value -or ($value -eq $script:baseTemplateNamePlaceholder) -or ($value -eq $script:customTemplateNamePlaceholder)) {
                    [System.Windows.Forms.MessageBox]::Show("$($inputDef.Label) を設定してください。", "一括実行", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
                    return 1
                }
            }
        }
    }

    foreach ($cd in $categoryDefs) {
        $bd = $cd.ButtonDefs[0]
        $bd.InputControls['ConfigName'].Text = $script:batchInputControls["ConfigName"].Text.Trim()
    }
    $bd0 = $categoryDefs[0].ButtonDefs[0]
    $bd0.InputControls['SpaceTemplateId'].Text = $script:batchInputControls["SpaceTemplateId"].Text.Trim()
    Copy-ComboSelection -From $cmbRunAllBaseTemplateName -To $cmbBaseTemplateName
    Copy-ComboSelection -From $cmbRunAllCustomTemplateName -To $cmbCustomTemplateName

    $lastExitCode = 0
    foreach ($cd in $categoryDefs) {
        $bd = $cd.ButtonDefs[0]
        $ic = $bd.InputControls
        $lastOutputLines = New-Object System.Collections.Generic.List[string]
        $exitCode = Invoke-BatchStep -ButtonDef ([PSCustomObject]@{ BatchPath = $bd.BatchPath; Label = $bd.Label }) `
            -GetBatArgs { param($bd2) & $bd.ArgsFn $ic } `
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

$script:batchRunButton.Add_Click({
    $script:isRunning = $true
    Set-RunButtonsEnabled $false
    Set-StepStatus -Label $lblOverallStatus -Text "実行中..."

    $exitCode = Invoke-SeededAllSteps

    if ($exitCode -eq 0) {
        Set-StepStatus -Label $lblOverallStatus -Text "成功" -State "成功"
    } elseif ($exitCode -eq 2) {
        Set-StepStatus -Label $lblOverallStatus -Text "警告" -State "警告"
    } else {
        Set-StepStatus -Label $lblOverallStatus -Text "失敗" -State "失敗"
    }

    Set-RunButtonsEnabled $true
    $script:isRunning = $false
})

$btnBatchRunAll.Add_Click({
    $excelPath = $txtBatchExcelPath.Text.Trim()
    if (!$excelPath -or !(Test-Path -LiteralPath $excelPath)) {
        [System.Windows.Forms.MessageBox]::Show("実行一覧ファイルを選択してください。", "複数実行", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        return
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
        [System.Windows.Forms.MessageBox]::Show("Excelの読み込みに失敗しました: $($_.Exception.Message)", "複数実行", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        return
    }
    if ($rows.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("Excelに行がありません。", "複数実行", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        return
    }

    $script:isRunning = $true
    Set-RunButtonsEnabled $false

    $origConfigNames = @{}
    for ($i = 0; $i -lt $categoryDefs.Count; $i++) {
        $bd = $categoryDefs[$i].ButtonDefs[0]
        $origConfigNames[$i] = if ($bd.InputControls -and $bd.InputControls['ConfigName']) { $bd.InputControls['ConfigName'].Text } else { "" }
    }
    $bd0 = $categoryDefs[0].ButtonDefs[0]
    $origSpaceTemplateId = if ($bd0.InputControls -and $bd0.InputControls['SpaceTemplateId']) { $bd0.InputControls['SpaceTemplateId'].Text } else { "" }
    $bd1 = $categoryDefs[1].ButtonDefs[0]
    $origSpaceId = if ($bd1.InputControls -and $bd1.InputControls['SpaceId']) { $bd1.InputControls['SpaceId'].Text } else { "" }
    $origBaseTemplateSelectedItem = if ($cmbBaseTemplateName) { $cmbBaseTemplateName.SelectedItem } else { $null }
    $origBaseTemplateText = if ($cmbBaseTemplateName) { $cmbBaseTemplateName.Text } else { "" }
    $origCustomTemplateSelectedItem = if ($cmbCustomTemplateName) { $cmbCustomTemplateName.SelectedItem } else { $null }
    $origCustomTemplateText = if ($cmbCustomTemplateName) { $cmbCustomTemplateName.Text } else { "" }

    $resultLines = New-Object System.Collections.Generic.List[string]
    for ($i = 0; $i -lt $rows.Count; $i++) {
        $row = $rows[$i]
        $rowConfigName = "$($row.'スペース識別名')".Trim()
        $rowTemplateId = "$($row.'スペーステンプレートID')".Trim()
        $rowBaseResourceTemplate = "$($row.'設定テンプレート名（基本）')".Trim()
        $rowCustomResourceTemplate = "$($row.'設定テンプレート名（カスタム）')".Trim()

        Set-StepStatus -Label $lblBatchStatus -Text "実行中... ($($i + 1)/$($rows.Count): $rowConfigName)" -State "実行中..."
        [System.Windows.Forms.Application]::DoEvents()

        Write-Log ""
        Write-Log "==================== 複数実行 $($i + 1)/$($rows.Count): $rowConfigName ===================="

        if (!$rowConfigName -or !$rowTemplateId -or !$rowBaseResourceTemplate) {
            Write-Log "スペース識別名・スペーステンプレートID・設定テンプレート名（基本）のいずれかが空のためスキップします。"
            $resultLines.Add("行$($i + 2) ($rowConfigName): スキップ（必須項目が空）")
            continue
        }

        foreach ($cd in $categoryDefs) {
            $bd = $cd.ButtonDefs[0]
            $bd.InputControls['ConfigName'].Text = $rowConfigName
        }
        $bd0 = $categoryDefs[0].ButtonDefs[0]
        $bd0.InputControls['SpaceTemplateId'].Text = $rowTemplateId
        $bd1 = $categoryDefs[1].ButtonDefs[0]
        $bd1.InputControls['SpaceId'].Text = ""
        $bd2 = $categoryDefs[2].ButtonDefs[0]
        $bd2.InputControls['BaseTemplateName'].Text = $rowBaseResourceTemplate
        $bd2.InputControls['CustomTemplateName'].Text = if ($rowCustomResourceTemplate) { $rowCustomResourceTemplate } else { $script:customTemplateNamePlaceholder }

        $exitCode = Invoke-AllStepsForCurrentInputs
        if ($exitCode -eq 0) {
            $resultLines.Add("行$($i + 2) ($rowConfigName): 成功")
        } elseif ($exitCode -eq 2) {
            $resultLines.Add("行$($i + 2) ($rowConfigName): 警告")
        } else {
            $resultLines.Add("行$($i + 2) ($rowConfigName): 失敗")
        }
    }

    Write-Log ""
    Write-Log "==================== 複数実行 結果 ===================="
    foreach ($line in $resultLines) { Write-Log $line }

    $failedCount = @($resultLines | Where-Object { $_ -match ": 失敗|: スキップ" }).Count
    $warningCount = @($resultLines | Where-Object { $_ -match "警告" }).Count
    $succsessCount = $rows.Count -$failedCount -$warningCount
    $multipleResultMessage = "終了（成功-$($succsessCount)件、警告-$($warningCount)件、失敗/スキップ-$($failedCount)件）"
    if ($failedCount -gt 0) {
        Set-StepStatus -Label $lblBatchStatus -Text $multipleResultMessage -State "失敗"
    } elseif ($warningCount -gt 0) {
        Set-StepStatus -Label $lblBatchStatus -Text $multipleResultMessage -State "警告"
    } else {
        Set-StepStatus -Label $lblBatchStatus -Text $multipleResultMessage -State "成功"
    }

    for ($i = 0; $i -lt $categoryDefs.Count; $i++) {
        $bd = $categoryDefs[$i].ButtonDefs[0]
        $bd.InputControls['ConfigName'].Text = $origConfigNames[$i]
    }
    $bd0 = $categoryDefs[0].ButtonDefs[0]
    $bd0.InputControls['SpaceTemplateId'].Text = $origSpaceTemplateId
    $bd1 = $categoryDefs[1].ButtonDefs[0]
    $bd1.InputControls['SpaceId'].Text = $origSpaceId
    if ($origBaseTemplateSelectedItem -and $cmbBaseTemplateName.Items.Contains($origBaseTemplateSelectedItem)) {
        $cmbBaseTemplateName.SelectedItem = $origBaseTemplateSelectedItem
    } else {
        $cmbBaseTemplateName.Text = $origBaseTemplateText
    }
    if ($origCustomTemplateSelectedItem -and $cmbCustomTemplateName.Items.Contains($origCustomTemplateSelectedItem)) {
        $cmbCustomTemplateName.SelectedItem = $origCustomTemplateSelectedItem
    } else {
        $cmbCustomTemplateName.Text = $origCustomTemplateText
    }

    Set-RunButtonsEnabled $true
    $script:isRunning = $false
})

function Get-TemplateFileNames {
    param([string]$EnvVarName)
    $templatePath = Get-ResolvedVar $EnvVarName
    if (!$templatePath -or !(Test-Path -LiteralPath $templatePath)) { return @() }
    return @(Get-ChildItem -LiteralPath $templatePath -Filter "*.xlsx" -ErrorAction SilentlyContinue |
        ForEach-Object { [System.IO.Path]::GetFileNameWithoutExtension($_.Name) } |
        Sort-Object)
}

function Set-ComboItems {
    param([System.Windows.Forms.ComboBox]$ComboBox, [string[]]$Names, [string]$Placeholder)
    $selected = $ComboBox.SelectedItem
    $ComboBox.Items.Clear()
    $ComboBox.Items.Add($Placeholder) | Out-Null
    foreach ($name in $Names) { $ComboBox.Items.Add($name) | Out-Null }

    if ($selected -and $ComboBox.Items.Contains($selected)) {
        $ComboBox.SelectedItem = $selected
    } else {
        $ComboBox.SelectedItem = $Placeholder
    }
}

function Update-BaseTemplateNameList {
    $names = Get-TemplateFileNames -EnvVarName "COMMON_BASE_TEMPLATE_PATH"
    Set-ComboItems -ComboBox $cmbBaseTemplateName -Names $names -Placeholder $script:baseTemplateNamePlaceholder
    Set-ComboItems -ComboBox $cmbRunAllBaseTemplateName -Names $names -Placeholder $script:baseTemplateNamePlaceholder
}

function Update-CustomTemplateNameList {
    $names = Get-TemplateFileNames -EnvVarName "COMMON_CUSTOM_TEMPLATE_PATH"
    Set-ComboItems -ComboBox $cmbCustomTemplateName -Names $names -Placeholder $script:customTemplateNamePlaceholder
    Set-ComboItems -ComboBox $cmbRunAllCustomTemplateName -Names $names -Placeholder $script:customTemplateNamePlaceholder
}

$fieldPanel = New-Object System.Windows.Forms.Panel
$fieldPanel.Dock = [System.Windows.Forms.DockStyle]::Fill
$fieldPanel.AutoScroll = $true

$tabSettings.Controls.Add($fieldPanel)

$settingsGroups = [ordered]@{
    "COMMON" = @{
        Label = "基本設定"
        Vars = [ordered]@{
            "COMMON_DOWNLOAD_PATH"        = @{ Label = "ダウンロード先のフォルダ"; Browse = "Folder" }
            "COMMON_BASE_TEMPLATE_PATH"   = @{ Label = "設定テンプレート（基本）ファイルのフォルダ"; Browse = "Folder" }
            "COMMON_CUSTOM_TEMPLATE_PATH" = @{ Label = "設定テンプレート（カスタム）ファイルのフォルダ"; Browse = "Folder" }
            "COMMON_CONFIG_PATH"          = @{ Label = "設定ファイルのフォルダ"; Browse = "Folder" }
            "COMMON_CHECK_OUTPUT_PATH"    = @{ Label = "チェック結果の出力先フォルダ"; Browse = "Folder" }
            "COMMON_LOG_PATH"             = @{ Label = "ログの出力先フォルダ"; Browse = "Folder" }
        }
    }
    "KINTONE" = @{
        Label = "kintoneの接続情報"
        Vars = [ordered]@{
            "KINTONE_SUB_DOMAIN" = @{ Label = "サブドメイン" }
            "KINTONE_LOGIN"      = @{ Label = "ログイン名" }
            "KINTONE_PASSWORD"   = @{ Label = "パスワード"; Masked = $true }
        }
    }
}

$settingsGroupLabels = @{}
$settingsVarLabels = [ordered]@{}
$settingsFolderBrowseVars = @()
$settingsFileBrowseVars = @()
$settingsMaskedVars = @()
$settingsMultilineVars = @()
foreach ($groupKey in $settingsGroups.Keys) {
    $settingsGroupLabels[$groupKey] = $settingsGroups[$groupKey].Label
    foreach ($varKey in $settingsGroups[$groupKey].Vars.Keys) {
        $varDef = $settingsGroups[$groupKey].Vars[$varKey]
        $settingsVarLabels[$varKey] = $varDef.Label
        if ($varDef.Browse -eq "Folder") { $settingsFolderBrowseVars += $varKey }
        if ($varDef.Browse -eq "File") { $settingsFileBrowseVars += $varKey }
        if ($varDef.Masked) { $settingsMaskedVars += $varKey }
        if ($varDef.Multiline) { $settingsMultilineVars += $varKey }
    }
}

$settingsToolTip = New-Object System.Windows.Forms.ToolTip
$kintoneVars = @($settingsGroups["KINTONE"].Vars.Keys)

$script:commonEnvResolver = { param($name) Get-ResolvedVar $name }
$script:fieldTextBoxes = @{}

function Get-SettingsFieldRows {
    $defaults = Get-SetEnvDefaults -Path $setEnvBat
    foreach ($varName in $settingsVarLabels.Keys) {
        if ($kintoneVars -contains $varName) {
            $varValue = if ($defaults.ContainsKey($varName)) { $defaults[$varName] } else { "" }
            $group = "KINTONE"
        } else {
            if (!$defaults.ContainsKey($varName)) { continue }
            $varValue = $defaults[$varName]
            $group = "COMMON"
        }
        [PSCustomObject]@{ Group = $group; VarName = $varName; Value = $varValue; Key = $varName }
    }
}

$settingsTrailingButtonVars = @{
    "KINTONE_PASSWORD" = { param($Panel, $Y, $Field)
        $fieldTextBoxes = $script:fieldTextBoxes
        Add-FieldActionButton -Panel $Panel -Y $Y -Text "テスト接続" -AddStatusLabel -OnClick {
            try {
                Invoke-ActionWithUpdateStatus -StatusLabel $Field.StatusLabel -Action {
                    $subDomainVal = $fieldTextBoxes["KINTONE_SUB_DOMAIN"].Text.Trim()
                    $loginVal = $fieldTextBoxes["KINTONE_LOGIN"].Text
                    $passwordVal = $fieldTextBoxes["KINTONE_PASSWORD"].Text
                    $baseUrlVal = "https://$subDomainVal.cybozu.com"
                    if (!$subDomainVal -or !$loginVal -or !$passwordVal) {
                        throw "サブドメイン・ログイン名・パスワードをすべて入力してください"
                    }
                    $authorization = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes("${loginVal}:${passwordVal}"))
                    Invoke-KintoneRequest -BaseUrl $baseUrlVal -Authorization $authorization -Method GET -Path "/k/v1/apps.json?limit=1" | Out-Null
                    [System.Windows.Forms.MessageBox]::Show("テスト接続に成功しました。", "完了", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
                }
            } catch {
                [System.Windows.Forms.MessageBox]::Show("エラーが発生しました: $_", "エラー", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error)
            }
        }.GetNewClosure()
    }
}

function Update-SettingsFields {
    Render-SettingsFields -Panel $fieldPanel -Rows (Get-SettingsFieldRows) -TargetTextBoxes $script:fieldTextBoxes -TrailingButtonVars $settingsTrailingButtonVars `
        -GroupLabels $settingsGroupLabels -VarLabels $settingsVarLabels -ToolTip $settingsToolTip -RootPath $rootPath -EnvResolver $script:commonEnvResolver `
        -MultilineVars $settingsMultilineVars -MaskedVars $settingsMaskedVars -FolderBrowseVars $settingsFolderBrowseVars -FileBrowseVars $settingsFileBrowseVars | Out-Null
}

$script:saveEnvBatGetValueFn = { param($name)
    if ($script:fieldTextBoxes.ContainsKey($name)) {
        $script:fieldTextBoxes[$name].Text
    } else {
        ""
    }
}
$script:saveEnvBatHasValueFn = { param($name) $true }

function Save-Settings {
    $nonKintoneVars = @($settingsVarLabels.Keys | Where-Object { $kintoneVars -notcontains $_ })
    Save-EnvBatFile -Path $setEnvBat -VarNames $nonKintoneVars -GetValueFn $script:saveEnvBatGetValueFn -HasValueFn $script:saveEnvBatHasValueFn
    Save-EnvBatFile -Path $setEnvBat -VarNames $kintoneVars -GetValueFn $script:saveEnvBatGetValueFn -HasValueFn $script:saveEnvBatHasValueFn
}

$settingsTopPanel = New-SettingsTopPanel `
    -OnSave { Save-Settings } `
    -OnReload { Update-SettingsFields }
$topPanel = $settingsTopPanel.Panel
$tabSettings.Controls.Add($topPanel)

Update-SettingsFields

$tabControl.Add_SelectedIndexChanged({
    if ($tabControl.SelectedTab -eq $tabRun) {
        Update-BaseTemplateNameList
        Update-CustomTemplateNameList
    } elseif ($tabControl.SelectedTab -eq $tabLogs) {
        Update-LogConfigNameList
        Update-LogView
    } elseif ($tabControl.SelectedTab -eq $tabSettings) {
        Update-SettingsFields
    }
})

Update-BaseTemplateNameList
Update-CustomTemplateNameList

$form.Add_Shown({
    Update-InnerRunTabHeight
    Update-SettingsFields
})
$tabControl.SelectedTab = $tabRun

[System.Windows.Forms.Application]::Run($form)
