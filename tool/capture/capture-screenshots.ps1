param([string]$Root, [string]$OutDir, [string]$PlanFile)
Add-Type -AssemblyName UIAutomationClient, UIAutomationTypes, System.Drawing, System.Windows.Forms
Add-Type -Namespace Win -Name User -MemberDefinition '[DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h); [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y); [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, IntPtr e);'
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
namespace Dwm {
  [StructLayout(LayoutKind.Sequential)]
  public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
  public static class Api {
    [DllImport("dwmapi.dll")]
    public static extern int DwmGetWindowAttribute(IntPtr hwnd, int attr, ref RECT rect, int size);
  }
}
"@

$rootPath = (Resolve-Path -LiteralPath $Root).Path
$outPath = (Resolve-Path -LiteralPath $OutDir).Path
$exe = Get-ChildItem -LiteralPath $rootPath -Filter *.exe | Select-Object -First 1
if (-not $exe) { throw "exe not found in $rootPath" }
$proc = Start-Process -FilePath $exe.FullName -WorkingDirectory $rootPath -PassThru
Start-Sleep -Seconds 5

$desktop = [System.Windows.Automation.AutomationElement]::RootElement
$win = $null
for ($i = 0; $i -lt 30 -and -not $win; $i++) {
  $cond = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ProcessIdProperty, $proc.Id)
  $w = $desktop.FindFirst([System.Windows.Automation.TreeScope]::Children, $cond)
  if ($w) { $win = $w } else { Start-Sleep -Milliseconds 500 }
}
if (-not $win) { Stop-Process -Id $proc.Id -Force; throw "window not found" }
$h = [IntPtr]$win.Current.NativeWindowHandle

function Focus { [Win.User]::SetForegroundWindow($h) | Out-Null; Start-Sleep -Milliseconds 500 }

function Click-At([int]$dx, [int]$dy) {
  $r = $win.Current.BoundingRectangle
  [Win.User]::SetCursorPos([int]($r.Left + $dx), [int]($r.Top + $dy)) | Out-Null
  [Win.User]::mouse_event(0x0002, 0, 0, 0, [IntPtr]::Zero)
  [Win.User]::mouse_event(0x0004, 0, 0, 0, [IntPtr]::Zero)
  Start-Sleep -Milliseconds 900
}

function Wheel-At([int]$dx, [int]$dy, [int]$delta) {
  $r = $win.Current.BoundingRectangle
  [Win.User]::SetCursorPos([int]($r.Left + $dx), [int]($r.Top + $dy)) | Out-Null
  [Win.User]::mouse_event(0x0800, 0, 0, ([BitConverter]::ToUInt32([BitConverter]::GetBytes([int]$delta), 0)), [IntPtr]::Zero)
  Start-Sleep -Milliseconds 700
}

function Save-Shot([string]$file) {
  Focus
  $fr = New-Object Dwm.RECT
  [void][Dwm.Api]::DwmGetWindowAttribute($h, 9, [ref]$fr, [System.Runtime.InteropServices.Marshal]::SizeOf([type][Dwm.RECT]))
  $width = $fr.Right - $fr.Left
  $height = $fr.Bottom - $fr.Top
  $bmp = New-Object System.Drawing.Bitmap $width, $height
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.CopyFromScreen($fr.Left, $fr.Top, 0, 0, $bmp.Size)
  $bmp.Save((Join-Path $outPath $file), [System.Drawing.Imaging.ImageFormat]::Png)
  $g.Dispose(); $bmp.Dispose()
  Write-Output "saved $file ${width}x${height}"
}

Focus
try {
  foreach ($line in (Get-Content -LiteralPath $PlanFile -Encoding UTF8)) {
    if (-not $line.Trim()) { continue }
    $step = $line.Trim()
    $p = $step -split '\s+'
    switch ($p[0]) {
      'shot'  { Save-Shot $p[1] }
      'click' { Click-At ([int]$p[1]) ([int]$p[2]) }
      'wheel' { Wheel-At ([int]$p[1]) ([int]$p[2]) ([int]$p[3]) }
      default { throw "unknown step: $step" }
    }
  }
} finally {
  Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
}
