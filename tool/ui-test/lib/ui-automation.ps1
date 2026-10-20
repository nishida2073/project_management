Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes

$script:UiRoot = [System.Windows.Automation.AutomationElement]::RootElement

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "確認に失敗: $Message" }
}

function Assert-Equal {
    param($Expected, $Actual, [string]$Message)
    if ($Expected -ne $Actual) { throw "確認に失敗: $Message（期待: $Expected / 実際: $Actual）" }
}

function Wait-Until {
    param(
        [Parameter(Mandatory)][scriptblock]$Condition,
        [int]$TimeoutSec = 15,
        [string]$Message = "条件"
    )
    $deadline = (Get-Date).AddSeconds($TimeoutSec)
    while ((Get-Date) -lt $deadline) {
        $result = & $Condition
        if ($result) { return $result }
        Start-Sleep -Milliseconds 300
    }
    throw "タイムアウト: $Message"
}

function New-UiCondition {
    param([hashtable]$Props)
    $conditions = @()
    foreach ($key in $Props.Keys) {
        $value = $Props[$key]
        $conditions += switch ($key) {
            "ControlType" { New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, $value) }
            "Name" { New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::NameProperty, $value) }
            "AutomationId" { New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::AutomationIdProperty, $value) }
            "ProcessId" { New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ProcessIdProperty, $value) }
            "ClassName" { New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ClassNameProperty, $value) }
            default { throw "未対応の条件: $key" }
        }
    }
    if ($conditions.Count -eq 1) { return $conditions[0] }
    return New-Object System.Windows.Automation.AndCondition([System.Windows.Automation.Condition[]]$conditions)
}

function Find-UiElement {
    param(
        [System.Windows.Automation.AutomationElement]$Parent,
        [hashtable]$Props,
        [System.Windows.Automation.TreeScope]$Scope = [System.Windows.Automation.TreeScope]::Descendants
    )
    $start = if ($Parent) { $Parent } else { $script:UiRoot }
    return $start.FindFirst($Scope, (New-UiCondition $Props))
}

function Find-UiElements {
    param(
        [System.Windows.Automation.AutomationElement]$Parent,
        [hashtable]$Props
    )
    $start = if ($Parent) { $Parent } else { $script:UiRoot }
    return $start.FindAll([System.Windows.Automation.TreeScope]::Descendants, (New-UiCondition $Props))
}

function Get-UiWindow {
    param([int]$ProcessId, [string]$Title, [int]$TimeoutSec = 15)
    $props = @{ ProcessId = $ProcessId; ControlType = [System.Windows.Automation.ControlType]::Window }
    if ($Title) { $props["Name"] = $Title }
    Wait-Until -TimeoutSec $TimeoutSec -Message "ウィンドウ $Title" -Condition {
        Find-UiElement -Props $props
    }
}

function Find-UiButton {
    param([System.Windows.Automation.AutomationElement]$Parent, [string]$Name, [string]$AutomationId)
    $props = @{ ControlType = [System.Windows.Automation.ControlType]::Button }
    if ($Name) { $props["Name"] = $Name }
    if ($AutomationId) { $props["AutomationId"] = $AutomationId }
    Find-UiElement -Parent $Parent -Props $props
}

function Invoke-UiElement {
    param([System.Windows.Automation.AutomationElement]$Element)
    $Element.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
}

function Set-UiValue {
    param([System.Windows.Automation.AutomationElement]$Element, [string]$Text)
    $Element.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).SetValue($Text)
}

function Get-UiValue {
    param([System.Windows.Automation.AutomationElement]$Element)
    $Element.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).Current.Value
}

function Select-UiTab {
    param([System.Windows.Automation.AutomationElement]$Window, [string]$Name)
    $tab = Find-UiElement -Parent $Window -Props @{ ControlType = [System.Windows.Automation.ControlType]::TabItem; Name = $Name }
    $tab.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select()
    Start-Sleep -Milliseconds 300
}

function Select-UiComboItem {
    param([System.Windows.Automation.AutomationElement]$Combo, [string]$Text)
    $Combo.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern).Expand()
    $item = Wait-Until -Message "コンボの項目 $Text" -Condition {
        Find-UiElement -Props @{ ControlType = [System.Windows.Automation.ControlType]::ListItem; Name = $Text }
    }
    $item.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select()
    Start-Sleep -Milliseconds 300
}

function Get-UiMessageText {
    param([System.Windows.Automation.AutomationElement]$Dialog)
    $all = $Dialog.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)
    return (@($all | ForEach-Object { $_.Current.Name } | Where-Object { $_ }) -join "`n")
}

function Close-UiMessageBox {
    param([System.Windows.Automation.AutomationElement]$Dialog)
    $ok = Find-UiElement -Parent $Dialog -Props @{ Name = "OK" }
    if (!$ok) { throw "メッセージのOKボタンが見つかりません" }
    Invoke-UiClickElement -Element $ok -Window $Dialog
}

function Enter-UiDialogText {
    param([int]$ProcessId, [string]$Title, [string]$Text)
    $dialog = Get-UiWindow -ProcessId $ProcessId -Title $Title
    $edit = Find-UiElement -Parent $dialog -Props @{ ControlType = [System.Windows.Automation.ControlType]::Edit }
    Set-UiValue -Element $edit -Text $Text
    Invoke-UiElement (Find-UiButton -Parent $dialog -Name "OK")
    Start-Sleep -Milliseconds 300
}

function Get-UiEditValues {
    param([System.Windows.Automation.AutomationElement]$Window)
    $values = @()
    $all = $Window.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)
    foreach ($element in $all) {
        if ($element.Current.Name) { $values += $element.Current.Name }
        try { $values += $element.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).Current.Value } catch { }
    }
    return $values
}
