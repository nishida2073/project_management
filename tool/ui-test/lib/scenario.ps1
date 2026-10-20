Add-Type -AssemblyName System.Drawing

Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
namespace UiTestDwm {
  [StructLayout(LayoutKind.Sequential)]
  public struct Rect { public int Left; public int Top; public int Right; public int Bottom; }
  public static class Api {
    [DllImport("dwmapi.dll")]
    public static extern int DwmGetWindowAttribute(IntPtr hwnd, int attr, ref Rect rect, int size);
  }
}
"@

$script:ShotNo = 0

function Wait-UiTarget {
    param([System.Windows.Automation.AutomationElement]$Window, [string]$Target)
    Wait-Until -Message "部品 $Target" -Condition {
        $element = Find-UiElement -Parent $Window -Props @{ AutomationId = $Target }
        if (!$element) { $element = Find-UiElement -Parent $Window -Props @{ Name = $Target } }
        $element
    }
}

function Get-UiDiagnostics {
    param($Window)
    if (!$Window) { return "" }
    $all = $Window.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)
    $items = @()
    foreach ($element in $all) {
        $name = $element.Current.Name
        if ($name) { $items += "$($element.Current.ControlType.ProgrammaticName):$name" }
        if ($items.Count -ge 40) { break }
    }
    return "`n  確認: ウィンドウ名=$($Window.Current.Name) / 部品の数=$($all.Count) / 名前のある部品=[$($items -join ' | ')]"
}

function Save-UiScreenshot {
    param([System.Windows.Automation.AutomationElement]$Window, [string]$Path)
    $handle = [IntPtr]$Window.Current.NativeWindowHandle
    $frame = New-Object UiTestDwm.Rect
    [void][UiTestDwm.Api]::DwmGetWindowAttribute($handle, 9, [ref]$frame, [System.Runtime.InteropServices.Marshal]::SizeOf([type][UiTestDwm.Rect]))
    $width = $frame.Right - $frame.Left
    $height = $frame.Bottom - $frame.Top
    $bitmap = New-Object System.Drawing.Bitmap -ArgumentList $width, $height
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.CopyFromScreen($frame.Left, $frame.Top, 0, 0, $bitmap.Size)
    $bitmap.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
    $graphics.Dispose()
    $bitmap.Dispose()
}

function Save-UiEvidence {
    param($Context, $Element = $null)
    $script:ShotNo++
    $name = "{0}-{1:D2}.png" -f $Context.ScenarioId, $script:ShotNo
    $target = if ($Element) { $Element } else { $Context.Window }
    Save-UiScreenshot -Window $target -Path (Join-Path $Context.EvidenceDir $name)
    Write-UiLog "    エビデンス: $name"
}

