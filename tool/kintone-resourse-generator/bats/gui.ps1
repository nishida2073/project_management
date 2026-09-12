# =========================================
# GUI（kintoneリソース生成ツール）
# =========================================
# download-kintone-resources.bat → generate-config-from-template.bat →
# apply-kintone-resources.bat → check-kintone-resources.bat を画面から順番に実行するGUI。
# 「実行」タブでスペース識別名等を入力し、工程ごとの実行ボタン（個別実行）か「一括実行」（全工程を順番に実行）で実行する。
# 「設定」タブでset-env.batの値（COMMON_*の各パス）とset-kintone.batの値（kintoneの接続情報）を編集する。

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

[System.Windows.Forms.Application]::EnableVisualStyles()
[System.Windows.Forms.Application]::SetCompatibleTextRenderingDefault($false)

if ($MyInvocation.MyCommand.Path) {
    $scriptDir = Split-Path $MyInvocation.MyCommand.Path
    $basePath = Split-Path $scriptDir -Parent
} else {
    $basePath = Split-Path ([System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName)
}
$createSpaceBat = Join-Path $basePath "create-space-from-template.bat"
$downloadBat = Join-Path $basePath "download-kintone-resources.bat"
$generateBat = Join-Path $basePath "generate-config-from-template.bat"
$applyBat = Join-Path $basePath "apply-kintone-resources.bat"
$checkBat = Join-Path $basePath "check-kintone-resources.bat"
$clientsDir = Join-Path $basePath "clients"
$setEnvBat = Join-Path $clientsDir "set-env.bat"
$setKintoneBat = Join-Path $clientsDir "set-kintone.bat"
$cp932 = [System.Text.Encoding]::GetEncoding(932)
$lineRegex = [regex]'^if not defined (?<var>\S+) set "\k<var>=(?<val>.*)"$'

$libraryDir = Join-Path $basePath "bats\library"
Get-ChildItem -Path $libraryDir -Filter *.ps1 -Recurse | ForEach-Object {
    . $_.FullName
}

$env:GUI_LOG_MODE = "1"

$form = New-Object System.Windows.Forms.Form
$form.Text = "kintoneリソース生成ツール"
$form.Size = New-Object System.Drawing.Size(780, 560)
$form.StartPosition = "CenterScreen"
$form.MinimumSize = New-Object System.Drawing.Size(600, 500)

$script:currentProc = $null
$script:stepOutputPaths = @{}
$script:runHadWarning = $false
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
$innerRunTabControl.Height = 404

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

$script:baseTemplateNamePlaceholder = "未選択"

$script:customTemplateNamePlaceholder = "指定なし"

$cmbBaseTemplateName = New-Object System.Windows.Forms.ComboBox
$cmbBaseTemplateName.Size = New-Object System.Drawing.Size(220, 22)
$cmbBaseTemplateName.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList

$cmbCustomTemplateName = New-Object System.Windows.Forms.ComboBox
$cmbCustomTemplateName.Size = New-Object System.Drawing.Size(180, 22)
$cmbCustomTemplateName.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList

$configNameInputDef = [PSCustomObject]@{ Name = "ConfigName"; Label = "スペース識別名"; LabelWidth = 151; InputWidth = 200 }
$spaceTemplateIdInputDef = [PSCustomObject]@{ Name = "SpaceTemplateId"; Label = "スペーステンプレートID"; LabelWidth = 151; InputWidth = 200 }
$spaceIdInputDef = [PSCustomObject]@{ Name = "SpaceId"; Label = "スペースID"; LabelWidth = 151; InputWidth = 200 }
# BaseTemplateName/CustomTemplateNameはファイル一覧からの動的な再読み込み（Update-BaseTemplateNameList等）が
# 必要なため、ExistingControlで既存のComboBoxインスタンスをそのまま行に配置する（新規作成しない）
$baseTemplateNameInputDef = [PSCustomObject]@{ Name = "BaseTemplateName"; Label = "設定テンプレート名（基本）"; LabelWidth = 151; ExistingControl = $cmbBaseTemplateName }
$customTemplateNameInputDef = [PSCustomObject]@{ Name = "CustomTemplateName"; Label = "設定テンプレート名（カスタム）"; LabelWidth = 151; ExistingControl = $cmbCustomTemplateName }

$stepMeta = @(
    [PSCustomObject]@{
        Id = 0; Label = "スペース作成"; StageKey = "createspace"; Bat = $createSpaceBat
        Inputs = @($configNameInputDef, $spaceTemplateIdInputDef)
        ArgsFn = { param($ic) @("-TemplateId", $ic['SpaceTemplateId'].Text.Trim(), "-SpaceName", $ic['ConfigName'].Text.Trim()) }
        OutputPathFn = $null
        # 成功時に出力されるSPACE_IDを次工程（ダウンロード）のスペースID欄へ引き継ぐ
        OnSuccessFn = {
            param($ic, $lastOutputLines)
            $idLine = $lastOutputLines | Where-Object { $_ -match 'SPACE_ID=(\d+)' } | Select-Object -Last 1
            if ($idLine -and $idLine -match 'SPACE_ID=(?<id>\d+)') {
                $nextIc = $script:stepInputControls[1]
                if ($nextIc -and $nextIc.ContainsKey('SpaceId')) { $nextIc['SpaceId'].Text = $Matches.id }
            }
        }
    }
    [PSCustomObject]@{
        Id = 1; Label = "ダウンロード"; StageKey = "download"; Bat = $downloadBat
        Inputs = @($configNameInputDef, $spaceIdInputDef)
        ArgsFn = { param($ic) @("-SpaceId", $ic['SpaceId'].Text.Trim(), "-ConfigName", $ic['ConfigName'].Text.Trim()) }
        OutputPathFn = { param($ic) Join-Path (Get-ResolvedVar "COMMON_DOWNLOAD_PATH") "$($ic['ConfigName'].Text.Trim())_download.xlsx" }
        # スペース識別名を未入力で実行した場合、ダウンロードしたスペース名から自動設定された
        # 値（CONFIG_NAME=行）でこの工程自身のスペース識別名欄を更新する
        OnSuccessFn = {
            param($ic, $lastOutputLines)
            $configLine = $lastOutputLines | Where-Object { $_ -match 'CONFIG_NAME=(.+)$' } | Select-Object -Last 1
            if ($configLine -and $configLine -match 'CONFIG_NAME=(?<name>.+)$') {
                $ic['ConfigName'].Text = $Matches.name.Trim()
            }
        }
    }
    [PSCustomObject]@{
        Id = 2; Label = "設定ファイルの生成"; StageKey = "generate"; Bat = $generateBat
        Inputs = @($configNameInputDef, $baseTemplateNameInputDef, $customTemplateNameInputDef)
        ArgsFn = {
            param($ic)
            $stepArgs = @("-BaseTemplateConfigName", $ic['BaseTemplateName'].Text.Trim(), "-DownloadConfigName", $ic['ConfigName'].Text.Trim())
            $customTemplateName = $ic['CustomTemplateName'].Text.Trim()
            if ($customTemplateName -and $customTemplateName -ne $script:customTemplateNamePlaceholder) {
                $stepArgs += @("-CustomTemplateConfigName", $customTemplateName)
            }
            $stepArgs
        }
        OutputPathFn = { param($ic) Join-Path (Get-ResolvedVar "COMMON_CONFIG_PATH") "$($ic['ConfigName'].Text.Trim())_config.xlsx" }
    }
    [PSCustomObject]@{
        Id = 3; Label = "kintoneへ反映"; StageKey = "apply"; Bat = $applyBat
        Inputs = @($configNameInputDef)
        ArgsFn = { param($ic) @("-ConfigName", $ic['ConfigName'].Text.Trim()) }
        OutputPathFn = $null
    }
    [PSCustomObject]@{
        Id = 4; Label = "データチェック"; StageKey = "check"; Bat = $checkBat
        Inputs = @($configNameInputDef)
        ArgsFn = { param($ic) @("-ConfigName", $ic['ConfigName'].Text.Trim()) }
        OutputPathFn = { param($ic) Join-Path (Get-ResolvedVar "COMMON_CHECK_OUTPUT_PATH") "$($ic['ConfigName'].Text.Trim())_check.xlsx" }
    }
)
$script:stepMetaById = @{}
foreach ($sm in $stepMeta) { $script:stepMetaById[$sm.Id] = $sm }

$categoryDefs = @($stepMeta | ForEach-Object {
    $stepId = $_.Id
    [PSCustomObject]@{
        Label = $_.Label
        ButtonDefs = @(
            [PSCustomObject]@{
                Label      = $_.Label
                Id         = $stepId
                Inputs     = $_.Inputs
                OpenTarget = if ($_.OutputPathFn) { { $script:stepOutputPaths[$stepId] }.GetNewClosure() } else { $null }
            }
        )
    }
})

$stepTabControl = New-Object System.Windows.Forms.TabControl

$tabRunAll = New-Object System.Windows.Forms.TabPage
$tabRunAll.Text = "一括実行"
$stepTabControl.Controls.Add($tabRunAll)

$runAllPanel = New-Object System.Windows.Forms.Panel
$runAllPanel.Location = New-Object System.Drawing.Point(0, 0)
$tabRunAll.Controls.Add($runAllPanel)

$grpRunAll = New-Object System.Windows.Forms.GroupBox
$grpRunAll.Text = "一括実行"
$grpRunAll.Location = New-Object System.Drawing.Point(10, 10)
$grpRunAll.Size = New-Object System.Drawing.Size(730, 60)
$grpRunAll.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left -bor [System.Windows.Forms.AnchorStyles]::Right
$runAllPanel.Controls.Add($grpRunAll)

$lblRunAllConfigName = New-Object System.Windows.Forms.Label
$lblRunAllConfigName.Text = "スペース識別名"
$lblRunAllConfigName.AutoSize = $true
$lblRunAllConfigName.Location = New-Object System.Drawing.Point(15, 18)
$grpRunAll.Controls.Add($lblRunAllConfigName)

$txtRunAllConfigName = New-Object System.Windows.Forms.TextBox
$txtRunAllConfigName.Size = New-Object System.Drawing.Size(200, 22)
$txtRunAllConfigName.Location = New-Object System.Drawing.Point(170, 15)
$grpRunAll.Controls.Add($txtRunAllConfigName)

$lblRunAllSpaceTemplateId = New-Object System.Windows.Forms.Label
$lblRunAllSpaceTemplateId.Text = "スペーステンプレートID"
$lblRunAllSpaceTemplateId.AutoSize = $true
$lblRunAllSpaceTemplateId.Location = New-Object System.Drawing.Point(15, 53)
$grpRunAll.Controls.Add($lblRunAllSpaceTemplateId)

$txtRunAllSpaceTemplateId = New-Object System.Windows.Forms.TextBox
$txtRunAllSpaceTemplateId.Size = New-Object System.Drawing.Size(200, 22)
$txtRunAllSpaceTemplateId.Location = New-Object System.Drawing.Point(170, 50)
$grpRunAll.Controls.Add($txtRunAllSpaceTemplateId)

$lblRunAllBaseTemplateName = New-Object System.Windows.Forms.Label
$lblRunAllBaseTemplateName.Text = "設定テンプレート名（基本）"
$lblRunAllBaseTemplateName.AutoSize = $true
$lblRunAllBaseTemplateName.Location = New-Object System.Drawing.Point(15, 88)
$grpRunAll.Controls.Add($lblRunAllBaseTemplateName)

$cmbRunAllBaseTemplateName = New-Object System.Windows.Forms.ComboBox
$cmbRunAllBaseTemplateName.Size = New-Object System.Drawing.Size(220, 22)
$cmbRunAllBaseTemplateName.Location = New-Object System.Drawing.Point(170, 85)
$cmbRunAllBaseTemplateName.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$grpRunAll.Controls.Add($cmbRunAllBaseTemplateName)

$lblRunAllCustomTemplateName = New-Object System.Windows.Forms.Label
$lblRunAllCustomTemplateName.Text = "設定テンプレート名（カスタム）"
$lblRunAllCustomTemplateName.AutoSize = $true
$lblRunAllCustomTemplateName.Location = New-Object System.Drawing.Point(15, 123)
$grpRunAll.Controls.Add($lblRunAllCustomTemplateName)

$cmbRunAllCustomTemplateName = New-Object System.Windows.Forms.ComboBox
$cmbRunAllCustomTemplateName.Size = New-Object System.Drawing.Size(180, 22)
$cmbRunAllCustomTemplateName.Location = New-Object System.Drawing.Point(170, 120)
$cmbRunAllCustomTemplateName.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList
$grpRunAll.Controls.Add($cmbRunAllCustomTemplateName)

$btnRunAll = New-Object System.Windows.Forms.Button
$btnRunAll.Text = "実行"
$btnRunAll.Size = New-Object System.Drawing.Size(100, 28)
$btnRunAll.Location = New-Object System.Drawing.Point(15, 158)
$grpRunAll.Controls.Add($btnRunAll)

$lblOverallStatus = New-Object System.Windows.Forms.Label
$lblOverallStatus.Text = ""
$lblOverallStatus.AutoSize = $true
$lblOverallStatus.Location = New-Object System.Drawing.Point(130, 164)
$lblOverallStatus.Font = New-Object System.Drawing.Font($lblOverallStatus.Font, [System.Drawing.FontStyle]::Bold)
$grpRunAll.Controls.Add($lblOverallStatus)

$grpRunAll.Size = New-Object System.Drawing.Size(730, ($btnRunAll.Bottom + 10))
$runAllPanel.Size = New-Object System.Drawing.Size(750, ($grpRunAll.Bottom + 10))

$stepTabResult = New-CategoryTabControl -CategoryDefs $categoryDefs -TabControl $stepTabControl `
    -OnRunClick { param($bd) Invoke-SingleStep -Id $bd.Id }

$script:stepStatusLabels = @{}
$script:stepInputControls = @{}
foreach ($cd in $categoryDefs) {
    $bd = $cd.ButtonDefs[0]
    $script:stepStatusLabels[$bd.Id] = $bd.StepStatusLabel
    $script:stepInputControls[$bd.Id] = $bd.InputControls
}

$stepTabControl.Dock = [System.Windows.Forms.DockStyle]::None
$stepTabControl.Location = New-Object System.Drawing.Point(0, 0)
$stepTabControl.Width = 760
$runTopPanel.Controls.Add($stepTabControl)

$stepTabControl.Height = 45 + $runAllPanel.Height

$stepTabControl.Add_SelectedIndexChanged({
    $runTopPanel.Height = $stepTabControl.Top + $stepTabControl.Height
    Update-InnerRunTabHeight
})
$runTopPanel.Height = $stepTabControl.Top + $stepTabControl.Height

function Update-InnerRunTabHeight {
    if ($innerRunTabControl.SelectedTab -eq $tabBatchRun) {
        $innerRunTabControl.Height = $batchPanel.Height + 30
    } else {
        $innerRunTabControl.Height = $runTopPanel.Height + 30
    }
    $tabRun.PerformLayout()
}

$batchPanel = New-Object System.Windows.Forms.Panel
$batchPanel.Dock = [System.Windows.Forms.DockStyle]::Top
$batchPanel.Height = 90

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
$lblBatchStatus.Font = New-Object System.Drawing.Font($lblBatchStatus.Font, [System.Drawing.FontStyle]::Bold)

$batchPanel.Controls.AddRange(@(
    $lblBatchExcelPath, $txtBatchExcelPath, $btnBatchBrowse, $btnBatchRunAll, $lblBatchStatus
))

$dlgBatchExcel = New-Object System.Windows.Forms.OpenFileDialog
$dlgBatchExcel.Filter = "Excelファイル (*.xlsx)|*.xlsx"

$btnBatchBrowse.Add_Click({
    if ($dlgBatchExcel.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $txtBatchExcelPath.Text = $dlgBatchExcel.FileName
    }
})

$txtLog = New-LogTextBox

$tabSingleRun.Controls.Add($runTopPanel)
$tabBatchRun.Controls.Add($batchPanel)

$tabRun.Controls.Add($txtLog)
$tabRun.Controls.Add($innerRunTabControl)

function Write-Log {
    param([string]$Text)
    Write-ColoredLine -TextBox $txtLog -Text $Text
}

function Get-StepBat {
    param([int]$Id)
    return $script:stepMetaById[$Id].Bat
}

function Get-StepArgs {
    param([int]$Id)
    return & $script:stepMetaById[$Id].ArgsFn $script:stepInputControls[$Id]
}

function Get-StepOutputPath {
    param([int]$Id)
    $sm = $script:stepMetaById[$Id]
    if (!$sm.OutputPathFn) { return $null }
    return & $sm.OutputPathFn $script:stepInputControls[$Id]
}

function Test-StepPrereq {
    param([int]$Id)
    $ic = $script:stepInputControls[$Id]
    if ($Id -ne 1 -and !$ic['ConfigName'].Text.Trim()) {
        [System.Windows.Forms.MessageBox]::Show("スペース識別名を入力してください。", "実行", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        return $false
    }
    if ($Id -eq 0 -and !$ic['SpaceTemplateId'].Text.Trim()) {
        [System.Windows.Forms.MessageBox]::Show("スペース作成にはスペーステンプレートIDが必要です。", "実行", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        return $false
    }
    if ($Id -eq 1 -and !$ic['SpaceId'].Text.Trim()) {
        [System.Windows.Forms.MessageBox]::Show("ダウンロードにはスペースIDが必要です。", "実行", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        return $false
    }
    if ($Id -eq 2 -and (!$ic['BaseTemplateName'].Text.Trim() -or $ic['BaseTemplateName'].Text.Trim() -eq $script:baseTemplateNamePlaceholder)) {
        [System.Windows.Forms.MessageBox]::Show("設定ファイルの生成には設定テンプレート名（基本）が必要です。", "実行", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        return $false
    }
    return $true
}

function Set-StepStatus {
    param([int]$Id, [string]$Text)
    $lbl = $script:stepStatusLabels[$Id]
    $lbl.Text = $Text
    $lbl.ForeColor = switch ($Text) {
        "実行中..." { [System.Drawing.Color]::Black }
        "成功"      { [System.Drawing.Color]::DarkGreen }
        "警告"      { [System.Drawing.Color]::DarkOrange }
        "失敗"      { [System.Drawing.Color]::DarkRed }
        default     { [System.Drawing.Color]::Gray }
    }
}

function Set-RunControlsEnabled {
    param([bool]$Enabled)
    foreach ($ic in $script:stepInputControls.Values) {
        foreach ($ctrl in $ic.Values) { $ctrl.Enabled = $Enabled }
    }
    $cmbBaseTemplateName.Enabled = $Enabled
    $cmbCustomTemplateName.Enabled = $Enabled
    $txtRunAllConfigName.Enabled = $Enabled
    $txtRunAllSpaceTemplateId.Enabled = $Enabled
    $cmbRunAllBaseTemplateName.Enabled = $Enabled
    $cmbRunAllCustomTemplateName.Enabled = $Enabled
    $btnRunAll.Enabled = $Enabled
    $btnBatchBrowse.Enabled = $Enabled
    $btnBatchRunAll.Enabled = $Enabled
    foreach ($btn in $stepTabResult.RunButtons) { $btn.Enabled = $Enabled }
}

function Sync-NextStepConfigName {
    param([int]$CompletedId)
    $curIc = $script:stepInputControls[$CompletedId]
    $nextIc = $script:stepInputControls[($CompletedId + 1)]
    if (!$curIc -or !$nextIc -or !$curIc.ContainsKey('ConfigName') -or !$nextIc.ContainsKey('ConfigName')) { return }
    $nextIc['ConfigName'].Text = $curIc['ConfigName'].Text.Trim()
}

function Invoke-Step {
    param([int]$Id)

    $sm = $script:stepMetaById[$Id]
    Set-StepStatus -Id $Id -Text "実行中..."
    Write-Log ""
    Write-Log "--------------- $($sm.Label) 開始 ---------------"

    $script:lastStepOutputLines = New-Object System.Collections.Generic.List[string]
    $exitCode = Invoke-BatStep -BatPath $sm.Bat -WorkingDirectory $basePath -BatArgs (Get-StepArgs -Id $Id) `
        -OnOutputLine { param($line) Write-Log $line; $script:lastStepOutputLines.Add($line) } `
        -CurrentProcessRef ([ref]$script:currentProc)

    $outputPath = Get-StepOutputPath -Id $Id
    if ($outputPath -and (Test-Path -LiteralPath $outputPath)) {
        $script:stepOutputPaths[$Id] = $outputPath
    }

    if ($exitCode -ne 0 -and $exitCode -ne 2) {
        Write-Log "--------------- $($sm.Label) 失敗（終了コード: $exitCode） ---------------"
        Set-StepStatus -Id $Id -Text "失敗"
        return $false
    }

    if ($exitCode -eq 2) {
        $script:runHadWarning = $true
        Write-Log "--------------- $($sm.Label) 完了（警告あり） ---------------"
    } else {
        Write-Log "--------------- $($sm.Label) 完了 ---------------"
    }
    Set-StepStatus -Id $Id -Text $(if ($exitCode -eq 2) { "警告" } else { "成功" })

    # 工程ごとの後処理（出力からの値の取り込みなど）はOnSuccessFnに任せ、Invoke-Step自体は
    # 工程の中身を知らない汎用ランナーのままにする。ConfigNameの次工程への引き継ぎは全工程共通のため、
    # OnSuccessFnより後に無条件で行う（工程自身がConfigNameを更新した場合はその後の値が伝播する）
    if ($sm.OnSuccessFn) { & $sm.OnSuccessFn $script:stepInputControls[$Id] $script:lastStepOutputLines }
    Sync-NextStepConfigName -CompletedId $Id
    return $true
}

function Invoke-SingleStep {
    param([int]$Id)

    if (!(Test-StepPrereq -Id $Id)) { return }

    $script:isRunning = $true
    Set-RunControlsEnabled $false
    $lblOverallStatus.Text = ""

    Invoke-Step -Id $Id | Out-Null

    Set-RunControlsEnabled $true
    $script:isRunning = $false
}

function Invoke-AllStepsForCurrentInputs {
    $script:runHadWarning = $false
    foreach ($sm in $stepMeta) {
        if (!(Test-StepPrereq -Id $sm.Id)) {
            return $sm.Label
        }
        if (!(Invoke-Step -Id $sm.Id)) {
            return $sm.Label
        }
    }
    return $null
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

function Invoke-SeededAllSteps {
    foreach ($sm in $stepMeta) {
        $script:stepInputControls[$sm.Id]['ConfigName'].Text = $txtRunAllConfigName.Text.Trim()
    }
    $script:stepInputControls[0]['SpaceTemplateId'].Text = $txtRunAllSpaceTemplateId.Text.Trim()
    Copy-ComboSelection -From $cmbRunAllBaseTemplateName -To $cmbBaseTemplateName
    Copy-ComboSelection -From $cmbRunAllCustomTemplateName -To $cmbCustomTemplateName
    return Invoke-AllStepsForCurrentInputs
}

$btnRunAll.Add_Click({
    $seedConfigName = $txtRunAllConfigName.Text.Trim()
    if (!$seedConfigName) {
        [System.Windows.Forms.MessageBox]::Show("スペース識別名を入力してください。", "実行", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        return
    }

    $script:isRunning = $true
    Set-RunControlsEnabled $false
    $lblOverallStatus.ForeColor = [System.Drawing.Color]::Black
    $lblOverallStatus.Text = "実行中..."

    $failedLabel = Invoke-SeededAllSteps

    if ($failedLabel) {
        $lblOverallStatus.ForeColor = [System.Drawing.Color]::DarkRed
        $lblOverallStatus.Text = "エラーが発生しました（$failedLabel）"
    } elseif ($script:runHadWarning) {
        $lblOverallStatus.ForeColor = [System.Drawing.Color]::DarkOrange
        $lblOverallStatus.Text = "完了しました（警告あり、要確認）"
    } else {
        $lblOverallStatus.ForeColor = [System.Drawing.Color]::DarkGreen
        $lblOverallStatus.Text = "完了しました"
    }

    Set-RunControlsEnabled $true
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
        $rows = @(Import-Excel -Path $excelPath)
    } catch {
        [System.Windows.Forms.MessageBox]::Show("Excelの読み込みに失敗しました: $($_.Exception.Message)", "複数実行", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        return
    }
    if ($rows.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("Excelに行がありません。", "複数実行", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        return
    }

    $script:isRunning = $true
    Set-RunControlsEnabled $false

    $origConfigNames = @{}
    foreach ($sm in $stepMeta) { $origConfigNames[$sm.Id] = $script:stepInputControls[$sm.Id]['ConfigName'].Text }
    $origSpaceTemplateId = $script:stepInputControls[0]['SpaceTemplateId'].Text
    $origSpaceId = $script:stepInputControls[1]['SpaceId'].Text
    $origBaseTemplateSelectedItem = $cmbBaseTemplateName.SelectedItem
    $origBaseTemplateText = $cmbBaseTemplateName.Text
    $origCustomTemplateSelectedItem = $cmbCustomTemplateName.SelectedItem
    $origCustomTemplateText = $cmbCustomTemplateName.Text

    $resultLines = New-Object System.Collections.Generic.List[string]
    for ($i = 0; $i -lt $rows.Count; $i++) {
        $row = $rows[$i]
        $rowConfigName = "$($row.'スペース識別名')".Trim()
        $rowTemplateId = "$($row.'スペーステンプレートID')".Trim()
        $rowBaseResourceTemplate = "$($row.'設定テンプレート名（基本）')".Trim()
        $rowCustomResourceTemplate = "$($row.'設定テンプレート名（カスタム）')".Trim()

        $lblBatchStatus.ForeColor = [System.Drawing.Color]::Black
        $lblBatchStatus.Text = "実行中... ($($i + 1)/$($rows.Count): $rowConfigName)"
        [System.Windows.Forms.Application]::DoEvents()

        Write-Log ""
        Write-Log "==================== 複数実行 $($i + 1)/$($rows.Count): $rowConfigName ===================="

        if (!$rowConfigName -or !$rowTemplateId -or !$rowBaseResourceTemplate) {
            Write-Log "スペース識別名・スペーステンプレートID・設定テンプレート名（基本）のいずれかが空のためスキップします。"
            $resultLines.Add("行$($i + 2) ($rowConfigName): スキップ（必須項目が空）")
            continue
        }

        $script:stepInputControls[0]['ConfigName'].Text = $rowConfigName
        $script:stepInputControls[0]['SpaceTemplateId'].Text = $rowTemplateId
        $script:stepInputControls[1]['SpaceId'].Text = ""
        if ($cmbBaseTemplateName.Items.Contains($rowBaseResourceTemplate)) {
            $cmbBaseTemplateName.SelectedItem = $rowBaseResourceTemplate
        } else {
            $cmbBaseTemplateName.Text = $rowBaseResourceTemplate
        }
        if (!$rowCustomResourceTemplate) {
            $cmbCustomTemplateName.SelectedItem = $script:customTemplateNamePlaceholder
        } elseif ($cmbCustomTemplateName.Items.Contains($rowCustomResourceTemplate)) {
            $cmbCustomTemplateName.SelectedItem = $rowCustomResourceTemplate
        } else {
            $cmbCustomTemplateName.Text = $rowCustomResourceTemplate
        }

        $failedLabel = Invoke-AllStepsForCurrentInputs
        if ($failedLabel) {
            $resultLines.Add("行$($i + 2) ($rowConfigName): 失敗（$failedLabel）")
        } elseif ($script:runHadWarning) {
            $resultLines.Add("行$($i + 2) ($rowConfigName): 成功（警告あり、要確認）")
        } else {
            $resultLines.Add("行$($i + 2) ($rowConfigName): 成功")
        }
    }

    Write-Log ""
    Write-Log "==================== 複数実行 結果 ===================="
    foreach ($line in $resultLines) { Write-Log $line }

    $failedCount = @($resultLines | Where-Object { $_ -match ": 失敗|: スキップ" }).Count
    $warningCount = @($resultLines | Where-Object { $_ -match "警告あり" }).Count
    if ($failedCount -gt 0) {
        $lblBatchStatus.ForeColor = [System.Drawing.Color]::DarkRed
        $lblBatchStatus.Text = "完了（$($rows.Count)件中$failedCount件が失敗/スキップ）"
    } elseif ($warningCount -gt 0) {
        $lblBatchStatus.ForeColor = [System.Drawing.Color]::DarkOrange
        $lblBatchStatus.Text = "完了しました（$($rows.Count)件中$warningCount件で警告あり、要確認）"
    } else {
        $lblBatchStatus.ForeColor = [System.Drawing.Color]::DarkGreen
        $lblBatchStatus.Text = "完了しました（全$($rows.Count)件成功）"
    }

    foreach ($sm in $stepMeta) { $script:stepInputControls[$sm.Id]['ConfigName'].Text = $origConfigNames[$sm.Id] }
    $script:stepInputControls[0]['SpaceTemplateId'].Text = $origSpaceTemplateId
    $script:stepInputControls[1]['SpaceId'].Text = $origSpaceId
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

    Set-RunControlsEnabled $true
    $script:isRunning = $false
})

function Read-EnvBatLines {
    param([string]$Path = $setEnvBat)
    if (!(Test-Path -LiteralPath $Path)) { return @() }
    return [System.IO.File]::ReadAllLines($Path, $cp932)
}

function Get-EnvBatDefaults {
    param([string]$Path = $setEnvBat)
    $result = @{}
    foreach ($line in (Read-EnvBatLines -Path $Path)) {
        $m = $lineRegex.Match($line.Trim())
        if ($m.Success) {
            $result[$m.Groups["var"].Value] = $m.Groups["val"].Value
        }
    }
    return $result
}

function Expand-VarTokens {
    param([string]$Value)
    if (!$Value) { return $Value }
    $expanded = $Value.Replace("%BASE_PATH%", "$basePath\")
    $expanded = [regex]::Replace($expanded, '%(\w+)%', {
        param($match)
        $refVal = Get-ResolvedVar $match.Groups[1].Value
        if ($refVal) { $refVal } else { $match.Value }
    })
    return $expanded
}

function Get-ResolvedVar {
    param([string]$VarName)
    $val = [Environment]::GetEnvironmentVariable($VarName)
    if (!$val) {
        $defaults = Get-EnvBatDefaults
        if ($defaults.ContainsKey($VarName)) {
            $val = $defaults[$VarName]
        }
    }
    if (!$val) { return $val }
    return Expand-VarTokens $val
}

function Resolve-BrowseStart {
    param([string]$RawValue)
    if (!$RawValue) { return $basePath }
    return Expand-VarTokens $RawValue
}

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

# 「2. 設定ファイルの生成」タブと「一括実行」タブの両方に同名コンボがあるため、
# 一覧取得（ファイルI/O）は1回だけ行い、結果を両方のコンボへ適用する
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

$topPanel = New-Object System.Windows.Forms.Panel
$topPanel.Dock = [System.Windows.Forms.DockStyle]::Top
$topPanel.Height = 46

$btnSave = New-Object System.Windows.Forms.Button
$btnSave.Text = "保存"
$btnSave.Location = New-Object System.Drawing.Point(20, 11)
$btnSave.Size = New-Object System.Drawing.Size(100, 24)

$btnReload = New-Object System.Windows.Forms.Button
$btnReload.Text = "再読込"
$btnReload.Location = New-Object System.Drawing.Point(130, 11)
$btnReload.Size = New-Object System.Drawing.Size(100, 24)

$lblSaveStatus = New-Object System.Windows.Forms.Label
$lblSaveStatus.Text = ""
$lblSaveStatus.AutoSize = $true
$lblSaveStatus.Location = New-Object System.Drawing.Point(244, 17)
$lblSaveStatus.Font = New-Object System.Drawing.Font($lblSaveStatus.Font, [System.Drawing.FontStyle]::Bold)

$topPanel.Controls.AddRange(@($btnSave, $btnReload, $lblSaveStatus))

function Test-KintoneConnectionFromFields {
    param(
        [System.Windows.Forms.Button]$Button,
        [System.Windows.Forms.Label]$StatusLabel
    )

    $baseUrlVal = $script:fieldTextBoxes["KINTONE_BASE_URL"].Text.Trim()
    $loginVal = $script:fieldTextBoxes["KINTONE_LOGIN"].Text
    $passwordVal = $script:fieldTextBoxes["KINTONE_PASSWORD"].Text

    if (!$baseUrlVal -or !$loginVal -or !$passwordVal) {
        $StatusLabel.ForeColor = [System.Drawing.Color]::DarkRed
        $StatusLabel.Text = "kintoneのサイトURL・ログイン名・パスワードをすべて入力してください"
        return
    }

    $Button.Enabled = $false
    $StatusLabel.ForeColor = [System.Drawing.Color]::Black
    $StatusLabel.Text = "接続テスト中..."
    [System.Windows.Forms.Application]::DoEvents()

    try {
        $pair = "${loginVal}:${passwordVal}"
        $authorization = [Convert]::ToBase64String([System.Text.Encoding]::UTF8.GetBytes($pair))
        Invoke-KintoneRequest -BaseUrl $baseUrlVal -Authorization $authorization -Method GET -Path "/k/v1/apps.json?limit=1" | Out-Null
        $StatusLabel.ForeColor = [System.Drawing.Color]::DarkGreen
        $StatusLabel.Text = "成功しました"
    } catch {
        $StatusLabel.ForeColor = [System.Drawing.Color]::DarkRed
        $StatusLabel.Text = "失敗しました（$($_.Exception.Message)）"
    }

    $Button.Enabled = $true
}

$fieldPanel = New-Object System.Windows.Forms.Panel
$fieldPanel.Dock = [System.Windows.Forms.DockStyle]::Fill
$fieldPanel.AutoScroll = $true

$tabSettings.Controls.Add($fieldPanel)
$tabSettings.Controls.Add($topPanel)

$varLabels = [ordered]@{
    "COMMON_DOWNLOAD_PATH"     = "ダウンロード先のフォルダ"
    "COMMON_BASE_TEMPLATE_PATH"     = "設定テンプレート（基本）ファイルのフォルダ"
    "COMMON_CUSTOM_TEMPLATE_PATH"   = "設定テンプレート（カスタム）ファイルのフォルダ"
    "COMMON_CONFIG_PATH"       = "設定ファイルのフォルダ"
    "COMMON_CHECK_OUTPUT_PATH" = "チェック結果の出力先フォルダ"
    "COMMON_LOG_PATH"          = "ログの出力先フォルダ"
    "KINTONE_BASE_URL"         = "kintoneのサイトURL"
    "KINTONE_LOGIN"            = "ログイン名"
    "KINTONE_PASSWORD"         = "パスワード"
}

$folderBrowseVars = @("COMMON_DOWNLOAD_PATH", "COMMON_BASE_TEMPLATE_PATH", "COMMON_CUSTOM_TEMPLATE_PATH", "COMMON_CONFIG_PATH", "COMMON_CHECK_OUTPUT_PATH", "COMMON_LOG_PATH")

$kintoneVars = @("KINTONE_BASE_URL", "KINTONE_LOGIN", "KINTONE_PASSWORD")
$passwordVars = @("KINTONE_PASSWORD")

$script:fieldTextBoxes = @{}

function Update-SettingsFields {
    $fieldPanel.Controls.Clear()
    $script:fieldTextBoxes = @{}

    $defaults = Get-EnvBatDefaults -Path $setEnvBat
    $kintoneDefaults = Get-EnvBatDefaults -Path $setKintoneBat
    $y = 10

    foreach ($varName in $varLabels.Keys) {
        $isKintoneVar = $kintoneVars -contains $varName
        if ($isKintoneVar) {
            $varValue = if ($kintoneDefaults.ContainsKey($varName)) { $kintoneDefaults[$varName] } else { "" }
        } else {
            if (!$defaults.ContainsKey($varName)) { continue }
            $varValue = $defaults[$varName]
        }

        if ($varName -eq "KINTONE_BASE_URL") {
            $y += 8
            $lblKintoneHeader = New-Object System.Windows.Forms.Label
            $lblKintoneHeader.Text = "kintoneの接続情報"
            $lblKintoneHeader.AutoSize = $true
            $lblKintoneHeader.Location = New-Object System.Drawing.Point(20, $y)
            $lblKintoneHeader.Font = New-Object System.Drawing.Font($lblKintoneHeader.Font, [System.Drawing.FontStyle]::Bold)
            $fieldPanel.Controls.Add($lblKintoneHeader)
            $y += 28
        }

        $lbl = New-Object System.Windows.Forms.Label
        $lbl.Text = $varLabels[$varName]
        $lbl.AutoSize = $false
        $lbl.Size = New-Object System.Drawing.Size(280, 20)
        $lbl.Location = New-Object System.Drawing.Point(20, $y)
        $fieldPanel.Controls.Add($lbl)

        if ($folderBrowseVars -contains $varName) {
            $txt = New-Object System.Windows.Forms.TextBox
            $txt.Text = $varValue
            $txt.Location = New-Object System.Drawing.Point(310, ($y - 2))
            $txt.Size = New-Object System.Drawing.Size(300, 22)
            $txt.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left

            $btnBrowse = New-Object System.Windows.Forms.Button
            $btnBrowse.Text = "参照..."
            $btnBrowse.Location = New-Object System.Drawing.Point(620, ($y - 3))
            $btnBrowse.Size = New-Object System.Drawing.Size(70, 24)
            $btnBrowse.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left
            $btnBrowse.Tag = $txt
            $btnBrowse.Add_Click({
                $targetTxt = $this.Tag
                $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
                $startPath = Resolve-BrowseStart $targetTxt.Text
                if (Test-Path -LiteralPath $startPath) {
                    $dlg.SelectedPath = $startPath
                }
                if ($dlg.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
                    $targetTxt.Text = $dlg.SelectedPath
                }
            })

            $fieldPanel.Controls.AddRange(@($txt, $btnBrowse))
            $script:fieldTextBoxes[$varName] = $txt
        } else {
            $txt = New-Object System.Windows.Forms.TextBox
            $txt.Text = $varValue
            $txt.Location = New-Object System.Drawing.Point(310, ($y - 2))
            $txt.Size = New-Object System.Drawing.Size(380, 22)
            $txt.Anchor = [System.Windows.Forms.AnchorStyles]::Top -bor [System.Windows.Forms.AnchorStyles]::Left
            if ($passwordVars -contains $varName) {
                $txt.UseSystemPasswordChar = $true
            }

            $fieldPanel.Controls.Add($txt)
            $script:fieldTextBoxes[$varName] = $txt
        }

        $y += 32
    }

    $y += 4
    $btnTestConnection = New-Object System.Windows.Forms.Button
    $btnTestConnection.Text = "接続テスト"
    $btnTestConnection.Location = New-Object System.Drawing.Point(310, $y)
    $btnTestConnection.Size = New-Object System.Drawing.Size(100, 26)
    $fieldPanel.Controls.Add($btnTestConnection)
    $y += 32

    $lblTestStatus = New-Object System.Windows.Forms.Label
    $lblTestStatus.Text = ""
    $lblTestStatus.AutoSize = $true
    $lblTestStatus.MaximumSize = New-Object System.Drawing.Size(420, 0)
    $lblTestStatus.Location = New-Object System.Drawing.Point(310, $y)
    $lblTestStatus.Font = New-Object System.Drawing.Font($lblTestStatus.Font, [System.Drawing.FontStyle]::Bold)
    $fieldPanel.Controls.Add($lblTestStatus)

    $btnTestConnection.Tag = $lblTestStatus
    $btnTestConnection.Add_Click({ Test-KintoneConnectionFromFields -Button $this -StatusLabel $this.Tag })
}

$btnReload.Add_Click({
    Update-SettingsFields
    $lblSaveStatus.ForeColor = [System.Drawing.Color]::Black
    $lblSaveStatus.Text = "再読込しました"
})

function Save-EnvBatFile {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string[]]$VarNames
    )
    $existingLines = Read-EnvBatLines -Path $Path
    $writtenVars = @{}

    $newLines = @(foreach ($line in $existingLines) {
        $m = $lineRegex.Match($line.Trim())
        $varName = if ($m.Success) { $m.Groups["var"].Value } else { $null }
        if ($varName -and $VarNames -contains $varName -and $script:fieldTextBoxes.ContainsKey($varName)) {
            $writtenVars[$varName] = $true
            $newVal = $script:fieldTextBoxes[$varName].Text
            "if not defined $varName set `"$varName=$newVal`""
        } else {
            $line
        }
    })

    foreach ($varName in $VarNames) {
        if (!$writtenVars.ContainsKey($varName) -and $script:fieldTextBoxes.ContainsKey($varName)) {
            $newLines += "if not defined $varName set `"$varName=$($script:fieldTextBoxes[$varName].Text)`""
        }
    }
    if ($existingLines.Count -eq 0) {
        $newLines = @("@echo off", "") + $newLines
    }

    $content = ($newLines -join "`r`n") + "`r`n"
    [System.IO.File]::WriteAllText($Path, $content, $cp932)
}

$btnSave.Add_Click({
    Save-EnvBatFile -Path $setEnvBat -VarNames @($varLabels.Keys | Where-Object { $kintoneVars -notcontains $_ })
    Save-EnvBatFile -Path $setKintoneBat -VarNames $kintoneVars

    $lblSaveStatus.ForeColor = [System.Drawing.Color]::DarkGreen
    $lblSaveStatus.Text = "保存しました"
})

Update-SettingsFields

$logStagePanel = New-Object System.Windows.Forms.Panel
$logStagePanel.Dock = [System.Windows.Forms.DockStyle]::Top
$logStagePanel.Height = 90

$lblLogConfigName = New-Object System.Windows.Forms.Label
$lblLogConfigName.Text = "スペース識別名"
$lblLogConfigName.AutoSize = $true
$lblLogConfigName.Location = New-Object System.Drawing.Point(20, 17)

$cmbLogConfigName = New-Object System.Windows.Forms.ComboBox
$cmbLogConfigName.Location = New-Object System.Drawing.Point(160, 14)
$cmbLogConfigName.Size = New-Object System.Drawing.Size(220, 24)
$cmbLogConfigName.DropDownStyle = [System.Windows.Forms.ComboBoxStyle]::DropDownList

$btnClearLogs = New-Object System.Windows.Forms.Button
$btnClearLogs.Text = "ログをすべて削除"
$btnClearLogs.Location = New-Object System.Drawing.Point(420, 13)
$btnClearLogs.Size = New-Object System.Drawing.Size(140, 26)
$btnClearLogs.Add_Click({
    $logPath = Get-ResolvedVar "COMMON_LOG_PATH"
    if (-not $logPath -or -not (Test-Path -LiteralPath $logPath)) { return }

    $logFiles = @(Get-ChildItem -LiteralPath $logPath -Filter "*.log" -ErrorAction SilentlyContinue)
    if ($logFiles.Count -eq 0) {
        [System.Windows.Forms.MessageBox]::Show("削除対象のログファイルがありません。", "ログの削除", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
        return
    }

    $confirm = [System.Windows.Forms.MessageBox]::Show("ログファイルを$($logFiles.Count)件すべて削除します。よろしいですか？", "ログの削除", [System.Windows.Forms.MessageBoxButtons]::YesNo, [System.Windows.Forms.MessageBoxIcon]::Warning)
    if ($confirm -ne [System.Windows.Forms.DialogResult]::Yes) { return }

    foreach ($file in $logFiles) {
        try {
            Remove-Item -LiteralPath $file.FullName -Force
        } catch {
            [System.Windows.Forms.MessageBox]::Show("削除に失敗したファイルがあります: $($file.Name)`r`n$($_.Exception.Message)", "ログの削除", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        }
    }
    Update-LogConfigNameList
    Update-LogView
})

$script:logStageRadios = @{}
for ($i = 0; $i -lt $stepMeta.Count; $i++) {
    $sm = $stepMeta[$i]
    $radio = New-Object System.Windows.Forms.RadioButton
    $radio.Text = $sm.Label
    $radio.AutoSize = $true
    $radio.Tag = $sm.StageKey
    $radio.Checked = ($sm.Id -eq 0)
    $radio.Location = New-Object System.Drawing.Point((20 + 140 * ($i % 3)), (40 + 24 * [Math]::Floor($i / 3)))
    $radio.Add_CheckedChanged({ if ($this.Checked) { Update-LogView } })
    $logStagePanel.Controls.Add($radio)
    $script:logStageRadios[$sm.StageKey] = $radio
}

$logStagePanel.Controls.AddRange(@($lblLogConfigName, $cmbLogConfigName, $btnClearLogs))

$logContentBox = New-LogTextBox

$tabLogs.Controls.Add($logContentBox)
$tabLogs.Controls.Add($logStagePanel)

function Update-LogConfigNameList {
    $selected = $cmbLogConfigName.SelectedItem
    $cmbLogConfigName.Items.Clear()
    $cmbLogConfigName.Items.Add("すべて") | Out-Null

    $logPath = Get-ResolvedVar "COMMON_LOG_PATH"
    if ($logPath -and (Test-Path -LiteralPath $logPath)) {
        $stageKeyPattern = ($stepMeta.StageKey -join '|')
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
    $stage = ($script:logStageRadios.GetEnumerator() | Where-Object { $_.Value.Checked }).Key
    $logPath = Get-ResolvedVar "COMMON_LOG_PATH"

    $logContentBox.Text = ""

    if (!($logPath -and (Test-Path -LiteralPath $logPath))) {
        return
    }

    $logConfigName = $cmbLogConfigName.SelectedItem
    $configFilter = if ($logConfigName -and $logConfigName -ne "すべて") { "$logConfigName" + "_" } else { "" }
    $files = Get-ChildItem -LiteralPath $logPath -Filter "${stage}_$configFilter*.log" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime

    $sections = foreach ($file in $files) { [System.IO.File]::ReadAllText($file.FullName, $cp932) }
    $logContentBox.Text = $sections -join "`r`n`r`n"
}

$cmbLogConfigName.Add_SelectedIndexChanged({ Update-LogView })

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
Update-LogConfigNameList
Update-LogView

$form.Add_Shown({ Update-InnerRunTabHeight })
$tabControl.SelectedTab = $tabRun

[System.Windows.Forms.Application]::Run($form)
