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

$commonEnvBat = Join-Path $scriptDir "common.bat"
$generatePackageBat = Join-Path $rootPath "generate-package.bat"
$generateConfigBat = Join-Path $rootPath "generate-config.bat"
$uploadKintoneFileBat = Join-Path $rootPath "upload-kintone-file.bat"


$clientsDir = Join-Path $rootPath "clients"

function Get-ClientNames {
    if (!(Test-Path -LiteralPath $clientsDir)) { return @() }
    $names = Get-ChildItem -LiteralPath $clientsDir -Filter "*.bat" -File -ErrorAction SilentlyContinue | ForEach-Object {
        [System.IO.Path]::GetFileNameWithoutExtension($_.Name)
    }
    return @($names | Select-Object -Unique | Sort-Object)
}

$blankOptions = @([PSCustomObject]@{ Text = ""; Value = "" })

function New-ClientInput {
    param([bool]$NewRow = $false)
    [PSCustomObject]@{ Name = "ClientName"; Label = "対象のグループ"; Default = ""; LabelWidth = 150; InputWidth = 150; Options = $blankOptions; NewRow = $NewRow }
}

function Get-NewClientInitialValues {
    param([string]$ClientName)
    $templateBatPath = Join-Path $clientsTemplateDir "client.bat"
    if (!(Test-Path -LiteralPath $templateBatPath)) { return @{} }

    $templateValues = Get-SetLineRawValues -Path $templateBatPath
    $result = @{}
    foreach ($key in $templateValues.Keys) {
        $value = $templateValues[$key]
        if ($key -eq "GenerateConfigPath") {
            $value = "%BASE_PATH%clients\$ClientName.xlsx"
        } elseif ($key -eq "GenerateOutputPath") {
            $value = "%BASE_PATH%generated\$ClientName"
        }
        $result[$key] = $value
    }
    return $result
}

function Update-GroupDropdowns {
    $allOption = [PSCustomObject]@{ Text = "すべて"; Value = "" }
    $clientNames = @(Get-ClientNames)

    $categoryDefs.ButtonDefs | Where-Object { $_.InputControls["ClientName"] } | ForEach-Object {
        Update-ComboBoxItems -ComboBox $_.InputControls["ClientName"] -Items $clientNames
    }

    $logItems = @($allOption) + $clientNames
    Update-ComboBoxItems -ComboBox $logTab.InputControls["GroupCombo"] -Items $logItems

    Update-ComboBoxItems -ComboBox $batchTab.InputControls["ClientName"] -Items $clientNames

    Update-ComboBoxItems -ComboBox $settingsGroupTop.Controls["GroupTarget"] -Items $clientNames

}

$zipFileCount = 3

function Get-UploadZipFiles {
    param($ic)
    $files = @()
    $inputNames = @(1..$zipFileCount | ForEach-Object { "TargetFilePath$_" }) + "TargetFolderPath"
    foreach ($name in $inputNames) {
        $value = Get-InputValue -Control $ic[$name]
        foreach ($p in @($value -split ';' | ForEach-Object { $_.Trim() } | Where-Object { $_ })) {
            if (Test-Path -LiteralPath $p -PathType Container) {
                $files += @(Get-ChildItem -LiteralPath $p -Filter *.zip -File | ForEach-Object { $_.FullName })
            } else {
                $files += $p
            }
        }
    }
    return @($files)
}
$zipFileInputs = @(1..$zipFileCount | ForEach-Object {
    [PSCustomObject]@{ Name = "TargetFilePath$_"; Label = "ファイル$_"; LabelWidth = 150; InputWidth = 300; NewRow = $true; Browse = "File"; Filter = "zipファイル (*.zip)|*.zip"; BrowseStartFn = { param($ic) $ic["TargetFolderPath"].Text }; Clear = $true }
})