function Invoke-UiStep {
    param($Step, $Context)
    Write-UiLog ("    操作: " + ($Step | ConvertTo-Json -Compress))
    switch ($Step.action) {
        "pressKey" {
            $dialog = Get-UiWindow -ProcessId $Context.ProcessId -Title $Step.window
            Focus-UiWindow -Window $dialog
            Send-UiKeys -Keys $Step.key
            Start-Sleep -Milliseconds 500
            Save-UiEvidence -Context $Context
        }
        "typeAt" {
            Invoke-UiClickAt -Window $Context.Window -X ([int]$Step.x) -Y ([int]$Step.y)
            Send-UiKeys -Keys "^a"
            if ($Step.value) { Send-UiKeys -Keys (ConvertTo-UiSendKeys -Text $Step.value) } else { Send-UiKeys -Keys "{DEL}" }
        }
        "expectDialogText" {
            $dialog = Get-UiWindow -ProcessId $Context.ProcessId -Title $Step.window
            $text = Get-UiMessageText -Dialog $dialog
            Assert-True ($text.Contains($Step.contains)) "メッセージに「$($Step.contains)」が含まれる（実際: $text）"
            Save-UiEvidence -Context $Context
        }
        "writeFile" {
            $path = Join-Path $Context.Root $Step.path
            New-Item -ItemType Directory -Path (Split-Path $path -Parent) -Force | Out-Null
            Set-Content -LiteralPath $path -Value $Step.text -Encoding ASCII
        }
        "expectFileContains" {
            $path = Join-Path $Context.Root $Step.path
            Wait-Until -Message "ファイルの内容 $($Step.path)" -Condition { (Test-Path -LiteralPath $path) -and ((Get-Content -LiteralPath $path -Raw).Contains($Step.contains)) } | Out-Null
        }
        "makeDir" {
            New-Item -ItemType Directory -Path (Join-Path $Context.Root $Step.path) -Force | Out-Null
        }
        "copyFile" {
            $from = Join-Path $Context.Root $Step.from
            $to = Join-Path $Context.Root $Step.to
            Copy-Item -LiteralPath $from -Destination $to -Force
        }
        "clickAt" {
            Invoke-UiClickAt -Window $Context.Window -X ([int]$Step.x) -Y ([int]$Step.y)
            Save-UiEvidence -Context $Context
        }
        "shot" {
            Save-UiEvidence -Context $Context
        }
        "click" {
            $element = Wait-UiTarget -Window $Context.Window -Target $Step.target
            Invoke-UiClickElement -Element $element -Window $Context.Window
            Save-UiEvidence -Context $Context
        }
        "selectComboAt" {
            Invoke-UiClickAt -Window $Context.Window -X ([int]$Step.x) -Y ([int]$Step.y)
            Send-UiKeys -Keys (ConvertTo-UiSendKeys -Text $Step.value)
            Send-UiKeys -Keys "{ENTER}"
            Save-UiEvidence -Context $Context
        }
        "enterDialog" {
            $dialog = Get-UiWindow -ProcessId $Context.ProcessId -Title $Step.window
            Focus-UiWindow -Window $dialog
            Send-UiKeys -Keys (ConvertTo-UiSendKeys -Text $Step.value)
            Save-UiEvidence -Context $Context
            Send-UiKeys -Keys "{ENTER}"
            Start-Sleep -Milliseconds 500
            Save-UiEvidence -Context $Context
        }
        "expectMessage" {
            $dialog = Get-UiWindow -ProcessId $Context.ProcessId -Title $Step.window
            $text = Get-UiMessageText -Dialog $dialog
            Save-UiEvidence -Context $Context
            Assert-True ($text -like "*$($Step.contains)*") "メッセージに「$($Step.contains)」が含まれる（実際: $text）"
            Close-UiMessageBox -Dialog $dialog
            Start-Sleep -Milliseconds 300
            Save-UiEvidence -Context $Context
        }
        "expectText" {
            $timeout = if ($Step.timeoutSec) { [int]$Step.timeoutSec } else { 15 }
            Wait-Until -TimeoutSec $timeout -Message "表示 $($Step.text)" -Condition {
                Find-UiElement -Parent $Context.Window -Props @{ Name = $Step.text }
            } | Out-Null
        }
        "expectFile" {
            $path = Join-Path $Context.Root $Step.path
            $expected = [bool]$Step.exists
            Wait-Until -Message "ファイルの有無 $($Step.path)" -Condition { (Test-Path -LiteralPath $path) -eq $expected } | Out-Null
        }
        default { throw "未対応の操作: $($Step.action)" }
    }
}

function Invoke-UiSetup {
    param($Scenario, [string]$Root)
    $index = 0
    foreach ($step in @($Scenario.setup)) {
        $index++
        try { Invoke-UiStep -Step $step -Context ([pscustomobject]@{ Root = $Root }) } catch { throw "準備 $index : $($_.Exception.Message)" }
    }
}

function Invoke-UiSteps {
    param($Scenario, $Context)
    $index = 0
    foreach ($step in @($Scenario.steps)) {
        $index++
        try { Invoke-UiStep -Step $step -Context $Context } catch {
            $message = $_.Exception.Message
            if ($message -like "タイムアウト*") { $message += Get-UiDiagnostics -Window $Context.Window }
            throw "手順 $index : $message"
        }
    }
}
