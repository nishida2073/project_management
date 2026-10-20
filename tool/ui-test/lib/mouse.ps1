Add-Type -AssemblyName System.Windows.Forms

Add-Type -Namespace UiTest -Name Native -MemberDefinition @'
[System.Runtime.InteropServices.DllImport("user32.dll")] public static extern bool SetForegroundWindow(System.IntPtr hWnd);
[System.Runtime.InteropServices.DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
[System.Runtime.InteropServices.DllImport("user32.dll")] public static extern void mouse_event(uint dwFlags, uint dx, uint dy, uint dwData, System.UIntPtr dwExtraInfo);
'@

function Invoke-UiMouseClick {
    param([int]$X, [int]$Y)
    [UiTest.Native]::SetCursorPos($X, $Y) | Out-Null
    [UiTest.Native]::mouse_event(0x0002, 0, 0, 0, [System.UIntPtr]::Zero)
    [UiTest.Native]::mouse_event(0x0004, 0, 0, 0, [System.UIntPtr]::Zero)
    Start-Sleep -Milliseconds 500
}

function Focus-UiWindow {
    param([System.Windows.Automation.AutomationElement]$Window)
    [UiTest.Native]::SetForegroundWindow([IntPtr]$Window.Current.NativeWindowHandle) | Out-Null
    Start-Sleep -Milliseconds 200
}

function Invoke-UiClickAt {
    param([System.Windows.Automation.AutomationElement]$Window, [int]$X, [int]$Y)
    $rect = $Window.Current.BoundingRectangle
    Focus-UiWindow -Window $Window
    Invoke-UiMouseClick -X ([int]($rect.Left + $X)) -Y ([int]($rect.Top + $Y))
}

function Invoke-UiClickElement {
    param([System.Windows.Automation.AutomationElement]$Element, [System.Windows.Automation.AutomationElement]$Window)
    $rect = $Element.Current.BoundingRectangle
    Focus-UiWindow -Window $Window
    Invoke-UiMouseClick -X ([int]($rect.Left + $rect.Width / 2)) -Y ([int]($rect.Top + $rect.Height / 2))
}

function ConvertTo-UiSendKeys {
    param([string]$Text)
    $special = "+^%~(){}[]"
    $result = ""
    foreach ($char in $Text.ToCharArray()) {
        if ($special.IndexOf($char) -ge 0) { $result += "{$char}" } else { $result += $char }
    }
    return $result
}

function Send-UiKeys {
    param([string]$Keys)
    [System.Windows.Forms.SendKeys]::SendWait($Keys)
    Start-Sleep -Milliseconds 300
}