$folderInput = [PSCustomObject]@{ Name = "TargetFolderPath"; Label = "フォルダ"; LabelWidth = 150; InputWidth = 300; NewRow = $true; Browse = "Folder"; Clear = $true }
$categoryDefs = @(
    [PSCustomObject]@{
        Label = "パッケージ定義"
        ButtonDefs = @(
            [PSCustomObject]@{ Label = "パッケージ定義ファイルの更新"; BatchLabel = "パッケージ定義ファイルの更新"; IncludeInBatch = $true; DefaultChecked = $false; BatchPath = $generateConfigBat; OpenTarget = { param($ic) Get-GroupXlsxPath (Get-ComboBoxValue -SelectedItem $ic["ClientName"].SelectedItem) }; Inputs = @((New-ClientInput)) }
        )
    },
    [PSCustomObject]@{
        Label = "パッケージ作成"
        ButtonDefs = @(
            [PSCustomObject]@{ Label = "パッケージの作成"; BatchLabel = "パッケージの作成"; IncludeInBatch = $true; BatchPath = $generatePackageBat; OpenTarget = { param($ic) $client = Get-ComboBoxValue -SelectedItem $ic["ClientName"].SelectedItem; if (!$client) { return $null }; Get-ResolvedVar "GenerateOutputPath" (Get-GroupBatPath $client $clientsDir) }; Inputs = @((New-ClientInput)) }
        )
    },
    [PSCustomObject]@{
        Label = "パッケージ反映"
        ButtonDefs = @(
            [PSCustomObject]@{
                Label = "パッケージのアップロード"
                IncludeInBatch = $true
                DefaultChecked = $false
                BatchArgsFn = {
                    param($bic)
                    $client = Get-InputValue -Control $bic["ClientName"]
                    $title = Get-InputValue -Control $bic["UploadTitle"]
                    $folder = Get-InputValue -Control $bic["UploadFolderPath"]
                    $zipFiles = @()
                    if ($folder -and (Test-Path -LiteralPath $folder -PathType Container)) {
                        $zipFiles = @(Get-ChildItem -LiteralPath $folder -Filter *.zip -File | ForEach-Object { $_.FullName })
                    }
                    @("-ClientName:$client", "-Title:$title", "-TargetFilePath:$($zipFiles -join ';')")
                }
                Inputs = @(
                    [PSCustomObject]@{ Name = "ClientName"; Label = "対象のグループ"; Default = ""; LabelWidth = 150; InputWidth = 150; Options = $blankOptions; OnChange = { param($ic) Update-FolderFromGroup $ic "TargetFolderPath" } }
                    [PSCustomObject]@{ Name = "Title"; Label = "タイトル"; LabelWidth = 150; InputWidth = 300; NewRow = $true }
                    $folderInput
                    $zipFileInputs
                    [PSCustomObject]@{ Name = "Description"; Label = "説明"; LabelWidth = 150; InputWidth = 300; NewRow = $true; Multiline = $true; Height = 60 }
                )
                BatchPath = $uploadKintoneFileBat
                ArgsFn = {
                    param($ic, $inputDefs)
                    $batArgs = @()
                    foreach ($inputDef in $inputDefs) {
                        if (-not $ic.ContainsKey($inputDef.Name)) { continue }
                        if ($inputDef.Name -like "TargetFilePath*" -or $inputDef.Name -eq "TargetFolderPath") { continue }
                        $value = (Get-InputValue -Control $ic[$inputDef.Name]) -replace "`r?`n", '\n'
                        $batArgs += "-$($inputDef.Name):$value"
                    }
                    $batArgs += "-TargetFilePath:$((Get-UploadZipFiles $ic) -join ';')"
                    $batArgs
                }
                Validator = {
                    param($ic)
                    if (-not (Get-InputValue -Control $ic["Title"])) {
                        [System.Windows.Forms.MessageBox]::Show("タイトルを入力してください", "実行", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
                        return $false
                    }
                    $dupNames = @(Get-UploadZipFiles $ic | ForEach-Object { [System.IO.Path]::GetFileName($_) } | Group-Object | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name })
                    if ($dupNames.Count -gt 0) {
                        [System.Windows.Forms.MessageBox]::Show("同じ名前のzipファイルがあります：`n" + ($dupNames -join "`n"), "実行", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
                        return $false
                    }
                    if ((Get-UploadZipFiles $ic).Count -eq 0) {
                        [System.Windows.Forms.MessageBox]::Show("zipファイルを1つ以上指定してください", "実行", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
                        return $false
                    }
                    return $true
                }
                OpenTarget = {
                    param($ic)
                    $client = Get-ComboBoxValue -SelectedItem $ic["ClientName"].SelectedItem
                    if (!$client) { return $null }
                    $raw = Get-SetLineRawValues -Path (Get-GroupBatPath $client $clientsDir)
                    if (!$raw["KintoneSubdomain"] -or !$raw["TargetAppId"]) { return $null }
                    "https://$($raw['KintoneSubdomain']).cybozu.com/k/$($raw['TargetAppId'])/"
                }
            }
        )
    }
)

$form = New-Form -Title "コース別パッケージ生成ツール" -Width 780 -Height 560 -MinWidth 600 -MinHeight 400 -CenterScreen
$script:currentProc = $null

$tabControl = New-TabControl
$tabRun = New-TabPage -Text "実行"
$tabLogs = New-TabPage -Text "ログ"
$tabSettings = New-TabPage -Text "設定"

$tabControl.Controls.AddRange(@($tabRun, $tabLogs, $tabSettings))
$form.Controls.Add($tabControl)


$execTabControl = New-TabControl

$allButtonDefs = @()
foreach ($cd in $categoryDefs) {
    foreach ($bd in $cd.ButtonDefs) {
        if ($bd.IncludeInBatch -ne $false) { $allButtonDefs += $bd }
    }
}

$tabBatchAll = New-TabPage -Text "一括実行"
$execTabControl.Controls.Add($tabBatchAll)

$batchRunAllInputs = @(
        [PSCustomObject]@{ Name = "ClientName"; Label = "対象のグループ"; Options = $blankOptions; LabelWidth = 150; InputWidth = 150; OnChange = { param($ic) Update-FolderFromGroup $ic "UploadFolderPath" "UploadTitle" } }
        [PSCustomObject]@{ Name = "UploadTitle"; Label = "タイトル"; LabelWidth = 150; InputWidth = 300; NewRow = $true; Require = $true }
        [PSCustomObject]@{ Name = "UploadFolderPath"; Label = "フォルダ"; LabelWidth = 150; InputWidth = 300; NewRow = $true; Browse = "Folder"; Require = $true }
)

$batchTab = New-BatchRunTab -TabPage $tabBatchAll -ButtonDefs $allButtonDefs `
    -Inputs $batchRunAllInputs `
    -OnOpenClick {
        param($target)
        Open-TargetOrWarn -Path $target
    } `
    -OnRunClick { Invoke-ExecuteAll }

function Set-RunButtonsEnabled {
    param([bool]$Enabled)
    Set-ButtonsEnabled -Buttons $categoryTab.RunButtons -Enabled $Enabled
    Set-ButtonsEnabled -Buttons @($batchTab.RunButton) -Enabled $Enabled
}

function Invoke-ExecuteAll {
    $uploadBd = $allButtonDefs | Where-Object { $_.BatchArgsFn } | Select-Object -First 1
    $uploadChk = $batchTab.CheckBoxes | Where-Object { $_.Tag -eq $uploadBd } | Select-Object -First 1
    if ($uploadChk -and $uploadChk.Checked) {
        $ic = $batchTab.InputControls
        foreach ($inputDef in $batchRunAllInputs) {
            if (-not $inputDef.Require) { continue }
            if (Get-InputValue -Control $ic[$inputDef.Name]) { continue }
            [System.Windows.Forms.MessageBox]::Show("$($inputDef.Label) を設定してください。", "一括実行", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
            return
        }
    }
    
    Invoke-BatchRunAll -ButtonDefs $allButtonDefs -CheckBoxes $batchTab.CheckBoxes `
        -StatusLabel $batchTab.StatusLabel -StatusLabels $batchTab.StatusLabels `
        -WriteLog { param($msg) Write-Log $msg } -SetRunButtonsEnabled { param($e) Set-RunButtonsEnabled $e } `
        -InvokeStep {
            param($bd)
            Invoke-BatchStep -ButtonDef $bd -WorkingDirectory $scriptDir -Form $form `
                -WriteLog { param($msg) Write-Log $msg } -CurrentProcessRef ([ref]$script:currentProc) `
                -GetBatArgs {
                    param($bd)
                    if ($bd.BatchArgsFn) { return & $bd.BatchArgsFn $batchTab.InputControls }
                    if ($bd.ArgsFn) { return & $bd.ArgsFn $bd.InputControls $bd.Inputs }
                    $batArgs = @()
                    foreach ($inputDef in $bd.Inputs) {
                        $value = Get-InputValue -Control $batchTab.InputControls[$inputDef.Name]
                        $batArgs += "-$($inputDef.Name):$value"
                    }
                    return $batArgs
                }
        }
}

$categoryTab = New-CategoryTabControl -TabControl $execTabControl -CategoryDefs $categoryDefs -OnRunClick {
    param($bd)
    if ($bd.Validator -and -not (& $bd.Validator $bd.InputControls)) { return 1 }
    Invoke-BatButton -ButtonDef $bd -WorkingDirectory $scriptDir -Form $form `
        -WriteLog { param($msg) Write-Log $msg } -SetRunButtonsEnabled { param($e) Set-RunButtonsEnabled $e } `
        -CurrentProcessRef ([ref]$script:currentProc) `
        -GetBatArgs {
            param($bd)
            if ($bd.ArgsFn) { return & $bd.ArgsFn $bd.InputControls $bd.Inputs }
            $batArgs = @()
            $inputMap = $bd.InputControls
            if ($inputMap) {
                foreach ($inputName in $inputMap.Keys) {
                    $batArgs += "-$($inputName):$(Get-InputValue -Control $inputMap[$inputName])"
                }
            }
            return $batArgs
        }
}

function Get-ButtonDefByBatchPath {
    param([string]$BatchPath)
    return $categoryDefs | ForEach-Object { $_.ButtonDefs } | Where-Object { $_.BatchPath -eq $BatchPath } | Select-Object -First 1
}
$execTabControl.Height = 45 + $batchTab.Panel.Height

$txtLog = New-LogTextBox

Add-StackedDockedControls -Container $tabRun -ControlsTopToBottom @($execTabControl, $txtLog)


$allButtonDefsForLog = @($categoryDefs | ForEach-Object { $_.ButtonDefs })

$logTabConditions = @(
    @{ PropertyName = "GroupCombo"; LabelText = "対象のグループ"; LabelWidth = 150; ComboWidth = 150; Options = $blankOptions }
)

$logTab = New-LogTab -TabPage $tabLogs -ButtonDefs $allButtonDefsForLog `
    -LabelFn { param($bd) Get-BatchDisplayLabel -ButtonDef $bd } `
    -Conditions $logTabConditions `
    -GetLogPathFn { Get-ResolvedVar "CommonLogPath" $commonEnvBat }

$clientsDir = Join-Path $rootPath "clients"
function Update-FolderFromGroup {
    param($ic, [string]$FolderKey, [string]$TitleKey = "")
    $client = Get-ComboBoxValue -SelectedItem $ic["ClientName"].SelectedItem
    if (!$client) { return }
    if ($TitleKey) { $ic[$TitleKey].Text = $client }
    $groupBat = Get-GroupBatPath $client $clientsDir
    if (Test-Path -LiteralPath $groupBat) { $ic[$FolderKey].Text = Get-ResolvedVar "GenerateOutputPath" $groupBat }
}
$clientsTemplateDir = Join-Path $clientsDir "template"

function Get-GroupXlsxPath { param([string]$GroupName) Join-Path $clientsDir "$GroupName.xlsx" }

$commonEnvResolver = { param($name) Get-ResolvedVar $name $commonEnvBat }

$settingsGroups = [ordered]@{
    "COMMON" = @{
        Label = "共通"
        Overridable = $false
        Vars = [ordered]@{
            "CommonLogPath" = @{ Label = "ログの出力先"; Browse = "Folder" }
        }
    }
    "KINTONE" = @{
        Label = "kintone接続"
        Vars = [ordered]@{
            "KintoneSubdomain"  = @{ Label = "サブドメイン" }
            "KintoneLoginName"  = @{ Label = "ログイン名" }
            "KintonePassword"   = @{ Label = "パスワード"; Masked = $true }
        }
    }
    "UPLOAD_KINTONE" = @{
        Label = "ファイル管理"
        Vars = [ordered]@{
            "TargetAppId"       = @{ Label = "対象アプリID" }
        }
    }
    "DOWNLOAD" = @{
        Label = "ダウンロード"
        Vars = [ordered]@{
            "DownloadSiteUrl"       = @{ Label = "ダウンロード元のサイトURL" }
            "DownloadSitePath"      = @{ Label = "ダウンロード元のフォルダ" }
            "DownloadSiteTenantId"  = @{ Label = "テナントID" }
            "DownloadLocalPath"     = @{ Label = "ダウンロード先のフォルダ"; Browse = "Folder" }
        }
    }
    "GENERATE" = @{
        Label = "パッケージ作成"
        Vars = [ordered]@{
            "GenerateSourcePath"      = @{ Label = "圧縮元のフォルダ"; Browse = "Folder"  }
            "GenerateConfigPath"      = @{ Label = "パッケージ定義ファイル"; Browse = "File"; Filter = "Excel ファイル (*.xlsx)|*.xlsx|すべてのファイル (*.*)|*.*" }
            "GenerateWorkPath"        = @{ Label = "作業用のフォルダ"; Browse = "Folder"  }
            "GenerateOutputPath"      = @{ Label = "パッケージの出力先"; Browse = "Folder" }
            "GenerateSheetsInclude"   = @{ Label = "対象のシート" }
            "GenerateSheetsExclude"   = @{ Label = "除外のシート" }
        }
    }
    "UPLOAD" = @{
        Label = "アップロード"
        Vars = [ordered]@{
            "UploadSiteUrl"       = @{ Label = "アップロード先のサイトURL" }
            "UploadSitePath"      = @{ Label = "アップロード先のフォルダ" }
            "UploadSiteTenantId"  = @{ Label = "テナントID" }
            "UploadLocalPath"     = @{ Label = "アップロード元のフォルダ"; Browse = "Folder" }
            "UploadItemsInclude"  = @{ Label = "対象の項目形式" }
            "UploadItemsExclude"  = @{ Label = "除外の項目形式" }
        }
    }
}

$commonSettingsVars = @($settingsGroups["COMMON"].Vars.Keys)
$downloadVars = @($settingsGroups["DOWNLOAD"].Vars.Keys)
$generateVars = @($settingsGroups["GENERATE"].Vars.Keys)
$uploadVars = @($settingsGroups["UPLOAD"].Vars.Keys)
$kintoneVars = @($settingsGroups["KINTONE"].Vars.Keys)
$uploadKintoneVars = @($settingsGroups["UPLOAD_KINTONE"].Vars.Keys)

function Test-KintoneConnectionFromSettings {
    param([string]$FieldName)

    $kintoneSubdomain = (Get-GroupSettingsFieldValue "KINTONE_KintoneSubdomain").Trim()
    $kintoneLoginName = Get-GroupSettingsFieldValue "KINTONE_KintoneLoginName"
    $kintonePassword = Get-GroupSettingsFieldValue "KINTONE_KintonePassword"
    $targetAppId = (Get-GroupSettingsFieldValue $FieldName).Trim()
    if (!$targetAppId) {
        throw "対象アプリIDを入力してください。"
    }

    return Test-KintoneConnectionWithAppId -Subdomain $kintoneSubdomain -LoginName $kintoneLoginName -Password $kintonePassword -AppIds @($targetAppId)
}
$settingsTrailingButtonVars = @{
    "TargetAppId" = { param($Panel, $Y, $Field) Add-FieldActionButton -Panel $Panel -Y $Y -Text "テスト接続" -AddStatusLabel -OnClick {
        Invoke-ActionWithUpdateStatus -StatusLabel $Field.StatusLabel -Action {
            Test-KintoneConnectionFromSettings -FieldName "UPLOAD_KINTONE_TargetAppId" | Out-Null
        }
    }.GetNewClosure() }
    "KintonePassword" = { param($Panel, $Y, $Field) Add-FieldActionButton -Panel $Panel -Y $Y -Text "テスト接続" -AddStatusLabel -OnClick {
        Invoke-ActionWithUpdateStatus -StatusLabel $Field.StatusLabel -Action {
            $kintoneSubdomain = (Get-GroupSettingsFieldValue "KINTONE_KintoneSubdomain").Trim()
            $kintoneLoginName = Get-GroupSettingsFieldValue "KINTONE_KintoneLoginName"
            $kintonePassword = Get-GroupSettingsFieldValue "KINTONE_KintonePassword"
            if (!$kintoneSubdomain -or !$kintoneLoginName -or !$kintonePassword) {
                throw "サブドメイン・ログイン名・パスワードをすべて入力してください。"
            }
            Test-KintoneConnection -Subdomain $kintoneSubdomain -LoginName $kintoneLoginName -Password $kintonePassword
        }
    }.GetNewClosure() }
}

$settingsRenderLists = Get-SettingsRenderLists -SettingsGroups $settingsGroups

$script:groupTemplateDefaults = $null
function Get-GroupTemplateDefaults {
    if ($null -eq $script:groupTemplateDefaults) {
        $clientBatPath = Join-Path $clientsTemplateDir "client.bat"
        $script:groupTemplateDefaults = [PSCustomObject]@{
            Auth = Get-SetLineRawValues -Path $clientBatPath
            Sync = Get-SetLineRawValues -Path $clientBatPath
        }
    }
    return $script:groupTemplateDefaults
}

$settingsSubTabControl = New-TabControl -Dock ([System.Windows.Forms.DockStyle]::Fill)
$tabSettings.Controls.Add($settingsSubTabControl)

$tabSettingsCommon = New-TabPage -Text "共通"
$settingsSubTabControl.Controls.Add($tabSettingsCommon)

$tabSettingsGroup = New-TabPage -Text "グループ別"
$settingsSubTabControl.Controls.Add($tabSettingsGroup)


function Get-CommonSettingsFiles {
    return @(
        [PSCustomObject]@{ Path = $commonEnvBat; Save = { Save-CommonSettings }; Reload = {} }
    )
}

$settingsCommonTopPanel = (New-SettingsTopPanel `
    -OnSave { foreach ($f in (Get-CommonSettingsFiles)) { & $f.Save }; Update-CommonSettingsFields } `
    -OnReload { foreach ($f in (Get-CommonSettingsFiles)) { & $f.Reload }; Update-CommonSettingsFields }).Panel

$settingsCommonBottomPanel = New-Panel -Dock ([System.Windows.Forms.DockStyle]::Fill) -AutoScroll

$tabSettingsCommon.Controls.Add($settingsCommonBottomPanel)
$tabSettingsCommon.Controls.Add($settingsCommonTopPanel)

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
    return @(
        [PSCustomObject]@{ Path = (Get-GroupBatPath $GroupName $clientsDir); Save = { Save-GroupSettings -GroupName $GroupName }.GetNewClosure(); Reload = {} }
    )
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

            if (($settingsGroupTop.Controls["GroupTarget"].Items | Where-Object { (Get-ComboBoxValue -SelectedItem $_) -eq $newName }) -or (Test-Path -LiteralPath (Get-GroupXlsxPath $newName)) -or (Test-Path -LiteralPath (Get-GroupBatPath $newName $clientsDir))) {
                [System.Windows.Forms.MessageBox]::Show("「$newName」は既に存在します。", "グループの新規作成", [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
                return
            }

            $settingsGroupTop.Controls["GroupTarget"].Items.Add([PSCustomObject]@{ Text = $newName; Value = $newName }) | Out-Null
            $settingsGroupTop.Controls["GroupTarget"].SelectedIndex = $settingsGroupTop.Controls["GroupTarget"].Items.Count - 1
        } }
        [PSCustomObject]@{ Name = "OpenXlsx"; Kind = "Link"; Text = "開く"; OnClick = {
            $target = Get-ComboBoxValue -SelectedItem $settingsGroupTop.Controls["GroupTarget"].SelectedItem
            Open-TargetOrWarn -Path (Get-GroupXlsxPath $target)
        } }
    ) `
    -OnSave {
        $target = Get-ComboBoxValue -SelectedItem $settingsGroupTop.Controls["GroupTarget"].SelectedItem
        if (!$target) { return }
        foreach ($f in (Get-GroupSettingsFiles -GroupName $target)) { & $f.Save }
        Update-GroupSettingsFields
    } `
    -OnReload {
        $target = Get-ComboBoxValue -SelectedItem $settingsGroupTop.Controls["GroupTarget"].SelectedItem
        foreach ($f in (Get-GroupSettingsFiles -GroupName $target)) { & $f.Reload }
        Update-GroupSettingsFields
    })

$settingsGroupBottomPanel = New-Panel -Dock ([System.Windows.Forms.DockStyle]::Fill) -AutoScroll

$tabSettingsGroup.Controls.Add($settingsGroupBottomPanel)
$tabSettingsGroup.Controls.Add($settingsGroupTop.Panel)

function Get-GroupNames {
    if (!(Test-Path -LiteralPath $clientsDir)) { return @() }
    $names = Get-ChildItem -LiteralPath $clientsDir -Filter "*.xlsx" -File -ErrorAction SilentlyContinue | ForEach-Object {
        [System.IO.Path]::GetFileNameWithoutExtension($_.Name)
    }
    return @($names | Select-Object -Unique | Sort-Object)
}

function Get-CommonSettingsFieldRows {
    $raw = Get-SetLineRawValues -Path $commonEnvBat
    foreach ($varName in $commonSettingsVars) {
        [PSCustomObject]@{ Key = $varName; VarName = $varName; Group = "COMMON"; Value = $raw[$varName] }
    }
}

function Get-GroupSettingsFieldRows {
    param([string]$GroupName)
    if (!$GroupName) { return }

    $rawClient = Get-SetLineRawValues -Path (Get-GroupBatPath $GroupName $clientsDir)
    $isPendingNewClient = !(Test-Path -LiteralPath (Get-GroupBatPath $GroupName $clientsDir))
    $newClientDefaults = if ($isPendingNewClient) { Get-NewClientInitialValues $GroupName } else { @{} }

    foreach ($groupKey in @("KINTONE", "UPLOAD_KINTONE", "DOWNLOAD", "GENERATE", "UPLOAD")) {
        $vars = switch ($groupKey) { "KINTONE" { $kintoneVars } "UPLOAD_KINTONE" { $uploadKintoneVars } "DOWNLOAD" { $downloadVars } "GENERATE" { $generateVars } default { $uploadVars } }
        foreach ($varName in $vars) {
            $value = if ($rawClient.ContainsKey($varName)) { $rawClient[$varName] } elseif ($newClientDefaults.ContainsKey($varName)) { $newClientDefaults[$varName] } else { "" }
            [PSCustomObject]@{ Key = "$($groupKey)_$varName"; VarName = $varName; Group = $groupKey; Value = $value }
        }
    }
}


function Update-CommonSettingsFields {
    Render-SettingsFields -Panel $settingsCommonBottomPanel -Rows (Get-CommonSettingsFieldRows) -TargetTextBoxes $settingsCommonFieldTextBoxes -RadioVars $settingsRenderLists.RadioVars `
        -GroupLabels $settingsRenderLists.GroupLabels -VarLabels $settingsRenderLists.VarLabels -RootPath $rootPath -EnvResolver $commonEnvResolver `
        -MultilineVars $settingsRenderLists.MultilineVars -MaskedVars $settingsRenderLists.MaskedVars -FolderBrowseVars $settingsRenderLists.FolderBrowseVars -FileBrowseVars $settingsRenderLists.FileBrowseVars -FileBrowseFilters $settingsRenderLists.FileBrowseFilters -NoOpenVars $settingsRenderLists.NoOpenVars -LabelWidth 150 | Out-Null
}

function Update-GroupSettingsFields {
    $scrollX = -$settingsGroupBottomPanel.AutoScrollPosition.X
    $scrollY = -$settingsGroupBottomPanel.AutoScrollPosition.Y

    $target = Get-ComboBoxValue -SelectedItem $settingsGroupTop.Controls["GroupTarget"].SelectedItem
    $trailingButtons = $settingsTrailingButtonVars.Clone()
    $resolverValue = $commonEnvResolver
    $rootPathValue = $rootPath
    Render-SettingsFields -Panel $settingsGroupBottomPanel -Rows (Get-GroupSettingsFieldRows -GroupName $target | Where-Object { $_.Group -in @("KINTONE", "UPLOAD_KINTONE", "GENERATE") }) -TargetTextBoxes $settingsGroupFieldTextBoxes -RadioVars $settingsRenderLists.RadioVars `
        -GroupLabels $settingsRenderLists.GroupLabels -VarLabels $settingsRenderLists.VarLabels -RootPath $rootPath -EnvResolver $commonEnvResolver `
        -MultilineVars $settingsRenderLists.MultilineVars -MaskedVars $settingsRenderLists.MaskedVars -FolderBrowseVars $settingsRenderLists.FolderBrowseVars -FileBrowseVars $settingsRenderLists.FileBrowseVars -FileBrowseFilters $settingsRenderLists.FileBrowseFilters -NoOpenVars $settingsRenderLists.NoOpenVars -LabelWidth 150 `
        -OnOpenClick ({ param($path) Resolve-BrowseStart -RawValue $path -DefaultPath $rootPathValue -Resolver $resolverValue -BasePath $rootPathValue }).GetNewClosure() `
        -TrailingButtonVars $trailingButtons | Out-Null

    $settingsGroupBottomPanel.AutoScrollPosition = New-Object System.Drawing.Point($scrollX, $scrollY)
}

function Save-CommonSettings {
    Save-EnvBatFile -Path $commonEnvBat -VarNames $commonSettingsVars `
        -GetValueFn { param($varName)
            Get-CommonSettingsFieldValue $varName
        } `
        -HasValueFn { param($varName)
            $true
        }
}

function Save-GroupSettings {
    param([string]$GroupName)

    $groupBatPath = Get-GroupBatPath $GroupName $clientsDir

    $saveGroupDownloadVarMap = @{}
    foreach ($varName in $downloadVars) {
        $saveGroupDownloadVarMap[$varName] = "DOWNLOAD_$varName"
    }

    $saveGroupGenerateVarMap = @{}
    foreach ($varName in $generateVars) {
        $saveGroupGenerateVarMap[$varName] = "GENERATE_$varName"
    }

    $saveGroupUploadVarMap = @{}
    foreach ($varName in $uploadVars) {
        $saveGroupUploadVarMap[$varName] = "UPLOAD_$varName"
    }

    $saveGroupKintoneVarMap = @{}
    foreach ($varName in $kintoneVars) {
        $saveGroupKintoneVarMap[$varName] = "KINTONE_$varName"
    }
    $saveGroupUploadKintoneVarMap = @{}
    foreach ($varName in $uploadKintoneVars) {
        $saveGroupUploadKintoneVarMap[$varName] = "UPLOAD_KINTONE_$varName"
    }

    $allVars = @() + @($saveGroupKintoneVarMap.Keys) + @($saveGroupUploadKintoneVarMap.Keys) + @($saveGroupDownloadVarMap.Keys) + @($saveGroupGenerateVarMap.Keys) + @($saveGroupUploadVarMap.Keys)

    Save-EnvBatFile -Path $groupBatPath -VarNames $allVars `
        -GetValueFn { param($varName)
            if ($saveGroupDownloadVarMap.ContainsKey($varName)) {
                Get-GroupSettingsFieldValue $saveGroupDownloadVarMap[$varName]
            } elseif ($saveGroupGenerateVarMap.ContainsKey($varName)) {
                Get-GroupSettingsFieldValue $saveGroupGenerateVarMap[$varName]
            } elseif ($saveGroupUploadVarMap.ContainsKey($varName)) {
                Get-GroupSettingsFieldValue $saveGroupUploadVarMap[$varName]
            } elseif ($saveGroupKintoneVarMap.ContainsKey($varName)) {
                Get-GroupSettingsFieldValue $saveGroupKintoneVarMap[$varName]
            } elseif ($saveGroupUploadKintoneVarMap.ContainsKey($varName)) {
                Get-GroupSettingsFieldValue $saveGroupUploadKintoneVarMap[$varName]
            } else {
                ""
            }
        } `
        -HasValueFn { param($varName)
            $true
        }

    $xlsxPath = Get-GroupXlsxPath $GroupName
    if (!(Test-Path -LiteralPath $xlsxPath)) {
        $templateXlsxPath = Join-Path $clientsTemplateDir "client.xlsx"
        if (Test-Path -LiteralPath $templateXlsxPath) {
            Copy-Item -LiteralPath $templateXlsxPath -Destination $xlsxPath
        }
    }

    Update-GroupDropdowns
}


$settingsSubTabControl.Add_SelectedIndexChanged({
    if ($settingsSubTabControl.SelectedTab -eq $tabSettingsCommon) {
        Update-CommonSettingsFields
    } elseif ($settingsSubTabControl.SelectedTab -eq $tabSettingsGroup) {
        Update-GroupSettingsFields
    }
})

$tabControl.Add_SelectedIndexChanged({
    if ($tabControl.SelectedTab -eq $tabLogs) {
        Update-LogView -LogTab $logTab
    }
})

$tabControl.SelectedTab = $tabRun

$form.Add_Shown({
    Update-CommonSettingsFields
    Update-GroupDropdowns
    Update-TabHeight -NestedTabControl $execTabControl
})

[System.Windows.Forms.Application]::Run($form)
